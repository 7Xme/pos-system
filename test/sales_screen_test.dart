import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/sales/bloc/sales_bloc.dart';
import 'package:bookstore_pos/features/sales/view/sales_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(AppDatabase db, Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SalesBloc(db: db)),
        BlocProvider(create: (_) => SettingsCubit(db: db)..load()),
      ],
      child: child,
    ),
  );
}

void main() {
  group('شاشة سجل المبيعات', () {
    testWidgets('تعرض فاتورة محفوظة وتفتح التفاصيل', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'كراسة 100 ورقة',
          barcode: '5001',
          price: 25,
          stockQty: const Value(40),
        ),
      );
      final p = await db.findByBarcode('5001');
      final inv = await DriftCheckoutRepository(db).checkout(
        [
          CartLine(
            product: ProductDto(
              id: p!.id,
              name: p.name,
              barcode: p.barcode,
              price: p.price,
              stockQty: p.stockQty,
            ),
            qty: 2,
          ),
        ],
        50,
        discount: 0,
      );

      await tester.pumpWidget(_wrap(db, const SalesScreen()));
      await tester.pumpAndSettle();

      // رقم الفاتورة + إجمالي اليوم
      expect(find.text(inv.invoiceNumber), findsOneWidget);
      expect(find.textContaining('مبيعات اليوم'), findsOneWidget);
      expect(find.text('50.00 درهم'), findsWidgets);

      // فتح التفاصيل يعرض اسم الصنف وزر إعادة الطباعة
      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('كراسة 100 ورقة'), findsWidgets);
      expect(find.text('إعادة طباعة'), findsOneWidget);
    });
  });
}
