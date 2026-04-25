// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/sport_type_icon.dart';

/// ## Test Scenarios
/// - [positive] Supported sport types map to the expected Material icons.
/// - [edge] Null/unknown sport types fall back to the generic fitness icon.
/// - [positive] Explicit size overrides are passed through to the Icon widget.
void main() {
  Widget buildIcon({String? sportType, double? size}) {
    return MaterialApp(
      home: Scaffold(
        body: SportTypeIcon(sportType: sportType, size: size),
      ),
    );
  }

  testWidgets('run maps to directions_run icon', (tester) async {
    await tester.pumpWidget(buildIcon(sportType: 'run'));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.directions_run);
  });

  testWidgets('ride maps to directions_bike icon', (tester) async {
    await tester.pumpWidget(buildIcon(sportType: 'ride'));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.directions_bike);
  });

  testWidgets('null sportType falls back to fitness_center icon', (
    tester,
  ) async {
    await tester.pumpWidget(buildIcon());
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.fitness_center);
  });

  testWidgets('unknown sportType falls back to fitness_center icon', (
    tester,
  ) async {
    await tester.pumpWidget(buildIcon(sportType: 'ski'));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.fitness_center);
  });

  testWidgets('passes explicit size to icon', (tester) async {
    await tester.pumpWidget(buildIcon(sportType: 'run', size: 28));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 28);
  });
}
