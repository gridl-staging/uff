import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:uff/src/core/presentation/copyable_error_text.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_smoke_overrides.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/pending_photo_providers.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

class CompassNorthLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLocked(bool isLocked) {
    state = isLocked;
  }
}

final compassNorthLockProvider =
    NotifierProvider<CompassNorthLockNotifier, bool>(
      CompassNorthLockNotifier.new,
    );

/// TODO: Document RecordingScreen.
class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  static const startButtonKey = Key('recording_start_button');
  static const pauseButtonKey = Key('recording_pause_button');
  static const resumeButtonKey = Key('recording_resume_button');
  static const stopButtonKey = Key('recording_stop_button');
  static const finishButtonKey = Key('recording_finish_button');
  static const reviewButtonKey = Key('recording_review_button');
  static const saveButtonKey = Key('recording_save_button');
  static const discardButtonKey = Key('recording_discard_button');
  static const distanceTextKey = Key('recording_distance_text');
  static const elapsedTextKey = Key('recording_elapsed_text');
  static const errorTextKey = Key('recording_error_text');
  static const statusLabelKey = Key('recording_status_label');
  static const gpsSignalDotKey = Key('recording_gps_signal_dot');
  static const compassButtonKey = Key('recording_compass_button');
  static const compassLockStatusKey = Key('recording_compass_lock_status');
  static const reCenterButtonKey = Key('recording_recenter_button');
  static const cameraModeButtonKey = Key('recording_camera_mode_button');
  static const photoCaptureButtonKey = Key('recording_photo_capture_button');

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

