part of 'fixtures.dart';

// ---------------------------------------------------------------------------
// Recording and activity-detail value readers
// ---------------------------------------------------------------------------

// Polling and scroll constants used by recording/detail reader helpers.
const _zeroDistanceLabel = 'Distance: 0.00 km';
const _distancePollInterval = Duration(milliseconds: 250);
const _maxDistancePollAttempts = 40;
// Detail pages grew taller after analytics and photo sections were added, so
// smaller emulator viewports need a few more drag cycles to reach the splits
// table reliably.
const _maxDetailScrollAttempts = 16;
const _detailScrollDelta = Offset(0, -360);
const _detailScrollSettleDuration = Duration(milliseconds: 250);
const _maxProfileScrollAttempts = 8;
const _profileScrollDelta = Offset(0, -320);
const _profileScrollSettleDuration = Duration(milliseconds: 250);
const emptyHistoryMessage = 'No saved activities yet.';

/// Waits until the recording header distance reaches a minimum threshold.
///
/// This helper intentionally uses `tester.pump` and `tester.widget`, which are
/// forbidden in smoke/full test files and therefore centralized in fixtures.
Future<void> waitForNonZeroDistance(
  PatrolIntegrationTester $, {
  double minimumDistanceKilometers = 0.01,
  int maxPollAttempts = _maxDistancePollAttempts,
}) async {
  if (minimumDistanceKilometers <= 0) {
    throw ArgumentError.value(
      minimumDistanceKilometers,
      'minimumDistanceKilometers',
      'must be greater than zero',
    );
  }
  if (maxPollAttempts <= 0) {
    throw ArgumentError.value(
      maxPollAttempts,
      'maxPollAttempts',
      'must be greater than zero',
    );
  }

  final distanceFinder = find.byKey(RecordingScreen.distanceTextKey);
  await $(distanceFinder).waitUntilVisible();

  for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
    final distanceText = $.tester.widget<Text>(distanceFinder);
    final label = distanceText.data;
    final distanceKilometers = _parseDistanceKilometers(label);

    if (distanceKilometers != null &&
        distanceKilometers >= minimumDistanceKilometers) {
      return;
    }
    if (distanceKilometers == null &&
        minimumDistanceKilometers <= 0.01 &&
        label != _zeroDistanceLabel) {
      return;
    }

    await $.tester.pump(_distancePollInterval);
  }

  throw StateError(
    'Timed out waiting for distance >= ${minimumDistanceKilometers.toStringAsFixed(2)} km after '
    '${maxPollAttempts * _distancePollInterval.inMilliseconds}ms.',
  );
}

double? _parseDistanceKilometers(String? label) {
  if (label == null) {
    return null;
  }

  final match = RegExp(
    r'^Distance:\s*([0-9]+(?:\.[0-9]+)?)\s*km$',
  ).firstMatch(label.trim());
  if (match == null) {
    return null;
  }

  return double.tryParse(match.group(1)!);
}

/// Reads and parses the recording-screen distance label (for example
/// `Distance: 0.42 km`).
Future<double> readRecordingDistanceKilometers(
  PatrolIntegrationTester $,
) async {
  final label = await _readTextByKey(
    $,
    RecordingScreen.distanceTextKey,
    description: 'recording distance value',
  );
  final parsedValue = _parseDistanceKilometers(label);
  if (parsedValue == null) {
    throw StateError('Unable to parse recording distance from "$label".');
  }

  return parsedValue;
}

/// Reads and parses the recording-screen elapsed label (for example
/// `Elapsed: 00:03:15`).
Future<Duration> readRecordingElapsedDuration(
  PatrolIntegrationTester $,
) async {
  final label = await _readTextByKey(
    $,
    RecordingScreen.elapsedTextKey,
    description: 'recording elapsed value',
  );
  final match = RegExp(
    r'^Elapsed:\s*([0-9]{2}):([0-9]{2}):([0-9]{2})$',
  ).firstMatch(label);
  if (match == null) {
    throw StateError(
      'Unable to parse recording elapsed duration from "$label".',
    );
  }

  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

/// Polls until recording distance increases by at least [minimumDeltaKilometers]
/// over [baselineKilometers].
Future<void> waitForRecordingDistanceIncrease(
  PatrolIntegrationTester $, {
  required double baselineKilometers,
  double minimumDeltaKilometers = 0.01,
  int maxPollAttempts = 120,
}) async {
  for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
    final distanceKilometers = await readRecordingDistanceKilometers($);
    if (distanceKilometers >= baselineKilometers + minimumDeltaKilometers) {
      return;
    }

    await $.tester.pump(_distancePollInterval);
  }

  throw StateError(
    'Timed out waiting for recording distance to increase by at least '
    '${minimumDeltaKilometers.toStringAsFixed(2)} km.',
  );
}

