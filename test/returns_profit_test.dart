import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/core/printing/pdf_profit.dart';
import 'package:bookstore_pos/core/printing/pdf_return.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/sales/bloc/sales_bloc.dart';
import 'package:bookstore_pos/features/sales/view/sales_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(Product, String)> _seedSale(
  AppDatabase db, {
  double price = 20,
  double cost = 12,
  int stock = 10,
  int qty = 3,
}) async {
  final id = await db.insertProduct(
    ProductsCompanion.insert(
      name: 'صنف مرتجع',
      barcode: '6001',
      price: price,
      cost: Value(cost),
      stockQty: Value(stock),
    ),
  );
  final p = (await db.getProduct(id))!;
  final res = await DriftCheckoutRepository(db).checkout(
    [
      CartLine(
        product: ProductDto(
          id: p.id,
          name: p.name,
          barcode: p.barcode,
          price: p.price,
          stockQty: p.stockQty,
        ),
        qty: qty,
      ),
    ],
    price * qty,
  );
  return (p, res.invoiceNumber);
}

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
  group('المرتجعات', () {
    test('البيع يلتقط التكلفة في السطر', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db);
      final inv =
          (await db.searchInvoices(invNo)).first;
      final lines = await db.invoiceItemsOf(inv.id);
      expect(lines.length, 1);
      expect(lines.first.unitCost, p.cost);
      expect((await db.getProduct(p.id))!.stockQty, 7);
    });

    test('إرجاع جزئي: مخزون وحدود ورسائل', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db);
      final invId =
          (await db.searchInvoices(invNo)).first.id;

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      final notices = <String>[];
      final errors = <String>[];
      final sub = bloc.stream.listen((s) {
        if (s.returnNotice != null) notices.add(s.returnNotice!);
        if (s.returnError != null) errors.add(s.returnError!);
      });

      bloc.add(SalesReturnStarted(invId));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.returnCaps[p.id], 3);

      bloc.add(SalesReturnConfirmed(
        invoiceId: invId,
        lines: {p.id: 2},
        reason: 'تالف',
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(notices.length, 1);
      expect((await db.getProduct(p.id))!.stockQty, 9);
      expect(await db.returnedQty(invId, p.id), 2);
      expect(bloc.state.lastReturn, isNotNull);
      expect(bloc.state.lastReturn!.total, 40);

      // تجاوز المتاح مرفوض
      bloc.add(SalesReturnConfirmed(
        invoiceId: invId,
        lines: {p.id: 2},
        reason: '',
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(errors.any((e) => e.contains('لا يمكن إرجاع')), true);
      expect((await db.getProduct(p.id))!.stockQty, 9);

      // إرجاع الباقي ينجح
      bloc.add(SalesReturnConfirmed(
        invoiceId: invId,
        lines: {p.id: 1},
        reason: '',
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      expect((await db.getProduct(p.id))!.stockQty, 10);
      expect(await db.returnedQty(invId, p.id), 3);
      await sub.cancel();
    });

    test('شارة الحالة: كاملة بعد إرجاع الكل وجزئية بعد إرجاع بعض', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db);
      final invId =
          (await db.searchInvoices(invNo)).first.id;

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(const SalesStarted());
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.invoices.first.hasReturns, false);
      expect(bloc.state.invoices.first.isFullyReturned, false);

      bloc.add(SalesReturnConfirmed(
        invoiceId: invId,
        lines: {p.id: 1},
        reason: '',
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      // _onReturnConfirmed يعيد التحميل تلقائياً
      final partial = bloc.state.invoices.first;
      expect(partial.hasReturns, true);
      expect(partial.isFullyReturned, false);
      expect(partial.returnedQty, 1);

      bloc.add(SalesReturnConfirmed(
        invoiceId: invId,
        lines: {p.id: 2},
        reason: '',
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      final full = bloc.state.invoices.first;
      expect(full.hasReturns, true);
      expect(full.isFullyReturned, true);
      expect(full.returnedQty, 3);
    });

    test('الإغلاق يخصم المردودات', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db);
      final invId =
          (await db.searchInvoices(invNo)).first.id;
      await db.createReturn(
        returnNumber: 'RET-T-1',
        invoiceId: invId,
        reason: '',
        items: [
          ReturnItemsCompanion(
            productId: Value(p.id),
            qty: const Value(1),
            unitPrice: const Value(20),
            unitCost: const Value(12),
            lineTotal: const Value(20),
            productName: Value(p.name),
          ),
        ],
      );
      final s = await db.closingSummaryOnDay(DateTime.now());
      expect(s.net, 60);
      expect(s.returns, 20);
    });

    testWidgets('حوار الإرجاع يفتح بعدّادات محكومة بالسقف', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await _seedSale(db);

      await tester.pumpWidget(_wrap(db, const SalesScreen()));
      await tester.pumpAndSettle();

      // زر الإرجاع مباشرة من سطر الفاتورة (دون فتح التفاصيل)
      await tester.tap(find.byTooltip('إرجاع'));
      await tester.pumpAndSettle();
      expect(find.textContaining('إرجاع من'), findsOneWidget);
      expect(find.textContaining('المتاح للإرجاع: 3'), findsOneWidget);

      // زيادة العداد تحدّث الإجمالي
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('إجمالي المرتجع'), findsOneWidget);
      expect(find.textContaining('20.00'), findsWidgets);

      // زر إرجاع الفاتورة كلها يملأ العدادات
      await tester.tap(find.text('إرجاع الفاتورة كلها'));
      await tester.pumpAndSettle();
      expect(find.textContaining('60.00'), findsWidgets);
    });

    testWidgets('الفاتورة المرتجعة بالكامل تحمل شارة وزرها معطّل', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db);
      final invId =
          (await db.searchInvoices(invNo)).first.id;
      await db.createReturn(
        returnNumber: 'RET-BADGE-1',
        invoiceId: invId,
        reason: '',
        items: [
          ReturnItemsCompanion(
            productId: Value(p.id),
            qty: const Value(3),
            unitPrice: const Value(20),
            unitCost: const Value(12),
            lineTotal: const Value(60),
            productName: Value(p.name),
          ),
        ],
      );

      await tester.pumpWidget(_wrap(db, const SalesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('مُرتجعة'), findsOneWidget);
      final btn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('مُرتجعة بالكامل — لا يمكن إرجاعها'),
          matching: find.byType(IconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });
  });

  group('تقرير الأرباح', () {
    test('الربح يشمل المردودات ويستبعد الأسطر بلا تكلفة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final (p, invNo) = await _seedSale(db); // 3×20 إيراد 60، تكلفة 36
      final invId =
          (await db.searchInvoices(invNo)).first.id;
      await db.createReturn(
        returnNumber: 'RET-P-1',
        invoiceId: invId,
        reason: '',
        items: [
          ReturnItemsCompanion(
            productId: Value(p.id),
            qty: const Value(1),
            unitPrice: const Value(20),
            unitCost: const Value(12),
            lineTotal: const Value(20),
            productName: Value(p.name),
          ),
        ],
      );
      // فاتورة قديمة بلا تكلفة مسجلة
      await db.saveInvoiceWithItems(
        invoiceNumber: 'INV-OLD-1',
        total: 50,
        amountPaid: 50,
        items: [
          InvoiceItemsCompanion(
            productId: Value(p.id),
            qty: const Value(1),
            unitPrice: const Value(50),
            lineTotal: const Value(50),
            productName: Value(p.name),
          ),
        ],
      );

      final r = await db.profitInRange(DateTime.now(), DateTime.now());
      expect(r.revenue, 110); // 60 + 50
      expect(r.refunds, 20);
      expect(r.cogs, 36); // القديم مستبعد
      expect(r.cogsReturned, 12);
      expect(r.noCostLines, 1);

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(const SalesProfitRequested());
      await Future.delayed(const Duration(milliseconds: 200));
      final pr = bloc.state.profit!;
      expect(pr.netRevenue, 90);
      expect(pr.profit, 90 - 24);
      expect(pr.noCostLines, 1);
      expect(pr.top.first.name, 'صنف مرتجع');
    });

    test('باني التقرير والإيصال يُبنيان', () async {
      final ret = await PdfReturnBuilder.build(
        shopName: 'مكتبة النجاح',
        returnNumber: 'RET-1',
        invoiceNumber: 'INV-1',
        date: DateTime(2026, 10, 12),
        lines: const [(name: 'قلم', qty: 1, unitPrice: 8, total: 8)],
        total: 8,
      );
      expect(String.fromCharCodes(ret.take(4)), '%PDF');

      final prof = await PdfProfitBuilder.build(
        shopName: 'مكتبة النجاح',
        scopeLabel: 'اليوم',
        revenue: 110,
        refunds: 20,
        cogs: 36,
        cogsReturned: 12,
        noCostLines: 1,
        top: const [(name: 'قلم', qty: 2, profit: 8)],
      );
      expect(String.fromCharCodes(prof.take(4)), '%PDF');
    });

    testWidgets('زر الأرباح يفتح الحوار بالملخص', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await _seedSale(db);

      await tester.pumpWidget(_wrap(db, const SalesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.trending_up_outlined));
      await tester.pumpAndSettle();

      expect(find.text('تقرير الأرباح — اليوم'), findsOneWidget);
      expect(find.textContaining('الربح الإجمالي'), findsWidgets);
    });
  });
}
