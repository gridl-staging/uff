import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/app.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/telemetry/telemetry_lifecycle_bootstrap.dart';
import 'package:uff/src/features/auth/data/auth_oauth_config.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_smoke_overrides.dart';
import 'package:uff/src/features/notifications/application/notification_providers.dart';
import 'package:uff/src/features/maps/data/mapbox_token_initializer.dart';
import 'package:uff/src/utils/app_environment.dart';

typedef RuntimeUnhandledCapture =
    Future<void> Function({
      required ProviderContainer rootContainer,
      required Object error,
      required StackTrace stackTrace,
      required Map<String, Object?> metadata,
    });
typedef RuntimeBootstrapSequenceRunner =
    Future<void> Function({
      required ProviderContainer rootContainer,
      required void Function(Widget app) runAppWidget,
    });
typedef RuntimeGuardedZoneRunner =
    Future<void> Function(
      Future<void> Function() body,
      void Function(Object error, StackTrace stackTrace) onError,
    );
typedef RuntimePlatformErrorHandler =
    bool Function(
      Object error,
      StackTrace stackTrace,
    );

/// Injected seams for runtime bootstrap and global error hook wiring.
class AppRuntimeDependencies {
  const AppRuntimeDependencies({
    required this.ensureFlutterBindingInitialized,
    required this.createRootContainer,
    required this.captureUnhandled,
    required this.runBootstrapSequence,
    required this.runAppWidget,
    required this.runGuardedZone,
    required this.readFlutterErrorHandler,
    required this.writeFlutterErrorHandler,
    required this.reportFlutterError,
    required this.presentFlutterError,
    required this.readPlatformErrorHandler,
    required this.writePlatformErrorHandler,
  });

  factory AppRuntimeDependencies.live() {
    return AppRuntimeDependencies(
      ensureFlutterBindingInitialized: WidgetsFlutterBinding.ensureInitialized,
      createRootContainer: ProviderContainer.new,
      captureUnhandled:
          ({
            required ProviderContainer rootContainer,
            required Object error,
            required StackTrace stackTrace,
            required Map<String, Object?> metadata,
          }) {
            return rootContainer
                .read(telemetryServiceProvider)
                .captureUnhandled(
                  error: error,
                  stackTrace: stackTrace,
                  metadata: metadata,
                );
          },
      runBootstrapSequence: _runBootstrapSequence,
      runAppWidget: runApp,
      runGuardedZone: _runInGuardedZone,
      readFlutterErrorHandler: () => FlutterError.onError,
      writeFlutterErrorHandler: (handler) {
        FlutterError.onError = handler;
      },
      reportFlutterError: FlutterError.reportError,
      presentFlutterError: FlutterError.presentError,
      readPlatformErrorHandler: () => PlatformDispatcher.instance.onError,
      writePlatformErrorHandler: (handler) {
        PlatformDispatcher.instance.onError = handler;
      },
    );
  }

  final VoidCallback ensureFlutterBindingInitialized;
  final ProviderContainer Function() createRootContainer;
  final RuntimeUnhandledCapture captureUnhandled;
  final RuntimeBootstrapSequenceRunner runBootstrapSequence;
  final void Function(Widget app) runAppWidget;
  final RuntimeGuardedZoneRunner runGuardedZone;
  final FlutterExceptionHandler? Function() readFlutterErrorHandler;
  final void Function(FlutterExceptionHandler? handler)
  writeFlutterErrorHandler;
  final void Function(FlutterErrorDetails details) reportFlutterError;
  final void Function(FlutterErrorDetails details) presentFlutterError;
  final RuntimePlatformErrorHandler? Function() readPlatformErrorHandler;
  final void Function(RuntimePlatformErrorHandler? handler)
  writePlatformErrorHandler;
}

@visibleForTesting
AppRuntimeDependencies runtimeDependencies = AppRuntimeDependencies.live();

@visibleForTesting
bool showBootstrapFailureDiagnostics = kDebugMode;

@visibleForTesting
Widget buildBootstrapFailureApp({
  required Object error,
  required StackTrace stackTrace,
  required bool showDiagnostics,
}) {
  return _BootstrapFailureApp(
    error: error,
    stackTrace: stackTrace,
    showDiagnostics: showDiagnostics,
  );
}

Future<void> main() async {
  await runMainEntrypoint(dependencies: runtimeDependencies);
}

