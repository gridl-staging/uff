import 'package:permission_handler/permission_handler.dart';

enum TrackingPermissionDecision {
  granted,
  denied,
  deniedPermanently,
}

/// NOTE(stuart): Document TrackingPermissionService.
class TrackingPermissionService {
  Future<TrackingPermissionDecision> ensureForegroundPermission() async {
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted || status.isLimited) {
      return TrackingPermissionDecision.granted;
    }

    final request = await Permission.locationWhenInUse.request();
    if (request.isGranted || request.isLimited) {
      return TrackingPermissionDecision.granted;
    }

    if (request.isPermanentlyDenied) {
      return TrackingPermissionDecision.deniedPermanently;
    }

    return TrackingPermissionDecision.denied;
  }

  Future<TrackingPermissionDecision> ensureBackgroundPermission() async {
    final status = await Permission.locationAlways.status;
    if (status.isGranted) {
      return TrackingPermissionDecision.granted;
    }

    final request = await Permission.locationAlways.request();
    if (request.isGranted) {
      return TrackingPermissionDecision.granted;
    }

    if (request.isPermanentlyDenied) {
      return TrackingPermissionDecision.deniedPermanently;
    }

    return TrackingPermissionDecision.denied;
  }
}
