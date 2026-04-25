import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/main.dart' as app;
import 'package:uff/src/core/telemetry/service/telemetry_flush_scheduler.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/telemetry/telemetry_lifecycle_bootstrap.dart';

class _RecordedUnhandledError {
  const _RecordedUnhandledError({
    required this.error,
    required this.stackTrace,
    required this.metadata,
  });

  final Object error;
  final StackTrace stackTrace;
  final Map<String, Object?> metadata;
}

class _RuntimeHarness {
  final List<_RecordedUnhandledError> capturedUnhandledErrors =
      <_RecordedUnhandledError>[];
  final List<FlutterErrorDetails> reportedFlutterErrors =
      <FlutterErrorDetails>[];
  final List<FlutterErrorDetails> presentedFlutterErrors =
      <FlutterErrorDetails>[];
  final List<Widget> mountedWidgets = <Widget>[];

  ProviderContainer? bootstrapContainer;
  FlutterExceptionHandler? flutterErrorHandler;
  app.RuntimePlatformErrorHandler? platformErrorHandler;
}

app.AppRuntimeDependencies _buildRuntimeDependencies({
  required _RuntimeHarness harness,
  required Future<void> Function({
    required ProviderContainer rootContainer,
    required void Function(Widget app) runAppWidget,
  })
  runBootstrapSequence,
  required Future<void> Function(
    Future<void> Function() body,
    void Function(Object error, StackTrace stackTrace) onError,
  )
  runGuardedZone,
  bool forwardReportedFlutterErrorsToCurrentHandler = false,
}) {
  return app.AppRuntimeDependencies(
    ensureFlutterBindingInitialized: () {},
    createRootContainer: ProviderContainer.new,
    captureUnhandled:
        ({
          required ProviderContainer rootContainer,
          required Object error,
          required StackTrace stackTrace,
          required Map<String, Object?> metadata,
        }) async {
          harness.capturedUnhandledErrors.add(
            _RecordedUnhandledError(
              error: error,
              stackTrace: stackTrace,
              metadata: Map<String, Object?>.from(metadata),
            ),
          );
        },
    runBootstrapSequence:
        ({
          required ProviderContainer rootContainer,
          required void Function(Widget app) runAppWidget,
        }) async {
          harness.bootstrapContainer = rootContainer;
          await runBootstrapSequence(
            rootContainer: rootContainer,
            runAppWidget: runAppWidget,
          );
        },
    runAppWidget: harness.mountedWidgets.add,
    runGuardedZone: runGuardedZone,
    readFlutterErrorHandler: () => harness.flutterErrorHandler,
    writeFlutterErrorHandler: (handler) {
      harness.flutterErrorHandler = handler;
    },
    reportFlutterError: (details) {
      harness.reportedFlutterErrors.add(details);
      if (forwardReportedFlutterErrorsToCurrentHandler) {
        harness.flutterErrorHandler?.call(details);
      }
    },
    presentFlutterError: harness.presentedFlutterErrors.add,
    readPlatformErrorHandler: () => harness.platformErrorHandler,
    writePlatformErrorHandler: (handler) {
      harness.platformErrorHandler = handler;
    },
  );
}

Future<void> _drainMicrotaskQueue() async {
  await Future<void>.delayed(Duration.zero);
}

