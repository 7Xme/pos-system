import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'online_tts_service.dart';

/// مصدر الصوت: تلقائي (SAPI ثم أونلاين) أو أحدهما حصراً.
enum TtsSource { auto, sapi, online }

/// نتيجة فحص الصوت التشخيصي (لا ترمي استثناءً أبداً).
typedef TtsDiagnosis = ({
  bool comOk,
  bool voiceCreated,
  bool speakOk,
  int speakHr,
  bool onlineOk,
  String sourceUsed,
  List<({String name, String lang})> voices,
  int arabicCount,
  String? error,
});

/// الخطوة 4: نطق المجموع الإجمالي بصوت عربي واضح (ar-SA)
///
/// يعمل بعد إتمام البيع مباشرة.
///
/// التنفيذ: SAPI الأصلي في Windows عبر `dart:ffi` — **بدون أي تهيئة عند
/// إقلاع التطبيق** (عكس إضافة flutter_tts التي تُنشئ صوت SAPI أثناء تسجيل
/// الإضافة وتُعطّل البرنامج كاملاً إذا كان نظام الصوت معطّلاً).
/// كل الأعطال هنا تتحول إلى `false` هادئ — التطبيق لا يتعطل أبداً بسبب الصوت.
class ArabicTtsService {
  ArabicTtsService._();
  static final ArabicTtsService instance = ArabicTtsService._();

  // SAPI: ar-SA = 0x401. أي صوت عربي آخر = primary LANGID == 1.
  static const int _arabicSaudi = 0x401;
  static const int _arabicPrimary = 0x001;

  Pointer<Void>? _voice;
  bool _comInit = false;

  /// لا يفعل شيئاً ثقيلاً عمداً — الصوت يُبنى كسلاً عند أول نطق.
  Future<void> init() async {}

  /// ينطق: "إجمالي الفاتورة: خمسة وثمانون درهماً"
  /// يُرجع true عند نجاح إرسال أمر النطق.
  Future<bool> speakTotal(
    double total, {
    String currency = 'درهم',
    TtsSource source = TtsSource.auto,
  }) async {
    final words = _amountToArabicWords(total);
    return speak('إجمالي الفاتورة: $words $currency', source: source);
  }

  /// يُرجع true عند نجاح النطق، وfalse (بدون رمي استثناء) عند أي عطل.
  /// auto: يجرب SAPI أولاً ثم الأونلاين.
  Future<bool> speak(
    String text, {
    TtsSource source = TtsSource.auto,
  }) async {
    if (!Platform.isWindows) return false;
    if (text.trim().isEmpty) return false;
    switch (source) {
      case TtsSource.sapi:
        return _speakSapi(text);
      case TtsSource.online:
        return OnlineTtsService.instance.speak(text);
      case TtsSource.auto:
        try {
          if (await _speakSapi(text)) return true;
        } catch (_) {
          // نسقط للبديل الأونلاين
        }
        return OnlineTtsService.instance.speak(text);
    }
  }

  Future<bool> _speakSapi(String text) async {
    try {
      return _speakSync(text);
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      final voice = _voice;
      if (voice != null) {
        _sapiSpeak(voice, nullptr, _spfPurgeBeforeSpeak, nullptr);
      }
    } catch (_) {
      // تجاهل — الإيقاف اختياري
    }
  }

