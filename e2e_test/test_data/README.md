# Test Fixture Data

GPS route fixtures for replay-based testing. Used by both unit tests
(`test/`) and e2e tests (`e2e_test/`).

## JSON Schema

Each fixture is a JSON array of point objects. Fields:

| Field          | Type     | Required | Description                        |
|----------------|----------|----------|------------------------------------|
| `sessionId`    | `int`    | yes      | Placeholder (overridden at load)   |
| `timestamp`    | `string` | yes      | ISO 8601 UTC                       |
| `latitude`     | `double` | yes      | Decimal degrees [-90, 90]          |
| `longitude`    | `double` | yes      | Decimal degrees [-180, 180]        |
| `elevation`    | `double` | no       | Meters above sea level             |
| `accuracy`     | `double` | no       | GPS accuracy in meters             |
| `speed`        | `double` | no       | Speed in m/s                       |
| `heartRateBpm` | `int`    | no       | Heart rate (beats per minute)      |
| `cadenceRpm`   | `double` | no       | Cadence (revolutions per minute)   |
| `powerWatts`   | `int`    | no       | Power output in watts              |

Sensor fields (`heartRateBpm`, `cadenceRpm`, `powerWatts`) are optional.
When absent, the parser defaults them to `null`.

## Fixture Files

- `5k_run.json` — Hand-crafted 5K run (620 points, no sensor data).
- `generated/interval_workout.json` — Interval workout with alternating
  hard/easy segments and HR data.
- `generated/hilly_10k.json` — Hilly 10K with 4 climbs, 320m elevation gain.
- `generated/auto_pause_test.json` — Run with 2 stationary pause windows.
- `generated/long_easy_run.json` — 60-minute easy run with HR, cadence, power.

## Expected Metrics Manifest

`expected_metrics.json` contains fixture-intrinsic expectations (point count,
distance, elapsed/moving time, elevation gain, interval/pause counts, pace).
Calculator-specific assertions (TSS, PMC) are deferred to later test stages.

## Generator

Regenerate all fixtures:

```bash
dart run test/fixtures/generate_fixtures.dart
```

This overwrites `generated/*.json` and `expected_metrics.json`.

## Loader

Unit tests use `parseFixturePointsFromJson()` from
`test/src/test_helpers/fixture_point_parser.dart`.

E2e tests use `loadFixturePoints()` from `e2e_test/fixtures.dart`,
which delegates to the same parser.