// ---------------------------------------------------------------------------
// Activity detail screen readers
// ---------------------------------------------------------------------------

/// Reads and parses the detail-screen distance summary (for example `5.24 km`).
Future<double> readActivityDetailDistanceKilometers(
  PatrolIntegrationTester $,
) async {
  final label = await _readTextByKey(
    $,
    ActivityDetailScreen.distanceValueTextKey,
    description: 'activity detail distance value',
  );
  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)\s*km$',
  ).firstMatch(label);
  final parsedValue = match == null ? null : double.tryParse(match.group(1)!);
  if (parsedValue == null) {
    throw StateError('Unable to parse distance kilometers from "$label".');
  }

  return parsedValue;
}

/// Reads and parses the detail-screen average pace summary (for example
/// `09:48 /km`) and returns whole seconds per kilometer.
Future<int> readActivityDetailAveragePaceSecondsPerKm(
  PatrolIntegrationTester $,
) async {
  final label = await _readTextByKey(
    $,
    ActivityDetailScreen.paceValueTextKey,
    description: 'activity detail average pace value',
  );
  final match = RegExp(r'^([0-9]{2}):([0-9]{2})\s*/km$').firstMatch(label);
  if (match == null) {
    throw StateError('Unable to parse average pace from "$label".');
  }

  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  return minutes * 60 + seconds;
}

/// Reads and parses the detail-screen duration summary (for example
/// `00:25:00`).
Future<Duration> readActivityDetailDuration(
  PatrolIntegrationTester $,
) async {
  final label = await _readTextByKey(
    $,
    ActivityDetailScreen.durationValueTextKey,
    description: 'activity detail duration value',
  );
  final match = RegExp(
    r'^([0-9]{2}):([0-9]{2}):([0-9]{2})$',
  ).firstMatch(label);
  if (match == null) {
    throw StateError('Unable to parse activity duration from "$label".');
  }

  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

/// Returns the visible split-row count in the detail split table.
Future<int> readActivityDetailSplitRowCount(PatrolIntegrationTester $) async {
  final splitsTableFinder = find.byKey(ActivityDetailScreen.splitsTableKey);
  await $(splitsTableFinder).waitUntilExists();
  final splitsTable = $.tester.widget<DataTable>(splitsTableFinder);
  return splitsTable.rows.length;
}

/// Reads the activity-detail analytics stress score (rTSS/cTSS/TSS) value.
Future<double> readActivityDetailTssValue(PatrolIntegrationTester $) async {
  // The saved detail screen renders analytics below the fold on compact
  // simulators. Reveal the section first so the exact label finder below is
  // measuring the real analytics contract, not a viewport accident.
  await revealActivityDetailAnalyticsSection($);

  final labelFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^(?:rTSS|cTSS|TSS)$').hasMatch(widget.data!),
    description: 'activity analytics TSS label',
  );
  // Once the card is revealed, wait for the exact label because the analytics
  // providers may still be settling for a brief moment after save completes.
  await $(labelFinder).waitUntilExists();

  final tileRowFinder = find.ancestor(
    of: labelFinder.first,
    matching: find.byType(Row),
  );
  final tileTextFinder = find.descendant(
    of: tileRowFinder.first,
    matching: find.byType(Text),
  );
  final parsedValues = tileTextFinder
      .evaluate()
      .map((element) => _textWidgetLabel(element.widget))
      .map(_extractFirstDecimalNumber)
      .whereType<double>()
      .toList(growable: false);

  if (parsedValues.isEmpty) {
    throw StateError('Unable to parse TSS metric value from analytics tile.');
  }

  return parsedValues.last;
}

/// Reads a Training Load card row (`Fitness`, `Fatigue`, or `Form`) and
/// returns the numeric value shown beside the label.
Future<double> readTrainingLoadMetricValue(
  PatrolIntegrationTester $, {
  required String label,
}) async {
  // Read the exact tile value by its dedicated key instead of scraping the
  // whole row. The row contains three sibling tiles, so row-level parsing can
  // accidentally return the Fitness value when the caller asked for Fatigue or
  // Form.
  final valueLabel = await _readTextByKey(
    $,
    _trainingLoadMetricValueKey(label),
    description: '$label training-load metric value',
  );
  final parsedValue = _extractFirstDecimalNumber(valueLabel);
  if (parsedValue == null) {
    throw StateError('Unable to parse "$label" training-load metric value.');
  }

  return parsedValue;
}

