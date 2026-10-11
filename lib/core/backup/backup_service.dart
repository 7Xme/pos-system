import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

/// النسخ الاحتياطي والاستعادة:
/// - التصدير: ملف ZIP واحد يحتوي ملف قاعدة البيانات + مجلد الصور.
/// - الاستيراد: اختيار ملف ZIP فيفك التطبيق ضغطه ويستبدل البيانات.
class BackupService {
  static const String dbFileName = 'bookstore_pos.sqlite';
  static const String imagesDirName = 'product_images';

  static Future<Directory> supportDir() => getApplicationSupportDirectory();

  static Future<File> dbFile() async =>
      File(p.join((await supportDir()).path, dbFileName));

  static Future<Directory> imagesDir() async =>
      Directory(p.join((await supportDir()).path, imagesDirName));

  // ── دوال خالصة (قابلة للاختبار) ──────────────────────────

  /// يبني بايتات ZIP من بايتات القاعدة + الصور (الاسم → البايتات).
  static List<int> buildZip({
    required List<int> dbBytes,
    required Map<String, List<int>> images,
  }) {
    final archive = Archive();
    archive.addFile(ArchiveFile(dbFileName, dbBytes.length, dbBytes));
    for (final entry in images.entries) {
      archive.addFile(
        ArchiveFile(
          '$imagesDirName/${entry.key}',
          entry.value.length,
          entry.value,
        ),
      );
    }
    return ZipEncoder().encode(archive);
  }

  /// يفك ZIP ويستخرج بايتات القاعدة + الصور. يرمي خطأ إذا كان الملف غير صالح.
  /// لأمان المسارات: تُقبل صور بأسماء ملفات فقط (بدون مجلدات متداخلة).
  static ({List<int> dbBytes, Map<String, List<int>> images}) parseZip(
    List<int> bytes,
  ) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw StateError('الملف المختار ليس أرشيف ZIP صالحاً');
    }
    List<int>? dbBytes;
    final images = <String, List<int>>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      final content = List<int>.from(f.content as List<int>);
      if (f.name == dbFileName) {
        dbBytes = content;
      } else if (f.name.startsWith('$imagesDirName/')) {
        final name = f.name.substring(imagesDirName.length + 1);
        if (name.isNotEmpty &&
            !name.contains('/') &&
            !name.contains('\\')) {
          images[name] = content;
        }
      }
    }
    if (dbBytes == null) {
      throw StateError('ملف ZIP لا يحتوي على قاعدة البيانات');
    }
    return (dbBytes: dbBytes, images: images);
  }

  // ── التصدير ──────────────────────────────────────────────

  /// يفتح حوار الحفظ ويكتب ملف ZIP. يُرجع مسار الحفظ، أو null عند الإلغاء.
  static Future<String?> exportBackup() async {
    final db = await dbFile();
    if (!await db.exists()) {
      throw StateError('لا توجد قاعدة بيانات بعد');
    }
    final imgs = await imagesDir();
    final images = <String, List<int>>{};
    if (await imgs.exists()) {
      await for (final ent in imgs.list()) {
        if (ent is File) {
          images[p.basename(ent.path)] = await ent.readAsBytes();
        }
      }
    }
    final zip = buildZip(dbBytes: await db.readAsBytes(), images: images);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'pos-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.zip';
    // حوار الحفظ يكتب البايتات بنفسه ويُرجع Uri الوجهة
    final uri = await FilePicker.saveFile(
      dialogTitle: 'حفظ النسخة الاحتياطية',
      fileName: name,
      bytes: Uint8List.fromList(zip),
    );
    if (uri == null) return null;
    return uri.toFilePath();
  }

  // ── الاستيراد ────────────────────────────────────────────

  /// يختار ملف ZIP ويفك ضغطه مستبدلاً قاعدة البيانات والصور.
  /// يُرجع true عند النجاح، وfalse إذا ألغى المستخدم الاختيار.
  /// مهم: تُغلق القاعدة الحالية — يجب إعادة تشغيل التطبيق بعدها.
  static Future<bool> importBackup(AppDatabase db) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'اختر ملف النسخة الاحتياطية (ZIP)',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = picked?.path;
    if (path == null) return false;
    final parsed = parseZip(await File(path).readAsBytes());
    // إغلاق القاعدة أولاً لتحرير ملف SQLite قبل استبداله
    await db.close();
    final dbF = await dbFile();
    await dbF.writeAsBytes(parsed.dbBytes, flush: true);
    final imgs = await imagesDir();
    if (await imgs.exists()) {
      await imgs.delete(recursive: true);
    }
    await imgs.create(recursive: true);
    for (final entry in parsed.images.entries) {
      await File(p.join(imgs.path, entry.key))
          .writeAsBytes(entry.value, flush: true);
    }
    return true;
  }

  /// يعيد تشغيل التطبيق (يُستخدم بعد الاستيراد الناجح).
  static Future<void> relaunchApp() async {
    try {
      await Process.start(Platform.resolvedExecutable, []);
    } finally {
      exit(0);
    }
  }

  /// معلومات للعرض: حجم القاعدة + عدد الصور.
  static Future<({bool hasDb, int dbKb, int imageCount})> stats() async {
    final db = await dbFile();
    final hasDb = await db.exists();
    var kb = 0;
    if (hasDb) kb = (await db.length()) ~/ 1024;
    var count = 0;
    final imgs = await imagesDir();
    if (await imgs.exists()) {
      await for (final ent in imgs.list()) {
        if (ent is File) count++;
      }
    }
    return (hasDb: hasDb, dbKb: kb, imageCount: count);
  }
}
