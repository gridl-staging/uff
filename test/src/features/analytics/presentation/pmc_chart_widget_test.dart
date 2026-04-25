import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';

/// ## Test Scenarios
/// - `[positive]` Produces three line series for CTL, ATL, TSB with correct values
/// - `[positive]` Renders LineChart with legend when given data
/// - `[positive]` Touch callback maps spot index to correct PmcDay values
/// - `[positive]` Selected values panel shows exact date and metric values
/// - `[negative]` Touch callback emits null for out-of-range spot indexes
/// - `[negative]` Touch callback emits null for null response
/// - `[isolation]` Touch is disabled when no callback provided (default behavior)
/// - `[edge]` Renders empty-state message with no LineChart when list empty
/// - `[edge]` Bottom axis interval scales for large day counts
/// - `[edge]` Selected values panel clears when refreshed chart data omits the touched date

const _expectedPmcChartEmptyStateMessage =
    'Not enough data to display the chart.';

List<PmcDay> _threeDaySample() => [
  PmcDay(date: DateTime.utc(2025), ctl: 40, atl: 55, tsb: -15, tssOnDay: 80),
  PmcDay(
    date: DateTime.utc(2025, 1, 2),
    ctl: 42,
    atl: 50,
    tsb: -8,
    tssOnDay: 60,
  ),
  PmcDay(
    date: DateTime.utc(2025, 1, 3),
    ctl: 44,
    atl: 48,
    tsb: -4,
    tssOnDay: 50,
  ),
];

List<PmcDay> _sampleDays(int count) {
  return List.generate(
    count,
    (index) => PmcDay(
      date: DateTime.utc(2025, 1, index + 1),
      ctl: 40 + index.toDouble(),
      atl: 55 - index.toDouble(),
      tsb: -15 + index.toDouble(),
      tssOnDay: (80 - index).toDouble(),
    ),
  );
}

List<PmcDay> _updatedSampleWithoutJan2() => [
  PmcDay(date: DateTime.utc(2025), ctl: 41, atl: 54, tsb: -13, tssOnDay: 75),
  PmcDay(
    date: DateTime.utc(2025, 1, 3),
    ctl: 45,
    atl: 47,
    tsb: -2,
    tssOnDay: 48,
  ),
];

TitleMeta _titleMeta({
  required SideTitles sideTitles,
  required AxisSide axisSide,
  required double appliedInterval,
}) {
  return TitleMeta(
    min: 0,
    max: 100,
    parentAxisSize: 300,
    axisPosition: 0,
    appliedInterval: appliedInterval,
    sideTitles: sideTitles,
    formattedValue: '',
    axisSide: axisSide,
    rotationQuarterTurns: 0,
  );
}

