// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:dashboard_ui/ui/widgets.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/theme.dart';

final titleColor = Colors.grey.shade700;
final borderColor = Colors.grey.shade500;

enum ChartTypes {
  sdkDeps('sdk.deps'),
  sdkLatency('sdk.latency'),
  packageCounts('package.count'),
  publishLatency('package.latency');

  final String category;

  const ChartTypes(this.category);
}

enum TimeRanges {
  month(30),
  quarter(91),
  year(365);

  final int days;

  const TimeRanges(this.days);
}

class ChartsPage extends StatefulWidget {
  final DataModel dataModel;

  const ChartsPage({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> {
  late QueryEngine queryEngine;

  @override
  void initState() {
    super.initState();

    queryEngine = QueryEngine(widget.dataModel);
    queryEngine.query();
  }

  // todo: have a progress indicator

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        Theme.of(context).textTheme.subtitle1!.copyWith(color: titleColor);

    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ValueListenableBuilder<ChartTypes>(
                  valueListenable: queryEngine.chartType,
                  builder: (context, chartType, child) {
                    return ExclusiveToggleButtons<ChartTypes>(
                      values: ChartTypes.values,
                      selection: chartType,
                      onPressed: (item) {
                        queryEngine.query(chartType: item);
                      },
                    );
                  },
                ),
                Expanded(
                  child: ValueListenableBuilder<QueryResult>(
                    valueListenable: queryEngine.queryResult,
                    builder: (context, result, _) {
                      return Text(
                        result.group.label,
                        style: titleStyle,
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: queryEngine.busy,
                  builder: (BuildContext context, bool busy, _) {
                    return Center(
                      child: SizedBox(
                        width: defaultIconSize,
                        height: defaultIconSize,
                        child: busy
                            ? const CircularProgressIndicator(
                                // color: Colors.white,
                                strokeWidth: 2,
                              )
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                ValueListenableBuilder<TimeRanges>(
                  valueListenable: queryEngine.timeRange,
                  builder: (context, range, child) {
                    return ExclusiveToggleButtons<TimeRanges>(
                      values: TimeRanges.values,
                      selection: range,
                      onPressed: (item) {
                        queryEngine.query(timeRange: item);
                      },
                    );
                  },
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 16),
                child: ValueListenableBuilder<QueryResult>(
                  valueListenable: queryEngine.queryResult,
                  builder: (context, result, _) {
                    return _TimeSeriesLineChart(group: result.group);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeSeriesLineChart extends StatelessWidget {
  // todo: add more colors
  static final colors = [
    const Color(0xFF68A7AD),
    const Color(0xFF398AB9),
    const Color(0xFFE5CB9F),
    const Color(0xFFD8D2CB),
    const Color(0xFFBB6464),
  ];

  final TimeSeriesGroup group;

  const _TimeSeriesLineChart({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final range = group.getBounds();

    return Stack(
      children: [
        LineChart(
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
        ),
        Padding(
          padding: const EdgeInsets.only(left: 60, top: 22),
          child: _ChartLegendWidget(group: group, colors: colors),
        ),
      ],
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
      color: colors[group.series.indexOf(series) % colors.length],
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
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '${date.month}/${date.day}',
        style: TextStyle(
          color: borderColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
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
  final String? units;

  TimeSeries(this.label, this.stats, {this.units});

  /// Return both the label as well as the value of the last newest entry.
  String get describe {
    if (stats.isEmpty) {
      return label;
    } else {
      var stat = stats.last;
      var suffix = units == null
          ? ''
          : stat.value == 1
              ? ' $units'
              : ' ${units}s';
      return '$label (${stat.value}$suffix)';
    }
  }

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
      series.isEmpty ? 100 : _nearestRoundNumber(_maxValue),
      _endDay,
      0,
    );
  }

  static double _nearestRoundNumber(double value) {
    // drop all digits; ceiling; add digits back
    var digits = value.ceil().toString().length - 1;
    var multiplier = math.pow(10, digits);
    value = value / multiplier;
    if (value < 1.5) {
      value = value < 1.25 ? 1.25 : 1.5;
    } else {
      value = value.ceilToDouble();
    }
    return value * multiplier;
  }
}

class _ChartLegendWidget extends StatelessWidget {
  final TimeSeriesGroup group;
  final List<Color> colors;

  const _ChartLegendWidget({
    required this.group,
    required this.colors,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade700),
      ),
      padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...group.series.map((series) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color:
                          colors[group.series.indexOf(series) % colors.length],
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    series.describe,
                    style: TextStyle(
                      color: borderColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class QueryEngine {
  final DataModel dataModel;

  QueryEngine(this.dataModel);

  void query({
    ChartTypes? chartType,
    TimeRanges? timeRange,
  }) {
    if (chartType != null) {
      _chartType.value = chartType;
    }

    if (timeRange != null) {
      _timeRange.value = timeRange;
    }

    chartType = _chartType.value;
    timeRange = _timeRange.value;

    final duration = Duration(days: timeRange.days);

    _busy.value = true;

    dataModel
        .queryStats(category: chartType.category, timePeriod: duration)
        .then(
      (List<Stat> result) {
        _busy.value = false;

        late TimeSeriesGroup group;

        switch (chartType!) {
          case ChartTypes.sdkDeps:
            group = TimeSeriesGroup('SDK Dependencies', duration);
            group.addSeries(TimeSeries('SDK dependency count', result));
            break;
          case ChartTypes.sdkLatency:
            group = TimeSeriesGroup('SDK Sync Latency', duration);
            group.addSeries(
              TimeSeries(
                'SDK P50 sync latency',
                result.where((s) => s.stat == 'p50').toList(),
                units: 'day',
              ),
            );
            group.addSeries(
              TimeSeries(
                'SDk P90 sync latency',
                result.where((s) => s.stat == 'p90').toList(),
                units: 'day',
              ),
            );
            break;
          case ChartTypes.packageCounts:
            group = TimeSeriesGroup('Package Counts', duration);

            var counts = <String, List<Stat>>{};
            var unowned = <String, List<Stat>>{};
            for (var stat in result) {
              if (stat.stat == 'count') {
                counts.putIfAbsent(stat.detail!, () => []).add(stat);
              } else if (stat.stat == 'unowned') {
                unowned.putIfAbsent(stat.detail!, () => []).add(stat);
              }
            }

            // flutter.dev doesn't use this
            unowned.remove('flutter.dev');

            // we care less about having these owned
            unowned.remove('labs.dart.dev');
            unowned.remove('google.dev');

            for (var entry in counts.entries) {
              group.addSeries(TimeSeries('${entry.key} count', entry.value));
            }
            for (var entry in unowned.entries) {
              group.addSeries(TimeSeries('${entry.key} unowned', entry.value));
            }

            group.series.sort((a, b) => a.label.compareTo(b.label));

            break;
          case ChartTypes.publishLatency:
            group = TimeSeriesGroup('Publish Latency', duration);

            var p50 = <String, List<Stat>>{};
            var p90 = <String, List<Stat>>{};
            for (var stat in result) {
              if (stat.stat == 'p50') {
                p50.putIfAbsent(stat.detail!, () => []).add(stat);
              } else if (stat.stat == 'p90') {
                p90.putIfAbsent(stat.detail!, () => []).add(stat);
              }
            }

            for (var entry in p50.entries) {
              group.addSeries(
                TimeSeries(
                  '${entry.key} P50 latency',
                  entry.value,
                  units: 'day',
                ),
              );
            }
            for (var entry in p90.entries) {
              group.addSeries(
                TimeSeries(
                  '${entry.key} P90 latency',
                  entry.value,
                  units: 'day',
                ),
              );
            }

            group.series.sort((a, b) => a.label.compareTo(b.label));

            break;
        }

        _queryResult.value = QueryResult(group: group);
      },
    );
  }

  // todo: this isn't fully correct - use counts
  ValueListenable<bool> get busy => _busy;
  final ValueNotifier<bool> _busy = ValueNotifier(true);

  ValueListenable<ChartTypes> get chartType => _chartType;
  final ValueNotifier<ChartTypes> _chartType =
      ValueNotifier(ChartTypes.publishLatency);

  ValueListenable<TimeRanges> get timeRange => _timeRange;
  final ValueNotifier<TimeRanges> _timeRange =
      ValueNotifier(TimeRanges.quarter);

  ValueListenable<QueryResult> get queryResult => _queryResult;
  final ValueNotifier<QueryResult> _queryResult =
      ValueNotifier(QueryResult.empty());
}

class QueryResult {
  final TimeSeriesGroup group;

  QueryResult({required this.group});

  factory QueryResult.empty() => QueryResult(
        group: TimeSeriesGroup('', const Duration(days: 30)),
      );
}
