import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';

/// حفظ صور المنتجات محلياً + تخزين مسارها في DB.
///
/// القيمة المحفوظة في القاعدة هي **اسم الملف فقط** (مثل `1712345678901.jpg`)
/// لتبقى القاعدة محمولة. المسارات القديمة المطلقة (من جهاز سابق) تُحلّ بالاسم
/// داخل مجلد الصور الحالي عبر [resolve].
class ProductImageStore {
  /// مجلد صور المنتجات الحالي (مجلد data المحمول أو مسار دعم التطبيق).
  static Future<Directory> imagesDirectory() async {
    await AppPaths.ensureInitialized();
    return AppPaths.imagesDir;
  }

  static Directory get imagesDir => AppPaths.imagesDir;

  /// اختيار صورة فقط (بدون حفظ) — الحفظ يتم عند حفظ المنتج
  static Future<File?> pick() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final path = file?.path;
    if (path == null) return null;
    return File(path);
  }

  static Future<String?> pickAndSave() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    final path = file.path;
    if (path == null) return null;
    return save(File(path));
  }

  /// ينسخ الصورة إلى مجلد الصور ويُرجع **اسم الملف** فقط.
  static Future<String> save(File source) async {
    final dir = await imagesDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = p.extension(source.path).toLowerCase();
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final dest = File(p.join(dir.path, name));
    await source.copy(dest.path);
    return name;
  }

  /// يحوّل قيمة `image_path` المحفوظة إلى مسار فعلي على هذا الجهاز.
  ///
  /// - اسم ملف فقط → داخل مجلد الصور الحالي.
  /// - مسار مطلق موجود → يُستعمل كما هو.
  /// - مسار مطلق من جهاز/مجلد آخر → يُبحث عن الملف بالاسم في مجلد الصور
  ///   الحالي ثم في مجلدات محمولة بجانب البرنامج.
  static String? resolve(String? stored) {
    if (stored == null) return null;
    final value = stored.trim();
    if (value.isEmpty) return null;

    if (File(value).existsSync()) return value;

    final name = p.basename(value);
    if (name.isEmpty || name == '.' || name == '..') return null;

    for (final dir in AppPaths.imageSearchDirs) {
      final candidate = p.join(dir.path, name);
      if (File(candidate).existsSync()) return candidate;
    }
    // غير موجود: نُرجع المسار المتوقع كي تعرض الواجهة أيقونة بديلة.
    return p.join(AppPaths.imagesDir.path, name);
  }

  /// ملف الصورة الفعلي أو `null` إذا لم تكن الصورة متوفرة.
  ///
  /// نتيجة البحث تُحفظ في ذاكرة مؤقتة: شبكة البيع/المخزون تعيد البناء كثيراً،
  /// وبدونها كان كل بناء يكرّر فحص وجود الملف على القرص (عدة مسارات عند
  /// غياب الصورة) لعشرات البطاقات.
  static File? fileFor(String? stored) {
    if (stored == null) return null;
    final key = stored.trim();
    if (key.isEmpty) return null;
    if (_fileCache.containsKey(key)) return _fileCache[key];

    final path = resolve(key);
    File? result;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) result = file;
    }
    if (_fileCache.length >= _maxCacheEntries) _fileCache.clear();
    _fileCache[key] = result;
    return result;
  }

  static final Map<String, File?> _fileCache = {};
  static const int _maxCacheEntries = 5000;

  /// يُفرِّغ ذاكرة مسارات الصور (بعد استيراد/تغيير ملفات الصور).
  static void clearCache() => _fileCache.clear();

  static Future<void> deleteIfExists(String? stored) async {
    final file = fileFor(stored);
    if (file != null) {
      await file.delete();
      _fileCache.remove(stored?.trim());
    }
  }
}
