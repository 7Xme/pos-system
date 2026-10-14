import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/inventory/view/product_form_dialog.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(AppDatabase db, Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => InventoryBloc(db: db)),
        BlocProvider(
          create: (_) => PosBloc(
            repo: DriftCatalogRepository(db),
            checkoutRepo: DriftCheckoutRepository(db),
          ),
        ),
      ],
      child: child,
    ),
  );
}

Future<int> _insert(
  AppDatabase db, {
  required String name,
  required String barcode,
  List<String> alternates = const [],
  double price = 10,
}) async {
  final id = await db.insertProductWithBarcodes(
    ProductsCompanion.insert(
      name: name,
      barcode: barcode,
      price: price,
      stockQty: const Value(10),
    ),
    [barcode, ...alternates],
  );
  return id;
}

void main() {
  group('باركودات متعددة', () {
    test('حفظ المنتج يكتب كل الباركودات والرئيسي في products.barcode',
        () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await _insert(
        db,
        name: 'كتاب',
        barcode: '978-AAA',
        alternates: ['978-BBB', '12345'],
      );

      final prod = await db.getProduct(id);
      expect(prod!.barcode, '978-AAA'); // الرئيسي
      expect(
        await db.barcodesOf(id),
        ['978-AAA', '978-BBB', '12345'],
      );
    });

    test('المسح بأي باركود إضافي يجد المنتج، والبحث يشمله', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await _insert(
        db,
        name: 'كتاب رياضيات',
        barcode: '9781111111111',
        alternates: ['9782222222222'],
      );

      // المسح بالرئيسي
      expect((await db.findByBarcode('9781111111111'))?.id, id);
      // المسح بالب��ر��ود الإضافي
      expect((await db.findByBarcode('9782222222222'))?.id, id);
      // المسح يتجاهل الفراغات
      expect((await db.findByBarcode('  9782222222222 '))?.id, id);

      // البحث بالب��ر��ود الإضافي
      final found = await db.searchProducts('222222');
      expect(found.map((p) => p.id), contains(id));

      // مستودع نقطة البيع يحمل كل الباركودات
      final dto = await DriftCatalogRepository(db).findByBarcode('9782222222222');
      expect(dto!.allBarcodes, ['9781111111111', '9782222222222']);
    });

    test('تعارض: باركود مستخدم في منتج آخر يُرفض برسالة واضحة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final a = await _insert(db, name: 'منتج أ', barcode: 'AAA');
      await _insert(
        db,
        name: 'منتج ب',
        barcode: 'BBB',
        alternates: ['CCC'],
      );

      // 'CCC' مستخدم بالفعل
      expect((await db.barcodeOwner('CCC'))?.name, 'منتج ب');
      expect(await db.barcodeOwner('CCC', exceptProductId: a), isNotNull);

      var msg = '';
      try {
        await db.setProductBarcodes(a, ['AAA', 'CCC']);
      } catch (e) {
        msg = e.toString();
      }
      expect(msg.contains('CCC'), true);
      expect(msg.contains('منتج ب'), true);
      // لم يتغيّر شيء
      expect((await db.getProduct(a))!.barcode, 'AAA');
    });

    test('تحديث الباركودات: إضافة وحذف ومزامنة الرئيسية', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await _insert(db, name: 'م', barcode: 'P1');

      await db.setProductBarcodes(id, ['P1', 'P2', 'P3']);
      expect(await db.barcodesOf(id), ['P1', 'P2', 'P3']);
      expect((await db.getProduct(id))!.barcode, 'P1');

      // تبديل الرئيسي + حذف واحد + فراغات وتكرار
      await db.setProductBarcodes(id, [' P9 ', 'P1', '', 'P2', 'P9']);
      expect(await db.barcodesOf(id), ['P9', 'P1', 'P2']);
      expect((await db.getProduct(id))!.barcode, 'P9');
      // الباركود القديم P3 لم يعد قابلاً للمسح
      expect(await db.findByBarcode('P3'), isNull);
      expect((await db.findByBarcode('P9'))!.id, id);
    });

    test('InventoryBloc يعلّم الباركودات ويقبل مسودة متعددة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await _insert(
        db,
        name: 'دفتر',
        barcode: 'D1',
        alternates: ['D2'],
      );

      final bloc = InventoryBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(InventoryStarted());
      await Future.delayed(const Duration(milliseconds: 250));
      final p = bloc.state.products.firstWhere((x) => x.id == id);
      expect(p.barcodes, ['D1', 'D2']);
      expect(p.extraBarcodesCount, 1);

      // البحث بالب��ر��ود الإضافي داخل المخزون
      bloc.add(InventoryQueryChanged('D2'));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.products.length, 1);
      expect(bloc.state.products.first.id, id);

      // حفظ بمسودة بباركودين
      bloc.add(InventoryProductSaved(
        ProductDraft(
          id: id,
          name: 'دفتر معدل',
          barcode: 'D2',
          barcodes: ['D2', 'D5'],
          price: 12,
          cost: 6,
          stockQty: 5,
          minStock: 2,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 300));
      final after = bloc.state.products.firstWhere((x) => x.id == id);
      expect(after.barcodes, ['D2', 'D5']);
      expect((await db.getProduct(id))!.barcode, 'D2');
    });

    testWidgets('النموذج يعرض صف باركود جديد ويحفظه', (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      final id = await _insert(db, name: 'قلم قديم', barcode: 'OLD1');

      await tester.pumpWidget(_wrap(db, Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showProductFormDialog(context, null),
          child: const Text('open'),
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('الباركود * (رئيسي)'), findsOneWidget);
      expect(find.text('إضافة باركود آخر'), findsOneWidget);

      // صف واحد افتراضياً
      expect(find.widgetWithText(TextFormField, 'الباركود * (رئيسي)'),
          findsOneWidget);

      // إضافة صف ثانٍ
      await tester.tap(find.text('إضافة باركود آخر'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'باركود إضافي'), findsOneWidget);

      // تعبئة
      await tester.enterText(
        find.widgetWithText(TextFormField, 'الباركود * (رئيسي)'),
        'Q1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'باركود إضافي'),
        'Q2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'اسم المنتج *'),
        'قلم معدني',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'سعر البيع *'),
        '15',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('إضافة المنتج'));
      await tester.pumpAndSettle();
      // انتظار عمل البلوك غير المتزامن (الكتابة في القاعدة)
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      expect(find.text('منتج جديد').evaluate(), isEmpty);

      // حُفظ المنتج الجديد بباركودين
      final all = await db.allProducts();
      final saved = all.firstWhere((p) => p.name == 'قلم معدني');
      expect(saved.barcode, 'Q1');
      expect(await db.barcodesOf(saved.id), ['Q1', 'Q2']);
      // المسح بالباركود الإضافي يجب أن يعطي المنتج الجديد لا غيره
      expect((await db.findByBarcode('Q2'))!.id, saved.id);
      expect(id > 0, true);
    });
  });
}