  /// تشخيص شامل لا يرمي استثناءً أبداً — يُستخدم في شاشة الإعدادات
  /// لمعرفة سبب عدم خروج الصوت. يجرب النطق الفعلي عبر المصدر المختار.
  Future<TtsDiagnosis> diagnose({
    TtsSource source = TtsSource.auto,
  }) async {
    const empty = <({String name, String lang})>[];
    TtsDiagnosis fail(String? error) => (
          comOk: false,
          voiceCreated: false,
          speakOk: false,
          speakHr: 0,
          onlineOk: false,
          sourceUsed: source.name,
          voices: empty,
          arabicCount: 0,
          error: error,
        );
    if (!Platform.isWindows) return fail('النظام ليس ويندوز');
    try {
      _ole32 ??= DynamicLibrary.open('ole32.dll');
      final coInit = _ole32!.lookupFunction<_CoInitN, _CoInitD>(
        'CoInitializeEx',
      );
      var comOk = _comInit;
      if (!comOk) {
        final hr = coInit(nullptr, _coinitApartmentThreaded);
        comOk = hr == _sOk || hr == 1 || (hr & 0xFFFFFFFF) == 0x80010106;
        if (comOk) _comInit = true;
      }
      if (!comOk) return fail('تعذرت تهيئة COM');
      final voice = _ensureVoice(_ole32!);
      final voices = _listAllVoices();
      final arabic =
          voices.where((v) => _isArabicLang(v.lang)).length;

      // فحص الأونلاين (جلب فقط دون تشغيل) — يعمل حتى لو SAPI ميت.
      var onlineOk = false;
      try {
        final probe =
            await OnlineTtsService.fetchAudio('اختبار').timeout(
                  const Duration(seconds: 15),
                );
        onlineOk = probe != null && probe.isNotEmpty;
      } catch (_) {
        onlineOk = false;
      }

      // النطق الفعلي عبر المصدر المختار (كما يحدث عند البيع).
      var speakOk = false;
      var speakHr = 0;
      var used = source.name;
      if (source == TtsSource.sapi) {
        if (voice == null) {
          return (
            comOk: true,
            voiceCreated: false,
            speakOk: false,
            speakHr: 0,
            onlineOk: onlineOk,
            sourceUsed: used,
            voices: voices,
            arabicCount: arabic,
            error:
                'تعذر إنشاء صوت SAPI — خدمة الصوت/النطق معطلة في الويندوز',
          );
        }
        speakHr = _speakTestPhrase(voice);
        speakOk = speakHr == _sOk;
      } else if (source == TtsSource.online) {
        speakOk = await OnlineTtsService.instance.speak('اختبار الصوت العربي');
      } else {
        // تلقائي: SAPI ثم أونلاين — مع تسجيل المصدر المستخدم فعلاً.
        if (voice != null) {
          speakHr = _speakTestPhrase(voice);
          if (speakHr == _sOk) {
            speakOk = true;
            used = TtsSource.sapi.name;
          }
        }
        if (!speakOk) {
          speakOk =
              await OnlineTtsService.instance.speak('اختبار الصوت العربي');
          if (speakOk) used = TtsSource.online.name;
        }
      }

      String? error;
      if (!speakOk) {
        error = !onlineOk && voice == null
            ? 'لا صوت ويندوز ولا إنترنت — لا يمكن النطق حالياً'
            : 'تعذر النطق عبر المصدر المختار';
      } else if (used == TtsSource.sapi.name && arabic == 0) {
        error =
            'يخرج الصوت لكن بلا صوت عربي — النطق العربي سيكون رديئاً. ثبت صوتاً عربياً من إعدادات ويندوز أو بدّل المصدر إلى أونلاين.';
      }
      return (
        comOk: true,
        voiceCreated: voice != null,
        speakOk: speakOk,
        speakHr: speakHr,
        onlineOk: onlineOk,
        sourceUsed: used,
        voices: voices,
        arabicCount: arabic,
        error: error,
      );
    } catch (e) {
      return fail('استثناء غير متوقع: $e');
    }
  }

  /// ينطق عبارة الاختبار عبر SAPI ويُرجع HRESULT.
  int _speakTestPhrase(Pointer<Void> voice) {
    final textPtr = 'اختبار الصوت العربي'.toNativeUtf16();
    try {
      return _sapiSpeak(
        voice,
        textPtr,
        _spfAsync | _spfPurgeBeforeSpeak,
        nullptr,
      );
    } finally {
      malloc.free(textPtr);
    }
  }

