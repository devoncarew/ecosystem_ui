import 'dart:convert';

import 'package:http/http.dart';
import 'package:http_retry/http_retry.dart';

/// Utilities to query pub.dev.
class Pub {
  late final Client _client;

  Pub() {
    _client = RetryClient(
      Client(),
      when: (response) => const [502, 503].contains(response.statusCode),
    );
  }

  Future<List<String>> packagesForPublisher(String publisherName) async {
    List<String> result =
        await _packagesForSearch('publisher:$publisherName+show:hidden')
            .toList();
    result.sort();
    return result;
  }

  Future<PackageInfo> getPackageInfo(String pkgName) async {
    final PackageOptions options = await getPackageOptions(pkgName);
    final json = await _getJson(Uri.https('pub.dev', 'api/packages/$pkgName'));
    return PackageInfo.from(json, options: options);
  }

  Future<PackageOptions> getPackageOptions(String pkgName) async {
    final json =
        await _getJson(Uri.https('pub.dev', 'api/packages/$pkgName/options'));
    return PackageOptions.from(json);
  }

  Stream<String> _packagesForSearch(String query) async* {
    final uri = Uri.parse('https://pub.dev/api/search');

    var page = 1;
    for (;;) {
      final targetUri = uri.replace(queryParameters: {
        'q': query,
        'page': page.toString(),
      });

      final map = await _getJson(targetUri);

      for (var package in (map['packages'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['package'] as String?)) {
        yield package!;
      }

      if (map.containsKey('next')) {
        page = page + 1;
      } else {
        break;
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final result = await _client.get(uri);
    if (result.statusCode == 200) {
      return jsonDecode(result.body) as Map<String, dynamic>;
    } else {
      throw StateError('Error getting `$uri` - ${result.statusCode}');
    }
  }

  void close() {
    _client.close();
  }
}

class PackageInfo {
  // {
  // "name":"usage",
  // "latest":{
  //   "version":"4.0.2",
  //   "pubspec":{
  //     "name":"usage",
  //     "version":"4.0.2",
  //     "description":"A Google Analytics wrapper for command-line, web, and Flutter apps.",
  //     "repository":"https://github.com/dart-lang/wasm",
  //     "environment":{
  //       "sdk":">=2.12.0-0 <3.0.0"
  //     },
  //     "dependencies":{
  //       "path":"^1.8.0"
  //     },
  //     "dev_dependencies":{
  //       "pedantic":"^1.9.0",
  //       "test":"^1.16.0"
  //     }
  //   },
  //   "archive_url":"https://pub.dartlang.org/packages/usage/versions/4.0.2.tar.gz",
  //   "published":"2021-03-30T17:44:54.093423Z"
  // },

  final Map<String, dynamic> json;
  final PackageOptions? options;

  PackageInfo.from(this.json, {this.options});

  String get name => json['name'];
  String get version => _latest['version'];
  String? get repository => _pubspec['repository'];
  String? get homepage => _pubspec['homepage'];
  String? get published => _latest['published'];

  late final Map<String, dynamic> _latest = json['latest'];
  late final Map<String, dynamic> _pubspec = _latest['pubspec'];

  bool get isDiscontinued => options?.isDiscontinued ?? false;
  bool get isUnlisted => options?.isUnlisted ?? false;

  String get encodedPubspec {
    return jsonEncode(_pubspec);
  }

  @override
  String toString() => '$name: $version';
}

class PackageOptions {
  // {"isDiscontinued":false,"replacedBy":null,"isUnlisted":true}

  final Map<String, dynamic> json;

  PackageOptions.from(this.json);

  bool get isDiscontinued => json['isDiscontinued'];
  String? get replacedBy => json['replacedBy'];
  bool get isUnlisted => json['isUnlisted'];
}
