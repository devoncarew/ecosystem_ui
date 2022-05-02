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
  Object? o =
      value.stringValue ?? value.booleanValue ?? value.timestampValue ?? value;
  return o.toString();
}
