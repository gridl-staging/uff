import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/social/application/social_comments_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';
import 'package:uff/src/features/social/presentation/activity_comments_section.dart';

import 'activity_detail_screen_test_support.dart';

void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'renders metadata card above summary, then analytics below, with controls available',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      // Metadata card (Title & Notes) is now first — right after the map —
      // so users can name their activity immediately after finishing a run.
      final metadataFinder = find.text('Title & Notes', skipOffstage: false);
      expect(metadataFinder, findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.titleFieldKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ActivityDetailScreen.descriptionFieldKey,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.saveButtonKey, skipOffstage: false),
        findsOneWidget,
      );

      // Scroll past the summary to the analytics section to verify ordering.
      // ListView lazily builds children, so we must scroll incrementally.
      await tester.scrollUntilVisible(
        find.text('Activity analytics'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final summaryFinder = find.text('Summary');
      final analyticsFinder = find.text('Activity analytics');
      expect(summaryFinder, findsOneWidget);
      expect(analyticsFinder, findsOneWidget);

      final summaryTop = tester.getTopLeft(summaryFinder).dy;
      final analyticsTop = tester.getTopLeft(analyticsFinder).dy;

      // Summary comes before Analytics in the layout.
      expect(summaryTop, lessThan(analyticsTop));
    },
  );

  testWidgets(
    'renders owner-facing read-only kudos count and list using remoteId',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-5',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityKudosProvider(
            'remote-activity-5',
          ).overrideWith(
            (ref) async => const ActivityKudosSummary(
              kudosCount: 2,
              viewerHasKudo: false,
              users: <ActivityKudoUser>[
                ActivityKudoUser(
                  userId: 'u1',
                  displayName: 'Alex',
                  avatarUrl: null,
                ),
                ActivityKudoUser(
                  userId: 'u2',
                  displayName: 'Taylor',
                  avatarUrl: null,
                ),
              ],
            ),
          ),
        ],
      );

      await tester.scrollUntilVisible(
        find.byKey(ActivityDetailScreen.ownerKudosSectionKey),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityDetailScreen.ownerKudosSectionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.ownerKudosCountTextKey),
        findsOneWidget,
      );
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Taylor'), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.ownerKudosToggleButtonKey),
        findsNothing,
      );
    },
  );

  testWidgets(
    'mounts ActivityCommentsSection after splits card when remoteId exists',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-comments-1',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityKudosProvider(
            'remote-activity-comments-1',
          ).overrideWith(
            (ref) async => const ActivityKudosSummary(
              kudosCount: 0,
              viewerHasKudo: false,
              users: <ActivityKudoUser>[],
            ),
          ),
          activityCommentsProvider(
            'remote-activity-comments-1',
          ).overrideWith((ref) async => []),
          ...defaultAuthOverrides(),
        ],
      );

      // Scroll to the comments section. In the new layout, comments are
      // after: metadata → summary → photos → splits → analytics → gear → kudos → comments.
      await tester.scrollUntilVisible(
        find.byKey(
          ActivityCommentsSection.sectionShellKey,
          skipOffstage: false,
        ),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityCommentsSection.sectionShellKey),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'skips ActivityCommentsSection when session has no remoteId',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      expect(
        find.byKey(
          ActivityCommentsSection.sectionShellKey,
          skipOffstage: false,
        ),
        findsNothing,
      );
    },
  );
}