bool hasAnyVisibleText(PatrolIntegrationTester $, List<String> labels) {
  for (final label in labels) {
    if (find.textContaining(label).evaluate().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<String> _readTextByKey(
  PatrolIntegrationTester $,
  Key key, {
  required String description,
}) async {
  final finder = find.byKey(key);
  await $(finder).waitUntilVisible();
  final textWidget = $.tester.widget<Widget>(finder);
  final label = _textWidgetLabel(textWidget);
  if (label.trim().isEmpty) {
    throw StateError('Expected non-empty text for $description.');
  }

  return label.trim();
}

String _textWidgetLabel(Widget widget) {
  if (widget is CopyableErrorText) {
    return widget.message;
  }

  if (widget is! Text) {
    throw StateError(
      'Expected a Text or CopyableErrorText widget, received ${widget.runtimeType}.',
    );
  }

  final data = widget.data;
  if (data != null) {
    return data;
  }

  return widget.textSpan?.toPlainText() ?? '';
}

double? _extractFirstDecimalNumber(String text) {
  final match = RegExp(r'[-+]?[0-9]+(?:\.[0-9]+)?').firstMatch(text);
  if (match == null) {
    return null;
  }

  return double.tryParse(match.group(0)!);
}

Key _trainingLoadMetricValueKey(String label) {
  switch (label) {
    case 'Fitness':
      return TrainingLoadCard.fitnessValueTextKey;
    case 'Fatigue':
      return TrainingLoadCard.fatigueValueTextKey;
    case 'Form':
      return TrainingLoadCard.formValueTextKey;
  }

  throw StateError('Unsupported training-load metric label "$label".');
}

// ---------------------------------------------------------------------------
// Scroll-to-reveal helpers
// ---------------------------------------------------------------------------

/// Scrolls activity detail until split content is visible.
///
/// The split card is below the fold on smaller emulator viewports, so tests
/// should call this before asserting on split table/message content.
Future<void> revealActivityDetailSplitsSection(
  PatrolIntegrationTester $,
) async {
  final splitsTableFinder = find.byKey(ActivityDetailScreen.splitsTableKey);
  final noSplitsMessageFinder = find.text(
    'Not enough distance to compute splits.',
  );
  final detailListScrollableFinder = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; attempt < _maxDetailScrollAttempts; attempt++) {
    final hasSplitContent =
        splitsTableFinder.evaluate().isNotEmpty ||
        noSplitsMessageFinder.evaluate().isNotEmpty;
    if (hasSplitContent) {
      return;
    }

    await $.tester.drag(detailListScrollableFinder, _detailScrollDelta);
    await $.tester.pump(_detailScrollSettleDuration);
  }

  throw StateError(
    'Unable to reveal activity detail split content after '
    '$_maxDetailScrollAttempts scroll attempts.',
  );
}

/// Scrolls activity detail until the analytics card is visible.
///
/// The saved detail screen can open above the analytics section on compact
/// emulators even after the run is finalized, so E2E readers must reveal the
/// card before making exact assertions against its labels or values.
Future<void> revealActivityDetailAnalyticsSection(
  PatrolIntegrationTester $,
) async {
  final analyticsCardFinder = find.byKey(ActivityAnalyticsSection.cardKey);
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'activity detail analytics section',
    candidateFinders: [analyticsCardFinder],
    maxAttempts: _maxDetailScrollAttempts,
    delta: _detailScrollDelta,
    settleDuration: _detailScrollSettleDuration,
  );
}

/// Scrolls activity detail until the editable metadata section is visible.
Future<void> revealActivityDetailMetadataSection(
  PatrolIntegrationTester $,
) async {
  final overflowMenuFinder = find.byKey(
    ActivityDetailScreen.overflowMenuButtonKey,
  );
  final editButtonFinder = find.byKey(ActivityDetailScreen.editButtonKey);

  await $(overflowMenuFinder).waitUntilVisible();
  await $(overflowMenuFinder).tap();
  await $(editButtonFinder).waitUntilVisible();
  await $(editButtonFinder).tap();

  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'activity detail metadata section',
    candidateFinders: [
      find.byKey(ActivityDetailScreen.visibilitySegmentedButtonKey),
      find.byKey(ActivityDetailScreen.saveButtonKey),
    ],
    maxAttempts: _maxDetailScrollAttempts,
    delta: _detailScrollDelta,
    settleDuration: _detailScrollSettleDuration,
  );
}

