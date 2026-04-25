import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('submission config security checks', () {
    test(
      'iOS export-compliance key is declared as non-exempt encryption false',
      () {
        final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

        expect(
          infoPlist,
          matches(
            RegExp(
              r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>',
              multiLine: true,
            ),
          ),
        );
      },
    );

    test(
      'iOS does not declare a temporary full-accuracy location purpose key',
      () {
        final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

        expect(
          infoPlist,
          isNot(contains('NSLocationTemporaryUsageDescriptionDictionary')),
        );
      },
    );

    test('Android manifest does not request POST_NOTIFICATIONS yet', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        isNot(contains('android.permission.POST_NOTIFICATIONS')),
      );
    });
  });
}