  /// يسرد كل أصوات SAPI المثبتة مع لغاتها (من الريجستري).
  List<({String name, String lang})> _listAllVoices() {
    const roots = [
      (_hkcu, 'HKEY_CURRENT_USER'),
      (_hklm, 'HKEY_LOCAL_MACHINE'),
    ];
    final out = <({String name, String lang})>[];
    for (final (hive, prefix) in roots) {
      final tokensKey =
          '$prefix\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens';
      for (final name in _enumSubKeys(hive, _stripPrefix(tokensKey))) {
        final sub = '${_stripPrefix(tokensKey)}\\$name';
        final display = _queryString(hive, sub, null) ?? name;
        final lang =
            _queryString(hive, '$sub\\Attributes', 'Language') ?? '?';
        out.add((name: display, lang: lang));
      }
    }
    return out;
  }

  bool _isArabicLang(String lang) {
    final v = int.tryParse(lang.trim(), radix: 16);
    return v != null && (v & 0x3FF) == _arabicPrimary;
  }

  // ── SAPI عبر FFI (متزامن، بلا await بين CoInit و Speak) ──────────────

  static const int _sOk = 0;
  static const int _spfAsync = 1;
  static const int _spfPurgeBeforeSpeak = 2;
  static const int _clsctxAll = 0x17;
  static const int _coinitApartmentThreaded = 0x2;
  static const int _keyRead = 0x20019;
  static const int _hklm = 0x80000002;
  static const int _hkcu = 0x80000001;
  static const int _regSz = 1;
  static const int _errorNoMoreItems = 259;

  DynamicLibrary? _ole32;
  DynamicLibrary? _sapi;

  bool _speakSync(String text) {
    _ole32 ??= DynamicLibrary.open('ole32.dll');
    final ole = _ole32!;

    final coInit = ole.lookupFunction<_CoInitN, _CoInitD>(
      'CoInitializeEx',
    );
    if (!_comInit) {
      final hr = coInit(nullptr, _coinitApartmentThreaded);
      // S_OK أو S_FALSE أو RPC_E_CHANGED_MODE كلها تعني: COM متاح
      if (hr != _sOk && hr != 1 && (hr & 0xFFFFFFFF) != 0x80010106) {
        return false;
      }
      _comInit = true;
    }

    final voice = _ensureVoice(ole);
    if (voice == null) return false;

    final textPtr = text.toNativeUtf16();
    try {
      final hr = _sapiSpeak(
        voice,
        textPtr,
        _spfAsync | _spfPurgeBeforeSpeak,
        nullptr,
      );
      return hr == _sOk;
    } finally {
      malloc.free(textPtr);
    }
  }

  Pointer<Void>? _ensureVoice(DynamicLibrary ole) {
    if (_voice != null) return _voice;
    final coCreate = ole.lookupFunction<_CoCreateN, _CoCreateD>(
      'CoCreateInstance',
    );

    final clsid = _guid(
      0x96749377,
      0x3391,
      0x11D2,
      const [0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96],
    ); // CLSID_SpVoice
    final iid = _guid(
      0x6C44DF74,
      0x72B5,
      0x4566,
      const [0x8E, 0x34, 0x58, 0x70, 0x72, 0x68, 0x68, 0x72],
    ); // IID_ISpVoice
    final out = calloc<Pointer<Void>>();
    try {
      final hr = coCreate(
        clsid,
        nullptr,
        _clsctxAll,
        iid,
        out,
      );
      if (hr != _sOk || out.value == nullptr) return null;
      _voice = out.value;
    } finally {
      malloc.free(clsid);
      malloc.free(iid);
      malloc.free(out);
    }

    // إعداد الصوت العربي + سرعة أبطأ — أي فشل هنا غير قاتل
    try {
      _configureVoice(_voice!);
    } catch (_) {
      // نكمل بالصوت الافتراضي
    }
    return _voice;
  }

  void _configureVoice(Pointer<Void> voice) {
    // سرعة أبطأ قليلاً لصوت واضح (-1)
    _callSetRate(voice, -1);
    // اختيار صوت عربي من الريجستري
    final tokenId = _findArabicVoiceTokenId();
    if (tokenId == null) return;
    _sapi ??= DynamicLibrary.open('sapi.dll');
    final fromId = _sapi!.lookupFunction<_SpTokenFromIdN, _SpTokenFromIdD>(
      'SpObjectTokenFromId',
    );
    final idPtr = tokenId.toNativeUtf16();
    final tokenOut = calloc<Pointer<Void>>();
    try {
      final hr = fromId(idPtr, tokenOut, 0);
      if (hr != _sOk || tokenOut.value == nullptr) return;
      final token = tokenOut.value;
      try {
        _callSetVoice(voice, token);
      } finally {
        _callRelease(token);
      }
    } finally {
      malloc.free(idPtr);
      malloc.free(tokenOut);
    }
  }

