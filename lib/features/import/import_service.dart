import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../core/database/app_database.dart';

/// تقدم الاستيراد — يُبث أثناء العمل لرسم شريط التقدم.
class ImportProgress {
  final int processed;
  final int total;
  final int inserted;
  final int skipped;

  const ImportProgress({
    required this.processed,
    required this.total,
    required this.inserted,
    required this.skipped,
  });

  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0.0, 1.0);
}

/// نتيجة الاستيراد النهائية.
class ImportResult {
  final int productsInserted;
  final int productsSkipped;
  final int categoriesCreated;
  final int imagesCopied;
  final int imagesMissing;
  final bool cancelled;

  const ImportResult({
    this.productsInserted = 0,
    this.productsSkipped = 0,
    this.categoriesCreated = 0,
    this.imagesCopied = 0,
    this.imagesMissing = 0,
    this.cancelled = false,
  });
}

/// استيراد كتالوج المنتجات من حزمة البيانات التي يوفّرها المطوّر.
///
/// المصدر: ملف `bookstore_pos.sqlite` داخل مجلد البيانات (يحوي جداول
/// categories / products / product_barcodes بنفس مخطط Drift).
///
/// الاستيراد **متكرر بأمان** (idempotent): الباركود مفتاح فريد، وإعادة التشغيل
/// تتخطى الموجود ولا تكرره ولا تمس الأسعار المُعدَّلة يدوياً.
class ProductImportService {
  static const String dbFileName = 'bookstore_pos.sqlite';
  static const int _chunk = 2000;

  /// هل يحوي هذا المجلد قاعدة بيانات الكتالوج؟
  static String? findDatabaseIn(String directory) {
    final candidate = File(p.join(directory, dbFileName));
    if (candidate.existsSync()) return candidate.path;
    return null;
  }

  /// مجلد صور الكتالوج بجانب قاعدة المصدر (إن وُجد).
  static Directory? _sourceImagesDir(String sourcePath) {
    final base = p.dirname(sourcePath);
    for (final name in const ['product_images', 'images']) {
      final dir = Directory(p.join(base, name));
      if (dir.existsSync()) return dir;
    }
    return null;
  }

  /// يجد ملف الصورة الفعلي: المسار المخزّن أولاً ثم بالاسم داخل مجلد المصدر.
  static File? _resolveImageFile(String stored, Directory? sourceImages) {
    final value = stored.trim();
    if (value.isEmpty) return null;
    final direct = File(value);
    if (direct.existsSync()) return direct;
    if (sourceImages == null) return null;
    final name = p.basename(value);
    if (name.isEmpty) return null;
    final candidate = File(p.join(sourceImages.path, name));
    return candidate.existsSync() ? candidate : null;
  }

  /// القيمة التي تُحفظ في `image_path`:
  /// - عند نسخ الصور: اسم الملف فقط (قاعدة محمولة).
  /// - بلا نسخ: المسار الفعلي للصورة (يبقى داخل مجلد المصدر).
  /// - إن لم تُوجد الصورة: اسم الملف فقط ليُبحث عنه لاحقاً.
  static String? _importedImagePath({
    required String? stored,
    required Directory? sourceImages,
    required bool copyImages,
  }) {
    if (stored == null || stored.trim().isEmpty) return null;
    final source = _resolveImageFile(stored, sourceImages);
    if (copyImages) {
      return source == null ? p.basename(stored) : p.basename(source.path);
    }
    return source?.path ?? p.basename(stored);
  }

