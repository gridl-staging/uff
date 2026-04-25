import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uff/src/core/telemetry/telemetry_enablement.dart';

/// Thin lifecycle widget that starts the telemetry flush scheduler on mount and
/// triggers a flush on app resume. All scheduler exceptions are swallowed so
/// telemetry never crashes product flows.
class TelemetryLifecycleBootstrap extends ConsumerStatefulWidget {
  const TelemetryLifecycleBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TelemetryLifecycleBootstrap> createState() =>
      _TelemetryLifecycleBootstrapState();
}

/// Observes app lifecycle to start and trigger the telemetry flush scheduler.
class _TelemetryLifecycleBootstrapState
    extends ConsumerState<TelemetryLifecycleBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      ref.read(telemetryFlushSchedulerProvider).start();
    } on Object {
      // Telemetry must never crash product flows.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        ref.read(telemetryFlushSchedulerProvider).triggerFlush();
      } on Object {
        // Telemetry must never crash product flows.
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
