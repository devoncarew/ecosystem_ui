// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:dashboard_ui/ui/widgets.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/data_model.dart';

class ChartsPage extends StatelessWidget {
  final DataModel dataModel;

  const ChartsPage({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: FutureBuilder<List<Stat>>(
          // todo: move the query elsewhere...
          future: dataModel.queryStats(
            category: 'sdk',
            timePeriod: const Duration(days: 90),
          ),
          builder: (BuildContext context, AsyncSnapshot<List<Stat>> snapshot) {
            if (snapshot.hasError) {
              return Text('${snapshot.error}');
            } else if (snapshot.hasData) {
              final stats = snapshot.data!;

              final TimeSeriesGroup group = TimeSeriesGroup(
                'SDK Sync Latency',
                const Duration(days: 30),
                // todo:
                // const Duration(days: 90),
              );

              group.addSeries(
                TimeSeries('SDK Deps Count',
                    stats.where((s) => s.stat == 'depsCount').toList()),
              );
              group.addSeries(
                TimeSeries('SDK Sync Latency P50',
                    stats.where((s) => s.stat == 'syncLatency.p50').toList()),
              );
              group.addSeries(
                TimeSeries('SDK Sync Latency P90',
                    stats.where((s) => s.stat == 'syncLatency.p90').toList()),
              );

              return TimeSeriesLineChart(group: group);
            } else {
              return const CircularProgressIndicator();
            }
          },
        ),
      ),
    );
  }
}

final titleColor = Colors.grey.shade700;
final borderColor = Colors.grey.shade500;

enum ChartTypes {
  sdkDeps,
  sdkLatency,
  publisherPackages,
  publisherLatency,
}

enum TimeRanges {
  days30,
  days90,
  days360,
}

class TimeSeriesLineChart extends StatelessWidget {
  final TimeSeriesGroup group;

  const TimeSeriesLineChart({
    required this.group,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const ExclusiveToggleButtons(
                  values: ChartTypes.values,
                  initialState: ChartTypes.publisherLatency,
                ),
                Expanded(
                  child: Text(
                    group.label,
                    style: Theme.of(context)
                        .textTheme
                        .subtitle1!
                        .copyWith(color: titleColor),
                    textAlign: TextAlign.center,
                  ),
                ),
                const ExclusiveToggleButtons(
                  values: TimeRanges.values,
                  initialState: TimeRanges.days90,
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 16),
                child: _LineChart(group: group),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// todo: the dot is very large
// todo: legend

class _LineChart extends StatelessWidget {
  // todo: redo these colors
  static final colors = [
    const Color(0xff27b6fc),
    Colors.green.shade400,
    Colors.teal,
    Colors.grey,
    Colors.brown,
  ];

  final TimeSeriesGroup group;

  const _LineChart({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final range = group.getBounds();

    return LineChart(
      LineChartData(
        titlesData: getTitlesData(),
        gridData: FlGridData(
          verticalInterval: 1.0,
          checkToShowVerticalLine: (double value) {
            DateTime vert = startDate.add(Duration(days: value.round()));
            return vert.day == 1;
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: borderColor, width: 2),
        ),
        lineBarsData: group.series.map(createBarData).toList(),
        minX: range.left,
        maxX: range.right,
        maxY: range.top,
        minY: range.bottom,
      ),
      swapAnimationDuration: kThemeAnimationDuration,
    );
  }

  FlTitlesData getTitlesData() {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          getTitlesWidget: leftTitleWidgets,
          showTitles: true,
          reservedSize: 40,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: 7, // todo:
          getTitlesWidget: bottomTitleWidgets,
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  LineChartBarData createBarData(TimeSeries series) {
    return LineChartBarData(
      color: colors[group.series.indexOf(series)],
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
      spots: series.toFlSpots(),
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        value.toInt().toString(),
        style: TextStyle(
          color: borderColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    var date = startDate.add(Duration(days: value.round()));
    return Padding(
      child: Text(
        '${date.month}/${date.day}',
        style: TextStyle(
          color: borderColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
      padding: const EdgeInsets.only(top: 10),
    );
  }
}

final startDate = DateTime(2022, 1, 1).toUtc();

double dateToDay(DateTime date) {
  return date.difference(startDate).inHours / 24.0;
}

class TimeSeries {
  final String label;
  final List<Stat> stats;

  TimeSeries(this.label, this.stats);

  double getOldestDate() {
    if (stats.isEmpty) return 0;

    return stats.fold<double>(
      dateToDay(stats.first.timestamp),
      (value, stat) => math.min(value, dateToDay(stat.timestamp)),
    );
  }

  double getLargestValue() {
    if (stats.isEmpty) return 0;

    return stats.fold<double>(
      stats.first.value.toDouble(),
      (value, stat) => math.max(value, stat.value.toDouble()),
    );
  }

  List<FlSpot> toFlSpots() {
    return stats
        .map((stat) => FlSpot(dateToDay(stat.timestamp), stat.value.toDouble()))
        .toList();
  }
}

class TimeSeriesGroup {
  final String label;
  final Duration duration;
  List<TimeSeries> series = [];
  double _maxValue = 0;
  late double _startDay;
  late double _endDay;

  TimeSeriesGroup(this.label, this.duration) {
    final now = DateTime.now();
    _endDay = dateToDay(now);
    _startDay = dateToDay(now.subtract(duration));
  }

  void addSeries(TimeSeries series) {
    this.series.add(series);

    _maxValue = math.max(_maxValue, series.getLargestValue());
  }

  Rect getBounds() {
    return Rect.fromLTRB(
      _startDay,
      _nearestDecimalMultiple(_maxValue),
      _endDay,
      0,
    );
  }

  static double _nearestDecimalMultiple(double value) {
    // drop all digits
    // ceiling
    // add digits back
    var digits = value.ceil().toString().length - 1;
    var multiplier = math.pow(10, digits);
    value = value / multiplier;
    value = value.ceilToDouble();
    return value * multiplier;
  }
}