/// Scrolls activity detail until the destructive delete control is visible.
Future<void> revealActivityDetailDeleteButton(PatrolIntegrationTester $) async {
  final overflowMenuFinder = find.byKey(
    ActivityDetailScreen.overflowMenuButtonKey,
  );
  final deleteButtonFinder = find.byKey(ActivityDetailScreen.deleteButtonKey);

  await $(overflowMenuFinder).waitUntilVisible();
  await $(overflowMenuFinder).tap();
  await $(deleteButtonFinder).waitUntilVisible();
}

/// Scrolls activity detail edit actions until the save button is visible.
Future<void> revealActivityDetailSaveButton(PatrolIntegrationTester $) async {
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'activity detail save button',
    candidateFinders: [find.byKey(ActivityDetailScreen.saveButtonKey)],
    maxAttempts: _maxDetailScrollAttempts,
    delta: _detailScrollDelta,
    settleDuration: _detailScrollSettleDuration,
  );
}

/// Waits for activity detail to return to read-only metadata mode after save.
Future<void> waitForActivityDetailSaveCompletion(
  PatrolIntegrationTester $,
) async {
  final visibilityBadgeFinder = find.byKey(
    ActivityDetailScreen.visibilityBadgeKey,
  );
  final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
  final saveFailureFinder = find.text(
    'Unable to save activity details. Please try again.',
  );

  for (var attempt = 0; attempt < 180; attempt++) {
    final didRenderReadOnlyMetadata =
        visibilityBadgeFinder.evaluate().isNotEmpty ||
        saveButtonFinder.evaluate().isEmpty;
    if (didRenderReadOnlyMetadata) {
      return;
    }

    if (saveFailureFinder.evaluate().isNotEmpty) {
      throw StateError(
        'Activity detail save surfaced the failure snackbar instead of '
        'returning to read-only mode.',
      );
    }

    await $.tester.pump(const Duration(milliseconds: 250));
  }

  throw StateError(
    'Activity detail save did not return to read-only mode within 45 seconds.',
  );
}

/// Scrolls profile content until quick links are visible.
///
/// The Profile tab can exceed small emulator viewports. Some tests need the
/// Privacy Zones quick link and should call this helper before tapping it.
Future<void> revealProfileSignOutButton(PatrolIntegrationTester $) async {
  final privacyZonesFinder = find.byKey(ProfileScreen.privacyZonesButtonKey);
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'profile quick links',
    candidateFinders: [privacyZonesFinder],
    maxAttempts: _maxProfileScrollAttempts,
    delta: _profileScrollDelta,
    settleDuration: _profileScrollSettleDuration,
  );
}

/// Opens Settings from the home shell and reveals the sign-out action.
Future<void> openSettingsAndRevealSignOutButton(
  PatrolIntegrationTester $,
) async {
  final openSettingsFinder = find.byKey(HomeShellScreen.openSettingsButtonKey);
  await $(openSettingsFinder).waitUntilVisible();
  await $(openSettingsFinder).tap();
  await revealSettingsSignOutButton($);
}

/// Scrolls settings content until the sign-out button is visible.
Future<void> revealSettingsSignOutButton(PatrolIntegrationTester $) async {
  final signOutFinder = find.byKey(SettingsScreen.signOutButtonKey);
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'settings sign-out button',
    candidateFinders: [signOutFinder],
    maxAttempts: _maxProfileScrollAttempts,
    delta: _profileScrollDelta,
    settleDuration: _profileScrollSettleDuration,
  );
}

/// Scrolls the draft review surface until the Save CTA is visible.
///
/// The review flow intentionally keeps title/notes/visibility and the final
/// Save action on the same long surface. Replay-based Patrol tests should use
/// this helper instead of assuming the save button starts in the viewport.
Future<void> revealDraftSaveButton(PatrolIntegrationTester $) async {
  final draftSaveFinder = find.byKey(ActivityDetailScreen.draftSaveButtonKey);
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'draft review save button',
    candidateFinders: [draftSaveFinder],
    maxAttempts: _maxProfileScrollAttempts,
    delta: _profileScrollDelta,
    settleDuration: _profileScrollSettleDuration,
  );
}

Future<void> _scrollUntilAnyFinderHitTestable(
  PatrolIntegrationTester $, {
  required String description,
  required List<Finder> candidateFinders,
  required int maxAttempts,
  required Offset delta,
  required Duration settleDuration,
}) async {
  final scrollableFinder = find.byType(Scrollable).first;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final hasVisibleTarget = candidateFinders.any(
      (finder) => finder.hitTestable().evaluate().isNotEmpty,
    );
    if (hasVisibleTarget) {
      return;
    }

    await $.tester.drag(scrollableFinder, delta);
    await $.tester.pump(settleDuration);
  }

  throw StateError(
    'Unable to reveal $description after $maxAttempts scroll attempts.',
  );
}
