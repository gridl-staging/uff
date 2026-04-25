import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';

const _pmcChartEmptyStateMessage = 'Not enough data to display the chart.';

const _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// NOTE(stuart): Document _PmcMetric.
enum _PmcMetric {
  fitness(label: 'Fitness', color: Colors.blue),
  fatigue(label: 'Fatigue', color: Colors.red),
  form(label: 'Form', color: Colors.green);

  const _PmcMetric({required this.label, required this.color});

  final String label;
  final Color color;

  double valueFor(PmcDay day) => switch (this) {
    _PmcMetric.fitness => day.ctl,
    _PmcMetric.fatigue => day.atl,
    _PmcMetric.form => day.tsb,
  };
}

/// Builds the [LineChartData] for a PMC chart from a list of [PmcDay]s.
///
/// Exposed for unit testing so callers can assert on series structure,
/// spot coordinates, axis configuration, and reference lines without
/// pumping a widget.
@visibleForTesting
LineChartData buildPmcChartData(
  List<PmcDay> days, {
  ValueChanged<PmcDay?>? onTouchedDay,
}) {
  final labelInterval = days.length > 1
      ? (days.length / 5).ceilToDouble().clamp(1.0, double.maxFinite)
      : 1.0;

  return LineChartData(
    lineBarsData: [
      for (final metric in _PmcMetric.values)
        _buildSeries(_buildSpots(days, metric), metric.color),
    ],
    extraLinesData: ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: 0,
          color: Colors.grey,
          strokeWidth: 1,
          dashArray: [5, 5],
        ),
      ],
    ),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: labelInterval,
          reservedSize: 30,
          getTitlesWidget: (value, meta) =>
              _bottomTitleWidget(value, meta, days),
        ),
      ),
      leftTitles: const AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: _leftTitleWidget,
        ),
      ),
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
    ),
    lineTouchData: onTouchedDay == null
        ? const LineTouchData(enabled: false)
        : LineTouchData(
            handleBuiltInTouches: false,
            touchSpotThreshold: 80,
            touchCallback: (event, response) {
              if (!event.isInterestedForInteractions) return;
              final spots = response?.lineBarSpots;
              if (spots == null || spots.isEmpty) {
                onTouchedDay(null);
                return;
              }
              final spotIndex = spots.first.spotIndex;
              if (spotIndex < 0 || spotIndex >= days.length) {
                onTouchedDay(null);
                return;
              }
              onTouchedDay(days[spotIndex]);
            },
          ),
    borderData: FlBorderData(show: false),
  );
}

List<FlSpot> _buildSpots(List<PmcDay> days, _PmcMetric metric) {
  return [
    for (var i = 0; i < days.length; i++)
      FlSpot(i.toDouble(), metric.valueFor(days[i])),
  ];
}

LineChartBarData _buildSeries(List<FlSpot> spots, Color color) {
  return LineChartBarData(
    spots: spots,
    color: color,
    isCurved: true,
    dotData: const FlDotData(show: false),
  );
}

Widget _bottomTitleWidget(double value, TitleMeta meta, List<PmcDay> days) {
  final index = _titleIndex(value, days.length);
  if (index < 0 || index >= days.length) {
    return const SizedBox.shrink();
  }

  final date = days[index].date;
  final label = '${_monthAbbreviations[date.month - 1]} ${date.day}';
  return SideTitleWidget(
    meta: meta,
    space: 4,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );
}

Widget _leftTitleWidget(double value, TitleMeta meta) {
  return SideTitleWidget(
    meta: meta,
    space: 4,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
    child: Text(_formatYAxisLabel(value), style: const TextStyle(fontSize: 10)),
  );
}

String _formatYAxisLabel(double value) {
  final roundedValue = value.round();
  if (roundedValue == 0) {
    return '0';
  }

  return roundedValue.toString();
}

int _titleIndex(double value, int dayCount) {
  final roundedValue = value.round();
  if ((value - roundedValue).abs() > 0.001) {
    return -1;
  }

  if (roundedValue < 0 || roundedValue >= dayCount) {
    return -1;
  }

  return roundedValue;
}

/// TODO: Document PmcChartWidget.
class PmcChartWidget extends StatefulWidget {
  const PmcChartWidget({required this.pmcDays, super.key});

  static const cardKey = Key('pmc_chart_card');
  static const emptyStateKey = Key('pmc_chart_card_empty_state');
  static const dataStateKey = Key('pmc_chart_card_data_state');
  static const selectedValuesPanelKey = Key('pmc_chart_selected_values_panel');

  final List<PmcDay> pmcDays;

  @override
  State<PmcChartWidget> createState() => _PmcChartWidgetState();
}

/// TODO: Document _PmcChartWidgetState.
class _PmcChartWidgetState extends State<PmcChartWidget> {
  PmcDay? _selectedDay;

  @override
  void didUpdateWidget(covariant PmcChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedDay == null) {
      return;
    }

    _selectedDay = _findDayForDate(widget.pmcDays, _selectedDay!.date);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pmcDays.isEmpty) {
      return Card(
        key: PmcChartWidget.cardKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: PmcChartWidget.emptyStateKey,
            children: [
              Icon(
                Icons.timeline,
                size: 40,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                _pmcChartEmptyStateMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      key: PmcChartWidget.cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: PmcChartWidget.dataStateKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _Legend(),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = (constraints.maxWidth * 0.6).clamp(
                  200.0,
                  350.0,
                );
                return SizedBox(
                  height: chartHeight,
                  child: LineChart(
                    buildPmcChartData(
                      widget.pmcDays,
                      onTouchedDay: (day) => setState(() => _selectedDay = day),
                    ),
                  ),
                );
              },
            ),
            if (_selectedDay != null) _SelectedValuesPanel(day: _selectedDay!),
          ],
        ),
      ),
    );
  }
}

PmcDay? _findDayForDate(List<PmcDay> days, DateTime date) {
  for (final day in days) {
    if (day.date.isAtSameMomentAs(date)) {
      return day;
    }
  }

  return null;
}

/// TODO: Document _SelectedValuesPanel.
class _SelectedValuesPanel extends StatelessWidget {
  const _SelectedValuesPanel({required this.day});

  final PmcDay day;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_monthAbbreviations[day.date.month - 1]} ${day.date.day}, '
        '${day.date.year}';

    return Padding(
      key: PmcChartWidget.selectedValuesPanelKey,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _MetricValue(
                label: 'Fitness',
                value: day.ctl.round().toString(),
                color: Colors.blue,
              ),
              _MetricValue(
                label: 'Fatigue',
                value: day.atl.round().toString(),
                color: Colors.red,
              ),
              _MetricValue(
                label: 'Form',
                value: day.tsb.round().toString(),
                color: Colors.green,
              ),
              _MetricValue(
                label: 'TSS',
                value: day.tssOnDay.round().toString(),
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// TODO: Document _MetricValue.
class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final metric in _PmcMetric.values)
          _LegendItem(color: metric.color, label: metric.label),
      ],
    );
  }
}

/// NOTE(stuart): Document _LegendItem.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
