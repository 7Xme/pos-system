import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/core/printing/pdf_closing.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/purchases/bloc/purchases_bloc.dart';
import 'package:bookstore_pos/features/sales/bloc/sales_bloc.dart';
import 'package:bookstore_pos/features/sales/view/sales_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Product> _seedProduct(
  AppDatabase db, {
  String name = 'قلم',
  String barcode = '7001',
  double price = 10,
  double cost = 10,
  int stock = 100,
}) async {
  final id = await db.insertProduct(
    ProductsCompanion.insert(
      name: name,
      barcode: barcode,
      price: price,
      cost: Value(cost),
      stockQty: Value(stock),
    ),
  );
  return (await db.getProduct(id))!;
}

CartLine _line(Product p, int qty) => CartLine(
      product: ProductDto(
        id: p.id,
        name: p.name,
        barcode: p.barcode,
        price: p.price,
        stockQty: p.stockQty,
      ),
      qty: qty,
    );

void main() {
  group('A1 — فرادة رقم الفاتورة/أمر الشراء', () {
    test('المولد: نفس اللحظة رقم واحد، والمحاولة لاحقة مختلفة', () {
      final now = DateTime(2026, 10, 12, 21, 30, 15, 250);
      expect(nextInvoiceNumber(now), nextInvoiceNumber(now));
      expect(nextInvoiceNumber(now, 1) == nextInvoiceNumber(now), false);
      expect(nextPoNumber(now), nextPoNumber(now));
      expect(nextPoNumber(now, 2).endsWith('-2'), true);
      // المللي ثانية جزء من الرقم
      expect(nextInvoiceNumber(now).contains('250'), true);
    });

    test('بيعان متتاليان ينجحان برقمين مختلفين', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final p = await _seedProduct(db);
      final repo = DriftCheckoutRepository(db);

      final r1 = await repo.checkout([_line(p, 1)], 10);
      final r2 = await repo.checkout([_line(p, 1)], 10);

      expect(r1.invoiceNumber == r2.invoiceNumber, false);
      expect(await db.invoiceNumberExists(r1.invoiceNumber), true);
      expect(await db.invoiceNumberExists(r2.invoiceNumber), true);
      expect((await db.recentInvoices()).length, 2);
    });
  });

  group('A2 — حماية الحذف', () {
    test('حذف منتج له سجل مبيعات مرفوض برسالة ويبقى المنتج', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final p = await _seedProduct(db);
      await db.saveInvoiceWithItems(
        invoiceNumber: 'INV-HIST-1',
        total: 20,
        amountPaid: 20,
        items: [
          InvoiceItemsCompanion(
            productId: Value(p.id),
            qty: const Value(2),
            unitPrice: const Value(10),
            lineTotal: const Value(20),
            productName: Value(p.name),
          ),
        ],
      );

      final bloc = InventoryBloc(db: db);
      addTearDown(bloc.close);
      final errors = <String>[];
      final sub = bloc.stream.listen((s) {
        if (s.error != null) errors.add(s.error!);
      });
      bloc.add(InventoryProductDeleted(p.id));
      await Future.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(errors.any((e) => e.contains('سجل')), true);
      expect(await db.getProduct(p.id), isNotNull);
    });

    test('حذف فئة فيها منتجات مرفوض برسالة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final catId = await db.insertCategory('قرطاسية');
      final pid = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'مسطرة',
          barcode: '7002',
          price: 5,
          categoryId: Value(catId),
        ),
      );
      expect(pid > 0, true);

      final bloc = InventoryBloc(db: db);
      addTearDown(bloc.close);
      final errors = <String>[];
      final sub = bloc.stream.listen((s) {
        if (s.error != null) errors.add(s.error!);
      });
      bloc.add(InventoryCategoryDeleted(catId));
      await Future.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(errors.any((e) => e.contains('منتج')), true);
      expect(
        (await db.allCategories()).any((c) => c.id == catId),
        true,
      );
    });
  });

  group('A3 — الكاشير', () {
    test('اسم الكاشير يُحفظ في الفاتورة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final p = await _seedProduct(db);
      await DriftCheckoutRepository(db).checkout(
        [_line(p, 1)],
        10,
        cashier: 'أحمد',
      );
      final inv = (await db.recentInvoices()).first;
      expect(inv.cashier, 'أحمد');
    });
  });

  group('A4 — أمان الاستلام والتكلفة', () {
    test('الاستلام المزدوج يضيف المخزون مرة واحدة ويحدّث التكلفة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final p = await _seedProduct(db, stock: 10, cost: 10);
      await db.createPurchaseOrder(
        poNumber: 'PO-RCV-1',
        supplierName: 'مورد',
        items: [
          PurchaseOrderItemsCompanion(
            productId: Value(p.id),
            qtyOrdered: const Value(5),
            unitCost: const Value(20),
          ),
        ],
      );
      final order =
          (await db.allPurchaseOrders()).firstWhere((o) => o.poNumber == 'PO-RCV-1');

      await db.receivePurchaseOrder(order.id);
      await db.receivePurchaseOrder(order.id); // تكرار يجب أن لا يؤثر

      final after = await db.getProduct(p.id);
      expect(after!.stockQty, 15); // 10 + 5 مرة واحدة
      // المتوسط المرجح: (10×10 + 5×20) / 15
      expect(after.cost, moreOrLessEquals(200 / 15, epsilon: 0.001));
      final reloaded =
          (await db.allPurchaseOrders()).firstWhere((o) => o.id == order.id);
      expect(reloaded.status, 'received');
    });
  });

  group('B — تقرير الإغلاق اليومي', () {
    Future<void> seedSales(AppDatabase db) async {
      final a = await _seedProduct(db, name: 'صنف أ', barcode: '8001');
      final b = await _seedProduct(db, name: 'صنف ب', barcode: '8002');
      InvoiceItemsCompanion item(int pid, int q, double u) =>
          InvoiceItemsCompanion(
            productId: Value(pid),
            qty: Value(q),
            unitPrice: Value(u),
            lineTotal: Value(q * u),
            productName: Value(pid == a.id ? 'صنف أ' : 'صنف ب'),
          );
      await db.saveInvoiceWithItems(
        invoiceNumber: 'INV-CLOSE-1',
        total: 100,
        amountPaid: 100,
        discount: 10,
        discountType: 'amount',
        items: [item(a.id, 3, 20), item(b.id, 2, 20)],
      );
      await db.saveInvoiceWithItems(
        invoiceNumber: 'INV-CLOSE-2',
        total: 50,
        amountPaid: 60,
        items: [item(a.id, 1, 50)],
      );
    }

    test('المجاميع والأعلى مبيعاً صحيحة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seedSales(db);

      final s = await db.closingSummaryOnDay(DateTime.now());
      expect(s.invoiceCount, 2);
      expect(s.net, 150);
      expect(s.discount, 10);
      expect(s.gross, 160);
      expect(s.paid, 160);
      expect(s.change, 10);
      expect(s.itemsSold, 6);

      final top = await db.topProductsOnDay(DateTime.now());
      expect(top.length, 2);
      expect(top.first.name, 'صنف أ');
      expect(top.first.qty, 4);
    });

    test('SalesBloc يجمّع الإغلاق عند الطلب', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seedSales(db);

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(const SalesClosingRequested());
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.closingLoading, false);
      expect(bloc.state.closing, isNotNull);
      expect(bloc.state.closing!.net, 150);
      expect(bloc.state.closing!.invoiceCount, 2);
    });

    test('PDF الإغلاق يُبنى', () async {
      final bytes = await PdfClosingBuilder.build(
        shopName: 'مكتبة النجاح',
        date: DateTime(2026, 10, 12),
        summary: const ClosingSummaryData(
          invoiceCount: 2,
          gross: 160,
          discount: 10,
          net: 150,
          paid: 160,
          change: 10,
          itemsSold: 6,
          top: [(name: 'صنف أ', qty: 4, total: 110)],
        ),
      );
      expect(bytes.isNotEmpty, true);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('زر التقرير يفتح الحوار بالملخص', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seedSales(db);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => SalesBloc(db: db)),
              BlocProvider(create: (_) => SettingsCubit(db: db)..load()),
            ],
            child: const SalesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.summarize_outlined));
      await tester.pumpAndSettle();

      expect(find.text('تقرير الإغلاق — اليوم'), findsOneWidget);
      expect(find.textContaining('الصافي'), findsWidgets);
      expect(find.textContaining('150.00'), findsWidgets);
    });
  });
}
