// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/feed_skeleton_card.dart';

/// ## Test Scenarios
/// - [positive] Feed skeleton card renders placeholder rows for feed layout sections.
/// - [positive] Placeholder sections use grey [BoxDecoration] styling.
/// - [positive] Feed skeleton list renders a deterministic number of cards.
void main() {
  Widget buildCard() {
    return const MaterialApp(
      home: Scaffold(
        body: FeedSkeletonCard(),
      ),
    );
  }

  Widget buildList() {
    return const MaterialApp(
      home: Scaffold(
        body: FeedSkeletonList(),
      ),
    );
  }

  testWidgets(
    'renders card placeholders for owner, title, map, metrics, social',
    (
      tester,
    ) async {
      await tester.pumpWidget(buildCard());

      expect(find.byKey(FeedSkeletonCard.cardKey), findsOneWidget);
      expect(find.byKey(FeedSkeletonCard.ownerRowKey), findsOneWidget);
      expect(find.byKey(FeedSkeletonCard.titleKey), findsOneWidget);
      expect(find.byKey(FeedSkeletonCard.mapKey), findsOneWidget);
      expect(find.byKey(FeedSkeletonCard.metricsRowKey), findsOneWidget);
      expect(find.byKey(FeedSkeletonCard.socialRowKey), findsOneWidget);
    },
  );

  testWidgets('placeholder rows use grey decoration styling', (tester) async {
    await tester.pumpWidget(buildCard());

    final ownerPlaceholder = tester.widget<DecoratedBox>(
      find.byKey(FeedSkeletonCard.ownerRowKey),
    );
    final decoration = ownerPlaceholder.decoration as BoxDecoration;
    expect(decoration.color, Colors.grey.shade300);
  });

  testWidgets('feed skeleton list renders three cards by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildList());
    expect(find.byType(FeedSkeletonCard), findsNWidgets(3));
  });
}
