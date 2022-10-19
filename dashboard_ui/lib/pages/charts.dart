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
  packages('package.count'),
  unowned('package.count'),
  sdkDeps('sdk.deps'),
  sdkLatency('sdk.latency'),
  google3Deps('google3.deps'),
  google3Latency('google3.latency'),
  publishP50('package.latency'),
  publishP90('package.latency');

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
  int zoom = 1;

  @override
  void initState() {
    super.initState();

    queryEngine = QueryEngine(widget.dataModel);
    queryEngine.query();

    queryEngine.queryResult.addListener(() {
      setState(() {
        // Reset the zoom.
        zoom = 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        Theme.of(context).textTheme.titleMedium!.copyWith(color: titleColor);

    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
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
                  const Expanded(child: SizedBox(width: 16)),
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
            ),
            ValueListenableBuilder<QueryResult>(
              valueListenable: queryEngine.queryResult,
              builder: (context, result, _) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    result.group.label,
                    style: titleStyle,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<QueryResult>(
                        valueListenable: queryEngine.queryResult,
                        builder: (context, result, _) {
                          return _TimeSeriesLineChart(
                            group: result.group,
                            zoom: zoom,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.zoom_in),
                            splashRadius: defaultSplashRadius,
                            onPressed: () {
                              setState(() => zoom *= 2);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.zoom_out),
                            splashRadius: defaultSplashRadius,
                            onPressed: zoom == 1
                                ? null
                                : () => setState(() => zoom ~/= 2),
                          ),
                        ],
                      ),
                    ),
                  ],
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
  static final colors = [
    const Color(0xFFffc09f),
    const Color(0xFFa0ced9),
    const Color(0xFF809bce),
    const Color(0xFFeac4d5),
    const Color(0xFFadf7b6),
    const Color(0xFFffee93),
  ];

  final TimeSeriesGroup group;
  final int zoom;

  const _TimeSeriesLineChart({
    required this.group,
    this.zoom = 1,
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
            minY: range.bottom,
            maxY: range.top / zoom,
            clipData:
                FlClipData(top: true, left: true, right: true, bottom: false),
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
          interval: group.timeInternal,
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

  int get lastValueOrZero {
    return stats.isEmpty ? 0 : stats.last.value;
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

  double get timeInternal =>
      duration.inDays < 14 ? 1 : (duration.inDays / 12.0).roundToDouble();

  void addSeries(TimeSeries series) {
    this.series.add(series);

    _maxValue = math.max(_maxValue, series.getLargestValue());
  }

  void sort() {
    series.sort((a, b) => a.label.compareTo(b.label));
  }

  Rect getBounds() {
    return Rect.fromLTRB(
      _startDay,
      series.isEmpty ? 100 : _nearestRoundNumber(_maxValue * 1.3),
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
    return Opacity(
      opacity: 0.7,
      child: Container(
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
                        color: colors[
                            group.series.indexOf(series) % colors.length],
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
    // We overquery by a few days in order to try to have continuity to the end
    // of the graph.
    final queryDuration = Duration(days: timeRange.days + 3);

    _busy.value = true;

    dataModel
        .queryStats(category: chartType.category, timePeriod: queryDuration)
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
            group = TimeSeriesGroup('SDK Sync Latency (days)', duration);
            group.addSeries(
              TimeSeries(
                'SDK P50 sync latency',
                result.where((s) => s.stat == 'p50').toList(),
                units: 'day',
              ),
            );
            group.addSeries(
              TimeSeries(
                'SDK P90 sync latency',
                result.where((s) => s.stat == 'p90').toList(),
                units: 'day',
              ),
            );
            break;
          case ChartTypes.google3Deps:
            group = TimeSeriesGroup('Google3 Dependencies', duration);
            group.addSeries(TimeSeries('Google3 synced count', result));
            break;
          case ChartTypes.google3Latency:
            group = TimeSeriesGroup('Google3 Sync Latency (days)', duration);
            group.addSeries(
              TimeSeries(
                'Google3 P50 sync latency',
                result.where((s) => s.stat == 'p50').toList(),
                units: 'day',
              ),
            );
            group.addSeries(
              TimeSeries(
                'Google3 P90 sync latency',
                result.where((s) => s.stat == 'p90').toList(),
                units: 'day',
              ),
            );
            break;
          case ChartTypes.packages:
            group = TimeSeriesGroup('Package Counts', duration);

            var counts = <String, List<Stat>>{};
            for (var stat in result.where((stat) => stat.stat == 'count')) {
              counts.putIfAbsent(stat.detail!, () => []).add(stat);
            }

            for (var entry in counts.entries) {
              group.addSeries(TimeSeries('${entry.key} count', entry.value));
            }
            group.sort();

            break;
          case ChartTypes.unowned:
            group = TimeSeriesGroup('Unowned Package Counts', duration);

            var unowned = <String, List<Stat>>{};
            for (var stat in result.where((stat) => stat.stat == 'unowned')) {
              unowned.putIfAbsent(stat.detail!, () => []).add(stat);
            }

            // flutter.dev doesn't use this
            unowned['flutter.dev']!.clear();

            for (var entry in unowned.entries) {
              group.addSeries(TimeSeries('${entry.key} unowned', entry.value));
            }
            group.sort();

            break;
          case ChartTypes.publishP50:
            group = TimeSeriesGroup('Publish Latency P50 (days)', duration);

            var publisherLatencies = <String, List<Stat>>{};
            for (var stat in result.where((s) => s.stat == 'p50')) {
              publisherLatencies.putIfAbsent(stat.detail!, () => []).add(stat);
            }

            for (var entry in publisherLatencies.entries) {
              group.addSeries(
                TimeSeries(
                  '${entry.key} P50 latency',
                  entry.value,
                  units: 'day',
                ),
              );
            }
            group.sort();

            break;
          case ChartTypes.publishP90:
            group = TimeSeriesGroup('Publish Latency P90 (days)', duration);

            var publisherLatencies = <String, List<Stat>>{};
            for (var stat in result.where((s) => s.stat == 'p90')) {
              publisherLatencies.putIfAbsent(stat.detail!, () => []).add(stat);
            }

            for (var entry in publisherLatencies.entries) {
              group.addSeries(
                TimeSeries(
                  '${entry.key} P90 latency',
                  entry.value,
                  units: 'day',
                ),
              );
            }
            group.sort();

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
      ValueNotifier(ChartTypes.publishP50);

  ValueListenable<TimeRanges> get timeRange => _timeRange;
  // TODO: switch this to 'quarter' once we've accumulated more data
  final ValueNotifier<TimeRanges> _timeRange = ValueNotifier(TimeRanges.month);

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
