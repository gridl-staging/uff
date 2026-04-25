import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity_detail_screen_test.dart stays under the hard size limit', () {
    final file = File(
      'test/src/features/activity_tracking/presentation/activity_detail_screen_test.dart',
    );
    final lineCount = file.readAsLinesSync().length;

    expect(
      lineCount,
      lessThanOrEqualTo(900),
      reason:
          'activity_detail_screen_test.dart must stay at or below 900 lines.',
    );
  });

  test('delete execution-path cases are not duplicated across test files', () {
    final duplicateFile = File(
      'test/src/features/activity_tracking/presentation/activity_detail_screen_delete_test.dart',
    ).readAsStringSync();

    expect(
      duplicateFile,
      isNot(
        contains(
          'confirming delete calls local deleteActivity and navigates away',
        ),
      ),
      reason:
          'Delete execution-path assertions are centralized in activity_detail_screen_test.dart.',
    );
  });
}
