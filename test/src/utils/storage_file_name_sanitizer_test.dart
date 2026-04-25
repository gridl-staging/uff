import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/utils/storage_file_name_sanitizer.dart';

void main() {
  group('sanitizeStorageFileName', () {
    const fallbackName = 'default_photo';

    test('keeps allowed characters unchanged', () {
      expect(
        sanitizeStorageFileName('my_photo-1.jpg', fallbackName: fallbackName),
        'my_photo-1.jpg',
      );
      expect(
        sanitizeStorageFileName('UPPER.PNG', fallbackName: fallbackName),
        'UPPER.PNG',
      );
    });

    test('removes path traversal segments and separators', () {
      expect(
        sanitizeStorageFileName('../../etc/passwd', fallbackName: fallbackName),
        'passwd',
      );
      expect(
        sanitizeStorageFileName(
          r'..\..\windows\system32',
          fallbackName: fallbackName,
        ),
        'system32',
      );
      expect(
        sanitizeStorageFileName(
          'subfolder/image.png',
          fallbackName: fallbackName,
        ),
        'image.png',
      );
    });

    test('replaces special characters and unicode with underscores', () {
      expect(
        sanitizeStorageFileName(
          'héllo wörld!@#.jpg',
          fallbackName: fallbackName,
        ),
        'h_llo_w_rld___.jpg',
      );
      expect(
        sanitizeStorageFileName('photo (1).jpg', fallbackName: fallbackName),
        'photo__1_.jpg',
      );
    });

    test('strips only leading dots', () {
      expect(
        sanitizeStorageFileName('.hidden', fallbackName: fallbackName),
        'hidden',
      );
      expect(
        sanitizeStorageFileName('...triple', fallbackName: fallbackName),
        'triple',
      );
      expect(
        sanitizeStorageFileName('no.dots.txt', fallbackName: fallbackName),
        'no.dots.txt',
      );
    });

    test('uses fallback only when sanitized name is truly empty', () {
      expect(
        sanitizeStorageFileName('', fallbackName: fallbackName),
        fallbackName,
      );
      expect(
        sanitizeStorageFileName(r'@#$%', fallbackName: fallbackName),
        '____',
      );
      expect(
        sanitizeStorageFileName('...', fallbackName: fallbackName),
        fallbackName,
      );
    });
  });
}
