import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../storage/app_paths.dart';

/// يزرع **الكتالوج الافتراضي** المرفق مع البرنامج عند أول تشغيل.
///
/// المصدر المرفق: `<مجلد exe>\data\bookstore_pos.sqlite` مع صوره في
/// `<مجلد exe>\data\product_images`. أثناء التطوير يُقبل أيضًا مجلد `data`
/// في جذر المشروع.
///
/// يعمل **قبل** فتح Drift: ينسخ قاعدة الكتالوج إلى مسار قاعدة التطبيق ثم يعيد
/// كتابة مسارات الصور لتشير إلى مجلد الصور المرفق (قراءة مباشرة، بلا نسخ).
///
/// لا يفعل شيئًا إذا كانت قاعدة التطبيق تحتوي منتجات مسبقًا (حماية لبيانات
/// المستخدم وإعداداته).
class CatalogBootstrap {
  static const String dbName = 'bookstore_pos.sqlite';
  static const String imagesFolder = 'product_images';
  static const String dataFolder = 'data';

  /// مجلد البيانات المرفق (يحوي قاعدة الكتالوج)، أو `null` إن لم يوجد.
  ///
  /// الترتيب: `<مجلد exe>\data` (المثبّت) ثم بحث تصاعدي عن `data`
  /// (تشغيل الـ exe المبنِي داخل المشروع) ثم مجلد العمل الحالي.
  static Directory? bundledDataDir() {
    final candidates = <Directory>[];
    try {
      var dir = File(Platform.resolvedExecutable).parent;
      candidates.add(Directory(p.join(dir.path, dataFolder)));
      for (var i = 0; i < 6; i++) {
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
        candidates.add(Directory(p.join(dir.path, dataFolder)));
      }
    } catch (_) {
      // تجاهل — سنعتمد على مجلد العمل أدناه
    }
    candidates.add(Directory(p.join(Directory.current.path, dataFolder)));

    for (final dir in candidates) {
      if (File(p.join(dir.path, dbName)).existsSync()) return dir;
    }
    return null;
  }

  /// يزرع الكتالوج إن كانت قاعدة التطبيق فارغة. يُرجع `true` عند الزرع.
  static Future<bool> seedIfEmpty() async {
    // الوضع المحمول: القاعدة والصور بجانب البرنامج تُستعمل مباشرةً.
    await AppPaths.ensureInitialized();
    if (AppPaths.isPortable) return false;

    final support = await getApplicationSupportDirectory();
    final appDb = File(p.join(support.path, dbName));

    // قاعدة موجودة ولديها منتجات → لا نلمسها.
    if (await appDb.exists() && _productCount(appDb.path) > 0) return false;

    final dataDir = bundledDataDir();
    if (dataDir == null) return false;
    final srcDb = File(p.join(dataDir.path, dbName));
    if (!await srcDb.exists()) return false;

    await support.create(recursive: true);
    if (await appDb.exists()) {
      await appDb.delete();
    }
    await srcDb.copy(appDb.path);

    final imagesDir = Directory(p.join(dataDir.path, imagesFolder));
    if (await imagesDir.exists()) {
      _rewriteImagePaths(appDb.path, imagesDir.path);
    }
    return true;
  }

  /// عدد المنتجات في ملف قاعدة بيانات (0 عند أي خطأ).
  static int _productCount(String dbPath) {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(dbPath, mode: sqlite.OpenMode.readOnly);
      final row = db.select('SELECT COUNT(*) AS c FROM products').first;
      return (row['c'] as int?) ?? 0;
    } catch (_) {
      return 0;
    } finally {
      db?.dispose();
    }
  }

  /// يعيد كتابة `products.image_path` ليبقى **اسم الملف فقط** مضافًا إلى
  /// [imagesDir]. يستعمل دالّتي replace/rtrim في SQLite لاستخراج اسم الملف
  /// (SQLite لا يوفّر basename).
  ///
  /// مثال: `...\product_images\8969.jpg` → `<imagesDir>\8969.jpg`.
  static void _rewriteImagePaths(String dbPath, String imagesDir) {
    final db = sqlite.sqlite3.open(dbPath);
    try {
      final prefix = imagesDir.endsWith(Platform.pathSeparator)
          ? imagesDir
          : imagesDir + Platform.pathSeparator;
      db.execute(
        'UPDATE products SET image_path = ?1 || '
        r"replace(image_path, rtrim(image_path, replace(image_path, '\', '')), '') "
        r"WHERE image_path IS NOT NULL AND TRIM(image_path) <> ''",
        [prefix],
      );
    } finally {
      db.dispose();
    }
  }
}