  /// يبحث في HKCU/HKLM عن صوت SAPI عربي، مفضلاً ar-SA (0x401).
  /// يُرجع TokenId مثل: HKEY_LOCAL_MACHINE\SOFTWARE\...\Tokens\...
  String? _findArabicVoiceTokenId() {
    const roots = [
      (_hkcu, 'HKEY_CURRENT_USER'),
      (_hklm, 'HKEY_LOCAL_MACHINE'),
    ];
    String? anyArabic;
    for (final (hive, prefix) in roots) {
      final tokensKey =
          '$prefix\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens';
      final names = _enumSubKeys(hive, _stripPrefix(tokensKey));
      for (final name in names) {
        final lang = _queryString(
          hive,
          '${_stripPrefix(tokensKey)}\\$name\\Attributes',
          'Language',
        );
        final parsed = lang == null
            ? null
            : int.tryParse(lang.trim(), radix: 16);
        if (parsed == null) continue;
        if (parsed == _arabicSaudi) return '$tokensKey\\$name';
        if ((parsed & 0x3FF) == _arabicPrimary) {
          anyArabic ??= '$tokensKey\\$name';
        }
      }
    }
    return anyArabic;
  }

  String _stripPrefix(String full) {
    final i = full.indexOf('\\');
    return i < 0 ? full : full.substring(i + 1);
  }

  List<String> _enumSubKeys(int hive, String subKey) {
    final out = <String>[];
    final adv = DynamicLibrary.open('Advapi32.dll');
    final open = adv.lookupFunction<_RegOpenN, _RegOpenD>(
      'RegOpenKeyExW',
    );
    final enumer = adv.lookupFunction<_RegEnumN, _RegEnumD>(
      'RegEnumKeyExW',
    );
    final close = adv.lookupFunction<_RegCloseN, _RegCloseD>(
      'RegCloseKey',
    );
    final subPtr = subKey.toNativeUtf16();
    final hkeyOut = calloc<IntPtr>();
    try {
      if (open(hive, subPtr, 0, _keyRead, hkeyOut) != _sOk) return out;
      final hkey = hkeyOut.value;
      try {
        for (var index = 0; ; index++) {
          final nameBuf = calloc<Uint16>(256);
          final lenBuf = calloc<Uint32>();
          try {
            lenBuf.value = 256;
            final rc = enumer(
              hkey,
              index,
              nameBuf,
              lenBuf,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
            );
            if (rc == _errorNoMoreItems) break;
            if (rc != _sOk) break;
            out.add(nameBuf.cast<Utf16>().toDartString());
          } finally {
            malloc.free(nameBuf);
            malloc.free(lenBuf);
          }
        }
      } finally {
        close(hkey);
      }
    } finally {
      malloc.free(subPtr);
      malloc.free(hkeyOut);
    }
    return out;
  }

