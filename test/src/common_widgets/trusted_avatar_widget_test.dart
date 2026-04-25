// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';

/// ## Test Scenarios
/// - [positive] HTTPS avatar URLs render trusted [NetworkImage] backgrounds.
/// - [edge] Non-HTTPS or null avatar URLs render initials from display name.
/// - [edge] Missing or blank display names render person-icon fallback.
/// - [positive] Radius defaults to 16 and supports explicit overrides.
void main() {
  Widget buildAvatar({
    String? avatarUrl,
    String? displayName,
    double? radius,
  }) {
    final avatar = radius == null
        ? TrustedAvatarWidget(
            avatarUrl: avatarUrl,
            displayName: displayName,
          )
        : TrustedAvatarWidget(
            avatarUrl: avatarUrl,
            displayName: displayName,
            radius: radius,
          );

    return MaterialApp(
      home: Scaffold(
        body: avatar,
      ),
    );
  }

  testWidgets('https URL renders CircleAvatar with NetworkImage', (
    tester,
  ) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('NetworkImageLoadException')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      buildAvatar(
        avatarUrl: 'https://cdn.example.com/avatar.png',
        displayName: 'Runner One',
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(
      avatar.backgroundImage,
      const NetworkImage('https://cdn.example.com/avatar.png'),
    );
  });

  testWidgets('non-HTTPS URL uses initials fallback from displayName', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAvatar(
        avatarUrl: 'http://cdn.example.com/avatar.png',
        displayName: 'Viewed Runner',
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.text('VR'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
  });

  testWidgets('null URL uses initials fallback from displayName', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAvatar(
        displayName: 'Test User',
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.text('TU'), findsOneWidget);
  });

  testWidgets('blank displayName falls back to person icon', (tester) async {
    await tester.pumpWidget(
      buildAvatar(
        displayName: '   ',
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('null displayName falls back to person icon', (tester) async {
    await tester.pumpWidget(buildAvatar());

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('radius defaults to 16', (tester) async {
    await tester.pumpWidget(
      buildAvatar(
        displayName: 'Runner One',
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.radius, 16);
  });

  testWidgets('radius supports explicit override', (tester) async {
    await tester.pumpWidget(
      buildAvatar(
        displayName: 'Runner One',
        radius: 22,
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.radius, 22);
  });
}
