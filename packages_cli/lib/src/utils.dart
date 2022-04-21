import 'package:http/http.dart';

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
