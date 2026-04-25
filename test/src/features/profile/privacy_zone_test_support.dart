import 'dart:async';

import 'package:uff/src/features/profile/data/privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

class CreateZoneCall {
  const CreateZoneCall({
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

/// Test double for [PrivacyZoneRepository] with controllable async behavior.
class FakePrivacyZoneRepository implements PrivacyZoneRepository {
  FakePrivacyZoneRepository({
    this.zonesToReturn = const <PrivacyZone>[],
    this.errorToThrow,
    this.loadingCompleter,
    this.createError,
    this.updateError,
    this.deleteError,
    this.createCompleter,
    this.updateCompleter,
    this.deleteCompleter,
  });

  List<PrivacyZone> zonesToReturn;
  Exception? errorToThrow;
  Completer<List<PrivacyZone>>? loadingCompleter;
  Exception? createError;
  Exception? updateError;
  Exception? deleteError;
  Completer<PrivacyZone>? createCompleter;
  Completer<void>? updateCompleter;
  Completer<void>? deleteCompleter;
  int loadZonesCallCount = 0;
  int createZoneCallCount = 0;
  int updateZoneCallCount = 0;
  int deleteZoneCallCount = 0;
  CreateZoneCall? lastCreateZoneCall;
  PrivacyZone? lastUpdatedZone;
  String? lastDeletedZoneId;

  @override
  Future<List<PrivacyZone>> loadZones() async {
    loadZonesCallCount++;

    final pendingLoad = loadingCompleter;
    if (pendingLoad != null) {
      return pendingLoad.future;
    }

    final error = errorToThrow;
    if (error != null) {
      throw error;
    }

    return zonesToReturn;
  }

  @override
  Future<PrivacyZone> createZone({
    required String label,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    createZoneCallCount++;
    lastCreateZoneCall = CreateZoneCall(
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );

    final pendingCreate = createCompleter;
    if (pendingCreate != null) {
      return pendingCreate.future;
    }

    final error = createError;
    if (error != null) {
      throw error;
    }

    final createdZone = PrivacyZone(
      id: 'zone-created-$createZoneCallCount',
      userId: 'user-1',
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    zonesToReturn = [...zonesToReturn, createdZone];
    return createdZone;
  }

  @override
  Future<void> updateZone(PrivacyZone zone) async {
    updateZoneCallCount++;
    lastUpdatedZone = zone;

    final pendingUpdate = updateCompleter;
    if (pendingUpdate != null) {
      await pendingUpdate.future;
      return;
    }

    final error = updateError;
    if (error != null) {
      throw error;
    }

    zonesToReturn = zonesToReturn
        .map((existingZone) => existingZone.id == zone.id ? zone : existingZone)
        .toList(growable: false);
  }

  @override
  Future<void> deleteZone(String id) async {
    deleteZoneCallCount++;
    lastDeletedZoneId = id;

    final pendingDelete = deleteCompleter;
    if (pendingDelete != null) {
      await pendingDelete.future;
      return;
    }

    final error = deleteError;
    if (error != null) {
      throw error;
    }

    zonesToReturn = zonesToReturn
        .where((zone) => zone.id != id)
        .toList(growable: false);
  }
}
