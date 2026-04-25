import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/presentation/copyable_error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copies the message and shows feedback when tapped', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CopyableErrorText('StorageException(message: boom)'),
        ),
      ),
    );

    await tester.tap(find.text('StorageException(message: boom)'));
    await tester.pump();

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, 'StorageException(message: boom)');
    expect(find.text('Copied error message.'), findsOneWidget);
  });
}
