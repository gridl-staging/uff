<!-- [scrai:start] -->
## features

| File | Summary |
| --- | --- |

| Directory | Summary |
| --- | --- |
| activity_tracking | This activity_tracking directory provides comprehensive test support utilities across all layers—application, data, and presentation—including fake/mock implementations of core services (TrackingEngine, TrackingRepository, SyncService) and helper fixtures for testing the activity tracking feature. |
| analytics | The analytics feature provides comprehensive workout and fitness analysis including domain calculators for heart rate zones, training stress, power curves, VDOT, PMC, race prediction, and interval detection, with application-layer providers managing state and presentation components for displaying analytics on the UI. |
| auth | This auth directory contains test utilities and doubles for authentication UI testing, including multiple mock AuthRepository implementations with controllable behaviors (delayed responses, errors, confirmation states) and a Riverpod provider override widget for isolated testing. |
| clubs | The clubs directory contains test utilities and factory functions for ClubDetailScreen, providing builder functions for various test configurations and data factories for clubs, members, runs, and authentication state. |
| import | The import directory provides test utilities and support infrastructure for the import pipeline's analytics functionality, including a harness class for setting up isolated test environments with deterministic inputs. |
| notifications | The notifications directory contains test doubles for the notifications feature, including a fake implementation of the notification token service that allows testing without hitting real backend services. |
| onboarding | The onboarding directory contains presentation-layer code for the onboarding flow, including test helper utilities for onboarding screen tests. |
| profile | The profile directory contains presentation layer code for the profile feature, with test support utilities for profile screen testing. |
| settings | The settings directory contains test support utilities for the settings screen, including mock notifiers for profile, theme, and telemetry configuration, along with scope builders that set up providers and routing for different test scenarios. |
| social | — |
<!-- [scrai:end] -->
