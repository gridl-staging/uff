import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/activity_gear_assignment_repository.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

void main() {
  late MockSupabaseClient mockClient;

  setUp(() {
    mockClient = MockSupabaseClient();
  });

  group('SupabaseActivityGearAssignmentRepository', () {
    test('loads activity gear assignment by remote activity id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        selectRows: const [
          <String, dynamic>{'id': 'remote-activity-1', 'gear_id': 'gear-123'},
        ],
      );
      when(() => mockClient.from('activities')).thenAnswer((_) => fakeBuilder);

      final repository = SupabaseActivityGearAssignmentRepository(mockClient);
      final assignedGearId = await repository.loadAssignedGearId(
        'remote-activity-1',
      );

      expect(assignedGearId, 'gear-123');
      expect(fakeBuilder.selectBuilder.lastEqColumn, 'id');
      expect(fakeBuilder.selectBuilder.lastEqValue, 'remote-activity-1');
    });

    test('updates activity gear assignment by remote activity id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        updateRows: const [
          <String, dynamic>{'id': 'remote-activity-2'},
        ],
      );
      when(() => mockClient.from('activities')).thenAnswer((_) => fakeBuilder);

      final repository = SupabaseActivityGearAssignmentRepository(mockClient);
      await repository.updateAssignedGearId('remote-activity-2', 'gear-987');

      expect(fakeBuilder.lastUpdatePayload!['gear_id'], 'gear-987');
      expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
      expect(fakeBuilder.updateBuilder.lastEqValue, 'remote-activity-2');
    });

    test('clears activity gear assignment by writing null gear_id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        updateRows: const [
          <String, dynamic>{'id': 'remote-activity-3'},
        ],
      );
      when(() => mockClient.from('activities')).thenAnswer((_) => fakeBuilder);

      final repository = SupabaseActivityGearAssignmentRepository(mockClient);
      await repository.updateAssignedGearId('remote-activity-3', null);

      expect(fakeBuilder.lastUpdatePayload!.containsKey('gear_id'), isTrue);
      expect(fakeBuilder.lastUpdatePayload!['gear_id'], isNull);
      expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
      expect(fakeBuilder.updateBuilder.lastEqValue, 'remote-activity-3');
    });

    test('throws when updating gear for missing remote activity id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('activities')).thenAnswer((_) => fakeBuilder);

      final repository = SupabaseActivityGearAssignmentRepository(mockClient);

      await expectLater(
        () => repository.updateAssignedGearId('missing-remote-id', 'gear-222'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
