import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:bookstore_pos/features/sales/bloc/sales_bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyDiscount', () {
    test('مبلغ ثابت يُطرح ويُقصّ عند الإجمالي', () {
      expect(applyDiscount(100, 20, 'amount'), 80);
      expect(applyDiscount(100, 250, 'amount'), 0);
    });

    test('نسبة مئوية تُحسب من الإجمالي وتُقصّ عند 100', () {
      expect(applyDiscount(200, 10, 'percent'), 180);
      expect(applyDiscount(200, 150, 'percent'), 0);
    });

    test('قيمة صفر أو سالبة = بلا خصم', () {
      expect(applyDiscount(50, 0, 'amount'), 50);
      expect(applyDiscount(50, -5, 'percent'), 50);
    });
  });

  group('PosBloc الخصم', () {
    test('تغيير الخصم يحدّث الصافي ويُصفَّر بعد إتمام البيع', () async {
      final bloc = PosBloc(
        repo: DemoCatalogRepository(),
        checkoutRepo: DemoCheckoutRepository(),
      );
      addTearDown(bloc.close);
      bloc.add(PosStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<PosState>((s) => s.status == PosStatus.ready)),
      );

      // مسطرة 30 سم = 12 درهم
      bloc.add(const PosBarcodeScanned('100005'));
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<PosState>((s) => s.cart.isNotEmpty)),
      );
      expect(bloc.state.total, 12);

      bloc.add(const PosDiscountChanged(2, 'amount'));
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<PosState>((s) => s.total == 10)),
      );
      expect(bloc.state.subtotal, 12);
      expect(bloc.state.discountAmount, 2);

      bloc.add(PosCheckout(10));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PosState>(
            (s) =>
                s.status == PosStatus.checkoutSuccess &&
                s.lastTotal == 10 &&
                s.lastSubtotal == 12 &&
                s.discountValue == 0,
          ),
        ),
      );
    });
  });

  group('Checkout المخزون والخصم', () {
    Future<AppDatabase> seedDb() async {
      final db = AppDatabase.memory();
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'قلم',
          barcode: '701',
          price: 8,
          stockQty: const Value(3),
        ),
      );
      return db;
    }

    test('يرفض البيع عند عدم كفاية المخزون', () async {
      final db = await seedDb();
      addTearDown(db.close);
      final repo = DriftCheckoutRepository(db);
      final p = await db.findByBarcode('701');
      final cart = [
        CartLine(product: ProductDto(
          id: p!.id,
          name: p.name,
          barcode: p.barcode,
          price: p.price,
          stockQty: p.stockQty,
        ), qty: 5),
      ];
      await expectLater(
        repo.checkout(cart, 100),
        throwsA(isA<StateError>()),
      );
      // المخزون لم يتغير
      expect((await db.findByBarcode('701'))!.stockQty, 3);
    });

    test('يحفظ الخصم واسم الصنف ويخصم المخزون', () async {
      final db = await seedDb();
      addTearDown(db.close);
      final repo = DriftCheckoutRepository(db);
      final p = await db.findByBarcode('701');
      final cart = [
        CartLine(product: ProductDto(
          id: p!.id,
          name: p.name,
          barcode: p.barcode,
          price: p.price,
          stockQty: p.stockQty,
        ), qty: 2),
      ];
      final res = await repo.checkout(cart, 16, discount: 2, discountType: 'amount');
      expect(res.total, 14);
      final inv = (await db.recentInvoices()).first;
      expect(inv.discount, 2);
      expect(inv.total, 14);
      final items = await db.invoiceItemsOf(inv.id);
      expect(items.single.productName, 'قلم');
      expect((await db.findByBarcode('701'))!.stockQty, 1);
    });
  });

  group('SalesBloc', () {
    test('يحمّل فواتير اليوم ويحسب الإجمالي ويفتح التفاصيل', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'كراسة',
          barcode: '801',
          price: 10,
          stockQty: const Value(50),
        ),
      );
      final p = await db.findByBarcode('801');
      final repo = DriftCheckoutRepository(db);
      await repo.checkout(
        [
          CartLine(product: ProductDto(
            id: p!.id,
            name: p.name,
            barcode: p.barcode,
            price: p.price,
            stockQty: p.stockQty,
          ), qty: 3),
        ],
        30,
      );

      final bloc = SalesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(const SalesStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<SalesState>(
            (s) => s.status == SalesStatus.ready && s.invoices.isNotEmpty,
          ),
        ),
      );
      expect(bloc.state.dayTotal, 30);
      expect(bloc.state.invoices.first.itemCount, 3);

      final id = bloc.state.invoices.first.invoice.id;
      bloc.add(SalesInvoiceOpened(id));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<SalesState>((s) => s.selectedItems.length == 1),
        ),
      );
      expect(bloc.state.selectedItems.first.productName, 'كراسة');
    });
  });
}
