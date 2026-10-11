import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/tts/arabic_tts_service.dart' show TtsSource;
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsCubit', () {
    test('القيم الافتراضية عند أول تشغيل', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cubit = SettingsCubit(db: db);
      await cubit.load();
      expect(cubit.state.shopName, 'مكتبة النجاح');
      expect(cubit.state.currency, 'درهم');
      expect(cubit.state.phone, '');
      expect(cubit.state.logoPath, isNull);
      expect(cubit.state.ttsSource, TtsSource.auto);
      expect(cubit.state.soundEnabled, true);
      expect(cubit.state.autoPrint, true);
      await cubit.close();
    });

    test('التحديث يُحفظ ويُسترجع بعد إعادة التحميل', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cubit = SettingsCubit(db: db);
      await cubit.update(
        shopName: 'مكتبة الفجر',
        cashier: 'أحمد',
        currency: 'دينار',
        phone: '0612345678',
        logoPath: () => '/tmp/logo.png',
        soundEnabled: false,
        autoPrint: false,
        ttsSource: TtsSource.online,
      );
      expect(cubit.state.shopName, 'مكتبة الفجر');
      expect(cubit.state.currency, 'دينار');
      expect(cubit.state.phone, '0612345678');
      expect(cubit.state.logoPath, '/tmp/logo.png');
      expect(cubit.state.ttsSource, TtsSource.online);
      expect(cubit.state.soundEnabled, false);

      final cubit2 = SettingsCubit(db: db);
      await cubit2.load();
      expect(cubit2.state.shopName, 'مكتبة الفجر');
      expect(cubit2.state.cashier, 'أحمد');
      expect(cubit2.state.currency, 'دينار');
      expect(cubit2.state.phone, '0612345678');
      expect(cubit2.state.logoPath, '/tmp/logo.png');
      expect(cubit2.state.ttsSource, TtsSource.online);
      expect(cubit2.state.soundEnabled, false);
      expect(cubit2.state.autoPrint, false);
      await cubit.close();
      await cubit2.close();
    });

    test('إزالة الشعار تُخزن كبلا شعار', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cubit = SettingsCubit(db: db);
      await cubit.update(logoPath: () => '/tmp/logo.png');
      expect(cubit.state.logoPath, '/tmp/logo.png');
      await cubit.update(logoPath: () => null);
      expect(cubit.state.logoPath, isNull);

      final cubit2 = SettingsCubit(db: db);
      await cubit2.load();
      expect(cubit2.state.logoPath, isNull);
      await cubit.close();
      await cubit2.close();
    });

    test('المفضلة: تثبيت وإلغاء منتج', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'قلم',
          barcode: '999',
          price: 5,
        ),
      );
      expect(await db.favoriteProducts(), isEmpty);
      expect(await db.setFavorite(id, true), true);
      final favs = await db.favoriteProducts();
      expect(favs.length, 1);
      expect(favs.first.name, 'قلم');
      expect(await db.setFavorite(id, false), true);
      expect(await db.favoriteProducts(), isEmpty);
    });
  });
}
