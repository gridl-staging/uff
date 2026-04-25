import 'package:uff/src/core/telemetry/domain/telemetry_breadcrumb.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_context.dart';

typedef JsonMap = Map<String, Object?>;

/// TODO: Document QueuedTelemetryEvent.
class QueuedTelemetryEvent {
  QueuedTelemetryEvent({
    required this.eventId,
    required this.capturedAt,
    required this.context,
    required JsonMap metadata,
    required List<TelemetryBreadcrumb> breadcrumbs,
    required this.attemptCount,
    required this.lastAttemptStatus,
    this.lastAttemptedAt,
  }) : metadata = Map<String, Object?>.unmodifiable(
         Map<String, Object?>.from(metadata),
       ),
       breadcrumbs = List<TelemetryBreadcrumb>.unmodifiable(
         _retainNewestBreadcrumbs(breadcrumbs),
       );

  factory QueuedTelemetryEvent.forUnhandled({
    required String eventId,
    required DateTime capturedAt,
    required TelemetryContextEnvelope context,
    required JsonMap metadata,
    required List<TelemetryBreadcrumb> breadcrumbs,
  }) {
    return QueuedTelemetryEvent(
      eventId: eventId,
      capturedAt: capturedAt,
      context: context,
      metadata: metadata,
      breadcrumbs: breadcrumbs,
      attemptCount: 0,
      lastAttemptStatus: neverAttemptedStatus,
    );
  }

  static const int breadcrumbRetentionLimit = 25;
  static const String neverAttemptedStatus = 'never_attempted';

  final String eventId;
  final DateTime capturedAt;
  final TelemetryContextEnvelope context;
  final JsonMap metadata;
  final List<TelemetryBreadcrumb> breadcrumbs;
  final int attemptCount;
  final String lastAttemptStatus;

  /// UTC timestamp of the most recent upload attempt, or null if never
  /// attempted.
  final DateTime? lastAttemptedAt;

  JsonMap toJson() {
    return <String, Object?>{
      'eventId': eventId,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'context': context.toJson(),
      'metadata': Map<String, Object?>.from(metadata),
      'breadcrumbs': breadcrumbs
          .map((TelemetryBreadcrumb breadcrumb) => breadcrumb.toJson())
          .toList(growable: false),
      'attemptCount': attemptCount,
      'lastAttemptStatus': lastAttemptStatus,
      'lastAttemptedAt': lastAttemptedAt?.toUtc().toIso8601String(),
    };
  }

  static List<TelemetryBreadcrumb> _retainNewestBreadcrumbs(
    List<TelemetryBreadcrumb> breadcrumbs,
  ) {
    if (breadcrumbs.length <= breadcrumbRetentionLimit) {
      return List<TelemetryBreadcrumb>.from(breadcrumbs);
    }

    final startIndex = breadcrumbs.length - breadcrumbRetentionLimit;
    return breadcrumbs.sublist(startIndex);
  }
}
