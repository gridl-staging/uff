import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_form_screen.dart';

import '../../auth/presentation/auth_test_support.dart';
import '../../../test_helpers/gear_form_test_helpers.dart';
import '../../../test_helpers/gear_test_support.dart';

/// ## Test Scenarios
/// - [positive] Create mode: validates required fields, saves new gear
/// - [positive] Create mode: type selector visible, save label is "Add Gear"
/// - [positive] Edit mode: type selector hidden, save label is "Save Changes"
/// - [positive] Edit mode: preloads lifecycle fields and saves exact updates
/// - [positive] Edit mode: explicit zero initial distance preloads as `0`
/// - [positive] Edit mode: delete renders as red outlined bottom action
/// - [negative] Create mode: blank required fields show validation errors
/// - [isolation] Edit mode: existing gear ownership is preserved through save mutations
/// - [edge] Auth pending state disables save button
/// - [edge] Edit mode: clearing preloaded `0` distance to blank is not treated as unsaved
/// - [error] Delete failure shows error snackbar
/// - [error] Save failure shows error snackbar
/// - [error] Missing user shows auth error

void main() {
  testWidgets('exposes stable key contract for create and edit mode actions', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GearFormScreen.nameFieldKey), findsOneWidget);
    expect(find.byKey(GearFormScreen.brandFieldKey), findsOneWidget);
    expect(find.byKey(GearFormScreen.modelFieldKey), findsOneWidget);
    expect(find.byKey(GearFormScreen.typeSegmentedButtonKey), findsOneWidget);
    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.saveButtonKey),
    );
    expect(find.byKey(GearFormScreen.saveButtonKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(GearFormScreen.saveButtonKey),
        matching: find.text('Add Gear'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(GearFormScreen.deleteButtonKey), findsNothing);

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: testShoeGear),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GearFormScreen.typeSegmentedButtonKey), findsNothing);
    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.retireButtonKey),
    );
    expect(find.byKey(GearFormScreen.retireButtonKey), findsOneWidget);
    expect(find.byKey(GearFormScreen.deleteButtonKey), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.delete), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(GearFormScreen.saveButtonKey),
        matching: find.text('Save Changes'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(GearFormScreen.deleteButtonKey),
        matching: find.text('Delete Gear'),
      ),
      findsOneWidget,
    );
    final deleteButton = tester.widget<OutlinedButton>(
      find.byKey(GearFormScreen.deleteButtonKey),
    );
    final border = deleteButton.style?.side?.resolve(<WidgetState>{});
    expect(
      border?.color,
      Theme.of(tester.element(find.byType(GearFormScreen))).colorScheme.error,
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.deleteButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(GearFormScreen.deleteConfirmDialogKey), findsOneWidget);
  });

  testWidgets('create mode validates required name', (tester) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final formScrollable = gearFormScrollableFinder(
      find.byKey(GearFormScreen.saveButtonKey),
    );
    await tester.drag(formScrollable, const Offset(0, 2000));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(repository.createGearCallCount, 0);
  });

  testWidgets('create mode validates initial distance when provided', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Race Bike',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '-3',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid distance'), findsOneWidget);
    expect(repository.createGearCallCount, 0);
  });

  testWidgets('create mode accepts zero initial distance when provided', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Race Bike',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '0',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid distance'), findsNothing);
    expect(repository.createGearCallCount, 1);
    expect(repository.lastCreatedItem?.totalDistanceMeters, 0);
  });

  testWidgets('create mode rejects negative zero initial distance input', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Race Bike',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '-0',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid distance'), findsOneWidget);
    expect(repository.createGearCallCount, 0);
  });

  testWidgets('create mode saves new gear and invalidates list provider', (
    tester,
  ) async {
    final repository = RecordingGearRepository();
    final now = DateTime.now();
    final expectedStartDate = DateTime(now.year, now.month, now.day);

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const Stack(children: [GearFormScreen(), GearListProbe()]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Race Bike',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(GearFormScreen.typeSegmentedButtonKey),
        matching: find.text('Bike'),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(GearFormScreen.brandFieldKey),
      'Specialized',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.modelFieldKey),
      'Tarmac SL8',
    );
    await tester.tap(find.byKey(GearFormScreen.startDateButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '1200.5',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.notesFieldKey),
      'Imported from previous tracking app',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.createGearCallCount, 1);
    expect(repository.lastCreatedItem?.id, '');
    expect(repository.lastCreatedItem?.userId, 'user-1');
    expect(repository.lastCreatedItem?.name, 'Race Bike');
    expect(repository.lastCreatedItem?.gearType, GearType.bike);
    expect(repository.lastCreatedItem?.startDate, expectedStartDate);
    expect(repository.lastCreatedItem?.brand, 'Specialized');
    expect(repository.lastCreatedItem?.model, 'Tarmac SL8');
    expect(repository.lastCreatedItem?.totalDistanceMeters, 1200.5);
    expect(
      repository.lastCreatedItem?.notes,
      'Imported from previous tracking app',
    );
    expect(repository.lastCreatedItem?.retired, isFalse);
    expect(repository.loadGearCallCount, 2);
  });

  testWidgets(
    'create mode ignores repeated saves while auth lookup is pending',
    (tester) async {
      final repository = RecordingGearRepository();
      final sessionCompleter = Completer<AuthState>();

      await tester.pumpWidget(
        buildGearFormScope(
          repository: repository,
          authRepository: DelayedSessionAuthRepository(sessionCompleter),
          authStateChanges: const Stream<AuthState>.empty(),
          child: const GearFormScreen(),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(GearFormScreen.nameFieldKey),
        'Race Bike',
      );

      final saveButton = find.byKey(GearFormScreen.saveButtonKey);
      await scrollToGearFormAction(tester, saveButton);
      await tapGearFormAction(tester, saveButton);
      await tester.pump();

      expect(repository.createGearCallCount, 0);

      await tapGearFormAction(tester, saveButton);
      await tester.pump();

      sessionCompleter.complete(
        const AuthState.authenticated(
          userId: 'user-1',
          email: 'user@example.com',
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.createGearCallCount, 1);
    },
  );

  testWidgets('create mode normalizes blank optional fields to null', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Trail Shoe',
    );
    await tester.enterText(find.byKey(GearFormScreen.brandFieldKey), '   ');
    await tester.enterText(find.byKey(GearFormScreen.modelFieldKey), '\t');

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.createGearCallCount, 1);
    expect(repository.lastCreatedItem?.brand, isNull);
    expect(repository.lastCreatedItem?.model, isNull);
  });

  testWidgets('edit mode preloads values and saves updates', (tester) async {
    final repository = RecordingGearRepository();
    final existingItem = testShoeGearWithLifecycleFields;

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: Stack(
          children: [
            GearFormScreen(existingItem: existingItem),
            const GearListProbe(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Gear'), findsOneWidget);
    expect(find.byKey(GearFormScreen.typeSegmentedButtonKey), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(GearFormScreen.nameFieldKey))
          .controller
          ?.text,
      'Daily Trainer',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Workout Shoe',
    );
    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.deleteButtonKey),
    );
    expect(find.byKey(GearFormScreen.deleteButtonKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(GearFormScreen.saveButtonKey),
        matching: find.text('Save Changes'),
      ),
      findsOneWidget,
    );
    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.initialDistanceFieldKey),
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(GearFormScreen.initialDistanceFieldKey),
          )
          .controller
          ?.text,
      '120500',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(GearFormScreen.notesFieldKey))
          .controller
          ?.text,
      'Everyday training pair',
    );

    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.initialDistanceFieldKey),
    );
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '131000',
    );
    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.notesFieldKey),
    );
    await tester.enterText(
      find.byKey(GearFormScreen.notesFieldKey),
      'Updated mileage after import cleanup',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.updateGearCallCount, 1);
    expect(repository.lastUpdatedItem?.id, existingItem.id);
    expect(repository.lastUpdatedItem?.userId, existingItem.userId);
    expect(repository.lastUpdatedItem?.name, 'Workout Shoe');
    expect(repository.lastUpdatedItem?.gearType, GearType.shoe);
    expect(repository.lastUpdatedItem?.totalDistanceMeters, 131000);
    expect(repository.lastUpdatedItem?.startDate, DateTime(2024, 3, 5));
    expect(
      repository.lastUpdatedItem?.notes,
      'Updated mileage after import cleanup',
    );
    expect(repository.lastUpdatedItem?.retired, isFalse);
    expect(repository.createGearCallCount, 0);
    expect(repository.loadGearCallCount, 2);
  });

  testWidgets('edit mode preloads explicit zero initial distance as 0', (
    tester,
  ) async {
    final repository = RecordingGearRepository();
    const existingItem = GearItem(
      id: 'gear-zero-distance',
      userId: 'user-1',
      name: 'Fresh Shoes',
      gearType: GearType.shoe,
      totalDistanceMeters: 0,
      retired: false,
    );

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: existingItem),
      ),
    );
    await tester.pumpAndSettle();

    await scrollToGearFormAction(
      tester,
      find.byKey(GearFormScreen.initialDistanceFieldKey),
    );
    final initialDistanceField = tester.widget<TextFormField>(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
    );
    expect(initialDistanceField.controller?.text, '0');
  });

  testWidgets('edit mode rejects negative zero initial distance input', (
    tester,
  ) async {
    final repository = RecordingGearRepository();
    final existingItem = testShoeGearWithLifecycleFields;

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: GearFormScreen(existingItem: existingItem),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '-0',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid distance'), findsOneWidget);
    expect(repository.updateGearCallCount, 0);
  });

  testWidgets(
    'edit mode clearing preloaded zero distance to blank exits without discard prompt',
    (tester) async {
      final repository = RecordingGearRepository();
      const existingItem = GearItem(
        id: 'gear-zero-distance',
        userId: 'user-1',
        name: 'Fresh Shoes',
        gearType: GearType.shoe,
        totalDistanceMeters: 0,
        retired: false,
      );

      await tester.pumpWidget(
        buildPoppableGearFormScope(
          repository: repository,
          child: const GearFormScreen(existingItem: existingItem),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(GearFormScreen.initialDistanceFieldKey),
        '',
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text(gearFormExitRouteLabel), findsOneWidget);
      expect(find.byType(GearFormScreen), findsNothing);
    },
  );

  testWidgets('edit mode toggles retire status using current form values', (
    tester,
  ) async {
    final repository = RecordingGearRepository();
    final existingItem = testShoeGearWithLifecycleFields;

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: GearFormScreen(existingItem: existingItem),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Retired Bike',
    );
    await tester.enterText(find.byKey(GearFormScreen.brandFieldKey), 'Canyon');
    await tester.enterText(
      find.byKey(GearFormScreen.modelFieldKey),
      'Endurace',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.initialDistanceFieldKey),
      '120600',
    );
    await tester.enterText(
      find.byKey(GearFormScreen.notesFieldKey),
      'Ready to retire',
    );

    await tapGearFormAction(tester, find.byKey(GearFormScreen.retireButtonKey));
    await tester.pumpAndSettle();

    expect(repository.updateGearCallCount, 1);
    expect(repository.lastUpdatedItem?.name, 'Retired Bike');
    expect(repository.lastUpdatedItem?.gearType, GearType.shoe);
    expect(repository.lastUpdatedItem?.brand, 'Canyon');
    expect(repository.lastUpdatedItem?.model, 'Endurace');
    expect(repository.lastUpdatedItem?.totalDistanceMeters, 120600);
    expect(repository.lastUpdatedItem?.notes, 'Ready to retire');
    expect(repository.lastUpdatedItem?.retired, isTrue);
  });

  testWidgets('edit mode deletes gear after confirmation', (tester) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: testShoeGear),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(GearFormScreen.deleteButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Delete gear?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteGearCallCount, 1);
    expect(repository.lastDeletedId, testShoeGear.id);
  });

  testWidgets('edit mode canceling delete keeps item untouched', (
    tester,
  ) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: testShoeGear),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(GearFormScreen.deleteButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Delete gear?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteGearCallCount, 0);
    expect(find.text('Edit Gear'), findsOneWidget);
  });

  testWidgets('delete failure shows snackbar and keeps screen active', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      deleteGearError: StateError('delete failed'),
    );

    await tester.pumpWidget(
      buildGearFormScope(
        repository: repository,
        child: const GearFormScreen(existingItem: testShoeGear),
      ),
    );
    await tester.pumpAndSettle();

    await tapGearFormAction(tester, find.byKey(GearFormScreen.deleteButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteGearCallCount, 1);
    expect(repository.lastDeletedId, testShoeGear.id);
    expect(
      find.text('Unable to delete gear. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Edit Gear'), findsOneWidget);
  });

  testWidgets('save failure shows snackbar and keeps screen active', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      createGearError: StateError('save failed'),
    );

    await tester.pumpWidget(
      buildGearFormScope(repository: repository, child: const GearFormScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GearFormScreen.nameFieldKey),
      'Tempo Shoe',
    );
    await tapGearFormAction(tester, find.byKey(GearFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.createGearCallCount, 1);
    expect(find.text('Unable to save gear. Please try again.'), findsOneWidget);
    expect(find.text('Add Gear'), findsOneWidget);
  });

  testWidgets(
    'create mode with missing user id shows snackbar and does not save',
    (tester) async {
      final repository = RecordingGearRepository();

      await tester.pumpWidget(
        buildGearFormScope(
          repository: repository,
          authRepository: RecordingAuthRepository(),
          authStateChanges: Stream<AuthState>.value(
            const AuthState.unauthenticated(),
          ),
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

      expect(repository.createGearCallCount, 0);
      expect(
        find.text('Unable to save gear. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Add Gear'), findsOneWidget);
    },
  );
}