@visibleForTesting
Future<void> runMainEntrypoint({
  required AppRuntimeDependencies dependencies,
}) async {
  final rootContainer = dependencies.createRootContainer();
  final runtimeFailureReporter = _RuntimeFailureReporter(
    captureUnhandled: dependencies.captureUnhandled,
    rootContainer: rootContainer,
  );

  final previousFlutterErrorHandler = dependencies.readFlutterErrorHandler();
  dependencies.writeFlutterErrorHandler((FlutterErrorDetails details) {
    final shouldPresentFrameworkError =
        previousFlutterErrorHandler == null ||
        previousFlutterErrorHandler != dependencies.presentFlutterError;
    if (shouldPresentFrameworkError) {
      dependencies.presentFlutterError(details);
    }
    try {
      previousFlutterErrorHandler?.call(details);
    } on Object {
      // Runtime hooks must stay non-throwing even if a previous handler fails.
    }
    unawaited(
      runtimeFailureReporter.capture(
        error: details.exception,
        stackTrace: details.stack ?? StackTrace.current,
        source: 'flutter_error',
        additionalMetadata: <String, Object?>{
          if (details.library != null) 'library': details.library,
          if (details.context != null) 'context': details.context.toString(),
          'silent': details.silent,
        },
      ),
    );
  });

  final previousPlatformErrorHandler = dependencies.readPlatformErrorHandler();
  dependencies.writePlatformErrorHandler((Object error, StackTrace stackTrace) {
    unawaited(
      runtimeFailureReporter.capture(
        error: error,
        stackTrace: stackTrace,
        source: 'platform_dispatcher',
      ),
    );
    try {
      return previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
    } on Object {
      // Platform error hooks must stay non-throwing when chaining handlers.
      return false;
    }
  });

  await dependencies.runGuardedZone(
    () async {
      // Initialize Flutter bindings INSIDE the guarded zone so runApp and
      // ensureInitialized share the same zone. A zone mismatch causes auth
      // state changes to not propagate to the GoRouter redirect.
      dependencies.ensureFlutterBindingInitialized();

      try {
        await dependencies.runBootstrapSequence(
          rootContainer: rootContainer,
          runAppWidget: dependencies.runAppWidget,
        );
      } on Object catch (error, stackTrace) {
        await runtimeFailureReporter.capture(
          error: error,
          stackTrace: stackTrace,
          source: 'bootstrap',
        );
        dependencies.reportFlutterError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'app bootstrap',
            context: ErrorDescription('while initializing runtime services'),
          ),
        );
        dependencies.runAppWidget(
          buildBootstrapFailureApp(
            error: error,
            stackTrace: stackTrace,
            showDiagnostics: showBootstrapFailureDiagnostics,
          ),
        );
      }
    },
    (Object error, StackTrace stackTrace) {
      unawaited(
        runtimeFailureReporter.capture(
          error: error,
          stackTrace: stackTrace,
          source: 'zone_guard',
        ),
      );
      dependencies.reportFlutterError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app runtime',
          context: ErrorDescription(
            'while handling an uncaught asynchronous error',
          ),
        ),
      );
    },
  );
}

Future<void> _runInGuardedZone(
  Future<void> Function() body,
  void Function(Object error, StackTrace stackTrace) onError,
) async {
  await (runZonedGuarded<Future<void>>(body, onError) ?? Future<void>.value());
}

const _bootstrapStepTimeout = Duration(seconds: 15);

Future<void> _runBootstrapSequence({
  required ProviderContainer rootContainer,
  required void Function(Widget app) runAppWidget,
}) async {
  final environmentAsset = resolveRuntimeEnvironmentAsset();
  debugPrint('BOOTSTRAP: loading $environmentAsset');
  await dotenv.load(fileName: environmentAsset).timeout(_bootstrapStepTimeout);

  final environment = dotenv.env;

  debugPrint('BOOTSTRAP: initializing Supabase');
  await Supabase.initialize(
    url: requireEnvironmentValue(
      environment: environment,
      key: 'SUPABASE_URL',
    ),
    anonKey: requireEnvironmentValue(
      environment: environment,
      key: 'SUPABASE_ANON_KEY',
    ),
  ).timeout(_bootstrapStepTimeout);

  // Auto-login for Maestro/E2E test builds. Signs in during bootstrap (before
  // the widget tree renders) so the auth state is already resolved when
  // GoRouter first evaluates its redirect. This is cleaner than entering
  // credentials through the UI and avoids auth stream timing edge cases.
  // Pass --dart-define=E2E_AUTO_LOGIN_EMAIL=x --dart-define=E2E_AUTO_LOGIN_PASSWORD=y
  const autoLoginEmail = String.fromEnvironment('E2E_AUTO_LOGIN_EMAIL');
  const autoLoginPassword = String.fromEnvironment('E2E_AUTO_LOGIN_PASSWORD');
  if (autoLoginEmail.isNotEmpty && autoLoginPassword.isNotEmpty) {
    debugPrint('BOOTSTRAP: auto-login for E2E test user $autoLoginEmail');
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(
            email: autoLoginEmail,
            password: autoLoginPassword,
          )
          .timeout(_bootstrapStepTimeout);
      debugPrint('BOOTSTRAP: auto-login succeeded');
    } on Object catch (e) {
      debugPrint('BOOTSTRAP: auto-login failed: $e');
    }
  }

  // Skip Firebase in Maestro/E2E test builds. Firebase initialization can
  // hang on iOS simulators with prod config, and push notifications are not
  // needed for smoke tests. Pass --dart-define=SKIP_FIREBASE=true to skip.
  const skipFirebase = bool.fromEnvironment('SKIP_FIREBASE');
  if (skipFirebase) {
    debugPrint('BOOTSTRAP: skipping Firebase (SKIP_FIREBASE=true)');
  } else {
    debugPrint('BOOTSTRAP: initializing Firebase');
    await Firebase.initializeApp().timeout(_bootstrapStepTimeout);
  }

  debugPrint('BOOTSTRAP: validating OAuth config');
  const AuthOAuthConfigInitializer().initialize(environment: environment);

  debugPrint('BOOTSTRAP: initializing Mapbox token');
  const MapboxTokenInitializer().initialize(
    environment: environment,
    applyAccessToken: MapboxOptions.setAccessToken,
  );

  final trackingSmokeOverrides = buildTrackingSmokeOverrides();
  const app = TelemetryLifecycleBootstrap(
    child: _NotificationRegistrarBootstrap(
      child: UffApp(),
    ),
  );

  debugPrint('BOOTSTRAP: running app');
  if (trackingSmokeOverrides.isEmpty) {
    runAppWidget(
      UncontrolledProviderScope(
        container: rootContainer,
        child: app,
      ),
    );
    return;
  }

  debugPrint('BOOTSTRAP: enabling replay tracking smoke overrides');
  final appContainer = ProviderContainer(
    parent: rootContainer,
    overrides: trackingSmokeOverrides,
  );
  runAppWidget(
    UncontrolledProviderScope(
      container: appContainer,
      child: app,
    ),
  );
}

