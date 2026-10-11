import 'package:archive/archive.dart';
import 'package:bookstore_pos/core/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupService ZIP', () {
    test('بناء ثم فك ZIP يحافظ على القاعدة والصور', () {
      final dbBytes = List<int>.generate(256, (i) => i % 256);
      final images = {
        'a.jpg': [1, 2, 3, 4],
        'b.png': [5, 6, 7],
      };
      final zip = BackupService.buildZip(dbBytes: dbBytes, images: images);
      expect(zip.isNotEmpty, true);

      final parsed = BackupService.parseZip(zip);
      expect(parsed.dbBytes, dbBytes);
      expect(parsed.images.keys.toSet(), {'a.jpg', 'b.png'});
      expect(parsed.images['a.jpg'], [1, 2, 3, 4]);
    });

    test('ZIP بدون صور يعمل', () {
      final zip = BackupService.buildZip(
        dbBytes: [9, 9, 9],
        images: {},
      );
      final parsed = BackupService.parseZip(zip);
      expect(parsed.dbBytes, [9, 9, 9]);
      expect(parsed.images, isEmpty);
    });

    test('ملف غير صالح يرمي خطأ واضحاً', () {
      expect(
        () => BackupService.parseZip([1, 2, 3]),
        throwsA(isA<StateError>()),
      );
    });

    test('ZIP بدون قاعدة بيانات يرمي خطأ واضحاً', () {
      final archive = Archive()
        ..addFile(ArchiveFile('product_images/x.jpg', 2, [1, 2]));
      final zip = ZipEncoder().encode(archive);
      expect(
        () => BackupService.parseZip(zip),
        throwsA(isA<StateError>()),
      );
    });
  });
}
