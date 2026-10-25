import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// مواضع تخزين التطبيق، مع دعم **نسخة محمولة** (Portable).
///
/// إذا وُجدت قاعدة البيانات بجانب التطبيق:
///   `<مجلد exe>\bookstore_pos.sqlite` أو
///   `<مجلد exe>\data\bookstore_pos.sqlite`
/// يعمل التطبيق على تلك الملفات مباشرةً (بدل نسخها إلى AppData)، فتنتقل
/// النسخة مع مجلدها إلى أي جهاز آخر دون استيراد أو مسارات ثابتة.
///
/// إن لم يوجد المجلد المحمول، يعود التطبيق إلى مسار دعم التطبيق القديم.
class AppPaths {
  static const String dbFileName = 'bookstore_pos.sqlite';
  static const String imagesFolderName = 'product_images';
  static const String dataFolderName = 'data';

  static bool _resolved = false;
  static bool _portable = false;
  static Directory _dataDir = Directory('.');
  static Directory _imagesDir = Directory('.');
  static String _dbPath = dbFileName;
  static List<Directory> _imageSearchDirs = const [];

  static Future<void>? _initFuture;

  /// هل يعمل التطبيق على مجلد بيانات محمول بجانب الـ exe؟
  static bool get isPortable {
    _ensureSyncDefaults();
    return _portable;
  }

  /// مجلد قاعدة البيانات (مجلد data المحمول أو مسار دعم التطبيق).
  static Directory get dataDir {
    _ensureSyncDefaults();
    return _dataDir;
  }

  /// مجلد الصور الحالي الذي تُحفظ فيه الصور الجديدة.
  static Directory get imagesDir {
    _ensureSyncDefaults();
    return _imagesDir;
  }

  /// مسار ملف قاعدة البيانات.
  static String get databaseFile {
    _ensureSyncDefaults();
    return _dbPath;
  }

  /// مجلدات البحث عن الصور القديمة بالاسم (بعد تغيّر مسار الجهاز).
  static List<Directory> get imageSearchDirs {
    _ensureSyncDefaults();
    return _imageSearchDirs;
  }

  static Future<String> databaseFilePath() async {
    await ensureInitialized();
    return _dbPath;
  }

  static Future<void> ensureInitialized() => _initFuture ??= _initialize();

  static Future<void> _initialize() async {
    if (_resolved) return;
    _detectPortable();
    if (_resolved) return;

    Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      support = _syncSupportDir();
    }
    _apply(support: support);
  }

  /// افتراضي متزامن: يسمح لبناء الواجهات بالعمل حتى لو لم تُهيَّأ بعد
  /// (مثلاً في اختبارات الواجهة).
  static void _ensureSyncDefaults() {
    if (_resolved) return;
    _detectPortable();
    if (_resolved) return;
    _apply(support: _syncSupportDir());
  }

  static void _detectPortable() {
    if (_resolved) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final candidates = [
        exeDir,
        Directory(p.join(exeDir.path, dataFolderName)),
      ];
      for (final dir in candidates) {
        final db = File(p.join(dir.path, dbFileName));
        if (!db.existsSync()) continue;
        if (!_canWrite(dir)) continue;
        _apply(
          dataDir: dir,
          dbPath: db.path,
          imagesDir: _findImagesDir(dir),
        );
        _portable = true;
        return;
      }
    } catch (_) {
      // تعذّر تحديد مسار exe — يُستعمل مسار دعم التطبيق.
    }
  }

  static void _apply({
    Directory? support,
    Directory? dataDir,
    String? dbPath,
    Directory? imagesDir,
  }) {
    _dataDir = dataDir ?? support!;
    _dbPath = dbPath ?? p.join(_dataDir.path, dbFileName);
    _imagesDir = imagesDir ?? Directory(p.join(_dataDir.path, imagesFolderName));
    _imageSearchDirs = _buildImageSearchDirs(_imagesDir);
    _resolved = true;
  }

  /// يفضّل `product_images` ثم `images`، ويقبل وجود الصور داخل `data` فرعية
  /// عندما تكون القاعدة بجانب الـ exe.
  static Directory _findImagesDir(Directory dataDir) {
    final candidates = <String>[
      p.join(dataDir.path, imagesFolderName),
      p.join(dataDir.path, 'images'),
      p.join(dataDir.path, dataFolderName, imagesFolderName),
      p.join(dataDir.path, dataFolderName, 'images'),
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return Directory(path);
    }
    return Directory(candidates.first);
  }

  /// مجلد الصور الحالي + مجلدات محمولة قد تكون بجانب الـ exe.
  static List<Directory> _buildImageSearchDirs(Directory primary) {
    final dirs = <Directory>[primary];

    void add(Directory dir) {
      if (!dir.existsSync()) return;
      if (dirs.any((d) => p.equals(d.path, dir.path))) return;
      dirs.add(dir);
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      add(Directory(p.join(exeDir.path, imagesFolderName)));
      add(Directory(p.join(exeDir.path, dataFolderName, imagesFolderName)));
      add(Directory(p.join(exeDir.path, 'images')));
      add(Directory(p.join(exeDir.path, dataFolderName, 'images')));
    } catch (_) {
      // تجاهل — يبقى المجلد الأساسي.
    }
    return dirs;
  }

  static bool _canWrite(Directory dir) {
    File? probe;
    try {
      probe = File(p.join(dir.path, '.ypos_write_test'));
      probe.writeAsStringSync('ok', flush: true);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (probe != null && probe.existsSync()) probe.deleteSync();
      } catch (_) {
        // تنظيف غير حرج
      }
    }
  }

  /// مسار دعم التطبيق على ويندوز: `%APPDATA%\YPOS\YPOS`
  /// (نفس ما ينتجه path_provider حسب CompanyName/ProductName).
  static Directory _syncSupportDir() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory(p.join(appData, 'YPOS', 'YPOS'));
    }
    return Directory(p.join(Directory.systemTemp.path, 'ypos'));
  }
}
