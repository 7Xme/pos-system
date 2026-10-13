import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/features/sales/bloc/sales_bloc.dart';
import 'package:bookstore_pos/features/sales/view/sales_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedDay(
  AppDatabase db,
  DateTime day, {
  required String invNo,
  required double total,
  String barcode = '9001',
}) async {
  if (await db.findByBarcode(barcode) == null) {
    await db.insertProduct(
      ProductsCompanion.insert(
        name: 'صنف $barcode',
        barcode: barcode,
        price: total,
        stockQty: const Value(50),
      ),
    );
  }
  final p = await db.findByBarcode(barcode);
  await db.saveInvoiceWithItems(
    invoiceNumber: invNo,
    total: total,
    amountPaid: total,
    createdAt: day,
    items: [
      InvoiceItemsCompanion(
        productId: Value(p!.id),
        qty: const Value(1),
        unitPrice: Value(total),
        lineTotal: Value(total),
        productName: Value(p.name),
      ),
    ],
  );
}

void main() {
  group('فلتر التاريخ في سجل المبيعات', () {
    test('يوم/مدة/كل/مسح + الإغلاق يتبع الفلتر', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final yesterday = today.subtract(const Duration(days: 1));
      await _seedDay(db, today, invNo: 'INV-D-1', total: 100);
      await _seedDay(
        db,
        yesterday,
        invNo: 'INV-D-2',
        total: 40,
        barcode: '9002',
      );

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(const SalesStarted());
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.length, 1);
      expect(bloc.state.dayTotal, 100);
      expect(bloc.state.filter.totalLabel, 'مبيعات اليوم:');

      bloc.add(SalesDaySelected(yesterday));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.length, 1);
      expect(
        bloc.state.invoices.first.invoice.invoiceNumber,
        'INV-D-2',
      );
      expect(bloc.state.dayTotal, 40);
      expect(bloc.state.filter.isCustom, true);
      expect(bloc.state.filter.chipLabel.isNotEmpty, true);

      bloc.add(SalesClosingRequested());
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.closing, isNotNull);
      expect(bloc.state.closing!.net, 40);
      expect(bloc.state.closing!.label, bloc.state.filter.closingScope);

      bloc.add(SalesRangeSelected(yesterday, today));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.length, 2);
      expect(bloc.state.dayTotal, 140);

      bloc.add(SalesModeChanged(false));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.length, 2);
      expect(bloc.state.dayTotal, 140);
      expect(bloc.state.filter.isAll, true);

      bloc.add(const SalesFilterReset());
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.length, 1);
      expect(bloc.state.dayTotal, 100);
      expect(bloc.state.filter.isToday, true);
    });

    testWidgets('زر التقويم يعرض القائمة والشارة تظهر مع الفلتر',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      final now = DateTime.now();
      await _seedDay(
        db,
        DateTime(now.year, now.month, now.day, 12),
        invNo: 'INV-W-1',
        total: 25,
      );

      SalesBloc? bloc;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) {
                  final b = SalesBloc(db: db);
                  bloc = b;
                  return b;
                },
              ),
              BlocProvider(create: (_) => SettingsCubit(db: db)..load()),
            ],
            child: const SalesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // زر التقويم يفتح قائمة الخيارات
      await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('فلتر التاريخ'), findsOneWidget);
      expect(find.text('يوم محدد'), findsOneWidget);
      expect(find.textContaining('مدة معينة'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // فلتر يوم يعرض الشارة والقائمة المفلترة
      final yesterday = now.subtract(const Duration(days: 1));
      bloc!.add(SalesDaySelected(yesterday));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('لا توجد فواتير.'), findsOneWidget);

      // المسح من الشارة يعيد اليوم
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('INV-W-1'), findsOneWidget);
    });
  });
}
