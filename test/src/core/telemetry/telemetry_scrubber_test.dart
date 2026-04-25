import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_scrubber.dart';

void main() {
  group('TelemetryScrubber', () {
    test(
      'removes secret-bearing keys and truncates exception fields deterministically',
      () {
        final scrubber = TelemetryScrubber(
          maxExceptionMessageLength: 24,
          maxStackTraceLength: 40,
        );

        const exceptionMessage = 'this message should be truncated at 24 chars';
        const stackTrace =
            'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8';
        final scrubbed = scrubber.scrubContext(<String, Object?>{
          'token': 'abc',
          'authorization': 'Bearer secret',
          'password': 'pw',
          'secret': 'hidden',
          'cookie': 'a=b',
          'exceptionMessage': exceptionMessage,
          'stackTrace': stackTrace,
          'safeField': 'keep',
        });

        expect(scrubbed.containsKey('token'), isFalse);
        expect(scrubbed.containsKey('authorization'), isFalse);
        expect(scrubbed.containsKey('password'), isFalse);
        expect(scrubbed.containsKey('secret'), isFalse);
        expect(scrubbed.containsKey('cookie'), isFalse);
        expect(scrubbed['safeField'], 'keep');
        expect(
          scrubbed['exceptionMessage'],
          exceptionMessage.substring(0, 24),
        );
        expect(scrubbed['stackTrace'], stackTrace.substring(0, 40));
      },
    );

    test(
      'redacts credential-like fragments inside exception and stack-trace strings',
      () {
        final scrubber = TelemetryScrubber();

        final scrubbed = scrubber.scrubContext(<String, Object?>{
          'exceptionMessage':
              'Authorization: Bearer super-secret-token password=hunter2',
          'stackTrace': 'GET /callback?refresh_token=abc123 session_id=xyz789',
        });

        expect(
          scrubbed['exceptionMessage'],
          'Authorization: [REDACTED] password=[REDACTED]',
        );
        expect(
          scrubbed['stackTrace'],
          'GET /callback?refresh_token=[REDACTED] session_id=[REDACTED]',
        );
      },
    );

    test(
      'rejects nested objects, lists, and non-finite numbers for both context and breadcrumb metadata',
      () {
        final scrubber = TelemetryScrubber();

        final invalidValues = <Object?>[
          <String, Object?>{'nested': true},
          <Object?>['list', 'values'],
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ];

        for (final invalid in invalidValues) {
          expect(
            () => scrubber.scrubContext(<String, Object?>{'invalid': invalid}),
            throwsArgumentError,
          );
          expect(
            () => scrubber.scrubBreadcrumbMetadata(<String, Object?>{
              'invalid': invalid,
            }),
            throwsArgumentError,
          );
        }
      },
    );
  });
}
