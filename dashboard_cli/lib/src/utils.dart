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
      value;
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

abstract class Logger {
  factory Logger() {
    return _Logger();
  }

  void write(String message);

  Logger subLogger(String name);

  void close({bool printElapsedTime = false});
}

class _Logger implements Logger {
  final List<_SubLogger> _subloggers = [];
  final Stopwatch timer = Stopwatch()..start();

  @override
  void write(String message) {
    print(message);
  }

  @override
  Logger subLogger(String name) {
    _SubLogger logger = _SubLogger(this, '  ', name);
    _subloggers.add(logger);
    return logger;
  }

  @override
  void close({bool printElapsedTime = false}) {
    for (var logger in _subloggers) {
      logger.close();
    }

    if (printElapsedTime) {
      num seconds = timer.elapsedMilliseconds / 1000.0;
      write('Finished in ${seconds.toStringAsFixed(1)} sec.');
    }
  }
}

class _SubLogger implements Logger {
  final Logger parent;
  final String indent;

  final StringBuffer buf = StringBuffer();

  _SubLogger(this.parent, this.indent, String name) {
    buf.writeln(name);
  }

  @override
  void write(String message) {
    buf.writeln('$indent$message');
  }

  @override
  Logger subLogger(String name) {
    throw 'unsupported';
  }

  @override
  void close({bool printElapsedTime = false}) {
    if (buf.isNotEmpty) {
      parent.write(buf.toString().trimRight());
      buf.clear();
    }
  }
}
