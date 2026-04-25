import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

/// ## Test Scenarios
/// - `[positive]` Follow-relationship status maps to exact labels and button variants.
/// - `[edge]` Avatar and display-name fallbacks render deterministic placeholders.
/// - `[negative]` Insecure avatar URLs are rejected and fall back to local placeholders.
/// - `[isolation]` Row-tap and follow-action callbacks remain independently scoped.
/// - `[positive]` Row taps and follow-action taps trigger independent callbacks.
void main() {
  // -- Test data builder ----------------------------------------------------

  SocialUserSummary makeUser({
    String userId = 'u1',
    String? displayName = 'Test User',
    String? avatarUrl,
    FollowRelationshipStatus status = FollowRelationshipStatus.none,
    String? followId,
  }) {
    return SocialUserSummary(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      relationship: FollowRelationship(
        currentUserId: 'viewer-1',
        targetUserId: userId,
        status: status,
        followId: followId,
      ),
    );
  }

  Widget buildRow(
    SocialUserSummary user, {
    VoidCallback? onFollowAction,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SocialUserRow(
          user: user,
          onFollowAction: onFollowAction,
          onTap: onTap,
        ),
      ),
    );
  }

  // -- Status → label + button type ----------------------------------------

  group('follow status rendering', () {
    testWidgets('none status renders Follow label in FilledButton', (
      tester,
    ) async {
      final user = makeUser();
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('Follow'), findsOneWidget);
      final actionFinder = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(actionFinder, findsOneWidget);
      expect(tester.widget<Widget>(actionFinder).runtimeType, FilledButton);
    });

    testWidgets('outgoingPending status renders Requested in OutlinedButton', (
      tester,
    ) async {
      final user = makeUser(status: FollowRelationshipStatus.outgoingPending);
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('Requested'), findsOneWidget);
      final actionFinder = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(actionFinder, findsOneWidget);
      expect(tester.widget<Widget>(actionFinder).runtimeType, OutlinedButton);
    });

    testWidgets('incomingPending status renders Accept in FilledButton', (
      tester,
    ) async {
      final user = makeUser(
        status: FollowRelationshipStatus.incomingPending,
        followId: 'f1',
      );
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('Accept'), findsOneWidget);
      final actionFinder = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(actionFinder, findsOneWidget);
      expect(tester.widget<Widget>(actionFinder).runtimeType, FilledButton);
    });

    testWidgets('following status renders Following in OutlinedButton', (
      tester,
    ) async {
      final user = makeUser(status: FollowRelationshipStatus.following);
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('Following'), findsOneWidget);
      final actionFinder = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(actionFinder, findsOneWidget);
      expect(tester.widget<Widget>(actionFinder).runtimeType, OutlinedButton);
    });
  });

  // -- Avatar fallback ------------------------------------------------------

  group('avatar fallback', () {
    testWidgets('null avatarUrl renders initials fallback from displayName', (
      tester,
    ) async {
      final user = makeUser();
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('TU'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets(
      'null avatarUrl and null displayName render person icon fallback',
      (tester) async {
        final user = makeUser(displayName: null);
        await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

        expect(find.byIcon(Icons.person), findsOneWidget);
      },
    );

    testWidgets(
      'null avatarUrl and blank displayName render person icon fallback',
      (tester) async {
        final user = makeUser(displayName: '  ');
        await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

        expect(find.byIcon(Icons.person), findsOneWidget);
      },
    );

    testWidgets('http avatarUrl is rejected and initials are shown', (
      tester,
    ) async {
      final user = makeUser(avatarUrl: 'http://example.com/avatar.png');
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('TU'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets('non-null avatarUrl renders no person icon', (tester) async {
      final user = makeUser(avatarUrl: 'https://example.com/avatar.png');
      // Suppress the expected NetworkImage 400 from the test HTTP client.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));
      await tester.pump();

      expect(find.byIcon(Icons.person), findsNothing);
    });
  });

  // -- DisplayName fallback -------------------------------------------------

  group('displayName fallback', () {
    testWidgets('null displayName falls back to userId', (tester) async {
      final user = makeUser(userId: 'test-id', displayName: null);
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('test-id'), findsOneWidget);
    });

    testWidgets('blank displayName falls back to userId', (tester) async {
      final user = makeUser(userId: 'blank-id', displayName: '   ');
      await tester.pumpWidget(buildRow(user, onFollowAction: () {}));

      expect(find.text('blank-id'), findsOneWidget);
    });
  });

  // -- Callbacks ------------------------------------------------------------

  group('callbacks', () {
    testWidgets('onTap fires on row tap, onFollowAction fires on button tap', (
      tester,
    ) async {
      var rowTapCount = 0;
      var actionTapCount = 0;
      final user = makeUser();

      await tester.pumpWidget(
        buildRow(
          user,
          onTap: () => rowTapCount += 1,
          onFollowAction: () => actionTapCount += 1,
        ),
      );

      // Tap the row body (not the action button).
      await tester.tap(find.byKey(SocialUserRow.userRowKey('u1')));
      await tester.pump();
      expect(rowTapCount, 1);
      expect(actionTapCount, 0);

      // Tap the action button and ensure callbacks remain independent.
      await tester.tap(find.byKey(SocialUserRow.actionButtonKey('u1')));
      await tester.pump();
      expect(rowTapCount, 1);
      expect(actionTapCount, 1);
    });
  });
}
