import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/pos/view/pos_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FavDemoRepo extends DemoCatalogRepository {
  @override
  Future<List<ProductDto>> favorites() async => [
        const ProductDto(
          id: 1,
          name: 'كراسة 100 ورقة',
          barcode: '100001',
          price: 25,
          stockQty: 120,
        ),
      ];
}

void main() {
  group('أزرار الاختصار في البيع', () {
    testWidgets('الشريط يظهر المثبتة والضغط يضيف للسلة', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => PosBloc(
                  repo: _FavDemoRepo(),
                  checkoutRepo: DemoCheckoutRepository(),
                ),
              ),
              BlocProvider(
                create: (_) => SettingsCubit(db: db),
              ),
            ],
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // زر الاختصار موجود
      expect(find.text('كراسة 100 ورقة — 25'), findsOneWidget);

      // الضغط يضيف للسلة
      await tester.tap(find.text('كراسة 100 ورقة — 25'));
      await tester.pumpAndSettle();
      expect(find.textContaining('الإجمالي: 25.00'), findsWidgets);
    });

    testWidgets('الفوكس يبقى في حقل الباركود بعد الإدخال + Enter',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => PosBloc(
                  repo: _FavDemoRepo(),
                  checkoutRepo: DemoCheckoutRepository(),
                ),
              ),
              BlocProvider(
                create: (_) => SettingsCubit(db: db),
              ),
            ],
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('barcodeField'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '100001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // أُضيف الصنف للسلة...
      expect(find.textContaining('الإجمالي: 25.00'), findsWidgets);
      // ...وبقي الفوكس في حقل الباركود جاهزاً للعملية التالية
      final node =
          tester.widget<TextField>(field).focusNode;
      expect(node?.hasFocus, true);
    });

    testWidgets('مسار الصورة يصل من القاعدة إلى بطاقة البيع', (tester) async {
      // تحقق منطقي (بدون فك صورة حقيقية — فك الصور يعلّق بيئة الاختبار):
      // المنتج المحفوظ بمسار صورة يرجعه المستودع كما هو لتعرضه البطاقة.
      final db = AppDatabase.memory();
      addTearDown(db.close);
      const fakePath = 'C:/fake/product.png';
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'منتج بصورة',
          barcode: '700001',
          price: 10,
          imagePath: const Value(fakePath),
        ),
      );
      final repo = DriftCatalogRepository(db);
      final found = await repo.findByBarcode('700001');
      expect(found?.imagePath, fakePath);
      final all = await repo.search('');
      expect(all.firstWhere((p) => p.barcode == '700001').imagePath, fakePath);
    });
  });
}
