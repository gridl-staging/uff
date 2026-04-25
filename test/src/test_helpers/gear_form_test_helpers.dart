import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_form_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';

import '../features/auth/presentation/auth_test_support.dart';
import 'gear_test_support.dart';

const gearFormExitRouteLabel = 'Gear Form Exit Route';
const gearListRouteLabel = 'Gear List Route';
const gearFormTestScreenSize = Size(1080, 2400);

const _defaultAuthState = AuthState.authenticated(
  userId: 'user-1',
  email: 'user@example.com',
);

ProviderScope _defaultProviderScope({
  required RecordingGearRepository repository,
  required Widget child,
  AuthRepository? authRepository,
  Stream<AuthState>? authStateChanges,
}) {
  final resolvedAuthRepository =
      authRepository ??
      RecordingAuthRepository(initialState: _defaultAuthState);
  final resolvedAuthStateChanges =
      authStateChanges ?? Stream.value(_defaultAuthState);

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(resolvedAuthRepository),
      authStateChangesProvider.overrideWith((ref) => resolvedAuthStateChanges),
      gearRepositoryProvider.overrideWithValue(repository),
    ],
    child: child,
  );
}

Widget buildGearFormScope({
  required RecordingGearRepository repository,
  required Widget child,
  AuthRepository? authRepository,
  Stream<AuthState>? authStateChanges,
}) {
  return _defaultProviderScope(
    repository: repository,
    authRepository: authRepository,
    authStateChanges: authStateChanges,
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: gearFormTestScreenSize),
        child: Scaffold(body: child),
      ),
    ),
  );
}

Widget buildPoppableGearFormScope({
  required RecordingGearRepository repository,
  required Widget child,
}) {
  return _defaultProviderScope(
    repository: repository,
    child: MaterialApp(
      initialRoute: GearRoutes.gearPath,
      routes: {
        '/': (_) => const MediaQuery(
          data: MediaQueryData(size: gearFormTestScreenSize),
          child: Scaffold(body: Text(gearFormExitRouteLabel)),
        ),
        GearRoutes.gearPath: (_) => MediaQuery(
          data: const MediaQueryData(size: gearFormTestScreenSize),
          child: child,
        ),
      },
    ),
  );
}

Widget buildDirectRouteGearFormScope({
  required RecordingGearRepository repository,
  required String initialLocation,
}) {
  return _defaultProviderScope(
    repository: repository,
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: GearRoutes.gearPath,
            builder: (_, __) => const MediaQuery(
              data: MediaQueryData(size: gearFormTestScreenSize),
              child: Scaffold(body: Text(gearListRouteLabel)),
            ),
          ),
          GoRoute(
            path: GearRoutes.gearNewPath,
            builder: (_, __) => const MediaQuery(
              data: MediaQueryData(size: gearFormTestScreenSize),
              child: GearFormScreen(),
            ),
          ),
          GoRoute(
            path: GearRoutes.gearPathPattern,
            builder: (_, state) => MediaQuery(
              data: const MediaQueryData(size: gearFormTestScreenSize),
              child: GearFormScreen(existingItem: state.extra! as GearItem),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> scrollToGearFormAction(WidgetTester tester, Finder finder) async {
  final scrollableFinder = gearFormScrollableFinder(finder);
  await tester.scrollUntilVisible(finder, 240, scrollable: scrollableFinder);

  final scrollableRect = tester.getRect(scrollableFinder);
  final targetRect = tester.getRect(finder);
  final overflowBottom = targetRect.bottom - scrollableRect.bottom;
  if (overflowBottom > 0) {
    await tester.drag(scrollableFinder, Offset(0, -(overflowBottom + 24)));
  }

  final overflowTop = scrollableRect.top - targetRect.top;
  if (overflowTop > 0) {
    await tester.drag(scrollableFinder, Offset(0, overflowTop + 24));
  }
  await tester.pump();
}

Future<void> tapGearFormAction(WidgetTester tester, Finder finder) async {
  await scrollToGearFormAction(tester, finder);
  tester.testTextInput.hide();
  await tester.pump();

  if (finder.hitTestable().evaluate().isNotEmpty) {
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
    return;
  }

  final actionWidget = tester.widget<Widget>(finder);
  if (actionWidget is ElevatedButton && actionWidget.onPressed != null) {
    actionWidget.onPressed!.call();
  } else if (actionWidget is OutlinedButton && actionWidget.onPressed != null) {
    actionWidget.onPressed!.call();
  } else if (actionWidget is TextButton && actionWidget.onPressed != null) {
    actionWidget.onPressed!.call();
  } else if (actionWidget is IconButton && actionWidget.onPressed != null) {
    actionWidget.onPressed!.call();
  } else {
    // Preserve existing behavior for non-button targets.
    await tester.tap(finder, warnIfMissed: false);
  }
  await tester.pump();
}

Finder gearFormScrollableFinder(Finder target) {
  final ancestorScrollables = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  if (ancestorScrollables.evaluate().isNotEmpty) {
    return ancestorScrollables.first;
  }

  final formScrollables = find.descendant(
    of: find.byType(GearFormScreen),
    matching: find.byType(Scrollable),
  );
  return formScrollables.first;
}

class DelayedSessionAuthRepository extends RecordingAuthRepository {
  DelayedSessionAuthRepository(this.sessionCompleter);

  final Completer<AuthState> sessionCompleter;

  @override
  Future<AuthState> getCurrentSession() => sessionCompleter.future;
}

class GearListProbe extends ConsumerWidget {
  const GearListProbe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(gearListProvider);
    return const SizedBox.shrink();
  }
}
