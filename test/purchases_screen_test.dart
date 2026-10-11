import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/purchases/bloc/purchases_bloc.dart';
import 'package:bookstore_pos/features/purchases/view/purchases_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('شاشة المشتريات', () {
    testWidgets('تعرض المسودة والأوامر والأزرار', (tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
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
                create: (_) => PurchasesBloc(db: db)
                  ..add(PurchasesStarted()),
              ),
              BlocProvider(
                create: (_) => InventoryBloc(db: db),
              ),
              BlocProvider(
                create: (_) => PosBloc(
                  repo: DemoCatalogRepository(),
                  checkoutRepo: DemoCheckoutRepository(),
                ),
              ),
              BlocProvider(
                create: (_) => SettingsCubit(db: db),
              ),
            ],
            child: const PurchasesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('قوائم المشتريات'), findsOneWidget);
      expect(find.text('إضافة المنخفضة تلقائياً'), findsOneWidget);
      expect(find.text('إضافة منتج'), findsOneWidget);
      expect(find.text('حفظ كأمر شراء'), findsOneWidget);
      expect(find.text('طباعة PDF'), findsOneWidget);
      expect(find.text('أوامر الشراء المحفوظة'), findsOneWidget);
    });
  });
}
