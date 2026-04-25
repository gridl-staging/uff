import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/features/social/presentation/remote_activity_detail_screen.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Seeded social feed card renders and supports navigation to
//   viewed-user profile and remote activity detail.
// - [positive] Viewer opens seeded feed activity and sees
//   RemoteActivityDetailScreen.photoStripKey on remote detail when photos are
//   available.
// - [edge] Remote detail hides the route preview when masking leaves fewer
//   than two viewer-visible route points.
// - [negative] After same-client account switch, the second account does not
//   see the first account's seeded feed activity card.
// - [isolation] Sign-out and re-login in the same app instance reloads feed
//   state for the new account and clears prior account feed data.
void main() {
  patrolTest(
    'seeded social feed navigates to masked remote detail without route preview',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedSocialScenario(
        maskFeedActivityForViewer: true,
      );
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupSocialScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      // Auth is pre-seeded; app just needs to render. Measured <1s; 20s
      // ceiling accommodates cold-start or slow CI.
      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);

      final feedCardFinder = find.byKey(
        FeedScreen.feedCardKey(scenario.feedActivityId),
      );
      // Feed card renders after API fetch; measured <2s, 15s for slow backend.
      await $(
        feedCardFinder,
      ).waitUntilVisible(timeout: const Duration(seconds: 15));
      await $(find.text(scenario.feedActivityTitle)).waitUntilVisible();

      await $(
        find.byKey(FeedScreen.ownerTapTargetKey(scenario.feedActivityId)),
      ).tap();
      await $(
        find.byKey(ViewedUserProfileScreen.headerCardKey),
      ).waitUntilVisible();

      await $(find.byTooltip('Back')).tap();
      await $(feedCardFinder).waitUntilVisible();

      await $(
        find.byKey(FeedScreen.activityTapTargetKey(scenario.feedActivityId)),
      ).tap();
      await $(
        find.byKey(RemoteActivityDetailScreen.contentStateKey),
      ).waitUntilVisible();
      await $(find.text(scenario.feedActivityTitle)).waitUntilVisible();
      expect(
        find.byKey(RemoteActivityDetailScreen.routePreviewKey),
        findsNothing,
      );
    },
  );

  patrolTest(
    'seeded social remote detail shows photo strip when photos are available',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedSocialScenario();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupSocialScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      // Auth is pre-seeded; app just needs to render. Measured <1s; 20s
      // ceiling accommodates cold-start or slow CI.
      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);

      final feedCardFinder = find.byKey(
        FeedScreen.feedCardKey(scenario.feedActivityId),
      );
      // Feed card renders after API fetch; measured <2s, 15s for slow backend.
      await $(
        feedCardFinder,
      ).waitUntilVisible(timeout: const Duration(seconds: 15));
      await $(find.text(scenario.feedActivityTitle)).waitUntilVisible();

      await $(
        find.byKey(FeedScreen.activityTapTargetKey(scenario.feedActivityId)),
      ).tap();
      await $(
        find.byKey(RemoteActivityDetailScreen.contentStateKey),
      ).waitUntilVisible();
      await $(find.text(scenario.feedActivityTitle)).waitUntilVisible();

      // Remote detail content renders before signed photo previews settle on
      // slower hosted runs, so wait for the strip rather than asserting
      // immediately after the route opens.
      await $(
        find.byKey(RemoteActivityDetailScreen.photoStripKey),
      ).waitUntilVisible();
    },
  );

  patrolTest(
    'seeded feed hides followed activity after same-client account switch',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedSocialScenario();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupSocialScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      // Auth pre-seeded; measured <1s, 20s ceiling for cold-start.
      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);

      final feedCardFinder = find.byKey(
        FeedScreen.feedCardKey(scenario.feedActivityId),
      );
      // Feed card after nav; measured <2s, 15s for slow backend.
      await $(
        feedCardFinder,
      ).waitUntilVisible(timeout: const Duration(seconds: 15));
      await $(find.text(scenario.feedActivityTitle)).waitUntilVisible();

      await navigateToHomeShellDestination($, HomeShellDestinationId.profile);
      await openSettingsAndRevealSignOutButton($);
      await $(find.byKey(SettingsScreen.signOutButtonKey)).waitUntilVisible();
      await $(find.byKey(SettingsScreen.signOutButtonKey)).tap();

      // Sign-out → login screen is a local state transition; 15s ceiling.
      await $(
        find.byKey(LoginScreen.emailFieldKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 15));
      await $(
        find.byKey(LoginScreen.emailFieldKey),
      ).enterText(scenario.searchTarget.email);
      await $(
        find.byKey(LoginScreen.passwordFieldKey),
      ).enterText(scenario.searchTarget.password);
      await $(find.byKey(LoginScreen.signInButtonKey)).tap();

      // Full re-auth flow; 20s ceiling (network-dependent).
      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);
      // Feed empty state may be in the widget tree but not hit-testable (e.g.
      // behind the bottom nav bar on smaller viewports). Use waitUntilExists
      // rather than waitUntilVisible, consistent with onboarding_flow_test.
      // Empty state renders after feed fetch returns 0 items; 15s ceiling.
      await $(
        find.byKey(FeedScreen.emptyStateKey),
      ).waitUntilExists(timeout: const Duration(seconds: 15));

      expect(feedCardFinder, findsNothing);
      expect(find.text(scenario.feedActivityTitle), findsNothing);
    },
  );
}
