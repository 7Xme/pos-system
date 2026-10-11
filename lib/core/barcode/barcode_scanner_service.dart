import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// قارئ الباركود كـ HID (محاكاة لوحة مفاتيح) — التقاط عام.
///
/// يعمل الماسح **تلقائياً دون نقر أي حقل**: المعالج مسجل على
/// `HardwareKeyboard` فيستقبل كل الضغطات مهما كان الفوكس، ويميز المسح
/// عن الكتابة البشرية بالتوقيت (الماسح: ~5-20ms بين الأحرف، البشري: أبطأ).
/// الأحرف المؤكد أنها مسح تُلتهم قبل وصولها للحقول، وبقايا الأحرف الأولى
/// تُمسح من الحقل المركّز عند اكتمال المسح — فلا يتلوث البحث ولا السلة.
///
/// الاستخدام في شاشة POS:
/// ```dart
/// HardwareKeyboard.instance.addHandler(BarcodeScannerService.handleKey);
/// final sub = BarcodeScannerService.stream.listen((code) {
///   context.read<PosBloc>().add(PosBarcodeScanned(code));
/// });
/// ```
class BarcodeScannerService {
  static final _controller = StreamController<String>.broadcast();

  static String _buffer = '';
  static int _exposed = 0; // أحرف وصلت للحقول ويجب مسحها عند المسح
  static bool _allFast = true;
  static DateTime? _lastKeyTime;

  /// مفتاح عام: تُعطّله AppShell خارج شاشة البيع (لأن الشاشات تبقى حيّة
  /// في IndexedStack) حتى لا يلتهم الماسح كتابة شاشات المخزون.
  static bool captureEnabled = true;

  /// أقصى فاصل بين حرفين ليُعتبرا من نفس المسح (الماسح أسرع بكثير).
  static const maxGap = Duration(milliseconds: 45);

  /// أقصر طول يُقبل كباركود ممسوح.
  static const minBarcodeLength = 4;

  /// بعد هذا العدد من الأحرف السريعة نتيقن أنه مسح ونلتهم الباقي.
  static const consumeAfter = 3;

  static Stream<String> get stream => _controller.stream;

  /// يُسجل عبر HardwareKeyboard.instance.addHandler — يُرجع true إذا التهم الحدث.
  static bool handleKey(KeyEvent event) {
    if (!captureEnabled) return false;
    // تكرار زر مضغوط (مفتاح عالق) ليس مسحاً ولا كتابة.
    if (event is KeyRepeatEvent) return false;
    if (event is! KeyDownEvent) return false;

    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter) {
      return _onEnter();
    }

    final char = event.character;
    if (char == null || char.isEmpty) {
      // Shift/Ctrl/Alt قد تسبق رموز الباركود — نتجاهلها دون تصفير.
      if (logical == LogicalKeyboardKey.shiftLeft ||
          logical == LogicalKeyboardKey.shiftRight ||
          logical == LogicalKeyboardKey.controlLeft ||
          logical == LogicalKeyboardKey.controlRight ||
          logical == LogicalKeyboardKey.altLeft ||
          logical == LogicalKeyboardKey.altRight) {
        return false;
      }
      _reset();
      return false;
    }
    if (char.trim().isEmpty) {
      _reset();
      return false;
    }

    final now = DateTime.now();
    final last = _lastKeyTime;
    _lastKeyTime = now;

    if (last == null) {
      // أول حرف: بداية تسلسل محتمل — يمر للحقل مع تذكره.
      _buffer = char;
      _exposed = 1;
      _allFast = true;
      return false;
    }
    if (now.difference(last) > maxGap) {
      // إيقاع بشري: تسلسل جديد من حرف واحد.
      _buffer = char;
      _exposed = 1;
      _allFast = false;
      return false;
    }
    // استمرار سريع: على الأرجح مسح.
    _buffer += char;
    if (_buffer.length <= consumeAfter) {
      _exposed = _buffer.length;
      return false;
    }
    return true; // التهام الأحرف المؤكدة حتى لا تلوث الحقول.
  }

  static bool _onEnter() {
    final code = _buffer.trim();
    final exposed = _exposed;
    final allFast = _allFast;
    _reset();
    if (code.length >= minBarcodeLength && allFast) {
      _stripScannedSuffix(exposed);
      _controller.add(code);
      return true; // نلتهم Enter حتى لا يضغط زراً مركزاً بالخطأ.
    }
    return false;
  }

  /// يمسح بقايا أحرف المسح (التي مرت قبل التيقن) من الحقل المركّز حالياً.
  static void _stripScannedSuffix(int count) {
    if (count <= 0) return;
    try {
      final state = FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (state == null) return;
      final value = state.textEditingValue;
      if (value.text.length < count) return;
      final kept = value.text.substring(0, value.text.length - count);
      state.userUpdateTextEditingValue(
        value.copyWith(
          text: kept,
          selection: TextSelection.collapsed(offset: kept.length),
        ),
        SelectionChangedCause.keyboard,
      );
    } catch (_) {
      // أي عطل هنا لا يجب أن يمنع إضافة الصنف.
    }
  }

  static void _reset() {
    _buffer = '';
    _exposed = 0;
    _allFast = true;
    _lastKeyTime = null;
  }

  /// تصفير الحالة (للاختبارات وعند تبديل الشاشات).
  static void reset() => _reset();

  /// للاختبار اليدوي / المسح عبر الكاميرا لاحقاً.
  static void pushManual(String code) {
    if (code.trim().length >= minBarcodeLength) {
      _controller.add(code.trim());
    }
  }

  static void dispose() => _controller.close();
}
