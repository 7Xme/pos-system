import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// قاعدة بيانات Drift — SQLite محلي سريع للديسكتوب
@DriftDatabase(
  tables: [
    Categories,
    Products,
    Invoices,
    InvoiceItems,
    PurchaseOrders,
    PurchaseOrderItems,
    Settings,
    Returns,
    ReturnItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// نسخة ذاكرة للاختبارات فقط
  AppDatabase.memory()
      : super(DatabaseConnection(NativeDatabase.memory()));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.isFavorite);
            await m.createTable(settings);
          }
          if (from < 3) {
            await m.addColumn(invoices, invoices.discount);
            await m.addColumn(invoices, invoices.discountType);
            await m.addColumn(invoiceItems, invoiceItems.productName);
          }
          if (from < 4) {
            await m.addColumn(invoiceItems, invoiceItems.unitCost);
            await m.createTable(returns);
            await m.createTable(returnItems);
          }
        },
      );

  // ── استعلامات سريعة للـ POS ─────────────────────────────

  /// بحث بالاسم أو الباركود (للسلة + شاشة البيع)
  Future<List<Product>> searchProducts(String query) {
    if (query.trim().isEmpty) {
      return (select(products)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)])
            ..limit(50))
          .get();
    }
    final q = '%${query.trim()}%';
    return (select(products)
          ..where(
            (t) =>
                t.isActive.equals(true) &
                (t.name.like(q) | t.barcode.like(q)),
          )
          ..limit(50))
        .get();
  }

  Future<Product?> findByBarcode(String barcode) {
    return (select(products)
          ..where(
            (t) => t.barcode.equals(barcode.trim()) & t.isActive.equals(true),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// تنبيه المخزون المنخفض
  Future<List<Product>> lowStockProducts() {
    return (select(products)
          ..where(
            (t) =>
                t.isActive.equals(true) &
                t.stockQty.isSmallerOrEqual(t.minStock),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.stockQty)]))
        .get();
  }

  /// حفظ فاتورة + خصم المخزون في Transaction واحدة (مهم للاستقرار)
  Future<int> saveInvoiceWithItems({
    required String invoiceNumber,
    required double total,
    required double amountPaid,
    required List<InvoiceItemsCompanion> items,
    double discount = 0,
    String discountType = 'amount',
    String? cashier,
    DateTime? createdAt,
  }) {
    return transaction(() async {
      final id = await into(invoices).insert(
        InvoicesCompanion(
          invoiceNumber: Value(invoiceNumber),
          createdAt: createdAt == null
              ? const Value.absent()
              : Value(createdAt),
          total: Value(total),
          discount: Value(discount),
          discountType: Value(discountType),
          amountPaid: Value(amountPaid),
          change: Value(amountPaid - total),
          cashier: Value(
            (cashier ?? '').trim().isEmpty ? 'كاشير' : cashier!.trim(),
          ),
        ),
      );
      for (final item in items) {
        await into(invoiceItems).insert(
          item.copyWith(invoiceId: Value(id)),
        );
        // خصم المخزون
        final prod = await (select(products)
              ..where((t) => t.id.equals(item.productId.value)))
            .getSingle();
        await (update(products)..where((t) => t.id.equals(prod.id))).write(
          ProductsCompanion(
            stockQty: Value(prod.stockQty - item.qty.value),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return id;
    });
  }

  // ── سجل المبيعات (v3) ──────────────────────────────────────

  /// هل رقم الفاتورة مستخدم؟ (لضمان فرادة الرقم عند البيع السريع)
  Future<bool> invoiceNumberExists(String no) async {
    final row = await (select(invoices)
          ..where((t) => t.invoiceNumber.equals(no))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// أحدث الفواتير (الأحدث أولاً) — مع حد أقصى.
  Future<List<Invoice>> recentInvoices({int limit = 100}) {
    return (select(invoices)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// حدود مدة شاملة: [بداية اليوم الأول, بداية اليوم بعد الأخير).
  /// تُرتَّب تلقائياً إن عُكس من/إلى.
  (DateTime, DateTime) _rangeBounds(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    final s = a.isAfter(b) ? b : a;
    final e = (a.isAfter(b) ? a : b).add(const Duration(days: 1));
    return (s, e);
  }

  /// فواتير يوم معيّن (بحسب التاريخ المحلي).
  Future<List<Invoice>> invoicesOnDay(DateTime day) =>
      invoicesInRange(day, day);

  /// فواتير مدة معينة (شاملة اليومين).
  Future<List<Invoice>> invoicesInRange(DateTime from, DateTime to) {
    final (start, end) = _rangeBounds(from, to);
    return (select(invoices)
          ..where(
            (t) =>
                t.createdAt.isBiggerOrEqualValue(start) &
                t.createdAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// سطور فاتورة معيّنة.
  Future<List<InvoiceItem>> invoiceItemsOf(int invoiceId) {
    return (select(invoiceItems)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// بحث برقم الفاتورة (مطابقة جزئية).
  Future<List<Invoice>> searchInvoices(String query, {int limit = 100}) {
    final q = '%${query.trim()}%';
    return (select(invoices)
          ..where((t) => t.invoiceNumber.like(q))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// عدد الأصناف (مجموع الكميات) لكل فاتورة — مفتاح: invoiceId.
  Future<Map<int, int>> invoiceItemCounts() async {
    final counts = <int, int>{};
    final rows = await customSelect(
      'SELECT invoice_id AS iid, COALESCE(SUM(qty), 0) AS q '
      'FROM invoice_items GROUP BY invoice_id',
      readsFrom: {invoiceItems},
    ).get();
    for (final r in rows) {
      counts[r.read<int>('iid')] = r.read<int>('q');
    }
    return counts;
  }

  /// ملخص الإغلاق لمدة معينة (شاملة اليومين) — مع إجمالي المردودات.
  Future<
      ({
        int invoiceCount,
        double gross,
        double discount,
        double net,
        double paid,
        double change,
        int itemsSold,
        double returns,
      })> closingSummaryInRange(DateTime from, DateTime to) async {
    final (start, end) = _rangeBounds(from, to);
    final count = invoices.id.count();
    final net = invoices.total.sum();
    final disc = invoices.discount.sum();
    final paid = invoices.amountPaid.sum();
    final chg = invoices.change.sum();
    final agg = await (selectOnly(invoices)
          ..addColumns([count, net, disc, paid, chg])
          ..where(
            invoices.createdAt.isBiggerOrEqualValue(start) &
                invoices.createdAt.isSmallerThanValue(end),
          ))
        .getSingle();
    final items = await customSelect(
      'SELECT COALESCE(SUM(ii.qty), 0) AS q FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'WHERE i.created_at >= ? AND i.created_at < ?',
      variables: [Variable<DateTime>(start), Variable<DateTime>(end)],
      readsFrom: {invoiceItems, invoices},
    ).getSingle();
    final netVal = agg.read(net) ?? 0.0;
    final discVal = agg.read(disc) ?? 0.0;
    return (
      invoiceCount: agg.read(count) ?? 0,
      gross: netVal + discVal,
      discount: discVal,
      net: netVal,
      paid: agg.read(paid) ?? 0.0,
      change: agg.read(chg) ?? 0.0,
      itemsSold: items.read<int>('q'),
      returns: await returnsTotalInRange(from, to),
    );
  }

  /// ملخص الإغلاق اليومي (يفوّض للمدى).
  Future<
      ({
        int invoiceCount,
        double gross,
        double discount,
        double net,
        double paid,
        double change,
        int itemsSold,
        double returns,
      })> closingSummaryOnDay(DateTime day) =>
      closingSummaryInRange(day, day);

  /// الأعلى مبيعاً في يوم معيّن (بالاسم المحفوظ وقت البيع).
  Future<List<({String name, int qty, double total})>> topProductsOnDay(
    DateTime day, {
    int limit = 5,
  }) =>
      topProductsInRange(day, day, limit: limit);

  /// الأعلى مبيعاً في مدة معينة (شاملة اليومين).
  Future<List<({String name, int qty, double total})>> topProductsInRange(
    DateTime from,
    DateTime to, {
    int limit = 5,
  }) async {
    final (start, end) = _rangeBounds(from, to);
    final rows = await customSelect(
      'SELECT ii.product_name AS name, SUM(ii.qty) AS q, '
      'SUM(ii.line_total) AS t FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'WHERE i.created_at >= ? AND i.created_at < ? '
      'GROUP BY ii.product_name ORDER BY q DESC LIMIT ?',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
        Variable<int>(limit),
      ],
      readsFrom: {invoiceItems, invoices},
    ).get();
    return [
      for (final r in rows)
        (
          name: r.read<String>('name'),
          qty: r.read<int>('q'),
          total: r.read<double>('t'),
        ),
    ];
  }

  /// إجمالي المبيعات ليوم معيّن (صافي بعد الخصم).
  Future<double> salesTotalOnDay(DateTime day) =>
      salesTotalInRange(day, day);

  /// إجمالي المبيعات لمدة معينة (شاملة اليومين).
  Future<double> salesTotalInRange(DateTime from, DateTime to) async {
    final (start, end) = _rangeBounds(from, to);
    final sum = invoices.total.sum();
    final q = selectOnly(invoices)
      ..addColumns([sum])
      ..where(
        invoices.createdAt.isBiggerOrEqualValue(start) &
            invoices.createdAt.isSmallerThanValue(end),
      );
    final row = await q.getSingle();
    return row.read(sum) ?? 0;
  }

  /// إجمالي كل السجل (لمرشح «الكل»).
  Future<double> salesTotalAll() async {
    final sum = invoices.total.sum();
    final row =
        await (selectOnly(invoices)..addColumns([sum])).getSingle();
    return row.read(sum) ?? 0;
  }

  // ── المرتجعات (v4) ────────────────────────────────────────

  /// الكمية المرتجعة سابقاً لصنف في فاتورة.
  Future<int> returnedQty(int invoiceId, int productId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(ri.qty), 0) AS q FROM return_items ri '
      'JOIN returns r ON r.id = ri.return_id '
      'WHERE r.invoice_id = ? AND ri.product_id = ?',
      variables: [Variable<int>(invoiceId), Variable<int>(productId)],
      readsFrom: {returnItems, returns},
    ).getSingle();
    return row.read<int>('q');
  }

  Future<bool> returnNumberExists(String no) async {
    final row = await (select(returns)
          ..where((t) => t.returnNumber.equals(no))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// إنشاء مرتجع جزئي: إدخال + استعادة مخزون (Transaction واحدة).
  /// items: companions بدون returnId (يُملأ هنا).
  /// يرمي StateError برسالة عربية عند مخالفة الكميات.
  Future<int> createReturn({
    required String returnNumber,
    required int invoiceId,
    required String reason,
    String? cashier,
    required List<ReturnItemsCompanion> items,
  }) {
    return transaction(() async {
      final inv = await (select(invoices)
            ..where((t) => t.id.equals(invoiceId)))
          .getSingleOrNull();
      if (inv == null) throw StateError('الفاتورة غير موجودة');
      final sold = <int, InvoiceItem>{};
      for (final l in await invoiceItemsOf(invoiceId)) {
        sold[l.productId] = l;
      }
      var total = 0.0;
      for (final it in items) {
        final pid = it.productId.value;
        final qty = it.qty.value;
        final line = sold[pid];
        if (line == null) throw StateError('صنف غير موجود في الفاتورة');
        if (qty <= 0) throw StateError('كمية الإرجاع يجب أن تكون أكبر من صفر');
        final already = await returnedQty(invoiceId, pid);
        if (already + qty > line.qty) {
          throw StateError(
            'لا يمكن إرجاع $qty من «${line.productName}» — '
            'المباع ${line.qty} والمرتجع سابقاً $already',
          );
        }
        total += it.lineTotal.value;
      }
      if (items.isEmpty) throw StateError('اختر صنفاً واحداً على الأقل');
      final id = await into(returns).insert(
        ReturnsCompanion.insert(
          returnNumber: returnNumber,
          invoiceId: invoiceId,
          reason: Value(reason.trim()),
          total: total,
          cashier: Value(
            (cashier ?? '').trim().isEmpty ? 'كاشير' : cashier!.trim(),
          ),
        ),
      );
      for (final it in items) {
        await into(returnItems).insert(it.copyWith(returnId: Value(id)));
        final prod = await getProduct(it.productId.value);
        if (prod != null) {
          await (update(products)..where((t) => t.id.equals(prod.id))).write(
            ProductsCompanion(
              stockQty: Value(prod.stockQty + it.qty.value),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
      return id;
    });
  }

  /// إجمالي المردودات في مدة (شاملة اليومين).
  Future<double> returnsTotalInRange(DateTime from, DateTime to) async {
    final (start, end) = _rangeBounds(from, to);
    final sum = returns.total.sum();
    final row = await (selectOnly(returns)
          ..addColumns([sum])
          ..where(
            returns.createdAt.isBiggerOrEqualValue(start) &
                returns.createdAt.isSmallerThanValue(end),
          ))
        .getSingle();
    return row.read(sum) ?? 0;
  }

  /// الربحية في مدة: الإيراد والمردودات والتكلفة (للمسجلة تكلفته فقط).
  /// الأسطر بلا تكلفة (unitCost = 0: فواتير ما قبل v4) تُستبعد وتُحصى في
  /// noCostLines — بلا أي تقدير.
  Future<
      ({
        double revenue,
        double refunds,
        double cogs,
        double cogsReturned,
        int noCostLines,
      })> profitInRange(DateTime from, DateTime to) async {
    final (start, end) = _rangeBounds(from, to);
    final vars = [Variable<DateTime>(start), Variable<DateTime>(end)];
    final s = await customSelect(
      'SELECT COALESCE(SUM(ii.line_total), 0) AS rev, '
      'COALESCE(SUM(CASE WHEN ii.unit_cost > 0 '
      'THEN ii.qty * ii.unit_cost ELSE 0 END), 0) AS cogs, '
      'COALESCE(SUM(CASE WHEN ii.unit_cost <= 0 THEN 1 ELSE 0 END), 0) '
      'AS ncost FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'WHERE i.created_at >= ? AND i.created_at < ?',
      variables: vars,
      readsFrom: {invoiceItems, invoices},
    ).getSingle();
    final r = await customSelect(
      'SELECT COALESCE(SUM(rt.total), 0) AS ref, '
      'COALESCE(SUM(CASE WHEN ri.unit_cost > 0 '
      'THEN ri.qty * ri.unit_cost ELSE 0 END), 0) AS cret, '
      'COALESCE(SUM(CASE WHEN ri.unit_cost <= 0 THEN 1 ELSE 0 END), 0) '
      'AS rnc FROM returns rt '
      'JOIN return_items ri ON ri.return_id = rt.id '
      'WHERE rt.created_at >= ? AND rt.created_at < ?',
      variables: vars,
      readsFrom: {returns, returnItems},
    ).getSingle();
    // COALESCE(..., 0) قد يرجع int — نحوّل عبر num بأمان.
    double d(QueryRow row, String k) =>
        (row.data[k] as num?)?.toDouble() ?? 0.0;
    return (
      revenue: d(s, 'rev'),
      refunds: d(r, 'ref'),
      cogs: d(s, 'cogs'),
      cogsReturned: d(r, 'cret'),
      noCostLines:
          s.read<int>('ncost') + r.read<int>('rnc'),
    );
  }

  /// الأعلى ربحاً في مدة (للأسطر ذات التكلفة المسجلة فقط).
  Future<List<({String name, int qty, double profit})>>
      topProfitProductsInRange(
    DateTime from,
    DateTime to, {
    int limit = 5,
  }) async {
    final (start, end) = _rangeBounds(from, to);
    final rows = await customSelect(
      'SELECT ii.product_name AS name, SUM(ii.qty) AS q, '
      'SUM(ii.line_total) - SUM(ii.qty * ii.unit_cost) AS p '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'WHERE i.created_at >= ? AND i.created_at < ? '
      'AND ii.unit_cost > 0 '
      'GROUP BY ii.product_name '
      'ORDER BY p DESC LIMIT ?',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
        Variable<int>(limit),
      ],
      readsFrom: {invoiceItems, invoices},
    ).get();
    return [
      for (final r in rows)
        (
          name: r.read<String>('name'),
          qty: r.read<int>('q'),
          profit: r.read<double>('p'),
        ),
    ];
  }

  // ── إدارة المخزون (منتجات + فئات) ──────────────────────────

  Future<List<Category>> allCategories() {
    return (select(categories)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<int> insertCategory(String name) {
    return into(categories).insert(CategoriesCompanion.insert(name: name));
  }

  Future<bool> updateCategoryName(int id, String name) {
    return (update(categories)..where((t) => t.id.equals(id)))
        .write(CategoriesCompanion(name: Value(name)))
        .then((n) => n > 0);
  }

  Future<int> deleteCategory(int id) {
    // ملاحظة: المفتاح الأجنبي للمنتجات NO ACTION — يجب التأكد من خلو
    // الفئة من المنتجات قبل الحذف (يفعل ذلك InventoryBloc).
    return (delete(categories)..where((t) => t.id.equals(id))).go();
  }

  Future<Map<int, int>> productCountByCategory() async {
    final counts = <int, int>{};
    final rows = await customSelect(
      'SELECT category_id AS cid, COUNT(*) AS c FROM products '
      'WHERE category_id IS NOT NULL GROUP BY category_id',
      readsFrom: {products},
    ).get();
    for (final r in rows) {
      counts[r.read<int>('cid')] = r.read<int>('c');
    }
    return counts;
  }

  Future<List<Product>> allProducts() {
    return (select(products)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Product?> getProduct(int id) {
    return (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertProduct(ProductsCompanion entry) {
    return into(products).insert(entry);
  }

  Future<bool> updateProduct(int id, ProductsCompanion entry) {
    return (update(products)..where((t) => t.id.equals(id)))
        .write(entry)
        .then((n) => n > 0);
  }

  Future<int> deleteProduct(int id) {
    return (delete(products)..where((t) => t.id.equals(id))).go();
  }

  /// هل للمنتج سجل (فواتير أو أوامر شراء)؟ — يمنع حذفه للحفاظ على السجل.
  Future<bool> hasProductHistory(int id) async {
    final sale = await (select(invoiceItems)
          ..where((t) => t.productId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (sale != null) return true;
    final po = await (select(purchaseOrderItems)
          ..where((t) => t.productId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return po != null;
  }

  // ── المفضلة (أزرار الاختصار) + الإعدادات — v2 ────────────

  Future<bool> setFavorite(int id, bool favorite) {
    return (update(products)..where((t) => t.id.equals(id)))
        .write(ProductsCompanion(isFavorite: Value(favorite)))
        .then((n) => n > 0);
  }

  Future<List<Product>> favoriteProducts() {
    return (select(products)
          ..where((t) => t.isActive.equals(true) & t.isFavorite.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<String?> getSetting(String key) {
    return (select(settings)..where((t) => t.key.equals(key)))
        .map((r) => r.value)
        .getSingleOrNull();
  }

  Future<void> setSetting(String key, String value) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  // ── أوامر الشراء (قوائم المشتريات) ─────────────────────────

  /// إنشاء أمر شراء مع سطوره في Transaction واحدة. يُرجع id الأمر.
  Future<int> createPurchaseOrder({
    required String poNumber,
    required String supplierName,
    String? supplierPhone,
    required List<PurchaseOrderItemsCompanion> items,
  }) {
    return transaction(() async {
      var total = 0.0;
      for (final it in items) {
        total += it.qtyOrdered.value * it.unitCost.value;
      }
      final id = await into(purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          poNumber: poNumber,
          supplierName: Value(supplierName),
          supplierPhone: Value(supplierPhone),
          totalCost: Value(total),
        ),
      );
      for (final item in items) {
        await into(purchaseOrderItems).insert(
          item.copyWith(poId: Value(id)),
        );
      }
      return id;
    });
  }

  /// هل رقم أمر الشراء مستخدم؟ (لضمان فرادة الرقم)
  Future<bool> poNumberExists(String no) async {
    final row = await (select(purchaseOrders)
          ..where((t) => t.poNumber.equals(no))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<PurchaseOrder>> allPurchaseOrders() {
    return (select(purchaseOrders)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<List<PurchaseOrderItem>> itemsOfOrder(int poId) {
    return (select(purchaseOrderItems)
          ..where((t) => t.poId.equals(poId)))
        .get();
  }

  Future<Map<int, int>> purchaseItemCounts() async {
    final counts = <int, int>{};
    final rows = await customSelect(
      'SELECT po_id AS pid, COUNT(*) AS c FROM purchase_order_items '
      'GROUP BY po_id',
      readsFrom: {purchaseOrderItems},
    ).get();
    for (final r in rows) {
      counts[r.read<int>('pid')] = r.read<int>('c');
    }
    return counts;
  }

  /// استلام أمر شراء: زيادة المخزون بالكميات المطلوبة وإغلاق الأمر.
  /// آمن ضد التكرار: الأمر المستلم مسبقاً لا يغيّر شيئاً.
  /// يحدّث سعر الشراء بالمتوسط المرجح مع المخزون الحالي.
  Future<void> receivePurchaseOrder(int poId) {
    return transaction(() async {
      final order = await (select(purchaseOrders)
            ..where((t) => t.id.equals(poId)))
          .getSingleOrNull();
      if (order == null || order.status == 'received') return;
      final items = await (select(purchaseOrderItems)
            ..where((t) => t.poId.equals(poId)))
          .get();
      for (final it in items) {
        final prod = await (select(products)
              ..where((t) => t.id.equals(it.productId)))
            .getSingleOrNull();
        if (prod == null) continue;
        final newQty = prod.stockQty + it.qtyOrdered;
        final newCost = newQty <= 0
            ? it.unitCost
            : (prod.stockQty * prod.cost + it.qtyOrdered * it.unitCost) /
                newQty;
        await (update(products)..where((t) => t.id.equals(prod.id))).write(
          ProductsCompanion(
            stockQty: Value(newQty),
            cost: Value(newCost),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await (update(purchaseOrderItems)
              ..where((t) => t.id.equals(it.id)))
            .write(
          PurchaseOrderItemsCompanion(
            qtyReceived: Value(it.qtyOrdered),
          ),
        );
      }
      await (update(purchaseOrders)..where((t) => t.id.equals(poId))).write(
        const PurchaseOrdersCompanion(
          status: Value('received'),
        ),
      );
    });
  }

  Future<int> deletePurchaseOrder(int id) {
    return (delete(purchaseOrders)..where((t) => t.id.equals(id))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'bookstore_pos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
