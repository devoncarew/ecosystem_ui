// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../model/data_model.dart';
import '../ui/widgets.dart';

class ChartsPage extends NavPage {
  final DataModel dataModel;

  ChartsPage(this.dataModel) : super('Charts');

  @override
  Widget createChild(BuildContext context, {Key? key}) {
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
              print(snapshot.error);
              return Text('${snapshot.error}');
            } else if (snapshot.hasData) {
              final stats = snapshot.data!;
              return LineChartSample(
                depsCount: stats.where((s) => s.stat == 'depsCount').toList(),
                latencyP50:
                    stats.where((s) => s.stat == 'syncLatency.p50').toList(),
                latencyP90:
                    stats.where((s) => s.stat == 'syncLatency.p90').toList(),
              );
            } else {
              return const CircularProgressIndicator();
            }
          },
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  static final DateTime now = DateTime.now();

  final List<Stat> depsCount;
  final List<Stat> latencyP50;
  final List<Stat> latencyP90;

  const _LineChart({
    required this.depsCount,
    required this.latencyP50,
    required this.latencyP90,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      sampleData1,
      swapAnimationDuration: kThemeAnimationDuration,
    );
  }

  LineChartData get sampleData1 => LineChartData(
        // lineTouchData: lineTouchData1,
        gridData: gridData,
        titlesData: titlesData1,
        borderData: borderData,
        lineBarsData: lineBarsData1,
        // todo: p90 is off the scale here...
        minX: 0, // todo:
        maxX: 14, // todo:
        maxY: 80,
        minY: 0,
      );

  FlTitlesData get titlesData1 => FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: bottomTitles,
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: leftTitles(),
        ),
      );

  List<LineChartBarData> get lineBarsData1 => [
        lineChartBarData1_1,
        lineChartBarData1_2,
        lineChartBarData1_3,
      ];

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      color: Color(0xff75729e),
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    String text = value.toInt().toString();
    return Text(text, style: style, textAlign: TextAlign.center);
  }

  SideTitles leftTitles() => SideTitles(
        getTitlesWidget: leftTitleWidgets,
        showTitles: true,
        interval: 10,
        reservedSize: 40,
      );

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      color: Color(0xff72719b),
      fontWeight: FontWeight.bold,
      fontSize: 16,
    );
    Widget text;
    int val = 14 - value.toInt();
    text = Text(
      DateTime.now().subtract(Duration(days: val)).toString(),
      style: style,
    );

    // switch (value.toInt()) {
    //   case 2:
    //     text = const Text('SEPT', style: style);
    //     break;
    //   case 7:
    //     text = const Text('OCT', style: style);
    //     break;
    //   case 12:
    //     text = const Text('DEC', style: style);
    //     break;
    //   default:
    //     text = const Text('');
    //     break;
    // }

    return Padding(child: text, padding: const EdgeInsets.only(top: 10.0));
  }

  SideTitles get bottomTitles => SideTitles(
        showTitles: true,
        reservedSize: 32,
        interval: 7,
        getTitlesWidget: bottomTitleWidgets,
      );

  FlGridData get gridData => FlGridData(show: false);

  FlBorderData get borderData => FlBorderData(
        show: true,
        border: const Border(
          bottom: BorderSide(color: Color(0xff4e4965), width: 4),
          left: BorderSide(color: Colors.transparent),
          right: BorderSide(color: Colors.transparent),
          top: BorderSide(color: Colors.transparent),
        ),
      );

  LineChartBarData get lineChartBarData1_1 => LineChartBarData(
        isCurved: true,
        color: const Color(0xff4af699),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
        spots: depsCount.map(_statToFlSpot).toList(),
      );

  LineChartBarData get lineChartBarData1_2 => LineChartBarData(
        isCurved: true,
        color: const Color(0xffaa4cfc),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
          show: false,
          color: const Color(0x00aa4cfc),
        ),
        spots: latencyP50.map(_statToFlSpot).toList(),
      );

  LineChartBarData get lineChartBarData1_3 => LineChartBarData(
        isCurved: true,
        color: const Color(0xff27b6fc),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
        spots: latencyP90.map(_statToFlSpot).toList(),
      );

  static FlSpot _statToFlSpot(Stat stat) {
    double x = now.difference(stat.timestamp.toDate()).inHours / 24.0;
    return FlSpot(14 - x, stat.value.toDouble());
  }
}

class LineChartSample extends StatelessWidget {
  final List<Stat> depsCount;
  final List<Stat> latencyP50;
  final List<Stat> latencyP90;

  const LineChartSample({
    required this.depsCount,
    required this.latencyP50,
    required this.latencyP90,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 16),
            const Text(
              'SDK Sync Latency',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 37),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 16, left: 6),
                child: _LineChart(
                  depsCount: depsCount,
                  latencyP50: latencyP50,
                  latencyP90: latencyP90,
                ),
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            print('refresh');
          },
        )
      ],
    );
  }
}