  /// يقرأ قيمة REG_SZ. valueName == null يعني القيمة الافتراضية (اسم العرض).
  String? _queryString(int hive, String subKey, String? valueName) {
    final adv = DynamicLibrary.open('Advapi32.dll');
    final open = adv.lookupFunction<_RegOpenN, _RegOpenD>(
      'RegOpenKeyExW',
    );
    final query = adv.lookupFunction<_RegQueryN, _RegQueryD>(
      'RegQueryValueExW',
    );
    final close = adv.lookupFunction<_RegCloseN, _RegCloseD>(
      'RegCloseKey',
    );
    final subPtr = subKey.toNativeUtf16();
    final namePtr = valueName?.toNativeUtf16();
    final hkeyOut = calloc<IntPtr>();
    try {
      if (open(hive, subPtr, 0, _keyRead, hkeyOut) != _sOk) return null;
      final hkey = hkeyOut.value;
      try {
        final typeOut = calloc<Uint32>();
        final lenOut = calloc<Uint32>();
        try {
          lenOut.value = 0;
          var rc = query(
            hkey,
            namePtr ?? nullptr,
            nullptr,
            typeOut,
            nullptr,
            lenOut,
          );
          if (rc != _sOk || typeOut.value != _regSz) return null;
          final chars = (lenOut.value ~/ 2) + 1;
          final buf = calloc<Uint16>(chars);
          try {
            lenOut.value = chars * 2;
            rc = query(
              hkey,
              namePtr ?? nullptr,
              nullptr,
              typeOut,
              buf,
              lenOut,
            );
            if (rc != _sOk) return null;
            return buf.cast<Utf16>().toDartString();
          } finally {
            malloc.free(buf);
          }
        } finally {
          malloc.free(typeOut);
          malloc.free(lenOut);
        }
      } finally {
        close(hkey);
      }
    } finally {
      malloc.free(subPtr);
      if (namePtr != null) malloc.free(namePtr);
      malloc.free(hkeyOut);
    }
  }

  // ── استدعاءات vtable (مواضع ثابتة في ISpVoice) ──────────────

  int _sapiSpeak(
    Pointer<Void> voice,
    Pointer<Utf16>? text,
    int flags,
    Pointer<Uint32>? streamNo,
  ) {
    // ISpVoice::Speak في الموضع 9 من vtable
    final fn = _speakFn(voice);
    return fn(voice, text ?? nullptr, flags, streamNo ?? nullptr);
  }

  void _callSetVoice(Pointer<Void> voice, Pointer<Void> token) {
    _setVoiceFn(voice)(voice, token); // ISpVoice::SetVoice في الموضع 7
  }

  void _callSetRate(Pointer<Void> voice, int rate) {
    _setRateFn(voice)(voice, rate); // ISpVoice::SetRate في الموضع 13
  }

  void _callRelease(Pointer<Void> obj) {
    _releaseFn(obj)(obj); // IUnknown::Release في الموضع 2
  }

  // دوال ملموسة تماماً (FFI يشترط أنواعاً ثابتة وقت الترجمة —
  // لا يمكن تمرير Type Parameters إلى asFunction)
  _SpeakD _speakFn(Pointer<Void> obj) {
    final vtable = obj.cast<Pointer<IntPtr>>().value;
    return Pointer<NativeFunction<_SpeakN>>.fromAddress(
      (vtable + 9).value,
    ).asFunction<_SpeakD>();
  }

  _SetVoiceD _setVoiceFn(Pointer<Void> obj) {
    final vtable = obj.cast<Pointer<IntPtr>>().value;
    return Pointer<NativeFunction<_SetVoiceN>>.fromAddress(
      (vtable + 7).value,
    ).asFunction<_SetVoiceD>();
  }

  _SetRateD _setRateFn(Pointer<Void> obj) {
    final vtable = obj.cast<Pointer<IntPtr>>().value;
    return Pointer<NativeFunction<_SetRateN>>.fromAddress(
      (vtable + 13).value,
    ).asFunction<_SetRateD>();
  }

  _ReleaseD _releaseFn(Pointer<Void> obj) {
    final vtable = obj.cast<Pointer<IntPtr>>().value;
    return Pointer<NativeFunction<_ReleaseN>>.fromAddress(
      (vtable + 2).value,
    ).asFunction<_ReleaseD>();
  }

  // ── (أُزيلت الدالة العامة: FFI يتطلب أنواعاً ملموسة) ─────────────

  Pointer<Uint8> _guid(int d1, int d2, int d3, List<int> d4) {
    final p = calloc<Uint8>(16);
    p.cast<Uint32>()[0] = d1;
    p.cast<Uint16>()[2] = d2;
    p.cast<Uint16>()[3] = d3;
    for (var i = 0; i < 8; i++) {
      p[8 + i] = d4[i];
    }
    return p;
  }

