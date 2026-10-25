// اختبار خدمة استيراد الكتالوج (سكربت الجمع ← قاعدة التطبيق).
//
// التشغيل:
//   flutter test test/product_import_test.dart
//
// ملاحظة: قاعدة البيانات تستعمل مكتبة SQLite الأصلية. على ويندوز يجب توفير
// `sqlite3.dll` في مسار البحث (PATH) قبل التشغيل — نسخة جاهزة تُنتَج مع بناء
// التطبيق في:
//   build\windows\x64\runner\Release\sqlite3.dll
// لذا يُنصح بالتشغيل هكذا:
//   $env:PATH = "$PWD\build\windows\x64\runner\Release;$env:PATH"
//   flutter test test/product_import_test.dart

import 'dart:io';

import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/features/import/import_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pos_import_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {
        // تنظيف اختياري — ويندوز قد يقفل الملفات لحظياً
      }
    }
  });

  /// ينشئ قاعدة مصدر بنفس مخطط Drift (نفس ما ينتجه سكربت الجمع).
  Future<AppDatabase> seedSource({int count = 25}) async {
    final db = AppDatabase.at(p.join(tmp.path, 'source.sqlite'));
    final books = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'كتب مدرسية'),
        );
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'أدوات مكتبية'),
        );

    // صورة وهمية للمنتج الأول لاختبار نسخ الصور
    final img = File(p.join(tmp.path, 'img0.jpg'))..writeAsBytesSync(const <int>[1, 2, 3]);

    for (var i = 0; i < count; i++) {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'منتج رقم $i',
              barcode: 'BC$i',
              price: 10.5 + i,
              cost: const Value(4.0),
              stockQty: const Value(999999),
              categoryId: Value(i.isEven ? books : null),
              imagePath: Value(i == 0 ? img.path : null),
            ),
          );
    }
    // المرآة الأولية للباركودات (كما يفعل سكربت الجمع)
    await db.customStatement(
      'INSERT OR IGNORE INTO product_barcodes (product_id, barcode, sort_order) '
      'SELECT id, barcode, 0 FROM products '
      "WHERE barcode IS NOT NULL AND TRIM(barcode) <> ''",
    );
    return db;
  }

  Future<int> countOf(AppDatabase db, String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  test('يستورد المنتجات والفئات والباركودات ويصلح للتكرار', () async {
    final src = await seedSource(count: 25);
    final target = AppDatabase.at(p.join(tmp.path, 'target.sqlite'));
    await target.customSelect('SELECT 1').get(); // فرض إنشاء الجداول

    final r1 = await ProductImportService.importFrom(
      target: target,
      sourcePath: p.join(tmp.path, 'source.sqlite'),
    );

    expect(r1.cancelled, isFalse);
    expect(r1.productsInserted, 25);
    expect(r1.productsSkipped, 0);
    expect(r1.categoriesCreated, 2);
    expect(await countOf(target, 'products'), 25);
    expect(await countOf(target, 'categories'), 2);
    // كل منتج له باركود مرآة في product_barcodes
    expect(await countOf(target, 'product_barcodes'), 25);

    // القيم الأساسية وصلت سليمة
    final first = await (target.select(target.products)
          ..where((t) => t.barcode.equals('BC7')))
        .getSingle();
    expect(first.name, 'منتج رقم 7');
    expect(first.price, 17.5);
    expect(first.stockQty, 999999);
    expect(first.categoryId, isNull); // 7 فردي ⇒ بلا فئة

    // ── التكرار الآمن: لا إدراج جديد ──
    final r2 = await ProductImportService.importFrom(
      target: target,
      sourcePath: p.join(tmp.path, 'source.sqlite'),
    );
    expect(r2.productsInserted, 0);
    expect(r2.productsSkipped, 25);
    expect(await countOf(target, 'products'), 25);

    await src.close();
    await target.close();
  });

  test('إعادة الاستيراد تملأ الصور الناقصة دون المساس بتعديلات المستخدم',
      () async {
    final src = await seedSource(count: 3);
    final target = AppDatabase.at(p.join(tmp.path, 'target4.sqlite'));

    await ProductImportService.importFrom(
      target: target,
      sourcePath: p.join(tmp.path, 'source.sqlite'),
    );

    // محاكاة استيراد جزئي: صورة ناقصة + تعديل يدوي على الاسم والسعر
    await (target.update(target.products)
          ..where((t) => t.barcode.equals('BC0')))
        .write(
      const ProductsCompanion(
        imagePath: Value(null),
        name: Value('اسم معدّل يدوياً'),
        price: Value(99.0),
      ),
    );

    final r = await ProductImportService.importFrom(
      target: target,
      sourcePath: p.join(tmp.path, 'source.sqlite'),
    );
    expect(r.productsInserted, 0);

    final after = await (target.select(target.products)
          ..where((t) => t.barcode.equals('BC0')))
        .getSingle();
    expect(after.imagePath, isNotNull, reason: 'الصورة الناقصة تُملأ');
    expect(after.name, 'اسم معدّل يدوياً', reason: 'الاسم لا يُستبدل');
    expect(after.price, 99.0, reason: 'السعر لا يُستبدل');

    await src.close();
    await target.close();
  });

  test('ينسخ الصور عند الطلب ويُرجع عددها', () async {
    final src = await seedSource(count: 3);
    final target = AppDatabase.at(p.join(tmp.path, 'target2.sqlite'));
    final imagesDest = p.join(tmp.path, 'copied_images');

    final r = await ProductImportService.importFrom(
      target: target,
      sourcePath: p.join(tmp.path, 'source.sqlite'),
      copyImages: true,
      imagesDestination: imagesDest,
    );

    expect(r.imagesCopied, 1);
    expect(r.imagesMissing, 0);
    expect(Directory(imagesDest).existsSync(), isTrue);
    expect(Directory(imagesDest).listSync().length, 1);

    await src.close();
    await target.close();
  });

  test('يرفض ملفاً ليس قاعدة كتالوج', () async {
    final bogus = File(p.join(tmp.path, 'bogus.sqlite'));
    // قاعدة SQLite صالحة لكنها ليست كتالوجاً (جدول آخر فقط)
    final raw = sqlite.sqlite3.open(bogus.path);
    raw.execute('CREATE TABLE foo (id INTEGER PRIMARY KEY, note TEXT)');
    raw.execute('PRAGMA user_version = 5');
    raw.dispose();

    final target = AppDatabase.at(p.join(tmp.path, 'target3.sqlite'));
    await expectLater(
      ProductImportService.importFrom(
        target: target,
        sourcePath: bogus.path,
      ),
      throwsA(isA<StateError>()),
    );
    await target.close();
  });

  test('يستورد الكتالوج الحقيقي المُجمَّع من الموقع (إن وُجد)', () async {
    final real = File(p.join(Directory.current.path, 'data', 'bookstore_pos.sqlite'));
    if (!real.existsSync()) {
      // ignore: avoid_print
      print('تخطٍّ: data/bookstore_pos.sqlite غير موجود');
      return;
    }
    final probe = AppDatabase.at(real.path);
    final realCount = await ProductImportService.currentProductCount(probe);
    await probe.close();
    final target = AppDatabase.at(p.join(tmp.path, 'real_target.sqlite'));

    final sw = Stopwatch()..start();
    final r = await ProductImportService.importFrom(
      target: target,
      sourcePath: real.path,
    );
    sw.stop();

    // ignore: avoid_print
    print('استيراد حقيقي: المصدر=$realCount مُدرَج=${r.productsInserted} '
        'مُتخطّى=${r.productsSkipped} فئات=${r.categoriesCreated} '
        'الزمن=${sw.elapsedMilliseconds}ms');
    expect(r.productsInserted, realCount);
    expect(await countOf(target, 'products'), realCount);

    await target.close();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