void main() {
  group('buildPmcChartData (unit tests)', () {
    test('produces three line series for CTL, ATL, TSB', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      expect(data.lineBarsData.length, 3);
    });

    test('CTL series spots map list indices to ctl values', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final ctlSpots = data.lineBarsData[0].spots;

      expect(ctlSpots.length, 3);
      expect(ctlSpots[0], const FlSpot(0, 40));
      expect(ctlSpots[1], const FlSpot(1, 42));
      expect(ctlSpots[2], const FlSpot(2, 44));
    });

    test('ATL series spots map list indices to atl values', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final atlSpots = data.lineBarsData[1].spots;

      expect(atlSpots.length, 3);
      expect(atlSpots[0], const FlSpot(0, 55));
      expect(atlSpots[1], const FlSpot(1, 50));
      expect(atlSpots[2], const FlSpot(2, 48));
    });

    test('TSB series spots map list indices to tsb values', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final tsbSpots = data.lineBarsData[2].spots;

      expect(tsbSpots.length, 3);
      expect(tsbSpots[0], const FlSpot(0, -15));
      expect(tsbSpots[1], const FlSpot(1, -8));
      expect(tsbSpots[2], const FlSpot(2, -4));
    });

    test('includes a dashed horizontal zero-reference line', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      final horizontalLines = data.extraLinesData.horizontalLines;
      expect(horizontalLines.length, 1);
      expect(horizontalLines.first.y, 0);
      // zero-reference line uses [5, 5] dashed pattern per pmc_chart_widget.dart:63
      expect(horizontalLines.first.dashArray, [5, 5]);
    });

    test(
      'touch is enabled with handleBuiltInTouches false when callback provided',
      () {
        PmcDay? touched;
        final days = _threeDaySample();
        final data = buildPmcChartData(
          days,
          onTouchedDay: (day) {
            touched = day;
          },
        );

        expect(data.lineTouchData.enabled, isTrue);
        expect(data.lineTouchData.handleBuiltInTouches, isFalse);
        expect(touched, isNull);
      },
    );

    test('touch is disabled when no callback provided', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      expect(data.lineTouchData.enabled, isFalse);
    });

    test('touch callback maps spot index 1 to exact Jan 2 sample values', () {
      PmcDay? touched;
      final days = _threeDaySample();
      final data = buildPmcChartData(
        days,
        onTouchedDay: (day) {
          touched = day;
        },
      );

      final response = LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [
          TouchLineBarSpot(
            data.lineBarsData[0],
            0,
            data.lineBarsData[0].spots[1],
            0,
          ),
        ],
      );
      data.lineTouchData.touchCallback!(
        FlTapDownEvent(TapDownDetails(localPosition: Offset.zero)),
        response,
      );

      expect(touched!.date, DateTime.utc(2025, 1, 2));
      expect(touched!.ctl, 42);
      expect(touched!.atl, 50);
      expect(touched!.tsb, -8);
      expect(touched!.tssOnDay, 60);
    });

    test('touch callback emits null for out-of-range spot index', () {
      PmcDay? touched;
      var callCount = 0;
      final days = _threeDaySample();
      final data = buildPmcChartData(
        days,
        onTouchedDay: (day) {
          callCount++;
          touched = day;
        },
      );

      final spots = [for (var i = 0; i < 5; i++) FlSpot(i.toDouble(), 0)];
      final bar = LineChartBarData(spots: spots);
      final response = LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [TouchLineBarSpot(bar, 0, spots[4], 0)],
      );
      data.lineTouchData.touchCallback!(
        FlTapDownEvent(TapDownDetails(localPosition: Offset.zero)),
        response,
      );

      expect(callCount, 1);
      expect(touched, isNull);
    });

    test('touch callback emits null for null response', () {
      PmcDay? touched;
      var callCount = 0;
      final days = _threeDaySample();
      final data = buildPmcChartData(
        days,
        onTouchedDay: (day) {
          callCount++;
          touched = day;
        },
      );

      data.lineTouchData.touchCallback!(
        FlTapDownEvent(TapDownDetails(localPosition: Offset.zero)),
        null,
      );

      expect(callCount, 1);
      expect(touched, isNull);
    });

    test('touch callback ignores uninterested events', () {
      var callCount = 0;
      final days = _threeDaySample();
      final data = buildPmcChartData(
        days,
        onTouchedDay: (day) {
          callCount++;
        },
      );

      final response = LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [
          TouchLineBarSpot(
            data.lineBarsData[0],
            0,
            data.lineBarsData[0].spots[0],
            0,
          ),
        ],
      );
      data.lineTouchData.touchCallback!(
        FlPanEndEvent(DragEndDetails()),
        response,
      );

      expect(callCount, 0);
    });

    test('bottom axis uses expected title visibility and interval', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final bottomSideTitles = data.titlesData.bottomTitles.sideTitles;

      expect(bottomSideTitles.showTitles, isTrue);
      expect(bottomSideTitles.interval, 1);
      expect(data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
      // Top and right axes should be hidden.
      expect(data.titlesData.topTitles.sideTitles.showTitles, isFalse);
      expect(data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
    });

    test('bottom axis interval scales to roughly five labels', () {
      final data = buildPmcChartData(_sampleDays(12));
      final bottomSideTitles = data.titlesData.bottomTitles.sideTitles;

      expect(bottomSideTitles.interval, 3);
    });

    test('bottom axis title formatter uses MMM d and hides out-of-range', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final bottomSideTitles = data.titlesData.bottomTitles.sideTitles;
      final meta = _titleMeta(
        sideTitles: bottomSideTitles,
        axisSide: AxisSide.bottom,
        appliedInterval: bottomSideTitles.interval ?? 1,
      );
      final inRangeTitle = bottomSideTitles.getTitlesWidget(1, meta);
      final outOfRangeTitle = bottomSideTitles.getTitlesWidget(9, meta);

      // x=1 → Jan 2 label (index 1 in _threeDaySample starting Jan 1)
      expect(
        inRangeTitle,
        isA<SideTitleWidget>().having(
          (w) => (w.child as Text).data,
          'label text',
          'Jan 2',
        ),
      );
      // x=9 is out of range → SizedBox.shrink (hidden)
      expect(
        outOfRangeTitle,
        isA<SizedBox>()
            .having((w) => w.width, 'width', 0)
            .having((w) => w.height, 'height', 0),
      );
    });

    test('bottom axis formatter hides non-integer x values', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);
      final bottomSideTitles = data.titlesData.bottomTitles.sideTitles;
      final meta = _titleMeta(
        sideTitles: bottomSideTitles,
        axisSide: AxisSide.bottom,
        appliedInterval: bottomSideTitles.interval ?? 1,
      );
      final fractionalTitle = bottomSideTitles.getTitlesWidget(1.5, meta);

      // fractional x=1.5 → SizedBox.shrink (hidden)
      expect(
        fractionalTitle,
        isA<SizedBox>()
            .having((w) => w.width, 'width', 0)
            .having((w) => w.height, 'height', 0),
      );
    });

    test(
      'left axis formatter rounds positive values to the nearest integer',
      () {
        final days = _threeDaySample();
        final data = buildPmcChartData(days);
        final leftSideTitles = data.titlesData.leftTitles.sideTitles;
        final meta = _titleMeta(
          sideTitles: leftSideTitles,
          axisSide: AxisSide.left,
          appliedInterval: leftSideTitles.interval ?? 1,
        );
        final leftTitle = leftSideTitles.getTitlesWidget(42.7, meta);

        // 42.7 rounds to 43; fitInside keeps label within chart bounds
        expect(
          leftTitle,
          isA<SideTitleWidget>()
              .having((w) => w.fitInside.enabled, 'fitInside', isTrue)
              .having((w) => (w.child as Text).data, 'label text', '43'),
        );
      },
    );

    test(
      'left axis formatter rounds negative values instead of truncating',
      () {
        final days = _threeDaySample();
        final data = buildPmcChartData(days);
        final leftSideTitles = data.titlesData.leftTitles.sideTitles;
        final meta = _titleMeta(
          sideTitles: leftSideTitles,
          axisSide: AxisSide.left,
          appliedInterval: leftSideTitles.interval ?? 1,
        );
        final leftTitle = leftSideTitles.getTitlesWidget(-0.7, meta);

        // -0.7 rounds to -1 (not truncated to 0)
        expect(
          leftTitle,
          isA<SideTitleWidget>().having(
            (w) => (w.child as Text).data,
            'label text',
            '-1',
          ),
        );
      },
    );

    test('top and right axes remain hidden', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      expect(data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
      expect(data.titlesData.topTitles.sideTitles.showTitles, isFalse);
      expect(data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
    });

    test('series colors are blue (CTL), red (ATL), green (TSB)', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      expect(data.lineBarsData[0].color, Colors.blue);
      expect(data.lineBarsData[1].color, Colors.red);
      expect(data.lineBarsData[2].color, Colors.green);
    });

    test('dot markers are hidden on all series', () {
      final days = _threeDaySample();
      final data = buildPmcChartData(days);

      for (final series in data.lineBarsData) {
        expect(series.dotData.show, isFalse);
      }
    });
  });

  group('PmcChartWidget (widget tests)', () {
    testWidgets('renders LineChart with legend when given data', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [PmcChartWidget(pmcDays: _threeDaySample())],
            ),
          ),
        ),
      );

      expect(find.byKey(PmcChartWidget.cardKey), findsOneWidget);
      expect(find.byKey(PmcChartWidget.dataStateKey), findsOneWidget);
      expect(find.byKey(PmcChartWidget.emptyStateKey), findsNothing);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.text('Fatigue'), findsOneWidget);
      expect(find.text('Form'), findsOneWidget);
    });

    testWidgets('chart height is responsive and clamped between 200-350px', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [PmcChartWidget(pmcDays: _threeDaySample())],
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(LineChart),
          matching: find.byType(SizedBox),
        ),
      );
      // Chart height is derived from available width via LayoutBuilder
      // (width * 0.6, clamped 200-350). In test context the exact value
      // depends on the test window size, so just verify it's within bounds.
      expect(sizedBox.height, greaterThanOrEqualTo(200));
      expect(sizedBox.height, lessThanOrEqualTo(350));
    });

    testWidgets(
      'renders empty-state message with no LineChart when list empty',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PmcChartWidget(pmcDays: [])),
          ),
        );

        expect(find.byKey(PmcChartWidget.cardKey), findsOneWidget);
        expect(find.byKey(PmcChartWidget.emptyStateKey), findsOneWidget);
        expect(find.byKey(PmcChartWidget.dataStateKey), findsNothing);
        expect(find.text(_expectedPmcChartEmptyStateMessage), findsOneWidget);
        expect(find.byType(LineChart), findsNothing);
      },
    );

    testWidgets('renders Performance title when given data', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [PmcChartWidget(pmcDays: _threeDaySample())],
            ),
          ),
        ),
      );

      expect(find.text('Performance'), findsOneWidget);
    });

    testWidgets(
      'selected-values panel is absent before any touch interaction',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [PmcChartWidget(pmcDays: _threeDaySample())],
              ),
            ),
          ),
        );

        expect(find.byKey(PmcChartWidget.dataStateKey), findsOneWidget);
        expect(find.byKey(PmcChartWidget.selectedValuesPanelKey), findsNothing);
      },
    );

    testWidgets(
      'tap interaction shows selected-values panel with Jan 2 sample metrics',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [PmcChartWidget(pmcDays: _threeDaySample())],
              ),
            ),
          ),
        );

        final chartRect = tester.getRect(find.byType(LineChart));
        final chartDragStart = Offset(
          chartRect.left + (chartRect.width * 0.45),
          chartRect.top + (chartRect.height * 0.22),
        );
        await tester.dragFrom(chartDragStart, Offset(chartRect.width * 0.1, 0));
        await tester.pumpAndSettle();

        final selectedPanel = find.byKey(PmcChartWidget.selectedValuesPanelKey);
        expect(selectedPanel, findsOneWidget);
        expect(
          find.descendant(
            of: selectedPanel,
            matching: find.text('Jan 2, 2025'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('Fitness: ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('Fatigue: ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('Form: ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('TSS: ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('42')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('50')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('-8')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectedPanel, matching: find.text('60')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'selected-values panel clears when refreshed data removes the touched date',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [PmcChartWidget(pmcDays: _threeDaySample())],
              ),
            ),
          ),
        );

        final chartRect = tester.getRect(find.byType(LineChart));
        final chartDragStart = Offset(
          chartRect.left + (chartRect.width * 0.45),
          chartRect.top + (chartRect.height * 0.22),
        );
        await tester.dragFrom(chartDragStart, Offset(chartRect.width * 0.1, 0));
        await tester.pumpAndSettle();

        expect(
          find.byKey(PmcChartWidget.selectedValuesPanelKey),
          findsOneWidget,
        );
        expect(find.text('Jan 2, 2025'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  PmcChartWidget(pmcDays: _updatedSampleWithoutJan2()),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(PmcChartWidget.selectedValuesPanelKey), findsNothing);
        expect(find.text('Jan 2, 2025'), findsNothing);
      },
    );
  });
}
