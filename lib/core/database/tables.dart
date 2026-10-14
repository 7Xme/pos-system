import 'package:drift/drift.dart';

/// مخطط قاعدة البيانات — الخطوة 2 (معتمد: بدون ضريبة/خصم، مجموع فقط + A4)
/// لتوليد الكود: dart run build_runner build

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  TextColumn get name => text()();
  // باركود فريد + مفهرس للبحث السريع عند المسح
  TextColumn get barcode => text().unique()();
  RealColumn get price => real()(); // سعر البيع
  RealColumn get cost => real().withDefault(const Constant(0))(); // سعر الشراء
  IntColumn get stockQty => integer().withDefault(const Constant(0))();
  IntColumn get minStock => integer().withDefault(const Constant(5))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // منتج مثبت في شريط الاختصارات (v2)
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// إعدادات المتجر (مفتاح → قيمة) — v2
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get cashier => text().withDefault(const Constant('كاشير'))();
  // total = الصافي بعد الخصم (v3: discount + discountType)
  RealColumn get total => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  // amount | percent
  TextColumn get discountType =>
      text().withDefault(const Constant('amount'))();
  RealColumn get amountPaid => real()();
  RealColumn get change => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get qty => integer()();
  // نسخة من السعر وقت البيع (حتى لو تغير سعر المنتج لاحقاً)
  RealColumn get unitPrice => real()();
  RealColumn get lineTotal => real()();
  // نسخة من اسم الصنف وقت البيع (لسجل المبيعات حتى لو حُذف المنتج) — v3
  TextColumn get productName => text().withDefault(const Constant(''))();
  // نسخة من التكلفة وقت البيع (لتقرير الأرباح) — v4 (القديم = 0: مستبعد)
  RealColumn get unitCost => real().withDefault(const Constant(0))();
}

/// باركودات متعددة للمنتج — v5.
/// كل باركود في سطر، و`barcode` فريد عالمياً حتى لا يتضارب المسح بين منتجين.
/// products.barcode يبقى الباركود الرئيسي (مرآة للسطر الأول) للطباعة والعرض.
class ProductBarcodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(
        Products,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get barcode => text().unique()();
  // ترتيب العرض داخل المنتج (0 = الرئيسي)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// المرتجعات — v4: إرجاع جزئي لأصناف فاتورة مع استعادة المخزون.
class Returns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().unique()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get reason => text().withDefault(const Constant(''))();
  RealColumn get total => real()();
  TextColumn get cashier => text().withDefault(const Constant('كاشير'))();
}

class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(Returns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get qty => integer()();
  RealColumn get unitPrice => real()();
  // نسخة من تكلفة سطر الفاتورة الأصلي (لصافي الربح بعد المردودات)
  RealColumn get unitCost => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();
  TextColumn get productName => text().withDefault(const Constant(''))();
}

class PurchaseOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get poNumber => text().unique()();
  TextColumn get supplierName => text().withDefault(const Constant(''))();
  TextColumn get supplierPhone => text().nullable()();
  // draft | ordered | received | cancelled
  TextColumn get status => text().withDefault(const Constant('draft'))();
  RealColumn get totalCost => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
}

class PurchaseOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get poId => integer().references(
        PurchaseOrders,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get qtyOrdered => integer()();
  IntColumn get qtyReceived => integer().withDefault(const Constant(0))();
  RealColumn get unitCost => real()();
}
