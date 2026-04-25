import 'dart:async';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/clubs/application/club_location_service.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/data/supabase_club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';

part 'club_providers.g.dart';

@riverpod
ClubRepository clubRepository(Ref ref) {
  return SupabaseClubRepository(Supabase.instance.client);
}

@riverpod
Future<List<Club>> myClubs(Ref ref) {
  return ref.read(clubRepositoryProvider).getMyClubs();
}

@riverpod
Future<Club?> clubDetail(Ref ref, String clubId) {
  return ref.read(clubRepositoryProvider).getClub(clubId);
}

@riverpod
Future<List<ClubMember>> clubMembers(Ref ref, String clubId) {
  return ref.read(clubRepositoryProvider).getClubMembers(clubId);
}

@riverpod
Future<List<Club>> clubSearch(Ref ref, String query) {
  final normalizedQuery = _normalizeSearchQuery(query);
  if (normalizedQuery == null) {
    return Future.value(const <Club>[]);
  }
  return ref.read(clubRepositoryProvider).searchClubs(normalizedQuery);
}

@riverpod
Future<List<Club>> nearbyClubs(Ref ref) async {
  final clubs = await ref.read(clubRepositoryProvider).listClubs();
  final location = await ref
      .read(clubLocationServiceProvider)
      .fetchCurrentLocation();
  if (location == null) {
    return clubs;
  }
  return _sortClubsByDistance(
    clubs: clubs,
    origin: location,
  );
}

@riverpod
Future<List<ClubRun>> upcomingClubRuns(Ref ref, String clubId) {
  return ref.read(clubRepositoryProvider).getUpcomingClubRuns(clubId);
}

String? _normalizeSearchQuery(String query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return null;
  }
  return trimmedQuery;
}

List<Club> _sortClubsByDistance({
  required List<Club> clubs,
  required ClubCoordinates origin,
}) {
  final indexedDistances =
      clubs
          .asMap()
          .entries
          .map((entry) {
            final club = entry.value;
            final latitude = club.locationLat;
            final longitude = club.locationLng;
            if (latitude == null || longitude == null) {
              return (
                index: entry.key,
                distanceMeters: null as double?,
                club: club,
              );
            }
            return (
              index: entry.key,
              distanceMeters: _haversineDistanceMeters(
                originLatitude: origin.latitude,
                originLongitude: origin.longitude,
                destinationLatitude: latitude,
                destinationLongitude: longitude,
              ),
              club: club,
            );
          })
          .toList(growable: false)
        ..sort((left, right) {
          final leftDistance = left.distanceMeters;
          final rightDistance = right.distanceMeters;
          if (leftDistance == null && rightDistance == null) {
            return left.index.compareTo(right.index);
          }
          if (leftDistance == null) {
            return 1;
          }
          if (rightDistance == null) {
            return -1;
          }
          final byDistance = leftDistance.compareTo(rightDistance);
          if (byDistance != 0) {
            return byDistance;
          }
          return left.index.compareTo(right.index);
        });

  return indexedDistances.map((entry) => entry.club).toList(growable: false);
}

double _haversineDistanceMeters({
  required double originLatitude,
  required double originLongitude,
  required double destinationLatitude,
  required double destinationLongitude,
}) {
  const earthRadiusMeters = 6371000.0;
  final originLatitudeRadians = _degreesToRadians(originLatitude);
  final destinationLatitudeRadians = _degreesToRadians(destinationLatitude);
  final latitudeDeltaRadians = _degreesToRadians(
    destinationLatitude - originLatitude,
  );
  final longitudeDeltaRadians = _degreesToRadians(
    destinationLongitude - originLongitude,
  );

  final haversineFormulaA =
      math.sin(latitudeDeltaRadians / 2) * math.sin(latitudeDeltaRadians / 2) +
      math.cos(originLatitudeRadians) *
          math.cos(destinationLatitudeRadians) *
          math.sin(longitudeDeltaRadians / 2) *
          math.sin(longitudeDeltaRadians / 2);
  final angularDistanceC =
      2 *
      math.atan2(
        math.sqrt(haversineFormulaA),
        math.sqrt(1 - haversineFormulaA),
      );
  return earthRadiusMeters * angularDistanceC;
}

double _degreesToRadians(double degrees) {
  return degrees * (math.pi / 180);
}

/// TODO: Document ClubMutationController.
@riverpod
class ClubMutationController extends _$ClubMutationController {
  @override
  FutureOr<void> build() {}

  Future<Club> createClub(CreateClubInput input) {
    return _runMutation<Club>(
      mutate: (repository) => repository.createClub(input),
      invalidateCaches: (createdClub) {
        _invalidateClubEntityCaches(clubId: createdClub.id);
      },
    );
  }

  Future<void> joinClub(String clubId) {
    return _runMutation<void>(
      mutate: (repository) => repository.joinClub(clubId),
      invalidateCaches: (_) {
        _invalidateClubEntityCaches(clubId: clubId);
      },
    );
  }

  Future<void> leaveClub(String clubId) {
    return _runMutation<void>(
      mutate: (repository) => repository.leaveClub(clubId),
      invalidateCaches: (_) {
        _invalidateClubEntityCaches(clubId: clubId);
      },
    );
  }

  Future<void> updateClub(Club club) {
    return _runMutation<void>(
      mutate: (repository) => repository.updateClub(club),
      invalidateCaches: (_) {
        _invalidateClubEntityCaches(clubId: club.id);
      },
    );
  }

  Future<void> deleteClub(String clubId) {
    return _runMutation<void>(
      mutate: (repository) => repository.deleteClub(clubId),
      invalidateCaches: (_) {
        _invalidateClubEntityCaches(clubId: clubId);
      },
    );
  }

  Future<ClubRun> createClubRun(CreateClubRunInput input) {
    return _runMutation<ClubRun>(
      mutate: (repository) => repository.createClubRun(input),
      invalidateCaches: (_) {
        _invalidateUpcomingRunsCache(clubId: input.clubId);
      },
    );
  }

  Future<T> _runMutation<T>({
    required Future<T> Function(ClubRepository repository) mutate,
    required void Function(T result) invalidateCaches,
  }) async {
    final mutationKeepAlive = ref.keepAlive();
    state = const AsyncLoading<void>();
    try {
      final result = await mutate(ref.read(clubRepositoryProvider));
      if (!ref.mounted) {
        return result;
      }
      state = const AsyncData<void>(null);
      invalidateCaches(result);
      return result;
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncError<void>(error, stackTrace);
      }
      rethrow;
    } finally {
      mutationKeepAlive.close();
    }
  }

  void _invalidateClubEntityCaches({required String clubId}) {
    ref
      ..invalidate(myClubsProvider)
      ..invalidate(clubDetailProvider(clubId))
      ..invalidate(clubMembersProvider(clubId))
      ..invalidate(nearbyClubsProvider)
      ..invalidate(clubSearchProvider);
  }

  void _invalidateUpcomingRunsCache({required String clubId}) {
    ref.invalidate(upcomingClubRunsProvider(clubId));
  }
}