  /// يتحقق أن [sourcePath] قاعدة كتالوج صالحة.
  ///
  /// يتم الفحص بفتح الملف **للقراءة فقط** بمكتبة SQLite مباشرةً، قبل فتحه
  /// بواسطة Drift — لأن فتح Drift لأي ملف قد ينشئ فيه جداول المخطط ويلوّث
  /// ملفاً ليس كتالوجاً.
  static void validateSource(String sourcePath) {
    final file = File(sourcePath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw StateError('ملف الكتالوج غير موجود أو فارغ:\n$sourcePath');
    }

    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(sourcePath, mode: sqlite.OpenMode.readOnly);

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'] as String)
          .toSet();
      const requiredTables = {'products', 'categories', 'product_barcodes'};
      final missingTables = requiredTables.difference(tables);
      if (missingTables.isNotEmpty) {
        throw StateError(
          'الملف المختار ليس قاعدة بيانات كتالوج صالحة\n'
          '(جداول مفقودة: ${missingTables.join(', ')})',
        );
      }

      final columns = db
          .select('PRAGMA table_info(products)')
          .map((r) => r['name'] as String)
          .toSet();
      const requiredColumns = {
        'id',
        'name',
        'barcode',
        'price',
        'cost',
        'stock_qty',
        'min_stock',
        'category_id',
        'image_path',
        'is_active',
      };
      final missingColumns = requiredColumns.difference(columns);
      if (missingColumns.isNotEmpty) {
        throw StateError(
          'بنية جدول products غير متوافقة\n'
          '(أعمدة مفقودة: ${missingColumns.join(', ')})',
        );
      }
    } on sqlite.SqliteException catch (e) {
      throw StateError('تعذّر قراءة الملف كقاعدة بيانات SQLite:\n${e.message}');
    } finally {
      db?.dispose();
    }
  }

  /// يستورد كل المنتجات من [sourcePath] إلى [target].
  ///
  /// [copyImages] = نسخ الصور إلى مجلد التطبيق بدل الإشارة إلى مجلد البيانات.
  static Future<ImportResult> importFrom({
    required AppDatabase target,
    required String sourcePath,
    bool copyImages = false,
    String? imagesDestination,
    bool Function()? isCancelled,
    void Function(ImportProgress)? onProgress,
  }) async {
    // تحقّق أولاً — قبل فتح Drift الذي قد ينشئ جداول في الملف المختار.
    validateSource(sourcePath);

    final sourceImages = _sourceImagesDir(sourcePath);
    final willCopy = copyImages && imagesDestination != null;
    final source = AppDatabase.at(sourcePath);
    var inserted = 0;
    var skipped = 0;
    var copied = 0;
    var missing = 0;

    try {
      final total = (await source
              .customSelect('SELECT COUNT(*) AS c FROM products')
              .getSingle())
          .read<int>('c');

      // ── 1) الفئات: إنشاء الناقص وربط الاسم بالمعرّف ──────────────
      final existing = await target.select(target.categories).get();
      final catIdByName = <String, int>{for (final c in existing) c.name: c.id};
      var categoriesCreated = 0;

      final srcCats = await source.select(source.categories).get();
      final srcCatNameById = <int, String>{
        for (final c in srcCats) c.id: c.name,
      };
      for (final c in srcCats) {
        if (catIdByName.containsKey(c.name)) continue;
        final id = await target.into(target.categories).insert(
              CategoriesCompanion.insert(
                name: c.name,
                description: Value(c.description),
                imagePath: Value(c.imagePath),
                createdAt: Value(DateTime.now()),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (id > 0) {
          catIdByName[c.name] = id;
          categoriesCreated++;
        }
      }

      // ── 2) المنتجات على دفعات ────────────────────────────────────
      var offset = 0;
      while (true) {
        if (isCancelled?.call() ?? false) {
          return ImportResult(cancelled: true);
        }
        final rows = await (source.select(source.products)
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(_chunk, offset: offset))
            .get();
        if (rows.isEmpty) break;

        final companions = <ProductsCompanion>[];
        for (final r in rows) {
          final catName =
              r.categoryId == null ? null : srcCatNameById[r.categoryId];
          companions.add(
            ProductsCompanion.insert(
              name: r.name,
              barcode: r.barcode,
              price: r.price,
              cost: Value(r.cost),
              stockQty: Value(r.stockQty),
              minStock: Value(r.minStock),
              categoryId: Value(
                catName == null ? null : catIdByName[catName],
              ),
              imagePath: Value(
                _importedImagePath(
                  stored: r.imagePath,
                  sourceImages: sourceImages,
                  copyImages: willCopy,
                ),
              ),
              isActive: Value(true),
              isFavorite: const Value(false),
            ),
          );
        }

        // insertOrIgnore: الباركود الموجود مسبقاً لا يُستبدل (حماية لتعديلات
        // المستخدم) — DoNothing في دفعات قد يفشل على قيود UNIQUE في SQLite.
        final insertedBefore = await target.productCount();
        await target.batch(
          (b) => b.insertAll(
            target.products,
            companions,
            mode: InsertMode.insertOrIgnore,
          ),
        );
        final insertedAfter = await target.productCount();
        final added = insertedAfter - insertedBefore;
        inserted += added;
        skipped += rows.length - added;

        offset += rows.length;
        onProgress?.call(
          ImportProgress(
            processed: offset,
            total: total,
            inserted: inserted,
            skipped: skipped,
          ),
        );
      }

      // ── 3) باركودات المنتجات (المرآة الأساسية) ───────────────────
      await target.customStatement(
        'INSERT OR IGNORE INTO product_barcodes (product_id, barcode, sort_order) '
        'SELECT id, barcode, 0 FROM products '
        "WHERE barcode IS NOT NULL AND TRIM(barcode) <> ''",
      );

      // ── 3ب) ملء الصور الناقصة للمنتجات الموجودة مسبقاً ────────────
      // إعادة الاستيراد بعد اكتمال الزحف يجب أن تجلب الصور التي كانت
      // مفقودة، دون المساس بالاسم/السعر/الكمية التي عدّلها المستخدم.
      // نكتب المسار الفعلي للصورة هنا (وليس مساراً قديماً من جهاز آخر).
      final missingImages = await target.customSelect(
        'SELECT id, barcode FROM products '
        "WHERE (image_path IS NULL OR TRIM(image_path) = '') "
        "AND barcode IS NOT NULL AND TRIM(barcode) <> ''",
        readsFrom: {target.products},
      ).get();
      if (missingImages.isNotEmpty) {
        final sourceByBarcode = <String, String>{};
        final barcodes = [
          for (final row in missingImages) row.read<String>('barcode'),
        ];
        const chunk = 500;
        for (var i = 0; i < barcodes.length; i += chunk) {
          final end =
              i + chunk < barcodes.length ? i + chunk : barcodes.length;
          final part = barcodes.sublist(i, end);
          final placeholders = List.filled(part.length, '?').join(',');
          final rows = await source.customSelect(
            'SELECT barcode, image_path FROM products '
            'WHERE barcode IN ($placeholders)',
            variables: [for (final b in part) Variable<String>(b)],
          ).get();
          for (final r in rows) {
            final image = r.read<String?>('image_path');
            if (image == null || image.trim().isEmpty) continue;
            sourceByBarcode[r.read<String>('barcode')] = image;
          }
        }
        for (final row in missingImages) {
          final image = sourceByBarcode[row.read<String>('barcode')];
          final path = _importedImagePath(
            stored: image,
            sourceImages: sourceImages,
            copyImages: willCopy,
          );
          if (path == null) continue;
          await (target.update(target.products)
                ..where((t) => t.id.equals(row.read<int>('id'))))
              .write(ProductsCompanion(imagePath: Value(path)));
        }
      }

      // ── 4) الصور (اختياري: نسخ محلي) ─────────────────────────────
      if (willCopy) {
        final dir = Directory(imagesDestination);
        await dir.create(recursive: true);
        final imgRows = await source
            .customSelect('SELECT image_path FROM products '
                "WHERE image_path IS NOT NULL AND TRIM(image_path) <> ''")
            .get();
        for (final row in imgRows) {
          if (isCancelled?.call() ?? false) {
            return ImportResult(cancelled: true);
          }
          final src = _resolveImageFile(
            row.read<String>('image_path'),
            sourceImages,
          );
          if (src == null) {
            missing++;
            continue;
          }
          final dst = File(p.join(dir.path, p.basename(src.path)));
          if (!await dst.exists()) {
            await src.copy(dst.path);
          }
          copied++;
        }
      }

      return ImportResult(
        productsInserted: inserted,
        productsSkipped: skipped,
        categoriesCreated: categoriesCreated,
        imagesCopied: copied,
        imagesMissing: missing,
      );
    } finally {
      await source.close();
    }
  }

  /// عدد المنتجات الحالي في قاعدة التطبيق (للعرض قبل الاستيراد).
  static Future<int> currentProductCount(AppDatabase db) async {
    try {
      return await db.productCount();
    } catch (_) {
      return 0;
    }
  }
}
