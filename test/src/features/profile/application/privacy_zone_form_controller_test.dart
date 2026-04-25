import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/application/privacy_zone_form_controller.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

import '../privacy_zone_test_support.dart';

/// ## Test Scenarios
/// - [positive] privacyZoneByIdProvider returns selected zone when ID exists
/// - [positive] privacyZoneByIdProvider returns null when ID does not exist
/// - [positive] createZone toggles loading, creates zone, and invalidates list provider
/// - [positive] updateZone updates repository and invalidates list provider
/// - [positive] deleteZone deletes record and invalidates list provider
/// - [error] Repository failures surface error messages and return failure values
void main() {
  group('privacyZoneByIdProvider', () {
    test(
      'returns selected zone when id exists in privacyZonesProvider data',
      () async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final selectedZone = await container.read(
          privacyZoneByIdProvider('zone-1').future,
        );

        expect(selectedZone!.label, 'Home');
      },
    );

    test(
      'returns null when id does not exist in privacyZonesProvider data',
      () async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final selectedZone = await container.read(
          privacyZoneByIdProvider('zone-missing').future,
        );

        expect(selectedZone, isNull);
      },
    );
  });

  group('privacyZoneFormControllerProvider', () {
    test(
      'createZone toggles loading, creates zone, and invalidates list provider',
      () async {
        final createCompleter = Completer<PrivacyZone>();
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
          createCompleter: createCompleter,
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final listSubscription = container.listen(
          privacyZonesProvider,
          (_, __) {},
        );
        addTearDown(listSubscription.close);
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 1);

        final actionFuture = container
            .read(privacyZoneFormControllerProvider.notifier)
            .createZone(
              const ValidatedPrivacyZoneFormInput(
                label: 'Gym',
                latitude: 40.72,
                longitude: -74.02,
                radiusMeters: 300,
              ),
            );

        expect(
          container.read(privacyZoneFormControllerProvider).activeOperation,
          PrivacyZoneFormOperation.creating,
        );

        createCompleter.complete(
          const PrivacyZone(
            id: 'zone-2',
            userId: 'user-1',
            label: 'Gym',
            latitude: 40.72,
            longitude: -74.02,
            radiusMeters: 300,
          ),
        );
        final createdZone = await actionFuture;

        expect(createdZone?.id, 'zone-2');
        expect(repository.createZoneCallCount, 1);
        expect(repository.lastCreateZoneCall?.label, 'Gym');
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 2);
        expect(
          container.read(privacyZoneFormControllerProvider).activeOperation,
          PrivacyZoneFormOperation.idle,
        );
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          isNull,
        );
      },
    );

    test(
      'updateZone updates repository and invalidates list provider',
      () async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final listSubscription = container.listen(
          privacyZonesProvider,
          (_, __) {},
        );
        addTearDown(listSubscription.close);
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 1);

        final didUpdate = await container
            .read(privacyZoneFormControllerProvider.notifier)
            .updateZone(
              existingZone: const PrivacyZone(
                id: 'zone-1',
                userId: 'user-1',
                label: 'Home',
                latitude: 40.71,
                longitude: -74.01,
                radiusMeters: 200,
              ),
              input: const ValidatedPrivacyZoneFormInput(
                label: 'Updated Home',
                latitude: 40.73,
                longitude: -74.03,
                radiusMeters: 275,
              ),
            );

        expect(didUpdate, isTrue);
        expect(repository.updateZoneCallCount, 1);
        expect(repository.lastUpdatedZone?.id, 'zone-1');
        expect(repository.lastUpdatedZone?.label, 'Updated Home');
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 2);
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          isNull,
        );
      },
    );

    test(
      'deleteZone deletes repository record and invalidates list provider',
      () async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final listSubscription = container.listen(
          privacyZonesProvider,
          (_, __) {},
        );
        addTearDown(listSubscription.close);
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 1);

        final didDelete = await container
            .read(privacyZoneFormControllerProvider.notifier)
            .deleteZone('zone-1');

        expect(didDelete, isTrue);
        expect(repository.deleteZoneCallCount, 1);
        expect(repository.lastDeletedZoneId, 'zone-1');
        await container.read(privacyZonesProvider.future);
        expect(repository.loadZonesCallCount, 2);
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          isNull,
        );
      },
    );

    test(
      'repository failures are surfaced in state and actions return failure',
      () async {
        final repository = FakePrivacyZoneRepository(
          createError: Exception('create failed'),
          updateError: Exception('update failed'),
          deleteError: Exception('delete failed'),
        );
        final container = ProviderContainer(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final didCreate = await container
            .read(privacyZoneFormControllerProvider.notifier)
            .createZone(
              const ValidatedPrivacyZoneFormInput(
                label: 'Gym',
                latitude: 40.72,
                longitude: -74.02,
                radiusMeters: 300,
              ),
            );

        expect(didCreate, isNull);
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          'Failed to create privacy zone. Please try again.',
        );

        final didUpdate = await container
            .read(privacyZoneFormControllerProvider.notifier)
            .updateZone(
              existingZone: const PrivacyZone(
                id: 'zone-1',
                userId: 'user-1',
                label: 'Home',
                latitude: 40.71,
                longitude: -74.01,
                radiusMeters: 200,
              ),
              input: const ValidatedPrivacyZoneFormInput(
                label: 'Updated Home',
                latitude: 40.73,
                longitude: -74.03,
                radiusMeters: 275,
              ),
            );

        expect(didUpdate, isFalse);
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          'Failed to update privacy zone. Please try again.',
        );

        final didDelete = await container
            .read(privacyZoneFormControllerProvider.notifier)
            .deleteZone('zone-1');

        expect(didDelete, isFalse);
        expect(
          container.read(privacyZoneFormControllerProvider).errorMessage,
          'Failed to delete privacy zone. Please try again.',
        );
        expect(
          container.read(privacyZoneFormControllerProvider).activeOperation,
          PrivacyZoneFormOperation.idle,
        );
      },
    );
  });
}