  // ── تحويل مبسط للأرقام إلى كلمات عربية (حتى مليون) ──
  String _amountToArabicWords(double amount) {
    final intPart = amount.floor();
    final fraction = ((amount - intPart) * 100).round();
    var result = _numberToWords(intPart);
    if (fraction > 0) {
      result += ' و${_numberToWords(fraction)} سنتيم';
    }
    return result;
  }

  static const _ones = [
    '',
    'واحد',
    'اثنان',
    'ثلاثة',
    'أربعة',
    'خمسة',
    'ستة',
    'سبعة',
    'ثمانية',
    'تسعة',
    'عشرة',
    'أحد عشر',
    'اثنا عشر',
  ];

  String _numberToWords(int n) {
    if (n == 0) return 'صفر';
    if (n < _ones.length) return _ones[n];
    if (n < 20) return '${_ones[n - 10]} عشر';
    if (n < 100) {
      const tens = [
        'عشرون',
        'ثلاثون',
        'أربعون',
        'خمسون',
        'ستون',
        'سبعون',
        'ثمانون',
        'تسعون',
      ];
      final t = n ~/ 10, o = n % 10;
      if (o == 0) return tens[t - 2];
      return '${_ones[o]} و${tens[t - 2]}';
    }
    if (n < 1000) {
      final h = n ~/ 100, r = n % 100;
      final head = h == 1 ? 'مائة' : h == 2 ? 'مائتان' : '${_ones[h]} مائة';
      if (r == 0) return head;
      return '$head و${_numberToWords(r)}';
    }
    if (n < 1000000) {
      final th = n ~/ 1000, r = n % 1000;
      final head =
          th == 1 ? 'ألف' : th == 2 ? 'ألفان' : '${_numberToWords(th)} آلاف';
      if (r == 0) return head;
      return '$head و${_numberToWords(r)}';
    }
    return n.toString(); // أكبر من مليون: ننطق الأرقام
  }
}

// ── توقيعات FFI ──────────────────────────────────────────────

typedef _CoInitN = Int32 Function(Pointer<Void>, Uint32);
typedef _CoInitD = int Function(Pointer<Void>, int);

typedef _CoCreateN
    = Int32 Function(Pointer<Uint8>, Pointer<Void>, Uint32, Pointer<Uint8>,
        Pointer<Pointer<Void>>);
typedef _CoCreateD
    = int Function(Pointer<Uint8>, Pointer<Void>, int, Pointer<Uint8>,
        Pointer<Pointer<Void>>);

typedef _SpTokenFromIdN
    = Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Int32);
typedef _SpTokenFromIdD
    = int Function(Pointer<Utf16>, Pointer<Pointer<Void>>, int);

typedef _SpeakN
    = Int32 Function(Pointer<Void>, Pointer<Utf16>, Uint32, Pointer<Uint32>);
typedef _SpeakD
    = int Function(Pointer<Void>, Pointer<Utf16>, int, Pointer<Uint32>);

typedef _SetVoiceN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _SetVoiceD = int Function(Pointer<Void>, Pointer<Void>);

typedef _SetRateN = Int32 Function(Pointer<Void>, Int32);
typedef _SetRateD = int Function(Pointer<Void>, int);

typedef _ReleaseN = Uint32 Function(Pointer<Void>);
typedef _ReleaseD = int Function(Pointer<Void>);

typedef _RegOpenN
    = Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _RegOpenD
    = int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>);

typedef _RegEnumN
    = Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>,
        Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _RegEnumD
    = int Function(int, int, Pointer<Uint16>, Pointer<Uint32>, Pointer<Void>,
        Pointer<Void>, Pointer<Void>, Pointer<Void>);

typedef _RegQueryN
    = Int32 Function(IntPtr, Pointer<Utf16>?, Pointer<Void>, Pointer<Uint32>,
        Pointer<Uint16>?, Pointer<Uint32>);
typedef _RegQueryD
    = int Function(int, Pointer<Utf16>?, Pointer<Void>, Pointer<Uint32>,
        Pointer<Uint16>?, Pointer<Uint32>);

typedef _RegCloseN = Int32 Function(IntPtr);
typedef _RegCloseD = int Function(int);
