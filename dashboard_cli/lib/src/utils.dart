import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:googleapis/firestore/v1.dart';

Future<String> httpGet(Uri uri) async {
  final httpClient = Client();
  final result = await httpClient.get(uri);
  httpClient.close();
  if (result.statusCode == 200) {
    return result.body;
  } else {
    throw StateError('Error getting `$uri` - ${result.statusCode}');
  }
}

extension ValueExt on Value {
  bool get isNullValue => nullValue != null;

  String get printValue {
    var value = this;
    Object? o = value.stringValue ??
        value.booleanValue ??
        value.integerValue ??
        value.timestampValue ??
        value.nullValue;
    return o.toString();
  }

  bool equalsValue(Value b) {
    var aStr = jsonEncode(toJson());
    var bStr = jsonEncode(b.toJson());
    return aStr.compareTo(bStr) == 0;
  }
}

double calulatePercentile(List<int> values, double percent) {
  if (values.isEmpty) return 0;
  if (values.length == 1) return values.first.toDouble();

  values.sort();

  double index = (values.length - 1) * percent;
  if (index == index.round()) {
    return values[index.round()].toDouble();
  }

  int floorIndex = index.floor();

  double lowerAdjusted = values[floorIndex] * (floorIndex + 1 - index);
  double upperAdjusted = values[floorIndex + 1] * (index - floorIndex);

  return lowerAdjusted + upperAdjusted;
}

class Logger {
  String _indent = '';
  final Stopwatch _timer = Stopwatch()..start();

  void write(String message) {
    print('$_indent$message');
  }

  void indent() {
    _indent = '  $_indent';
  }

  void outdent() {
    _indent = _indent.substring(2);
  }

  void close({bool printElapsedTime = false}) {
    if (printElapsedTime) {
      num seconds = _timer.elapsedMilliseconds / 1000.0;
      write('Finished in ${seconds.toStringAsFixed(1)} sec.');
    }
  }
}

String firestoreEntityEncode(String str) {
  return str.replaceAll('/', '%2F');
}

class Profiler {
  final Map<String, int> _timesMs = {};
  final Map<String, int> _invocations = {};

  String? _task;
  Stopwatch? _stopwatch;

  void start(String task) {
    _task = task;
    _stopwatch = Stopwatch()..start();
  }

  void stop() {
    _stopwatch!.stop();
    _timesMs.putIfAbsent(_task!, () => 0);
    _timesMs[_task!] = _timesMs[_task]! + _stopwatch!.elapsedMilliseconds;
    _invocations.putIfAbsent(_task!, () => 0);
    _invocations[_task!] = _invocations[_task]! + 1;
  }

  Future<T> run<T>(String task, Future<T> work) async {
    try {
      start(task);
      return await work;
    } finally {
      stop();
    }
  }

  String results() {
    var buf = StringBuffer();

    for (var task in _timesMs.keys) {
      var ms = _timesMs[task]!;
      var count = _invocations[task]!;

      buf.writeln(
          '${task.padLeft(14)}: ${(ms / 1000.0).toStringAsFixed(1)}s ($count calls)');
    }

    return buf.toString();
  }
}
