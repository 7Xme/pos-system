import 'package:drift/drift.dart';

import 'app_database.dart';

/// بيانات تجريبية صغيرة — **للاختبارات فقط**.
///
/// لم يعد التطبيق يستدعيها عند الإقلاع: الكتالوج الافتراضي يأتي من الملف
/// المرفق عبر [CatalogBootstrap] (انظر `lib/core/database/catalog_bootstrap.dart`).
Future<void> ensureSeeded(AppDatabase db) async {
  final has = await db.hasAnyProduct();
  if (has) return;

  final stationery = await db.insertCategory('قرطاسية');
  final bags = await db.insertCategory('حقائب مدرسية');
  final books = await db.insertCategory('كتب خارجية');

  final data = <(int, String, String, double, int, bool)>[
    // (الفئة، الاسم، الباركود، السعر، المخزون، مثبت كاختصار؟)
    (stationery, 'كراسة 100 ورقة', '100001', 25, 120, true),
    (stationery, 'قلم جاف أزرق', '100002', 8, 500, true),
    (stationery, 'علبة ألوان 12', '100003', 65, 40, false),
    (bags, 'شنطة مدرسية', '100004', 450, 15, false),
    (stationery, 'مسطرة 30 سم', '100005', 12, 200, false),
    (books, 'كتاب خارجي رياضيات', '100006', 120, 30, false),
  ];

  for (final (catId, name, barcode, price, stock, fav) in data) {
    await db.insertProductWithBarcodes(
      ProductsCompanion.insert(
        name: name,
        barcode: barcode,
        price: price,
        cost: Value(price * 0.7),
        stockQty: Value(stock),
        categoryId: Value(catId),
        isFavorite: Value(fav),
      ),
      [barcode],
    );
  }
}
