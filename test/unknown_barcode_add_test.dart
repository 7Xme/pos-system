import 'package:bookstore_pos/core/barcode/barcode_scanner_service.dart';
import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/pos/view/pos_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('الباركود المجهول', () {
    test('مسح باركود غير موجود يضبط missingBarcode ثم يُصفّى', () async {
      final bloc = PosBloc(
        repo: DemoCatalogRepository(),
        checkoutRepo: DemoCheckoutRepository(),
      );
      addTearDown(bloc.close);

      bloc.add(const PosBarcodeScanned('999999'));
      await Future.delayed(const Duration(milliseconds: 150));

      expect(bloc.state.missingBarcode, '999999');
      expect(bloc.state.cart, isEmpty);
      expect(bloc.state.status, PosStatus.ready);

      bloc.add(PosMissingBarcodeHandled());
      await Future.delayed(Duration.zero);
      expect(bloc.state.missingBarcode, isNull);
    });

    testWidgets('نموذج الإضافة السريعة يظهر بالباركود المحفوظ ويُضاف للقاعدة',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      BarcodeScannerService.captureEnabled = true;
      BarcodeScannerService.reset();
      addTearDown(() {
        BarcodeScannerService.captureEnabled = true;
        BarcodeScannerService.reset();
      });

      final db = AppDatabase.memory();
      addTearDown(db.close);

      await tester.pumpWidget(
        RepositoryProvider<AppDatabase>.value(
          value: db,
          child: MaterialApp(
            locale: const Locale('ar'),
            home: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (_) => PosBloc(
                    repo: DriftCatalogRepository(db),
                    checkoutRepo: DriftCheckoutRepository(db),
                  ),
                ),
                BlocProvider(create: (_) => InventoryBloc(db: db)),
                BlocProvider(create: (_) => SettingsCubit(db: db)),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // مسح باركود غير موجود عبر مسار الماسح الحقيقي
      BarcodeScannerService.pushManual('999999');
      await tester.pumpAndSettle();

      // ظهر نموذج الإضافة والباركود معبّأ
      expect(find.text('منتج جديد'), findsOneWidget);
      expect(find.text('999999'), findsWidgets);

      // املأ الاسم والسعر
      await tester.enterText(
        find.widgetWithText(TextFormField, 'اسم المنتج *'),
        'ممحاة',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'سعر البيع *'),
        '3',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('إضافة المنتج'));
      await tester.pumpAndSettle();

      // أُغلق النموذج وحُفظ الصنف في القاعدة
      expect(find.text('منتج جديد'), findsNothing);
      final saved = await db.findByBarcode('999999');
      expect(saved, isNotNull);
      expect(saved!.name, 'ممحاة');
      expect(saved.price, 3);
      expect(saved.stockQty, 1);
    });
  });
}