/// ## Test Scenarios
/// - `[error]` Bootstrap failures route through telemetry capture, Flutter reporting, and fallback UI.
/// - `[positive]` Flutter and platform error hooks preserve previous-handler semantics.
/// - `[edge]` Hook failures are swallowed while telemetry capture continues.
/// - `[statemachine]` Zone-guard failures fan out through both unhandled capture and framework reporting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'main forwards bootstrap failures through telemetry, FlutterError.reportError, and fallback rendering',
    () async {
      final harness = _RuntimeHarness();
      var previousFlutterErrorCallCount = 0;
      harness.flutterErrorHandler = (FlutterErrorDetails details) {
        previousFlutterErrorCallCount += 1;
      };
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              throw StateError('bootstrap exploded');
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
        forwardReportedFlutterErrorsToCurrentHandler: true,
      );
      final originalDependencies = app.runtimeDependencies;
      addTearDown(() {
        app.runtimeDependencies = originalDependencies;
      });
      app.runtimeDependencies = dependencies;

      await app.main();
      await _drainMicrotaskQueue();

      expect(harness.bootstrapContainer?.runtimeType, ProviderContainer);
      expect(harness.reportedFlutterErrors, hasLength(1));
      expect(previousFlutterErrorCallCount, 1);
      expect(
        harness.capturedUnhandledErrors
            .map((capture) => capture.metadata['source'])
            .toSet(),
        containsAll(<String>{'bootstrap', 'flutter_error'}),
      );
      expect(harness.mountedWidgets, hasLength(1));
      expect(
        harness.mountedWidgets.single.runtimeType.toString(),
        '_BootstrapFailureApp',
      );
    },
  );

  testWidgets(
    'bootstrap fallback hides raw startup details when diagnostics are disabled',
    (tester) async {
      await tester.pumpWidget(
        app.buildBootstrapFailureApp(
          error: StateError(
            'bootstrap exploded with Authorization: Bearer abc',
          ),
          stackTrace: StackTrace.fromString('sensitive-stack'),
          showDiagnostics: false,
        ),
      );

      expect(find.text('The app failed during bootstrap.'), findsOneWidget);
      expect(
        find.text(
          'Restart the app. If it keeps failing, reinstall or update it.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('bootstrap exploded'), findsNothing);
      expect(find.textContaining('Authorization: Bearer abc'), findsNothing);
      expect(find.textContaining('sensitive-stack'), findsNothing);
    },
  );

  test(
    'FlutterError hook preserves previous handler and framework presentation while tagging flutter_error metadata',
    () async {
      final harness = _RuntimeHarness();
      var previousFlutterErrorCallCount = 0;
      harness.flutterErrorHandler = (FlutterErrorDetails details) {
        previousFlutterErrorCallCount += 1;
      };
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
      );

      await app.runMainEntrypoint(dependencies: dependencies);

      final runtimeHandler = harness.flutterErrorHandler;

      runtimeHandler!.call(
        FlutterErrorDetails(
          exception: StateError('flutter failure'),
          stack: StackTrace.fromString('flutter-stack'),
          library: 'widget library',
          context: ErrorDescription('while painting'),
        ),
      );
      await _drainMicrotaskQueue();

      expect(previousFlutterErrorCallCount, 1);
      expect(harness.presentedFlutterErrors, hasLength(1));
      expect(harness.capturedUnhandledErrors, hasLength(1));
      final capturedMetadata = harness.capturedUnhandledErrors.single.metadata;
      expect(
        capturedMetadata,
        allOf(
          containsPair('source', 'flutter_error'),
          containsPair('library', 'widget library'),
          containsPair('context', 'while painting'),
          containsPair('silent', isFalse),
        ),
      );
    },
  );

  test(
    'FlutterError hook does not double-present when the previous handler already is framework presentation',
    () async {
      final harness = _RuntimeHarness();
      harness.flutterErrorHandler = harness.presentedFlutterErrors.add;
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
      );

      await app.runMainEntrypoint(dependencies: dependencies);

      final runtimeHandler = harness.flutterErrorHandler;

      runtimeHandler!.call(
        FlutterErrorDetails(
          exception: StateError('flutter failure'),
          stack: StackTrace.fromString('flutter-stack'),
        ),
      );
      await _drainMicrotaskQueue();

      expect(harness.presentedFlutterErrors, hasLength(1));
      expect(harness.capturedUnhandledErrors, hasLength(1));
      expect(
        harness.capturedUnhandledErrors.single.metadata['source'],
        'flutter_error',
      );
    },
  );

  test(
    'FlutterError hook swallows previous-handler exceptions and still captures flutter_error telemetry',
    () async {
      final harness = _RuntimeHarness()
        ..flutterErrorHandler = (FlutterErrorDetails details) {
          throw StateError('previous flutter handler failed');
        };
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
      );

      await app.runMainEntrypoint(dependencies: dependencies);

      final runtimeHandler = harness.flutterErrorHandler;

      expect(
        () => runtimeHandler!.call(
          FlutterErrorDetails(
            exception: StateError('flutter failure'),
            stack: StackTrace.fromString('flutter-stack'),
          ),
        ),
        returnsNormally,
      );
      await _drainMicrotaskQueue();

      expect(harness.presentedFlutterErrors, hasLength(1));
      expect(harness.capturedUnhandledErrors, hasLength(1));
      expect(
        harness.capturedUnhandledErrors.single.metadata['source'],
        'flutter_error',
      );
    },
  );

  test(
    'PlatformDispatcher hook preserves previous handler return value and tags platform_dispatcher metadata',
    () async {
      final harness = _RuntimeHarness();
      var previousPlatformErrorCallCount = 0;
      harness.platformErrorHandler = (Object error, StackTrace stackTrace) {
        previousPlatformErrorCallCount += 1;
        return true;
      };
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
      );

      await app.runMainEntrypoint(dependencies: dependencies);

      final runtimeHandler = harness.platformErrorHandler;

      final handled = runtimeHandler!(
        StateError('platform failure'),
        StackTrace.fromString('platform-stack'),
      );
      await _drainMicrotaskQueue();

      expect(handled, isTrue);
      expect(previousPlatformErrorCallCount, 1);
      expect(harness.capturedUnhandledErrors, hasLength(1));
      expect(
        harness.capturedUnhandledErrors.single.metadata['source'],
        'platform_dispatcher',
      );
    },
  );

  test(
    'PlatformDispatcher hook swallows previous-handler exceptions and returns false',
    () async {
      final harness = _RuntimeHarness()
        ..platformErrorHandler = (Object error, StackTrace stackTrace) {
          throw StateError('previous platform handler failed');
        };
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
            },
      );

      await app.runMainEntrypoint(dependencies: dependencies);

      final runtimeHandler = harness.platformErrorHandler;

      final handled = runtimeHandler!(
        StateError('platform failure'),
        StackTrace.fromString('platform-stack'),
      );
      await _drainMicrotaskQueue();

      expect(handled, isFalse);
      expect(harness.capturedUnhandledErrors, hasLength(1));
      expect(
        harness.capturedUnhandledErrors.single.metadata['source'],
        'platform_dispatcher',
      );
    },
  );

  test(
    'runZonedGuarded outer handler tags zone_guard metadata and forwards Flutter reporting',
    () async {
      final harness = _RuntimeHarness();
      final dependencies = _buildRuntimeDependencies(
        harness: harness,
        runBootstrapSequence:
            ({
              required ProviderContainer rootContainer,
              required void Function(Widget app) runAppWidget,
            }) async {
              runAppWidget(const SizedBox.shrink());
            },
        runGuardedZone:
            (
              Future<void> Function() body,
              void Function(Object error, StackTrace stackTrace) onError,
            ) async {
              await body();
              onError(
                StateError('zone failure'),
                StackTrace.fromString('zone-stack'),
              );
            },
        forwardReportedFlutterErrorsToCurrentHandler: true,
      );

      await app.runMainEntrypoint(dependencies: dependencies);
      await _drainMicrotaskQueue();

      expect(harness.reportedFlutterErrors, hasLength(1));
      expect(harness.presentedFlutterErrors, hasLength(1));
      expect(
        harness.capturedUnhandledErrors
            .map((capture) => capture.metadata['source'])
            .toSet(),
        containsAll(<String>{'zone_guard', 'flutter_error'}),
      );
    },
  );

  group('TelemetryLifecycleBootstrap', () {
    testWidgets(
      'starts scheduler on init and triggers flush on app resume',
      (tester) async {
        var flushCallCount = 0;
        final flushCompleters = <Completer<Duration?>>[];
        final scheduler = TelemetryFlushScheduler(
          flush: () {
            flushCallCount += 1;
            final completer = Completer<Duration?>();
            flushCompleters.add(completer);
            return completer.future;
          },
        );

        final container = ProviderContainer(
          overrides: [
            telemetryFlushSchedulerProvider.overrideWithValue(scheduler),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TelemetryLifecycleBootstrap(
              child: SizedBox.shrink(),
            ),
          ),
        );

        // start() should have fired one flush immediately.
        expect(flushCallCount, 1);

        // Complete the startup flush.
        flushCompleters[0].complete(null);
        await tester.pumpAndSettle();

        // Simulate app resume.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(flushCallCount, 2);
      },
    );

    testWidgets(
      'concurrent resumes during in-flight flush do not create parallel flushes',
      (tester) async {
        var flushCallCount = 0;
        final flushCompleters = <Completer<Duration?>>[];
        final scheduler = TelemetryFlushScheduler(
          flush: () {
            flushCallCount += 1;
            final completer = Completer<Duration?>();
            flushCompleters.add(completer);
            return completer.future;
          },
        );

        final container = ProviderContainer(
          overrides: [
            telemetryFlushSchedulerProvider.overrideWithValue(scheduler),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TelemetryLifecycleBootstrap(
              child: SizedBox.shrink(),
            ),
          ),
        );

        // Startup flush is in-flight.
        expect(flushCallCount, 1);

        // Two resume events while in-flight.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        // Still only 1 flush because the first is in-flight.
        expect(flushCallCount, 1);

        // Complete the startup flush — one deferred flush should fire.
        flushCompleters[0].complete(null);
        await tester.pump();
        await tester.pump();

        expect(flushCallCount, 2);
      },
    );

    testWidgets(
      'swallows scheduler exceptions during start and resume',
      (tester) async {
        var callCount = 0;
        final scheduler = TelemetryFlushScheduler(
          flush: () {
            callCount += 1;
            throw StateError('telemetry flush crashed');
          },
        );

        final container = ProviderContainer(
          overrides: [
            telemetryFlushSchedulerProvider.overrideWithValue(scheduler),
          ],
        );
        addTearDown(container.dispose);

        // start() throws — should be swallowed.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TelemetryLifecycleBootstrap(
              child: SizedBox.shrink(),
            ),
          ),
        );
        expect(callCount, 1);

        // Resume throws — should also be swallowed.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(callCount, 2);

        // Widget tree is still intact.
        expect(find.byType(SizedBox), findsOneWidget);
      },
    );

    testWidgets(
      'does not react to lifecycle states other than resumed',
      (tester) async {
        var flushCallCount = 0;
        final scheduler = TelemetryFlushScheduler(
          flush: () async {
            flushCallCount += 1;
            return null;
          },
        );

        final container = ProviderContainer(
          overrides: [
            telemetryFlushSchedulerProvider.overrideWithValue(scheduler),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TelemetryLifecycleBootstrap(
              child: SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(flushCallCount, 1); // Only start() flush.

        // paused, inactive, hidden, detached — none should trigger flush.
        for (final state in [
          AppLifecycleState.paused,
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.detached,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }

        expect(flushCallCount, 1);
      },
    );
  });
}
