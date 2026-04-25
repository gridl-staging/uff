import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/data/privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

final privacyZoneFormControllerProvider =
    NotifierProvider<PrivacyZoneFormController, PrivacyZoneFormState>(
      PrivacyZoneFormController.new,
    );

enum PrivacyZoneFormOperation {
  idle,
  creating,
  updating,
  deleting,
}

/// NOTE(stuart): Document PrivacyZoneFormState.
@immutable
class PrivacyZoneFormState {
  const PrivacyZoneFormState({
    this.activeOperation = PrivacyZoneFormOperation.idle,
    this.errorMessage,
  });

  final PrivacyZoneFormOperation activeOperation;
  final String? errorMessage;

  bool get isSubmitting => activeOperation != PrivacyZoneFormOperation.idle;

  PrivacyZoneFormState copyWith({
    PrivacyZoneFormOperation? activeOperation,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PrivacyZoneFormState(
      activeOperation: activeOperation ?? this.activeOperation,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

/// NOTE(stuart): Document PrivacyZoneFormController.
class PrivacyZoneFormController extends Notifier<PrivacyZoneFormState> {
  late final PrivacyZoneRepository _repository;

  @override
  PrivacyZoneFormState build() {
    _repository = ref.read(privacyZoneRepositoryProvider);
    return const PrivacyZoneFormState();
  }

  Future<PrivacyZone?> createZone(ValidatedPrivacyZoneFormInput input) async {
    _beginOperation(PrivacyZoneFormOperation.creating);

    try {
      final createdZone = await _repository.createZone(
        label: input.label,
        latitude: input.latitude,
        longitude: input.longitude,
        radiusMeters: input.radiusMeters,
      );
      _finishSuccessfulOperation();
      return createdZone;
    } on Object {
      _finishFailedOperation(
        'Failed to create privacy zone. Please try again.',
      );
      return null;
    }
  }

  Future<bool> updateZone({
    required PrivacyZone existingZone,
    required ValidatedPrivacyZoneFormInput input,
  }) async {
    _beginOperation(PrivacyZoneFormOperation.updating);

    try {
      await _repository.updateZone(_updatedZone(existingZone, input));
      _finishSuccessfulOperation();
      return true;
    } on Object {
      _finishFailedOperation(
        'Failed to update privacy zone. Please try again.',
      );
      return false;
    }
  }

  Future<bool> deleteZone(String zoneId) async {
    _beginOperation(PrivacyZoneFormOperation.deleting);

    try {
      await _repository.deleteZone(zoneId);
      _finishSuccessfulOperation();
      return true;
    } on Object {
      _finishFailedOperation(
        'Failed to delete privacy zone. Please try again.',
      );
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  void _beginOperation(PrivacyZoneFormOperation operation) {
    state = state.copyWith(
      activeOperation: operation,
      clearErrorMessage: true,
    );
  }

  void _finishSuccessfulOperation() {
    _invalidatePrivacyZones();
    state = state.copyWith(
      activeOperation: PrivacyZoneFormOperation.idle,
      clearErrorMessage: true,
    );
  }

  void _finishFailedOperation(String errorMessage) {
    state = state.copyWith(
      activeOperation: PrivacyZoneFormOperation.idle,
      errorMessage: errorMessage,
    );
  }

  PrivacyZone _updatedZone(
    PrivacyZone existingZone,
    ValidatedPrivacyZoneFormInput input,
  ) {
    return PrivacyZone(
      id: existingZone.id,
      userId: existingZone.userId,
      label: input.label,
      latitude: input.latitude,
      longitude: input.longitude,
      radiusMeters: input.radiusMeters,
    );
  }

  void _invalidatePrivacyZones() {
    ref.invalidate(privacyZonesProvider);
  }
}

@immutable
class ValidatedPrivacyZoneFormInput {
  const ValidatedPrivacyZoneFormInput({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String label;
  final double latitude;
  final double longitude;
  final int radiusMeters;
}

@immutable
class PrivacyZoneFormParseResult {
  const PrivacyZoneFormParseResult._({this.value, this.errorMessage});

  const PrivacyZoneFormParseResult.success(ValidatedPrivacyZoneFormInput value)
    : this._(value: value);

  const PrivacyZoneFormParseResult.failure(String errorMessage)
    : this._(errorMessage: errorMessage);

  final ValidatedPrivacyZoneFormInput? value;
  final String? errorMessage;

  bool get isValid => value != null;
}

@immutable
class PrivacyZonePreviewCoordinates {
  const PrivacyZonePreviewCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

PrivacyZoneFormParseResult parsePrivacyZoneFormInput({
  required String labelText,
  required String latitudeText,
  required String longitudeText,
  required String radiusText,
}) {
  final label = labelText.trim();
  if (label.isEmpty) {
    return const PrivacyZoneFormParseResult.failure('Label is required.');
  }

  final coordinatesResult = _parseCoordinates(
    latitudeText: latitudeText,
    longitudeText: longitudeText,
  );
  if (coordinatesResult.errorMessage != null) {
    return PrivacyZoneFormParseResult.failure(coordinatesResult.errorMessage!);
  }

  final radiusResult = _parsePositiveIntField(
    valueText: radiusText,
    fieldName: 'Radius',
  );
  if (radiusResult.errorMessage != null) {
    return PrivacyZoneFormParseResult.failure(radiusResult.errorMessage!);
  }

  final coordinates = coordinatesResult.value!;
  return PrivacyZoneFormParseResult.success(
    ValidatedPrivacyZoneFormInput(
      label: label,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters: radiusResult.value!,
    ),
  );
}

@immutable
class _CoordinateParseResult {
  const _CoordinateParseResult({
    this.value,
    this.errorMessage,
  });

  final PrivacyZonePreviewCoordinates? value;
  final String? errorMessage;
}

_CoordinateParseResult _parseCoordinates({
  required String latitudeText,
  required String longitudeText,
}) {
  final latitudeResult = _parseBoundedDoubleField(
    valueText: latitudeText,
    fieldName: 'Latitude',
    minimum: -90,
    maximum: 90,
  );
  if (latitudeResult.errorMessage != null) {
    return _CoordinateParseResult(errorMessage: latitudeResult.errorMessage);
  }

  final longitudeResult = _parseBoundedDoubleField(
    valueText: longitudeText,
    fieldName: 'Longitude',
    minimum: -180,
    maximum: 180,
  );
  if (longitudeResult.errorMessage != null) {
    return _CoordinateParseResult(errorMessage: longitudeResult.errorMessage);
  }

  return _CoordinateParseResult(
    value: PrivacyZonePreviewCoordinates(
      latitude: latitudeResult.value!,
      longitude: longitudeResult.value!,
    ),
  );
}

@immutable
class _DoubleFieldParseResult {
  const _DoubleFieldParseResult({
    this.value,
    this.errorMessage,
  });

  final double? value;
  final String? errorMessage;
}

_DoubleFieldParseResult _parseBoundedDoubleField({
  required String valueText,
  required String fieldName,
  required double minimum,
  required double maximum,
}) {
  final parsed = double.tryParse(valueText.trim());
  if (parsed == null) {
    return _DoubleFieldParseResult(
      errorMessage: '$fieldName must be a number.',
    );
  }
  if (!parsed.isFinite) {
    return _DoubleFieldParseResult(
      errorMessage: '$fieldName must be a finite number.',
    );
  }
  if (parsed < minimum || parsed > maximum) {
    final minLabel = _formatRangeBound(minimum);
    final maxLabel = _formatRangeBound(maximum);
    return _DoubleFieldParseResult(
      errorMessage: '$fieldName must be between $minLabel and $maxLabel.',
    );
  }
  return _DoubleFieldParseResult(value: parsed);
}

String _formatRangeBound(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

@immutable
class _IntFieldParseResult {
  const _IntFieldParseResult({
    this.value,
    this.errorMessage,
  });

  final int? value;
  final String? errorMessage;
}

_IntFieldParseResult _parsePositiveIntField({
  required String valueText,
  required String fieldName,
}) {
  final parsed = int.tryParse(valueText.trim());
  if (parsed == null) {
    return _IntFieldParseResult(
      errorMessage: '$fieldName must be a whole number.',
    );
  }
  if (parsed <= 0) {
    return _IntFieldParseResult(
      errorMessage: '$fieldName must be greater than 0.',
    );
  }
  return _IntFieldParseResult(value: parsed);
}

PrivacyZonePreviewCoordinates? parsePrivacyZonePreviewCoordinates({
  required String latitudeText,
  required String longitudeText,
}) {
  final parseResult = parsePrivacyZoneFormInput(
    labelText: 'preview',
    latitudeText: latitudeText,
    longitudeText: longitudeText,
    radiusText: '1',
  );
  final value = parseResult.value;
  if (value == null) {
    return null;
  }

  return PrivacyZonePreviewCoordinates(
    latitude: value.latitude,
    longitude: value.longitude,
  );
}
