import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/maps/data/mapbox_token_initializer.dart';

/// ## Test Scenarios
/// - [positive] Valid pk token is applied via applyAccessToken callback
/// - [edge] Missing MAPBOX_ACCESS_TOKEN key returns null
/// - [edge] Blank (whitespace-only) token returns null
/// - [edge] Secret-scoped (sk.) token returns null

void main() {
  group('MapboxTokenInitializer', () {
    test('returns null and skips applyAccessToken when token is missing', () {
      var applyCallCount = 0;

      final result = const MapboxTokenInitializer().initialize(
        environment: const {},
        applyAccessToken: (_) => applyCallCount++,
      );

      expect(result, isNull);
      expect(applyCallCount, 0);
    });

    test('returns null and skips applyAccessToken when token is blank', () {
      var applyCallCount = 0;

      final result = const MapboxTokenInitializer().initialize(
        environment: const {'MAPBOX_ACCESS_TOKEN': '   '},
        applyAccessToken: (_) => applyCallCount++,
      );

      expect(result, isNull);
      expect(applyCallCount, 0);
    });

    test(
      'returns null and skips applyAccessToken when token is secret-scoped',
      () {
        var applyCallCount = 0;

        final result = const MapboxTokenInitializer().initialize(
          environment: const {'MAPBOX_ACCESS_TOKEN': 'sk.secret-token'},
          applyAccessToken: (_) => applyCallCount++,
        );

        expect(result, isNull);
        expect(applyCallCount, 0);
      },
    );

    test('applies the configured token when it is present', () {
      var applyCallCount = 0;
      var appliedToken = '';

      final resolvedToken = const MapboxTokenInitializer().initialize(
        environment: const {'MAPBOX_ACCESS_TOKEN': 'pk.test-token'},
        applyAccessToken: (token) {
          applyCallCount += 1;
          appliedToken = token;
        },
      );

      expect(resolvedToken, 'pk.test-token');
      expect(appliedToken, 'pk.test-token');
      expect(applyCallCount, 1);
    });
  });
}
