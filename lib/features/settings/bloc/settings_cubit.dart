import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/app_database.dart';
import '../../../core/tts/arabic_tts_service.dart'
    show TtsSource;

/// إعدادات المتجر — تُحفظ في جدول Settings (مفتاح → قيمة)
class ShopSettings extends Equatable {
  final String shopName;
  final String cashier;
  final String currency;
  final String phone;
  final String? logoPath;
  final bool soundEnabled;
  final bool autoPrint;
  final TtsSource ttsSource;

  const ShopSettings({
    this.shopName = 'مكتبة النجاح',
    this.cashier = 'كاشير',
    this.currency = 'درهم',
    this.phone = '',
    this.logoPath,
    this.soundEnabled = true,
    this.autoPrint = true,
    this.ttsSource = TtsSource.auto,
  });

  ShopSettings copyWith({
    String? shopName,
    String? cashier,
    String? currency,
    String? Function()? phone,
    String? Function()? logoPath,
    bool? soundEnabled,
    bool? autoPrint,
    TtsSource? ttsSource,
  }) {
    return ShopSettings(
      shopName: shopName ?? this.shopName,
      cashier: cashier ?? this.cashier,
      currency: currency ?? this.currency,
      phone: phone != null ? phone() ?? '' : this.phone,
      logoPath: logoPath != null ? logoPath() : this.logoPath,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      autoPrint: autoPrint ?? this.autoPrint,
      ttsSource: ttsSource ?? this.ttsSource,
    );
  }

  @override
  List<Object?> get props => [
        shopName,
        cashier,
        currency,
        phone,
        logoPath,
        soundEnabled,
        autoPrint,
        ttsSource,
      ];
}

class SettingsCubit extends Cubit<ShopSettings> {
  final AppDatabase db;
  SettingsCubit({required this.db}) : super(const ShopSettings());

  static const kShop = 'shop_name';
  static const kCashier = 'cashier';
  static const kCurrency = 'currency';
  static const kPhone = 'shop_phone';
  static const kLogo = 'shop_logo';
  static const kSound = 'sound_enabled';
  static const kPrint = 'auto_print';
  static const kTts = 'tts_source';

  static TtsSource parseSource(String? v) =>
      TtsSource.values.asNameMap()[v] ?? TtsSource.auto;

  Future<void> load() async {
    try {
      final logoRaw = await db.getSetting(kLogo);
      emit(ShopSettings(
        shopName: await db.getSetting(kShop) ?? 'مكتبة النجاح',
        cashier: await db.getSetting(kCashier) ?? 'كاشير',
        currency: await db.getSetting(kCurrency) ?? 'درهم',
        phone: await db.getSetting(kPhone) ?? '',
        logoPath:
            (logoRaw == null || logoRaw.isEmpty) ? null : logoRaw,
        soundEnabled: (await db.getSetting(kSound) ?? '1') == '1',
        autoPrint: (await db.getSetting(kPrint) ?? '1') == '1',
        ttsSource: parseSource(await db.getSetting(kTts)),
      ));
    } catch (_) {
      // تبقى القيم الافتراضية
    }
  }

  Future<void> update({
    String? shopName,
    String? cashier,
    String? currency,
    String? phone,
    String? Function()? logoPath,
    bool? soundEnabled,
    bool? autoPrint,
    TtsSource? ttsSource,
  }) async {
    final next = state.copyWith(
      shopName: shopName,
      cashier: cashier,
      currency: currency,
      phone: phone == null ? null : () => phone,
      logoPath: logoPath,
      soundEnabled: soundEnabled,
      autoPrint: autoPrint,
      ttsSource: ttsSource,
    );
    emit(next);
    try {
      await db.setSetting(kShop, next.shopName);
      await db.setSetting(kCashier, next.cashier);
      await db.setSetting(kCurrency, next.currency);
      await db.setSetting(kPhone, next.phone);
      final logo = next.logoPath;
      if (logo == null) {
        // حذف المفتاح عند إزالة الشعار (قيمة فارغة تعني: بلا شعار)
        await db.setSetting(kLogo, '');
      } else {
        await db.setSetting(kLogo, logo);
      }
      await db.setSetting(kSound, next.soundEnabled ? '1' : '0');
      await db.setSetting(kPrint, next.autoPrint ? '1' : '0');
      await db.setSetting(kTts, next.ttsSource.name);
    } catch (_) {
      // التجاهل: الواجهة محدثة والخطأ غير قاتل
    }
  }
}