// TODO(uff): Document _RecordingScreenState.
/// TODO: Document _RecordingScreenState.
class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  MapViewUserLocationCameraMode _cameraMode =
      MapViewUserLocationCameraMode.perspective;
  int _northUpRequestGeneration = 0;

  mapbox.MapboxMap? _mapboxMap;
  final ValueNotifier<double> _bearingNotifier = ValueNotifier<double>(0);

  RecordingController get _recordingController =>
      ref.read(recordingControllerProvider.notifier);

  bool get _isPerspectiveCameraMode =>
      _cameraMode == MapViewUserLocationCameraMode.perspective;

  @override
  void dispose() {
    _bearingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(recordingControllerProvider);
    final pendingPhotoServiceState = ref.watch(pendingPhotoServiceProvider);
    final isNorthUpLocked = ref.watch(compassNorthLockProvider);
    final routePoints = toRoutePoints(controllerState.points);
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;
    final cleanedPoints = cleanTrackingPoints(
      controllerState.points,
    ).cleanedPoints;
    final liveDistance = calculateTrackDistanceMeters(cleanedPoints);
    final liveElapsed = controllerState.elapsed(now: DateTime.now());
    final livePacePerKilometer = calculatePacePerKilometer(
      distanceMeters: liveDistance,
      elapsedTime: liveElapsed,
    );
    final livePacePerMile = calculatePacePerMile(
      distanceMeters: liveDistance,
      elapsedTime: liveElapsed,
    );

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            key: ValueKey<Object?>(controllerState.session?.id ?? 'idle'),
            followUserLocation: true,
            userLocationCameraMode: _cameraMode,
            followUserHeading: !isNorthUpLocked,
            northUpRequestGeneration: _northUpRequestGeneration,
            routePoints: routePoints,
            showNativeCompass: false,
            onMapCreated: _handleMapCreated,
            onBearingChanged: (bearing) => _bearingNotifier.value = bearing,
          ),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.black.withValues(alpha: 0.6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _buildGpsSignalDot(
                          quality: controllerState.gpsSignalQuality,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            key: RecordingScreen.statusLabelKey,
                            _statusLabel(controllerState.status),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _statusColor(controllerState.status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Distance: ${formatDistance(liveDistance, preferredUnits: preferredUnits)}',
                      key: RecordingScreen.distanceTextKey,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Elapsed: ${formatDuration(liveElapsed)}',
                      key: RecordingScreen.elapsedTextKey,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Pace: ${formatPaceForPreferredUnits(pacePerKilometer: livePacePerKilometer, pacePerMile: livePacePerMile, preferredUnits: preferredUnits)}',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: paceColor(livePacePerKilometer),
                      ),
                    ),
                    if (controllerState.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      CopyableErrorText(
                        controllerState.errorMessage!,
                        key: RecordingScreen.errorTextKey,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompassButton(isNorthUpLocked: isNorthUpLocked),
                const SizedBox(height: 8),
                _buildReCenterButton(),
                const SizedBox(height: 8),
                _buildCameraModeButton(),
              ],
            ),
          ),

          // Photo capture button — visible during active recording only after
          // the pending photo service has resolved. This keeps us from
          // presenting a dead capture affordance while camera access and
          // storage setup are still loading.
          if ((controllerState.status == TrackingSessionStatus.recording ||
                  controllerState.status == TrackingSessionStatus.paused) &&
              pendingPhotoServiceState.hasValue)
            Positioned(
              left: 16,
              bottom: 180,
              child: _buildPhotoCaptureButton(),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildActionButtons(controllerState),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps [child] in a circular container with a subtle drop shadow,
  /// used by the map-overlay control buttons (compass, camera mode, photo).
  Widget _buildMapOverlayCircle({
    required Widget child,
    Color? color,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCompassButton({required bool isNorthUpLocked}) {
    return _buildMapOverlayCircle(
      padding: const EdgeInsets.all(10),
      child: ValueListenableBuilder<double>(
        valueListenable: _bearingNotifier,
        builder: (context, bearing, _) {
          return GestureDetector(
            key: RecordingScreen.compassButtonKey,
            onTap: _toggleNorthLock,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const CustomPaint(
                        size: Size.square(52),
                        painter: _CompassDialPainter(),
                      ),
                      Transform.rotate(
                        angle: -bearing * (math.pi / 180),
                        child: const _CompassNeedle(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  key: RecordingScreen.compassLockStatusKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isNorthUpLocked
                        ? Colors.black.withValues(alpha: 0.78)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isNorthUpLocked ? 'North locked' : 'Free rotate',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isNorthUpLocked ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReCenterButton() {
    return _buildMapOverlayCircle(
      child: IconButton(
        key: RecordingScreen.reCenterButtonKey,
        onPressed: () => unawaited(_reCenterOnCurrentPosition()),
        tooltip: 'Re-center on current position',
        icon: const Icon(Icons.my_location, color: Colors.black87),
      ),
    );
  }

  Widget _buildCameraModeButton() {
    return _buildMapOverlayCircle(
      child: IconButton(
        key: RecordingScreen.cameraModeButtonKey,
        onPressed: _toggleCameraMode,
        tooltip: _isPerspectiveCameraMode
            ? 'Switch to top-down view'
            : 'Switch to perspective view',
        icon: Icon(
          _isPerspectiveCameraMode
              ? Icons.map_outlined
              : Icons.landscape_outlined,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildPhotoCaptureButton() {
    return _buildMapOverlayCircle(
      color: Colors.white,
      child: IconButton(
        key: RecordingScreen.photoCaptureButtonKey,
        onPressed: _capturePhoto,
        tooltip: 'Take photo',
        iconSize: 28,
        icon: const Icon(Icons.camera_alt, color: Colors.blueAccent),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    final controllerState = ref.read(recordingControllerProvider);
    final sessionId = controllerState.session?.id;
    if (sessionId == null) {
      return;
    }
    final lastTrackedCoordinate = controllerState.points.lastOrNull?.coordinate;

    final serviceAsync = ref.read(pendingPhotoServiceProvider);
    final service = serviceAsync.asData?.value;
    if (service == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not ready yet. Try again.')),
        );
      }
      return;
    }

    await service.capturePhoto(
      sessionId,
      latitude: lastTrackedCoordinate?.latitude,
      longitude: lastTrackedCoordinate?.longitude,
    );
  }

  Widget _buildGpsSignalDot({required GpsSignalQuality quality}) {
    final color = switch (quality) {
      GpsSignalQuality.red => Colors.redAccent,
      GpsSignalQuality.amber => Colors.amberAccent,
      GpsSignalQuality.green => Colors.greenAccent,
    };
    return Container(
      key: RecordingScreen.gpsSignalDotKey,
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  void _handleMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  Future<void> _reCenterOnCurrentPosition() async {
    final mapboxMap = _mapboxMap;
    final currentCoordinate = ref
        .read(recordingControllerProvider)
        .points
        .lastOrNull
        ?.coordinate;
    if (mapboxMap == null || currentCoordinate == null) {
      return;
    }

    await mapboxMap.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            currentCoordinate.longitude,
            currentCoordinate.latitude,
          ),
        ),
      ),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  void _toggleNorthLock() {
    final isNorthUpLocked = ref.read(compassNorthLockProvider);
    final shouldLockNorth = !isNorthUpLocked;
    ref.read(compassNorthLockProvider.notifier).setLocked(shouldLockNorth);
    if (shouldLockNorth) {
      setState(() {
        _northUpRequestGeneration += 1;
      });
    }
  }

  void _toggleCameraMode() {
    final nextIsPerspectiveMode = !_isPerspectiveCameraMode;
    ref
        .read(compassNorthLockProvider.notifier)
        .setLocked(!nextIsPerspectiveMode);
    setState(() {
      _cameraMode = nextIsPerspectiveMode
          ? MapViewUserLocationCameraMode.perspective
          : MapViewUserLocationCameraMode.topDown;
    });
  }

  Widget _buildActionButtons(RecordingControllerState state) {
    final allowStartWithoutGpsFix = ref.watch(
      allowRecordingStartWithoutGpsFixProvider,
    );

    return switch (state.status) {
      TrackingSessionStatus.idle => Row(
        children: [
          _buildActionButton(
            key: RecordingScreen.startButtonKey,
            // Smoke builds can inject a replay engine that becomes live only
            // after Start, so they bypass the initial GPS-fix gate.
            onPressed:
                state.gpsSignalQuality != GpsSignalQuality.red ||
                    allowStartWithoutGpsFix
                ? () => _runAction(_recordingController.startRecording)
                : null,
            label: 'Start',
          ),
        ],
      ),
      TrackingSessionStatus.recording => Row(
        children: [
          _buildActionButton(
            key: RecordingScreen.pauseButtonKey,
            onPressed: () => _runAction(_recordingController.pauseRecording),
            label: 'Pause',
          ),
        ],
      ),
      TrackingSessionStatus.paused => Row(
        children: [
          _buildActionButton(
            key: RecordingScreen.resumeButtonKey,
            onPressed: () => _runAction(_recordingController.resumeRecording),
            label: 'Resume',
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            key: RecordingScreen.finishButtonKey,
            onPressed: _finishRecordingAndReview,
            label: 'Finish',
          ),
        ],
      ),
      TrackingSessionStatus.stopped => Row(
        children: [
          _buildActionButton(
            key: RecordingScreen.reviewButtonKey,
            onPressed: _openDraftReview,
            label: 'Review activity',
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildActionButton({
    required Key key,
    required VoidCallback? onPressed,
    required String label,
  }) {
    return Expanded(
      child: ElevatedButton(
        key: key,
        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 56)),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Future<T?> _runAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      _reportActionError(error);
      return null;
    }
  }

  Future<void> _finishRecordingAndReview() async {
    await _runAction(_recordingController.finishRecording);
    if (!mounted) {
      return;
    }
    await _openDraftReview();
  }

  Future<void> _openDraftReview() async {
    final sessionId = ref.read(recordingControllerProvider).session?.id;
    if (!mounted || sessionId == null) {
      return;
    }
    unawaited(context.push(ActivityRoutes.activityDetailPath(sessionId)));
  }

  void _reportActionError(Object error) {
    if (error is InvalidTrackingTransition) {
      _recordingController.setErrorMessage('Invalid action for current state.');
      return;
    }

    _recordingController.setErrorMessage(
      'Unable to complete that action. Please try again.',
    );
  }

  /// User-friendly label for the current tracking status. Shown in the
  /// status pane overlay on the recording screen.
  static String _statusLabel(TrackingSessionStatus status) {
    return switch (status) {
      TrackingSessionStatus.idle => 'Ready',
      TrackingSessionStatus.recording => 'Recording',
      TrackingSessionStatus.paused => 'Paused',
      TrackingSessionStatus.stopped => 'Review',
      TrackingSessionStatus.saving => 'Saving...',
      TrackingSessionStatus.saved => 'Saved',
      TrackingSessionStatus.discarded => 'Discarded',
    };
  }

  /// Accent color for the status label. Green for recording, amber for
  /// paused/saving, white for everything else.
  static Color _statusColor(TrackingSessionStatus status) {
    return switch (status) {
      TrackingSessionStatus.recording ||
      TrackingSessionStatus.saved => Colors.greenAccent,
      TrackingSessionStatus.paused ||
      TrackingSessionStatus.saving ||
      TrackingSessionStatus.stopped => Colors.amberAccent,
      _ => Colors.white,
    };
  }
}

/// TODO: Document _CompassDialPainter.
class _CompassDialPainter extends CustomPainter {
  const _CompassDialPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ringPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, radius - 0.7, ringPaint);

    for (var index = 0; index < 24; index += 1) {
      final angle = (index / 24) * 2 * math.pi - (math.pi / 2);
      final isCardinal = index % 6 == 0;
      final tickLength = isCardinal ? 8.0 : 4.5;
      final tickPaint = Paint()
        ..color = Colors.black.withValues(alpha: isCardinal ? 0.75 : 0.45)
        ..strokeWidth = isCardinal ? 1.8 : 1.2
        ..strokeCap = StrokeCap.round;
      final outer = Offset(
        center.dx + math.cos(angle) * (radius - 5),
        center.dy + math.sin(angle) * (radius - 5),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 5 - tickLength),
        center.dy + math.sin(angle) * (radius - 5 - tickLength),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - (textPainter.width / 2), center.dy - radius + 8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// TODO: Document _CompassNeedle.
class _CompassNeedle extends StatelessWidget {
  const _CompassNeedle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.topCenter,
            child: CustomPaint(
              size: Size(12, 14),
              painter: _CompassNeedlePainter(color: Colors.redAccent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Transform.rotate(
              angle: math.pi,
              child: const CustomPaint(
                size: Size(10, 12),
                painter: _CompassNeedlePainter(color: Colors.black87),
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// TODO: Document _CompassNeedlePainter.
class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.78)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
