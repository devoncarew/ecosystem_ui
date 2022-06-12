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

// todo: make these extension methods
bool compareValues(Value a, Value b) {
  var aStr = jsonEncode(a.toJson());
  var bStr = jsonEncode(b.toJson());
  return aStr.compareTo(bStr) == 0;
}

String printValue(Value value) {
  Object? o = value.stringValue ??
      value.booleanValue ??
      value.integerValue ??
      value.timestampValue ??
      value.nullValue;
  return o.toString();
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
