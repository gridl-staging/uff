import 'package:flutter/material.dart';

/// Feed-card loading skeleton placeholder.
class FeedSkeletonCard extends StatelessWidget {
  const FeedSkeletonCard({super.key});

  static const cardKey = Key('feed_skeleton_card');
  static const ownerRowKey = Key('feed_skeleton_owner_row');
  static const titleKey = Key('feed_skeleton_title');
  static const mapKey = Key('feed_skeleton_map');
  static const metricsRowKey = Key('feed_skeleton_metrics');
  static const socialRowKey = Key('feed_skeleton_social');

  @override
  Widget build(BuildContext context) {
    final placeholderColor = Colors.grey.shade300;

    return Card(
      key: cardKey,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FeedSkeletonBar(
              barKey: ownerRowKey,
              height: 20,
              width: double.infinity,
              color: placeholderColor,
            ),
            const SizedBox(height: 8),
            _FeedSkeletonBar(
              barKey: titleKey,
              height: 18,
              width: 220,
              color: placeholderColor,
            ),
            const SizedBox(height: 8),
            _FeedSkeletonBar(
              barKey: mapKey,
              height: 150,
              width: double.infinity,
              color: placeholderColor,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 10),
            _FeedSkeletonBar(
              barKey: metricsRowKey,
              height: 14,
              width: 190,
              color: placeholderColor,
            ),
            const SizedBox(height: 10),
            _FeedSkeletonBar(
              barKey: socialRowKey,
              height: 18,
              width: 120,
              color: placeholderColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical stack of feed skeleton cards for initial feed loading.
class FeedSkeletonList extends StatelessWidget {
  const FeedSkeletonList({
    this.itemCount = 3,
    super.key,
  }) : assert(
         itemCount >= 3 && itemCount <= 4,
         'FeedSkeletonList.itemCount must be between 3 and 4.',
       );

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: List<Widget>.generate(
          itemCount,
          (index) => const FeedSkeletonCard(),
          growable: false,
        ),
      ),
    );
  }
}

/// TODO: Document _FeedSkeletonBar.
class _FeedSkeletonBar extends StatelessWidget {
  const _FeedSkeletonBar({
    required this.barKey,
    required this.height,
    required this.width,
    required this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final Key barKey;
  final double height;
  final double width;
  final Color color;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: height,
        width: width,
        child: DecoratedBox(
          key: barKey,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }
}
