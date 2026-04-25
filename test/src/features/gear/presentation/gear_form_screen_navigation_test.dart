import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_form_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';

import '../../../test_helpers/gear_form_test_helpers.dart';
import '../../../test_helpers/gear_test_support.dart';

/// ## Test Scenarios
/// - [positive] Clean form exits immediately on back
/// - [positive] Direct-entry save falls back to gear list route
/// - [negative] Dirty form keeps user on form until changes are discarded
/// - [negative] Save failure keeps unsaved-change guard active
/// - [isolation] In-flight mutations block route-exit side effects
/// - [edge] Start date, distance, and notes count as unsaved edits
void main() {
  testWidgets('clean form exits immediately on back', (tester) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text(gearFormExitRouteLabel), findsOneWidget);
    expect(find.byType(GearFormScreen), findsNothing);
  });

  testWidgets('dirty form shows discard prompt and stay keeps edits', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Tempo Shoe',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('You have unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextFormField>(
      find.byKey(GearFormScreen.nameFieldKey),
    );
    expect(nameField.controller?.text, 'Tempo Shoe');
    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);
  });

  testWidgets('dirty form treats initial distance and notes as unsaved edits', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '75',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.notesFieldKey),
      'Travel shoe',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);
  });

  testWidgets('dirty form treats start date selection as unsaved edit', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GearFormScreen.startDateButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);
  });

  testWidgets('save failure keeps unsaved-change back guard active', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      createGearError: StateError('save failed'),
    );

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Tempo Shoe',
    );
    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);
  });

  testWidgets('back navigation is ignored while create save is in flight', (
    tester,
  ) async {
    final repository = RecordingGearRepository()
      ..createGearCompleter = Completer<GearItem>();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Tempo Shoe',
    );
    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);

    repository.createGearCompleter!.complete(repository.lastCreatedItem!);
    await tester.pumpAndSettle();
  });

  testWidgets('direct-entry save falls back to gear list route on success', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildDirectRouteGearFormScope(
        repository: repository,
        initialLocation: GearRoutes.gearNewPath,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Tempo Shoe',
    );
    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.createGearCallCount, 1);
    expect(find.text(gearListRouteLabel), findsOneWidget);
    expect(find.byType(GearFormScreen), findsNothing);
  });

  testWidgets('back navigation is blocked while retire mutation is in flight', (
    tester,
  ) async {
    final repository = RecordingGearRepository()
      ..updateGearCompleter = Completer<void>();

    await tester.pumpWidget(
      buildPoppableGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: testShoeGear),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(GearFormScreen.retireButtonKey));
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(find.byType(GearFormScreen), findsOneWidget);
    expect(find.text(gearFormExitRouteLabel), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);

    repository.updateGearCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
