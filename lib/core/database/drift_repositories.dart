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

/// نفس [ProductDto] مع كل الباركودات (الرئيسي أولاً).
Future<ProductDto> _toDtoWithBarcodes(
  Product p,
  AppDatabase db,
) async =>
    _toDto(p).copyWithBarcodeList(await db.barcodesOf(p.id));

extension ProductDtoBarcodes on ProductDto {
  ProductDto copyWithBarcodeList(List<String> list) => ProductDto(
        id: id,
        name: name,
        barcode: barcode,
        price: price,
        stockQty: stockQty,
        imagePath: imagePath,
        barcodes: list,
      );
}

/// مصدر الأصناف الحقيقي من Drift
class DriftCatalogRepository implements PosCatalogRepository {
  final AppDatabase db;
  DriftCatalogRepository(this.db);

  @override
  Future<List<ProductDto>> search(String query) async {
    final rows = await db.searchProducts(query);
    final map = await db.barcodesOfAll([for (final r in rows) r.id]);
    return [
      for (final r in rows)
        _toDto(r).copyWithBarcodeList(
          map[r.id] ?? [if (r.barcode.trim().isNotEmpty) r.barcode],
        ),
    ];
  }

  @override
  Future<ProductDto?> findByBarcode(String barcode) async {
    final row = await db.findByBarcode(barcode);
    return row == null ? null : await _toDtoWithBarcodes(row, db);
  }

  @override
  Future<List<ProductDto>> favorites() async {
    final rows = await db.favoriteProducts();
    final map = await db.barcodesOfAll([for (final r in rows) r.id]);
    return [
      for (final r in rows)
        _toDto(r).copyWithBarcodeList(
          map[r.id] ?? [if (r.barcode.trim().isNotEmpty) r.barcode],
        ),
    ];
  }
}

/// مولّد رقم فاتورة فريد: طابع زمني بالمللي ثانية + لاحقة عند التعارض.
/// يمنع تكرار الرقم عند بيعين في نفس الثانية (العمود UNIQUE).
String nextInvoiceNumber(DateTime now, [int attempt = 0]) {
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      'INV-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}${now.millisecond.toString().padLeft(3, '0')}';
  return attempt <= 0 ? base : '$base-$attempt';
}

/// حفظ البيع الحقيقي: فاتورة + سطور + خصم مخزون (Transaction واحدة)
class DriftCheckoutRepository implements PosCheckoutRepository {
  final AppDatabase db;
  DriftCheckoutRepository(this.db);

  @override
  Future<({String invoiceNumber, double total})> checkout(
    List<CartLine> cart,
    double amountPaid, {
    double discount = 0,
    String discountType = 'amount',
    String? cashier,
  }) async {
    final subtotal = cart.fold<double>(0, (s, e) => s + e.total);
    final total = applyDiscount(subtotal, discount, discountType);
    // تحقق صارم من المخزون الحالي قبل الحفظ (يمنع البيع السالب)،
    // مع التقاط التكلفة الحالية للقطة الربحية (v4).
    final costs = <int, double>{};
    for (final l in cart) {
      final prod = await db.getProduct(l.product.id);
      if (prod == null || prod.stockQty < l.qty) {
        throw StateError(
          'المتاح من «${l.product.name}»: ${prod?.stockQty ?? 0} فقط '
          '(المطلوب ${l.qty})',
        );
      }
      costs[l.product.id] = prod.cost;
    }
    final now = DateTime.now();
    var attempt = 0;
    var invNo = nextInvoiceNumber(now);
    while (attempt < 5 && await db.invoiceNumberExists(invNo)) {
      attempt++;
      invNo = nextInvoiceNumber(now, attempt);
    }
    final items = [
      for (final l in cart)
        InvoiceItemsCompanion(
          productId: Value(l.product.id),
          qty: Value(l.qty),
          unitPrice: Value(l.product.price),
          lineTotal: Value(l.total),
          productName: Value(l.product.name),
          unitCost: Value(costs[l.product.id] ?? 0),
        ),
    ];
    await db.saveInvoiceWithItems(
      invoiceNumber: invNo,
      total: total,
      amountPaid: amountPaid,
      cashier: cashier,
      items: items,
      discount: discountType == 'percent'
          ? subtotal - total // القيمة المحسوبة بالدرهم
          : discount.clamp(0, subtotal),
      discountType: discountType,
    );
    return (invoiceNumber: invNo, total: total);
  }
}
