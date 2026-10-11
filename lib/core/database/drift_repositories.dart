import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../features/pos/bloc/pos_bloc.dart';

ProductDto _toDto(Product p) => ProductDto(
      id: p.id,
      name: p.name,
      barcode: p.barcode,
      price: p.price,
      stockQty: p.stockQty,
      imagePath: p.imagePath,
    );

/// مصدر الأصناف الحقيقي من Drift
class DriftCatalogRepository implements PosCatalogRepository {
  final AppDatabase db;
  DriftCatalogRepository(this.db);

  @override
  Future<List<ProductDto>> search(String query) async {
    final rows = await db.searchProducts(query);
    return rows.map(_toDto).toList();
  }

  @override
  Future<ProductDto?> findByBarcode(String barcode) async {
    final row = await db.findByBarcode(barcode);
    return row == null ? null : _toDto(row);
  }

  @override
  Future<List<ProductDto>> favorites() async {
    final rows = await db.favoriteProducts();
    return rows.map(_toDto).toList();
  }
}

/// حفظ البيع الحقيقي: فاتورة + سطور + خصم مخزون (Transaction واحدة)
class DriftCheckoutRepository implements PosCheckoutRepository {
  final AppDatabase db;
  DriftCheckoutRepository(this.db);

  @override
  Future<({String invoiceNumber, double total})> checkout(
    List<CartLine> cart,
    double amountPaid,
  ) async {
    final total = cart.fold<double>(0, (s, e) => s + e.total);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final invNo =
        'INV-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final items = [
      for (final l in cart)
        InvoiceItemsCompanion(
          productId: Value(l.product.id),
          qty: Value(l.qty),
          unitPrice: Value(l.product.price),
          lineTotal: Value(l.total),
        ),
    ];
    await db.saveInvoiceWithItems(
      invoiceNumber: invNo,
      total: total,
      amountPaid: amountPaid,
      items: items,
    );
    return (invoiceNumber: invNo, total: total);
  }
}
