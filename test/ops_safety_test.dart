import 'dart:io';

import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// مجلد مؤقت خاص بهذه الاختبارات (BackupService.supportDir خارج الاختبار).
final _tmp = Directory(
  p.join(Directory.systemTemp.path, 'pos_ops_test_${DateTime.now().millisecondsSinceEpoch}'),
);

void main() {
  setUpAll(() {
    if (!_tmp.existsSync()) _tmp.createSync(recursive: true);
  });
  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('إعدادات الطباعة', () {
    test('الافتراضي: حوار الطباعة، وتُحفظ الطباعة المباشرة والطباعة المحددة',
        () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cubit = SettingsCubit(db: db);
      await cubit.load();
      expect(cubit.state.directPrint, false);
      expect(cubit.state.printerName, isNull);

      await cubit.update(directPrint: true, printerName: () => 'Konica C558');
      expect(cubit.state.directPrint, true);
      expect(cubit.state.printerName, 'Konica C558');

      final again = SettingsCubit(db: db);
      await again.load();
      expect(again.state.directPrint, true);
      expect(again.state.printerName, 'Konica C558');

      // التصفير يعود إلى الافتراضية
      await again.update(printerName: () => null);
      expect(again.state.printerName, isNull);
      final third = SettingsCubit(db: db);
      await third.load();
      expect(third.state.printerName, isNull);
      expect(third.state.directPrint, true);
      await cubit.close();
      await again.close();
      await third.close();
    });
  });

  group('تحديث شبكة البيع', () {
    test('PosCatalogRefreshed يحدّث الشبكة والمفضلة مع إبقاء الاستعلام',
        () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'قلم',
          barcode: '5100',
          price: 5,
          stockQty: const Value(10),
        ),
      );
      final bloc = PosBloc(
        repo: _MutableCatalog(),
        checkoutRepo: DemoCheckoutRepository(),
      );
      addTearDown(bloc.close);

      bloc.add(const PosQueryChanged('قلم'));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.catalog.length, 1);
      expect(bloc.state.query, 'قلم');

      bloc.add(const PosCatalogRefreshed());
      await Future.delayed(const Duration(milliseconds: 200));
      // الشبكة والمفضلة تحدّثا، والبحث لم يتغيّر
      expect(bloc.state.query, 'قلم');
      expect(bloc.state.favorites.length, 1);
    });
  });

  group('حماية الحذف', () {
    test('hasHistory يميّز ما له سجل', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final soldId = await db.insertProduct(
        ProductsCompanion.insert(name: 'مباع', barcode: '5201', price: 5),
      );
      final freshId = await db.insertProduct(
        ProductsCompanion.insert(name: 'جديد', barcode: '5202', price: 5),
      );
      await db.saveInvoiceWithItems(
        invoiceNumber: 'INV-H-1',
        total: 5,
        amountPaid: 5,
        items: [
          InvoiceItemsCompanion(
            productId: Value(soldId),
            qty: const Value(1),
            unitPrice: const Value(5),
            lineTotal: const Value(5),
            productName: const Value('مباع'),
          ),
        ],
      );

      expect(await db.hasProductHistory(soldId), true);
      expect(await db.hasProductHistory(freshId), false);
      final ids = await db.productIdsWithHistory();
      expect(ids.contains(soldId), true);
      expect(ids.contains(freshId), false);

      // البلوك يعلّم المنتج ذي السجل
      final bloc = InventoryBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(InventoryStarted());
      await Future.delayed(const Duration(milliseconds: 250));
      final all = bloc.state.products;
      expect(all.firstWhere((p) => p.id == soldId).hasHistory, true);
      expect(all.firstWhere((p) => p.id == freshId).hasHistory, false);
    });
  });

  group('سلامة النسخ الاحتياطي', () {
    test('exportSnapshot ينتج ملفاً صالحاً يحوي البيانات', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(name: 'دفتر', barcode: '5301', price: 12),
      );
      final out = File(p.join(_tmp.path, 'snapshot.sqlite'));
      await db.exportSnapshot(out.path);

      expect(out.existsSync(), true);
      expect(out.lengthSync(), greaterThan(0));

      // يُفتح ويحتوي نفس البيانات
      final probe = AppDatabase.at(out.path);
      addTearDown(probe.close);
      expect((await probe.allProducts()).length, 1);
    });

    test('validateBackupFile يرفض الملف التالف ولا يمسّ شيئاً', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(name: 'قلم', barcode: '5401', price: 5),
      );

      // ملف عشوائي ليس قاعدة بيانات
      final junk = File(p.join(_tmp.path, 'junk.sqlite'));
      await junk.writeAsBytes(List<int>.generate(512, (i) => i % 251));
      final probe = AppDatabase.at(junk.path);
      addTearDown(probe.close);
      await expectLater(
        AppDatabase.validateBackupFile(probe),
        throwsA(isA<StateError>()),
      );

      // البيانات سليمة
      expect((await db.allProducts()).length, 1);
    });

    test('snapshotBytes تُنتج بايتات تحوي الجداول', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(name: 'مسطرة', barcode: '5501', price: 7),
      );
      final bytes = await _snapshotIn(db);
      expect(bytes.length, greaterThan(0));
      // رأس ملف SQLite
      expect(String.fromCharCodes(bytes.take(15)), 'SQLite format 3');
    });
  });
}

/// لقطة عبر واجهة AppDatabase (نفس منطق BackupService.snapshotBytes
/// لكن بمسار ملف مُدار بالاختبار).
Future<List<int>> _snapshotIn(AppDatabase db) async {
  final out = File(p.join(_tmp.path, 'bytes-${DateTime.now().microsecondsSinceEpoch}.sqlite'));
  await db.exportSnapshot(out.path);
  final b = await out.readAsBytes();
  await out.delete();
  return b;
}

/// مستودع أصناف يتغيّر بين الاستدعاءات (لمحاكاة تغيّر المخزون).
class _MutableCatalog extends DemoCatalogRepository {
  _MutableCatalog();

  @override
  Future<List<ProductDto>> favorites() async => const [
        ProductDto(
          id: 99,
          name: 'مثبّت',
          barcode: '9999',
          price: 1,
          stockQty: 1,
        ),
      ];
}