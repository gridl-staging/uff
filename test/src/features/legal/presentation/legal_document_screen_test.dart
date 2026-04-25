import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/legal/presentation/legal_document_screen.dart';

class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle.assets(this._assets) : _responses = null;
  _TestAssetBundle.sequence(this._responses) : _assets = null;

  final Map<String, String>? _assets;
  final List<Object>? _responses;
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError('Binary asset loading is not used in this test.');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final assets = _assets;
    if (assets != null) {
      final markdown = assets[key];
      if (markdown == null) {
        throw FlutterError('Unable to load asset: $key');
      }
      return markdown;
    }

    final responses = _responses!;
    final index = loadCount < responses.length
        ? loadCount
        : responses.length - 1;
    loadCount++;
    final response = responses[index];
    if (response is String) {
      return response;
    }
    if (response is Exception) {
      throw response;
    }
    if (response is Error) {
      throw response;
    }
    throw StateError('Unsupported test response type: ${response.runtimeType}');
  }
}

void main() {
  group('LegalDocumentScreen', () {
    testWidgets('renders markdown when the asset is present', (tester) async {
      final bundle = _TestAssetBundle.assets(<String, String>{
        'docs/privacy_policy.md': '# Privacy Policy\n\nThis is the policy.',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LegalDocumentScreen(
            title: 'Privacy Policy',
            assetPath: 'docs/privacy_policy.md',
            assetBundle: bundle,
          ),
        ),
      );

      expect(
        find.byKey(LegalDocumentScreen.loadingIndicatorKey),
        findsOneWidget,
      );

      await tester.pumpAndSettle();

      expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
      expect(find.byType(Markdown), findsOneWidget);
      expect(find.text('This is the policy.'), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
    });

    testWidgets('shows a failure state when the asset is missing', (
      tester,
    ) async {
      final bundle = _TestAssetBundle.assets(<String, String>{});

      await tester.pumpWidget(
        MaterialApp(
          home: LegalDocumentScreen(
            title: 'Terms of Service',
            assetPath: 'docs/terms_of_service.md',
            assetBundle: bundle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsOneWidget);
      expect(
        find.text('Unable to load this document right now.'),
        findsOneWidget,
      );
      expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsNothing);
    });

    testWidgets('failure state exposes retry that reloads the document', (
      tester,
    ) async {
      final bundle = _TestAssetBundle.sequence(<Object>[
        FlutterError('Unable to load asset: docs/privacy_policy.md'),
        '# Privacy Policy\n\nRecovered content.',
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: LegalDocumentScreen(
            title: 'Privacy Policy',
            assetPath: 'docs/privacy_policy.md',
            assetBundle: bundle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.retryButtonKey), findsOneWidget);

      await tester.tap(find.byKey(LegalDocumentScreen.retryButtonKey));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(bundle.loadCount, 2);
      expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
      expect(find.text('Recovered content.'), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
    });

    testWidgets(
      'direct-entry failure back action falls back to the app entry route',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/legal',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Text('Root Route'),
              ),
            ),
            GoRoute(
              path: '/legal',
              builder: (context, state) => LegalDocumentScreen(
                title: 'Privacy Policy',
                assetPath: 'docs/missing_privacy_policy.md',
                assetBundle: _TestAssetBundle.assets(const <String, String>{}),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(routerConfig: router),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsOneWidget);

        await tester.tap(find.byKey(LegalDocumentScreen.backButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Root Route'), findsOneWidget);
      },
    );
  });
}
