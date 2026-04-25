import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/presentation/club_run_form_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [positive] Form renders title, description, meeting point, distance, pace fields and date/time picker
// - [positive] Save button stays disabled until required title is present
// - [positive] Successful create calls createClubRun with exact CreateClubRunInput values
// - [edge] Meeting point field renders above description to match screen spec order
// - [negative] Validation blocks save — title required
// - [negative] Validation blocks save — scheduledAt in the past rejected
// - [isolation] Consecutive form opens show clean state
// - [edge] Direct-entry create save falls back to the club detail route
// - [error] Mutation failure shows snackbar without exiting

void main() {
  late RecordingClubRepository repository;

  setUp(() {
    repository = RecordingClubRepository()
      ..createdRunToReturn = makeClubRun(id: 'new-run-id', title: 'Test Run');
  });

  group('form fields', () {
    testWidgets(
      'renders title, description, meeting point, distance, pace fields',
      (tester) async {
        await tester.pumpWidget(
          _buildFormScope(
            repository: repository,
            child: const ClubRunFormScreen(clubId: 'club-1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ClubRunFormScreen.titleFieldKey), findsOneWidget);
        expect(
          find.byKey(ClubRunFormScreen.descriptionFieldKey),
          findsOneWidget,
        );
        expect(
          find.byKey(ClubRunFormScreen.meetingPointFieldKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubRunFormScreen.distanceFieldKey), findsOneWidget);
        expect(find.byKey(ClubRunFormScreen.paceFieldKey), findsOneWidget);
        expect(
          find.byKey(ClubRunFormScreen.datePickerButtonKey),
          findsOneWidget,
        );
        expect(
          find.byKey(ClubRunFormScreen.timePickerButtonKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubRunFormScreen.saveButtonKey), findsOneWidget);
      },
    );

    testWidgets('meeting point field appears above description field', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      final meetingPointFinder = find.byKey(
        ClubRunFormScreen.meetingPointFieldKey,
      );
      final descriptionFinder = find.byKey(
        ClubRunFormScreen.descriptionFieldKey,
      );

      await tester.ensureVisible(meetingPointFinder);
      await tester.ensureVisible(descriptionFinder);

      final meetingPointTop = tester.getTopLeft(meetingPointFinder).dy;
      final descriptionTop = tester.getTopLeft(descriptionFinder).dy;

      expect(meetingPointTop < descriptionTop, true);
    });

    testWidgets('save button label matches screen spec', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      final saveLabelFinder = find.descendant(
        of: find.byKey(ClubRunFormScreen.saveButtonKey),
        matching: find.text('Schedule Run'),
      );
      expect(saveLabelFinder, findsOneWidget);
    });
  });

  group('create', () {
    testWidgets(
      'successful create calls createClubRun with exact input values',
      (tester) async {
        await tester.pumpWidget(
          _buildFormScope(
            repository: repository,
            child: const ClubRunFormScreen(clubId: 'club-abc'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ClubRunFormScreen.titleFieldKey),
          'Morning 5K',
        );
        await tester.enterText(
          find.byKey(ClubRunFormScreen.descriptionFieldKey),
          'Easy pace group run',
        );
        await tester.enterText(
          find.byKey(ClubRunFormScreen.meetingPointFieldKey),
          'Park entrance',
        );
        await tester.enterText(
          find.byKey(ClubRunFormScreen.distanceFieldKey),
          '5.0',
        );
        await tester.enterText(
          find.byKey(ClubRunFormScreen.paceFieldKey),
          'Easy 6:00/km',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ClubRunFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(repository.createClubRunCallCount, 1);
        final input = repository.lastCreateClubRunInput!;
        expect(input.clubId, 'club-abc');
        expect(input.title, 'Morning 5K');
        expect(input.description, 'Easy pace group run');
        expect(input.meetingPointName, 'Park entrance');
        expect(input.distanceMeters, 5000.0);
        expect(input.paceDescription, 'Easy 6:00/km');
        // scheduledAt should be in the future (default is tomorrow).
        expect(input.scheduledAt.isAfter(DateTime.now()), isTrue);
      },
    );
  });

  group('validation', () {
    testWidgets(
      'save button is disabled until title is entered while default date and time stay unchanged',
      (tester) async {
        await tester.pumpWidget(
          _buildFormScope(
            repository: repository,
            child: const ClubRunFormScreen(clubId: 'club-1'),
          ),
        );
        await tester.pumpAndSettle();

        final dateLabelFinder = find.descendant(
          of: find.byKey(ClubRunFormScreen.datePickerButtonKey),
          matching: find.byType(Text),
        );
        final timeLabelFinder = find.descendant(
          of: find.byKey(ClubRunFormScreen.timePickerButtonKey),
          matching: find.byType(Text),
        );
        final initialDateLabel = tester
            .widget<Text>(dateLabelFinder.first)
            .data;
        final initialTimeLabel = tester
            .widget<Text>(timeLabelFinder.first)
            .data;

        ElevatedButton saveButton() => tester.widget<ElevatedButton>(
          find.byKey(ClubRunFormScreen.saveButtonKey),
        );

        expect(saveButton().onPressed == null, true);

        await tester.enterText(
          find.byKey(ClubRunFormScreen.titleFieldKey),
          'Morning Run',
        );
        await tester.pumpAndSettle();

        expect(saveButton().onPressed == null, false);
        expect(
          tester.widget<Text>(dateLabelFinder.first).data,
          initialDateLabel,
        );
        expect(
          tester.widget<Text>(timeLabelFinder.first).data,
          initialTimeLabel,
        );
      },
    );

    testWidgets('save stays disabled when title is empty', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(ClubRunFormScreen.saveButtonKey),
      );
      expect(saveButton.onPressed == null, true);

      await tester.tap(find.byKey(ClubRunFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(repository.createClubRunCallCount, 0);
    });

    testWidgets('blocks save when scheduledAt is in the past', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubRunFormScreen(
            clubId: 'club-1',
            initialDate: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
            ),
            initialTime: const TimeOfDay(hour: 8, minute: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubRunFormScreen.titleFieldKey),
        'Past Run',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ClubRunFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      // Save should be rejected with a snackbar error.
      expect(
        find.text('Scheduled time must be in the future.'),
        findsOneWidget,
      );
      expect(repository.createClubRunCallCount, 0);
    });
  });

  group('isolation', () {
    testWidgets('consecutive form opens show clean state', (tester) async {
      // First form with data entered.
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(key: Key('form-1'), clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubRunFormScreen.titleFieldKey),
        'First Run',
      );

      final titleField1 = tester.widget<TextFormField>(
        find.byKey(ClubRunFormScreen.titleFieldKey),
      );
      expect(titleField1.controller!.text, 'First Run');

      // Second form with different key to force new State.
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(key: Key('form-2'), clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      final titleField2 = tester.widget<TextFormField>(
        find.byKey(ClubRunFormScreen.titleFieldKey),
      );
      expect(titleField2.controller!.text, '');
    });
  });

  group('error handling', () {
    testWidgets('mutation failure shows snackbar without exiting', (
      tester,
    ) async {
      repository.createClubRunError = Exception('Network error');

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubRunFormScreen(clubId: 'club-1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubRunFormScreen.titleFieldKey),
        'Error Run',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClubRunFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to schedule run. Please try again.'),
        findsOneWidget,
      );
      // Form should still be visible.
      expect(find.byKey(ClubRunFormScreen.titleFieldKey), findsOneWidget);
    });
  });

  group('edge navigation', () {
    testWidgets(
      'direct-entry create save falls back to the club detail route',
      (tester) async {
        final router = GoRouter(
          initialLocation: ClubRoutes.clubRunNewPath('club-abc'),
          routes: [
            GoRoute(
              path: ClubRoutes.clubRunNewPathPattern,
              builder: (_, state) =>
                  ClubRunFormScreen(clubId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: ClubRoutes.clubDetailPathPattern,
              builder: (_, state) => Scaffold(
                body: Text('club-detail-screen:${state.pathParameters['id']}'),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          _buildRouterScope(repository: repository, router: router),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ClubRunFormScreen.titleFieldKey),
          'Direct Entry Run',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ClubRunFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('club-detail-screen:club-abc'), findsOneWidget);
        expect(find.byKey(ClubRunFormScreen.titleFieldKey), findsNothing);
      },
    );
  });
}

Widget _buildFormScope({
  required RecordingClubRepository repository,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      authenticatedUserOverride(),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget _buildRouterScope({
  required RecordingClubRepository repository,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      authenticatedUserOverride(),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
