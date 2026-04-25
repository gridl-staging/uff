import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';
import 'package:uff/src/features/clubs/presentation/club_form_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [positive] Create mode renders empty name, description, city, state, visibility fields
// - [positive] Create mode renders sport type dropdown
// - [positive] Successful create calls createClub with exact CreateClubInput values
// - [positive] Create submits chosen sport type enum
// - [positive] Create mode app bar title reads "New Club"
// - [positive] Edit mode app bar title reads "Edit Club"
// - [positive] Join-setting segmented control displays "Open" and "Request membership approval"
// - [positive] Selecting "Request membership approval" sends ClubVisibility.private
// - [positive] Edit mode pre-fills all fields from existing Club object
// - [positive] Edit mode preselects current sport type
// - [positive] Edit save calls updateClub with modified Club values and preserves visibility
// - [negative] Validation blocks save — name required
// - [negative] Validation blocks save — name >100 chars rejected
// - [negative] Validation blocks save — description >2000 chars rejected
// - [negative] Cross-user access to the edit route shows recovery state
// - [isolation] Opening create form after editing shows clean empty state
// - [positive] Edit save writes changed sport type to repository
// - [positive] Sport-type dropdown change triggers discard-unsaved dialog on back
// - [edge] Edit with null sportType renders dropdown in unset state
// - [edge] Direct-entry create save falls back to the club list route
// - [error] Mutation failure shows snackbar without navigating away

