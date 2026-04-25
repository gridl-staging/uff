import 'dart:async';

import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';

/// Reusable clubs test double with call recording and controllable async flows.
class RecordingClubRepository implements ClubRepository {
  List<Club> clubsToReturn = const <Club>[];
  List<Club> myClubsToReturn = const <Club>[];
  List<ClubMember> clubMembersToReturn = const <ClubMember>[];
  List<ClubRun> upcomingRunsToReturn = const <ClubRun>[];
  Club? clubToReturn;
  Club? createdClubToReturn;
  ClubRun? createdRunToReturn;

  Object? getClubError;
  Object? listClubsError;
  Object? searchClubsError;
  Object? getMyClubsError;
  Object? createClubError;
  Object? updateClubError;
  Object? deleteClubError;
  Object? joinClubError;
  Object? leaveClubError;
  Object? getClubMembersError;
  Object? getUpcomingRunsError;
  Object? createClubRunError;

  int getClubCallCount = 0;
  int listClubsCallCount = 0;
  int searchClubsCallCount = 0;
  int getMyClubsCallCount = 0;
  int createClubCallCount = 0;
  int updateClubCallCount = 0;
  int deleteClubCallCount = 0;
  int joinClubCallCount = 0;
  int leaveClubCallCount = 0;
  int getClubMembersCallCount = 0;
  int getUpcomingRunsCallCount = 0;
  int createClubRunCallCount = 0;

  String? lastClubId;
  String? lastSearchQuery;
  String? lastDeletedClubId;
  String? lastJoinedClubId;
  String? lastLeftClubId;
  String? lastMembersClubId;
  String? lastUpcomingRunsClubId;
  Club? lastUpdatedClub;
  CreateClubInput? lastCreateClubInput;
  CreateClubRunInput? lastCreateClubRunInput;

  Completer<Club>? createClubCompleter;
  Completer<void>? updateClubCompleter;
  Completer<void>? joinClubCompleter;
  Completer<void>? leaveClubCompleter;
  Completer<ClubRun>? createClubRunCompleter;

  Never _throwRecordedError(Object error) {
    if (error case final Exception exception) {
      throw exception;
    }
    if (error case final Error fatalError) {
      throw fatalError;
    }
    throw StateError(
      'RecordingClubRepository errors must be Exception or Error, got ${error.runtimeType}.',
    );
  }

  @override
  Future<Club?> getClub(String clubId) async {
    getClubCallCount += 1;
    lastClubId = clubId;
    if (getClubError case final Object error) {
      _throwRecordedError(error);
    }
    return clubToReturn;
  }

  @override
  Future<List<Club>> listClubs() async {
    listClubsCallCount += 1;
    if (listClubsError case final Object error) {
      _throwRecordedError(error);
    }
    return clubsToReturn;
  }

  @override
  Future<List<Club>> searchClubs(String query) async {
    searchClubsCallCount += 1;
    lastSearchQuery = query;
    if (searchClubsError case final Object error) {
      _throwRecordedError(error);
    }
    return clubsToReturn;
  }

  @override
  Future<List<Club>> getMyClubs() async {
    getMyClubsCallCount += 1;
    if (getMyClubsError case final Object error) {
      _throwRecordedError(error);
    }
    return myClubsToReturn;
  }

  @override
  Future<Club> createClub(CreateClubInput input) async {
    createClubCallCount += 1;
    lastCreateClubInput = input;
    if (createClubError case final Object error) {
      _throwRecordedError(error);
    }
    if (createClubCompleter case final Completer<Club> completer) {
      return completer.future;
    }
    if (createdClubToReturn case final Club created) {
      return created;
    }
    throw StateError(
      'RecordingClubRepository.createdClubToReturn must be set.',
    );
  }

  @override
  Future<void> updateClub(Club club) async {
    updateClubCallCount += 1;
    lastUpdatedClub = club;
    if (updateClubError case final Object error) {
      _throwRecordedError(error);
    }
    if (updateClubCompleter case final Completer<void> completer) {
      return completer.future;
    }
  }

  @override
  Future<void> deleteClub(String clubId) async {
    deleteClubCallCount += 1;
    lastDeletedClubId = clubId;
    if (deleteClubError case final Object error) {
      _throwRecordedError(error);
    }
  }

  @override
  Future<void> joinClub(String clubId) async {
    joinClubCallCount += 1;
    lastJoinedClubId = clubId;
    if (joinClubError case final Object error) {
      _throwRecordedError(error);
    }
    if (joinClubCompleter case final Completer<void> completer) {
      return completer.future;
    }
  }

  @override
  Future<void> leaveClub(String clubId) async {
    leaveClubCallCount += 1;
    lastLeftClubId = clubId;
    if (leaveClubError case final Object error) {
      _throwRecordedError(error);
    }
    if (leaveClubCompleter case final Completer<void> completer) {
      return completer.future;
    }
  }

  @override
  Future<List<ClubMember>> getClubMembers(String clubId) async {
    getClubMembersCallCount += 1;
    lastMembersClubId = clubId;
    if (getClubMembersError case final Object error) {
      _throwRecordedError(error);
    }
    return clubMembersToReturn;
  }

  @override
  Future<List<ClubRun>> getUpcomingClubRuns(String clubId) async {
    getUpcomingRunsCallCount += 1;
    lastUpcomingRunsClubId = clubId;
    if (getUpcomingRunsError case final Object error) {
      _throwRecordedError(error);
    }
    return upcomingRunsToReturn;
  }

  @override
  Future<ClubRun> createClubRun(CreateClubRunInput input) async {
    createClubRunCallCount += 1;
    lastCreateClubRunInput = input;
    if (createClubRunError case final Object error) {
      _throwRecordedError(error);
    }
    if (createClubRunCompleter case final Completer<ClubRun> completer) {
      return completer.future;
    }
    if (createdRunToReturn case final ClubRun run) {
      return run;
    }
    throw StateError('RecordingClubRepository.createdRunToReturn must be set.');
  }
}
