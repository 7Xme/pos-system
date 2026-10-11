import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// حفظ صور المنتجات محلياً + تخزين مسارها في DB
/// المسار: `<app_support>/product_images/<timestamp>.<ext>`
class ProductImageStore {
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

  static Future<String> save(File source) async {
    final dir = await getApplicationSupportDirectory();
    final imagesDir = Directory(p.join(dir.path, 'product_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final ext = p.extension(source.path).toLowerCase();
    final name = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = File(p.join(imagesDir.path, name));
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