/// Captures bootstrap and hook failures without cascading secondary crashes.
class _RuntimeFailureReporter {
  const _RuntimeFailureReporter({
    required RuntimeUnhandledCapture captureUnhandled,
    required ProviderContainer rootContainer,
  }) : _captureUnhandled = captureUnhandled,
       _rootContainer = rootContainer;

  final RuntimeUnhandledCapture _captureUnhandled;
  final ProviderContainer _rootContainer;

  Future<void> capture({
    required Object error,
    required StackTrace stackTrace,
    required String source,
    Map<String, Object?> additionalMetadata = const <String, Object?>{},
  }) async {
    final metadata = <String, Object?>{
      'source': source,
      ...additionalMetadata,
    };
    try {
      await _captureUnhandled(
        rootContainer: _rootContainer,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      );
    } on Object {
      // Runtime capture should never crash hook handlers or bootstrap fallback.
    }
  }
}

/// Wraps the app with a Semantics node exposing push token sync state.
class _NotificationRegistrarBootstrap extends ConsumerWidget {
  const _NotificationRegistrarBootstrap({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrarState = ref.watch(notificationRegistrarProvider);
    final statusLabel = registrarState.when(
      data: (_) => 'synced',
      error: (_, __) => 'error',
      loading: () => 'loading',
    );
    // container: true forces a dedicated SemanticsNode for the status
    // identifier so it does not merge with the receipt Semantics child.
    return Semantics(
      container: true,
      identifier: 'notification-status-$statusLabel',
      child: _NotificationReceiptBootstrap(child: child),
    );
  }
}

/// Wraps the app with a Semantics node exposing push receipt state.
///
/// Identifier is `notification-receipt-none` until a notification arrives,
/// then `notification-receipt-present`. The most recent message id is
/// exposed via Semantics.value so device-lane tests can correlate the
/// observed receipt to the dispatched payload.
class _NotificationReceiptBootstrap extends ConsumerWidget {
  const _NotificationReceiptBootstrap({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(notificationReceiptProvider);
    final presenceLabel = receipt == null ? 'none' : 'present';
    return Semantics(
      container: true,
      identifier: 'notification-receipt-$presenceLabel',
      value: receipt?.messageId ?? '',
      child: child,
    );
  }
}

/// Testing-only factory for [_NotificationRegistrarBootstrap].
///
/// Exposes the private bootstrap widget so tests can exercise its Semantics
/// identifier without importing `main.dart` internals.
@visibleForTesting
Widget buildNotificationRegistrarBootstrapForTesting({
  required Widget child,
}) {
  return _NotificationRegistrarBootstrap(child: child);
}

// TODO(uff): Document _BootstrapFailureApp.
/// TODO: Document _BootstrapFailureApp.
class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({
    required this.error,
    required this.stackTrace,
    required this.showDiagnostics,
  });

  final Object error;
  final StackTrace stackTrace;
  final bool showDiagnostics;

  @override
  Widget build(BuildContext context) {
    final errorText = error.toString();
    final stackText = stackTrace.toString();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Startup Error')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Text(
                'The app failed during bootstrap.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Restart the app. If it keeps failing, reinstall or update it.',
              ),
              if (showDiagnostics) ...[
                const SizedBox(height: 16),
                SelectableText(errorText),
                const SizedBox(height: 16),
                SelectableText(stackText),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
