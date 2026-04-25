import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

import '../privacy_zone_test_support.dart';

/// ## Test Scenarios
/// - [positive] privacyZonesProvider loads zones from the repository provider
void main() {
  group('privacyZonesProvider', () {
    test('loads zones from the repository provider', () async {
      final repository = FakePrivacyZoneRepository()
        ..zonesToReturn = const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 51.5074,
            longitude: -0.1278,
            radiusMeters: 200,
          ),
        ];

      final container = ProviderContainer(
        overrides: [
          privacyZoneRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(privacyZonesProvider, (_, __) {});
      addTearDown(subscription.close);

      final zones = await container.read(privacyZonesProvider.future);

      expect(zones, hasLength(1));
      expect(zones.single.label, 'Home');
      expect(repository.loadZonesCallCount, 1);
    });
  });
}
