import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gear_form_test_helpers.dart';

// ## Test Scenarios
// - [positive] tap helper drives Flutter gesture pipeline when action is hit-testable
// - [edge] tap helper falls back to direct callback only when action is not hit-testable
void main() {
  testWidgets('tapGearFormAction uses a real tap for hit-testable actions', (
    tester,
  ) async {
    const actionKey = Key('gear-form-action');
    var pointerDownCount = 0;
    var actionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => pointerDownCount += 1,
              child: Column(
                children: [
                  const SizedBox(height: 800),
                  ElevatedButton(
                    key: actionKey,
                    onPressed: () => actionCount += 1,
                    child: const Text('Save'),
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(actionKey));

    expect(actionCount, 1);
    expect(pointerDownCount, 1);
  });

  testWidgets('tapGearFormAction falls back when action is not hit-testable', (
    tester,
  ) async {
    const actionKey = Key('gear-form-hidden-action');
    var actionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 800),
                IgnorePointer(
                  child: ElevatedButton(
                    key: actionKey,
                    onPressed: () => actionCount += 1,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(actionKey));

    expect(actionCount, 1);
  });
}
