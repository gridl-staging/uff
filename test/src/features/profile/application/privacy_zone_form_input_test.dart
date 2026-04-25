import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/application/privacy_zone_form_controller.dart';

/// ## Test Scenarios
/// - [positive] Valid label, coordinates, and radius parse to ValidatedPrivacyZoneFormInput
/// - [edge] Empty or whitespace-only label is rejected
/// - [edge] Non-numeric, out-of-bounds, and NaN latitude values are rejected
/// - [edge] Non-numeric, out-of-bounds, and NaN longitude values are rejected
/// - [edge] Non-integer and non-positive radius values are rejected
/// - [edge] Non-finite preview coordinates return null
void main() {
  group('parsePrivacyZoneFormInput', () {
    test('trims label and parses valid coordinate/radius values', () {
      final parseResult = parsePrivacyZoneFormInput(
        labelText: '  Home  ',
        latitudeText: ' 40.7128 ',
        longitudeText: ' -74.0060 ',
        radiusText: ' 250 ',
      );

      expect(parseResult.value!.label, 'Home');
      expect(parseResult.value!.latitude, 40.7128);
      expect(parseResult.value!.longitude, -74.006);
      expect(parseResult.value!.radiusMeters, 250);
      expect(parseResult.errorMessage, isNull);
    });

    test('rejects empty trimmed label', () {
      final parseResult = parsePrivacyZoneFormInput(
        labelText: '   ',
        latitudeText: '40.7128',
        longitudeText: '-74.0060',
        radiusText: '250',
      );

      expect(parseResult.value, isNull);
      expect(parseResult.errorMessage, 'Label is required.');
    });

    test('rejects invalid latitude parsing and bounds', () {
      final parseFailure = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: 'north',
        longitudeText: '-74.0060',
        radiusText: '250',
      );
      expect(parseFailure.errorMessage, 'Latitude must be a number.');

      final outOfBounds = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '90.1',
        longitudeText: '-74.0060',
        radiusText: '250',
      );
      expect(outOfBounds.errorMessage, 'Latitude must be between -90 and 90.');

      final notFinite = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: 'NaN',
        longitudeText: '-74.0060',
        radiusText: '250',
      );
      expect(notFinite.errorMessage, 'Latitude must be a finite number.');
    });

    test('rejects invalid longitude parsing and bounds', () {
      final parseFailure = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '40.7128',
        longitudeText: 'west',
        radiusText: '250',
      );
      expect(parseFailure.errorMessage, 'Longitude must be a number.');

      final outOfBounds = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '40.7128',
        longitudeText: '-180.1',
        radiusText: '250',
      );
      expect(
        outOfBounds.errorMessage,
        'Longitude must be between -180 and 180.',
      );

      final notFinite = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '40.7128',
        longitudeText: 'NaN',
        radiusText: '250',
      );
      expect(notFinite.errorMessage, 'Longitude must be a finite number.');
    });

    test('rejects non-positive or non-integer radius values', () {
      final parseFailure = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '40.7128',
        longitudeText: '-74.0060',
        radiusText: 'abc',
      );
      expect(parseFailure.errorMessage, 'Radius must be a whole number.');

      final notPositive = parsePrivacyZoneFormInput(
        labelText: 'Home',
        latitudeText: '40.7128',
        longitudeText: '-74.0060',
        radiusText: '0',
      );
      expect(notPositive.errorMessage, 'Radius must be greater than 0.');
    });
  });

  group('parsePrivacyZonePreviewCoordinates', () {
    test('returns null for non-finite coordinates', () {
      expect(
        parsePrivacyZonePreviewCoordinates(
          latitudeText: 'NaN',
          longitudeText: '-74.0060',
        ),
        isNull,
      );
      expect(
        parsePrivacyZonePreviewCoordinates(
          latitudeText: '40.7128',
          longitudeText: 'NaN',
        ),
        isNull,
      );
    });
  });
}
