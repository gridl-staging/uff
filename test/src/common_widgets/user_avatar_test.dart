import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/user_avatar.dart';

// ## Test Scenarios
// - [positive] HTTPS avatar URL renders a CircleAvatar with NetworkImage
// - [positive] Initials fallback from single-word displayName
// - [positive] Initials fallback from multi-word displayName
// - [edge] Empty displayName falls back to '?'
// - [edge] Null displayName falls back to '?'
// - [negative] HTTP (non-HTTPS) URL falls back to initials
// - [negative] Garbage string URL falls back to initials
// - [isolation] Widget has no external state dependencies
// - [positive] Shared trusted-avatar helper accepts only trusted HTTPS URLs

void main() {
  group('trustedHttpsAvatarImageProvider', () {
    test('returns NetworkImage for trusted HTTPS avatar URL', () {
      final provider = trustedHttpsAvatarImageProvider(
        'https://cdn.example.com/avatar.jpg',
      );
      if (provider is! NetworkImage) {
        fail('Expected trustedHttpsAvatarImageProvider to return NetworkImage');
      }

      expect(provider.url, 'https://cdn.example.com/avatar.jpg');
    });

    test('rejects non-HTTPS and malformed avatar URLs', () {
      expect(
        trustedHttpsAvatarImageProvider('http://cdn.example.com/avatar.jpg'),
        isNull,
      );
      expect(trustedHttpsAvatarImageProvider('not-a-url'), isNull);
      expect(trustedHttpsAvatarImageProvider('https:///avatar.jpg'), isNull);
    });
  });

  group('UserAvatar', () {
    testWidgets('renders CircleAvatar with backgroundImage for HTTPS URL', (
      tester,
    ) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: 'https://cdn.example.com/avatar.jpg',
              displayName: 'Alice',
            ),
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      final networkImage = avatar.backgroundImage! as NetworkImage;
      expect(networkImage.url, 'https://cdn.example.com/avatar.jpg');
      expect(find.text('A'), findsNothing);
    });

    testWidgets('shows single initial for single-word displayName', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(avatarUrl: null, displayName: 'Alice'),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });

    testWidgets('shows two initials for multi-word displayName', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(avatarUrl: null, displayName: 'Alice Runner'),
          ),
        ),
      );

      expect(find.text('AR'), findsOneWidget);
    });

    testWidgets('falls back to ? for empty displayName', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(avatarUrl: null, displayName: ''),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('falls back to ? for null displayName', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(avatarUrl: null, displayName: null),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('HTTP URL falls back to initials', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: 'http://insecure.example.com/avatar.jpg',
              displayName: 'Bob',
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('garbage URL falls back to initials', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: 'not-a-url',
              displayName: 'Charlie',
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('respects custom radius', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: null,
              displayName: 'Dan',
              radius: 24,
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 24);
    });
  });
}
