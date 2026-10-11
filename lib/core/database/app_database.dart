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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// نسخة ذاكرة للاختبارات فقط
  AppDatabase.memory()
      : super(DatabaseConnection(NativeDatabase.memory()));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.isFavorite);
            await m.createTable(settings);
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
  }) {
    return transaction(() async {
      final id = await into(invoices).insert(
        InvoicesCompanion(
          invoiceNumber: Value(invoiceNumber),
          total: Value(total),
          amountPaid: Value(amountPaid),
          change: Value(amountPaid - total),
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
    // المنتجات المرتبطة تصبح بدون فئة (SET NULL حسب المخطط)
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
  Future<void> receivePurchaseOrder(int poId) {
    return transaction(() async {
      final items = await (select(purchaseOrderItems)
            ..where((t) => t.poId.equals(poId)))
          .get();
      for (final it in items) {
        final prod = await (select(products)
              ..where((t) => t.id.equals(it.productId)))
            .getSingleOrNull();
        if (prod == null) continue;
        await (update(products)..where((t) => t.id.equals(prod.id))).write(
          ProductsCompanion(
            stockQty: Value(prod.stockQty + it.qtyOrdered),
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
