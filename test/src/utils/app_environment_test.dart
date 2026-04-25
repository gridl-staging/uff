import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/utils/app_environment.dart';

void main() {
  group('app environment resolution', () {
    test('defaults APP_ENV to dev when no dart define is provided', () {
      final environmentName = readConfiguredAppEnvironment();
      final resolvedAsset = resolveEnvironmentAssetForName(environmentName);

      expect(environmentName, defaultAppEnvironmentName);
      expect(resolvedAsset, '.env.dev');
    });

    test('maps supported app environments to runtime dotenv assets', () {
      expect(resolveEnvironmentAssetForName('dev'), '.env.dev');
      expect(resolveEnvironmentAssetForName('staging'), '.env.staging');
      expect(resolveEnvironmentAssetForName('prod'), '.env.prod');
    });

    test('fails fast for unsupported app environments', () {
      expect(
        () => resolveEnvironmentAssetForName('qa'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Unsupported APP_ENV value "qa".'),
              contains('Supported APP_ENV values: dev, staging, prod.'),
            ),
          ),
        ),
      );
    });

    test('throws when a required runtime value is missing', () {
      expect(
        () => requireEnvironmentValue(
          environment: const {},
          key: 'SUPABASE_URL',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Missing required SUPABASE_URL.'),
              contains(runtimeEnvironmentSetupGuidance),
            ),
          ),
        ),
      );
    });

    test('returns trimmed required runtime values', () {
      expect(
        requireEnvironmentValue(
          environment: const {'SUPABASE_ANON_KEY': '  anon-key  '},
          key: 'SUPABASE_ANON_KEY',
        ),
        'anon-key',
      );
    });
  });

  group('checked-in runtime env placeholders', () {
    test('include all required keys across dev, staging, and prod', () {
      for (final envPath in runtimeEnvironmentAssetNames) {
        final env = _loadEnvFile(envPath);

        expect(
          env.keys,
          containsAll(const {
            'SUPABASE_URL',
            'SUPABASE_ANON_KEY',
            'MAPBOX_ACCESS_TOKEN',
            'ENABLE_APPLE_SIGN_IN',
            'ENABLE_GOOGLE_SIGN_IN',
            'GOOGLE_WEB_CLIENT_ID',
            'GOOGLE_IOS_CLIENT_ID',
            'APPLE_SERVICE_ID',
          }),
          reason: '$envPath must keep all required runtime placeholder keys.',
        );
        expect(
          env['ENABLE_APPLE_SIGN_IN'],
          'false',
          reason:
              '$envPath keeps Apple Sign-In hidden until the hosted runtime is explicitly validated.',
        );
        expect(
          env['ENABLE_GOOGLE_SIGN_IN'],
          'false',
          reason:
              '$envPath keeps Google Sign-In hidden until the hosted runtime is explicitly validated.',
        );
        expect(
          env['GOOGLE_WEB_CLIENT_ID']?.trim().isNotEmpty,
          isTrue,
          reason:
              '$envPath must keep a non-empty Google web client placeholder.',
        );
        expect(
          env['GOOGLE_IOS_CLIENT_ID']?.trim().isNotEmpty,
          isTrue,
          reason:
              '$envPath must keep a non-empty Google iOS client placeholder.',
        );
        expect(
          env['APPLE_SERVICE_ID'],
          'com.gridl.uff',
          reason:
              '$envPath must keep the checked-in Apple service id contract.',
        );
      }
    });
  });
}

Map<String, String> _loadEnvFile(String path) {
  final env = <String, String>{};
  for (final rawLine in File(path).readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final separatorIndex = line.indexOf('=');
    if (separatorIndex == -1) {
      continue;
    }
    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    env[key] = value;
  }
  return env;
}