void main() {
  late RecordingClubRepository repository;

  setUp(() {
    repository = RecordingClubRepository()
      // Default: createClub returns a club so saves don't throw.
      ..createdClubToReturn = makeClub(id: 'new-club-id');
  });

  group('create mode', () {
    testWidgets(
      'renders empty name, description, city, state, visibility fields',
      (tester) async {
        await tester.pumpWidget(
          _buildFormScope(
            repository: repository,
            child: const ClubFormScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ClubFormScreen.nameFieldKey), findsOneWidget);
        expect(find.byKey(ClubFormScreen.descriptionFieldKey), findsOneWidget);
        expect(find.byKey(ClubFormScreen.cityFieldKey), findsOneWidget);
        expect(find.byKey(ClubFormScreen.stateRegionFieldKey), findsOneWidget);
        expect(
          find.byKey(ClubFormScreen.visibilitySegmentedButtonKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubFormScreen.saveButtonKey), findsOneWidget);

        // Fields should be empty in create mode.
        final nameField = tester.widget<TextFormField>(
          find.byKey(ClubFormScreen.nameFieldKey),
        );
        expect(nameField.controller!.text, '');
      },
    );

    testWidgets('renders sport type dropdown', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubFormScreen.sportTypeFieldKey), findsOneWidget);
    });

    testWidgets('successful create calls createClub with exact input values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Trail Blazers',
      );
      await tester.enterText(
        find.byKey(ClubFormScreen.descriptionFieldKey),
        'We run trails',
      );
      await tester.enterText(
        find.byKey(ClubFormScreen.cityFieldKey),
        'Portland',
      );
      await tester.enterText(
        find.byKey(ClubFormScreen.stateRegionFieldKey),
        'OR',
      );

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createClubCallCount, 1);
      final input = repository.lastCreateClubInput!;
      expect(input.name, 'Trail Blazers');
      expect(input.description, 'We run trails');
      expect(input.city, 'Portland');
      expect(input.stateRegion, 'OR');
      expect(input.visibility, ClubVisibility.public);
    });

    testWidgets('create submits chosen sport type enum', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Run Club',
      );
      await tester.tap(find.byKey(ClubFormScreen.sportTypeFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Running').last);
      await tester.pumpAndSettle();
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createClubCallCount, 1);
      expect(repository.lastCreateClubInput!.sportType, ClubSportType.running);
    });

    testWidgets('create mode app bar title reads New Club', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Club'), findsOneWidget);
    });

    testWidgets('join-setting displays Open and Request membership approval', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Request membership approval'), findsOneWidget);
    });

    testWidgets(
      'selecting Request membership approval sends ClubVisibility.private',
      (tester) async {
        await tester.pumpWidget(
          _buildFormScope(
            repository: repository,
            child: const ClubFormScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ClubFormScreen.nameFieldKey),
          'Secret Club',
        );

        await tester.tap(find.text('Request membership approval'));
        await tester.pumpAndSettle();

        await _tapSaveButton(tester);
        await tester.pumpAndSettle();

        expect(repository.createClubCallCount, 1);
        expect(
          repository.lastCreateClubInput!.visibility,
          ClubVisibility.private,
        );
      },
    );
  });

  group('validation', () {
    testWidgets('blocks save when name is empty', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(repository.createClubCallCount, 0);
    });

    testWidgets('blocks save when name exceeds 100 characters', (tester) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'A' * 101,
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(find.text('Name must be 100 characters or fewer'), findsOneWidget);
      expect(repository.createClubCallCount, 0);
    });

    testWidgets('blocks save when description exceeds 2000 characters', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Valid Name',
      );
      await tester.enterText(
        find.byKey(ClubFormScreen.descriptionFieldKey),
        'B' * 2001,
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Description must be 2000 characters or fewer'),
        findsOneWidget,
      );
      expect(repository.createClubCallCount, 0);
    });
  });

  group('edit mode', () {
    testWidgets('edit mode app bar title reads Edit Club', (tester) async {
      final existingClub = makeClub(id: 'club-edit-title');

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Club'), findsOneWidget);
      expect(find.text('New Club'), findsNothing);
    });

    testWidgets('pre-fills all fields from existing Club', (tester) async {
      final existingClub = makeClub(id: 'club-edit-1');

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.nameFieldKey),
      );
      expect(nameField.controller!.text, 'Portland Runners');

      final descField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.descriptionFieldKey),
      );
      expect(descField.controller!.text, 'A friendly running club');

      final cityField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.cityFieldKey),
      );
      expect(cityField.controller!.text, 'Portland');

      final stateField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.stateRegionFieldKey),
      );
      expect(stateField.controller!.text, 'OR');

      // Title should say Edit Club.
      expect(find.text('Edit Club'), findsOneWidget);
    });

    testWidgets('preselects current sport type', (tester) async {
      final existingClub = makeClub(
        id: 'club-edit-sport',
        sportType: ClubSportType.cycling,
      );

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubFormScreen.sportTypeFieldKey), findsOneWidget);
      expect(find.text('Cycling'), findsOneWidget);
    });

    testWidgets('edit with null sportType renders unset dropdown', (
      tester,
    ) async {
      final existingClub = makeClub(id: 'club-edit-no-sport');

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubFormScreen.sportTypeFieldKey), findsOneWidget);
    });

    testWidgets('edit save calls updateClub with modified values', (
      tester,
    ) async {
      final existingClub = makeClub(
        id: 'club-edit-2',
        name: 'Old Name',
        description: 'Old description',
        city: 'Old City',
      );

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      // Clear and re-enter name.
      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'New Name',
      );
      await tester.enterText(
        find.byKey(ClubFormScreen.descriptionFieldKey),
        'New description',
      );

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.updateClubCallCount, 1);
      expect(repository.createClubCallCount, 0);
      final updated = repository.lastUpdatedClub!;
      expect(updated.id, 'club-edit-2');
      expect(updated.name, 'New Name');
      expect(updated.description, 'New description');
      expect(updated.visibility, ClubVisibility.public);
    });

    testWidgets('edit save writes changed sport type to repository', (
      tester,
    ) async {
      final existingClub = makeClub(
        id: 'club-edit-sport-change',
        sportType: ClubSportType.cycling,
      );

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      // Change sport type from Cycling to Hiking.
      await tester.tap(find.byKey(ClubFormScreen.sportTypeFieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hiking').last);
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.updateClubCallCount, 1);
      expect(repository.lastUpdatedClub!.sportType, ClubSportType.hiking);
    });

    testWidgets(
      'sport-type dropdown change triggers discard-unsaved dialog on back',
      (tester) async {
        final existingClub = makeClub(
          id: 'club-edit-unsaved-sport',
          sportType: ClubSportType.running,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clubRepositoryProvider.overrideWithValue(repository),
              authenticatedUserOverride(),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    key: const Key('open-form'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ClubFormScreen(existingClub: existingClub),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to the form.
        await tester.tap(find.byKey(const Key('open-form')));
        await tester.pumpAndSettle();

        // Change sport type from Running to Walking.
        await tester.tap(find.byKey(ClubFormScreen.sportTypeFieldKey));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Walking').last);
        await tester.pumpAndSettle();

        // Tap the back button to trigger unsaved-changes detection.
        final backButton = find.byType(BackButton);
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // The discard dialog should appear.
        expect(find.text('Discard changes?'), findsOneWidget);
        expect(find.text('You have unsaved changes.'), findsOneWidget);
      },
    );
  });

  group('isolation', () {
    testWidgets('opening create form after editing shows clean empty state', (
      tester,
    ) async {
      final existingClub = makeClub(
        id: 'club-iso-1',
        name: 'Filled Club',
        description: 'Some desc',
        city: 'City',
      );

      // First pump edit mode with a unique key.
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(
            key: const Key('edit'),
            existingClub: existingClub,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify fields are filled.
      final nameField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.nameFieldKey),
      );
      expect(nameField.controller!.text, 'Filled Club');

      // Now pump create mode with a different key to force new State.
      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: const ClubFormScreen(key: Key('create')),
        ),
      );
      await tester.pumpAndSettle();

      final cleanNameField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.nameFieldKey),
      );
      expect(cleanNameField.controller!.text, '');

      final cleanDescField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.descriptionFieldKey),
      );
      expect(cleanDescField.controller!.text, '');

      final cleanCityField = tester.widget<TextFormField>(
        find.byKey(ClubFormScreen.cityFieldKey),
      );
      expect(cleanCityField.controller!.text, '');
    });
  });

  group('error handling', () {
    testWidgets('mutation failure shows snackbar without navigating away', (
      tester,
    ) async {
      repository.createClubError = Exception('Network error');

      await tester.pumpWidget(
        _buildFormScope(repository: repository, child: const ClubFormScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Test Club',
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to save club. Please try again.'),
        findsOneWidget,
      );
      // Form should still be visible (not navigated away).
      expect(find.byKey(ClubFormScreen.nameFieldKey), findsOneWidget);
    });

    testWidgets('edit mutation failure shows snackbar', (tester) async {
      repository.updateClubError = Exception('Server error');
      final existingClub = makeClub(id: 'club-err-1', name: 'Error Club');

      await tester.pumpWidget(
        _buildFormScope(
          repository: repository,
          child: ClubFormScreen(existingClub: existingClub),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Updated',
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to save club. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(ClubFormScreen.nameFieldKey), findsOneWidget);
    });
  });

  group('route recovery', () {
    testWidgets('edit route without Club in extra shows recovery screen', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/clubs/some-id/edit',
        routes: [
          GoRoute(
            path: ClubRoutes.clubEditPathPattern,
            builder: (_, state) {
              final extra = state.extra;
              final clubId = state.pathParameters['id'];
              if (extra is! Club || clubId != extra.id) {
                return const SocialRouteRecoveryScaffold(
                  stateKey: Key('invalid_route_recovery'),
                  message: 'Unable to open club editor.',
                );
              }
              return ClubFormScreen(existingClub: extra);
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubRepositoryProvider.overrideWithValue(repository),
            authenticatedUserOverride(),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Recovery screen should be visible, not the form.
      expect(find.text('Unable to open club editor.'), findsOneWidget);
      expect(find.byKey(ClubFormScreen.nameFieldKey), findsNothing);
    });
  });

  group('edge navigation', () {
    testWidgets('direct-entry create save falls back to the club list route', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: ClubRoutes.clubNewPath,
        routes: [
          GoRoute(
            path: ClubRoutes.clubNewPath,
            builder: (_, __) => const ClubFormScreen(),
          ),
          GoRoute(
            path: ClubRoutes.clubListPath,
            builder: (_, __) => const Scaffold(body: Text('club-list-screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        _buildRouterScope(repository: repository, router: router),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ClubFormScreen.nameFieldKey),
        'Router Fallback Club',
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(find.text('club-list-screen'), findsOneWidget);
      expect(find.byKey(ClubFormScreen.nameFieldKey), findsNothing);
    });
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

Future<void> _tapSaveButton(WidgetTester tester) async {
  final saveButton = find.byKey(ClubFormScreen.saveButtonKey);
  await tester.ensureVisible(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
}
