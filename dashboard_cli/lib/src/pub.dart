import 'dart:convert';

import 'package:dashboard_cli/src/utils.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

/// Utilities to query pub.dev.
class Pub {
  late final Client _client;
  final Profiler profiler;

  Pub({required this.profiler}) {
    _client = RetryClient(
      Client(),
      when: (response) => const [502, 503].contains(response.statusCode),
    );
  }

  Future<List<String>> packagesForPublisher(
    String publisherName, {
    bool includeHidden = true,
  }) async {
    var showHidden = includeHidden ? '+show:hidden' : '';
    List<String> result =
        await _packagesForSearch('publisher:$publisherName$showHidden')
            .toList();
    result.sort();
    return result;
  }

  Future<PackageInfo> getPackageInfo(String pkgName) async {
    final options = getPackageOptions(pkgName);
    final metrics = getPackageMetrics(pkgName);
    final json = _getJson(Uri.https('pub.dev', 'api/packages/$pkgName'));

    return PackageInfo.from(
      await json,
      options: await options,
      metrics: await metrics,
    );
  }

  Future<PackageOptions> getPackageOptions(String pkgName) async {
    final json = await profiler.run('pub.query',
        _getJson(Uri.https('pub.dev', 'api/packages/$pkgName/options')));
    return PackageOptions.from(json);
  }

  Future<PackageMetrics> getPackageMetrics(String pkgName) async {
    final json = await profiler.run('pub.query',
        _getJson(Uri.https('pub.dev', 'api/packages/$pkgName/metrics')));
    return PackageMetrics.from(json);
  }

  Stream<String> _packagesForSearch(String query) async* {
    profiler.start('pub.query');

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

    profiler.stop();
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
  final PackageOptions options;
  final PackageMetrics? metrics;

  PackageInfo.from(
    this.json, {
    required this.options,
    this.metrics,
  });

  String get name => json['name'];
  String get version => _latest['version'];
  String get published => _latest['published'];
  String? get repository => _pubspec['repository'];
  String? get homepage => _pubspec['homepage'];
  String? get issueTracker => _pubspec['issue_tracker'];

  int? unpublishedCommits;
  DateTime? unpublishedCommitDate;

  int? issueCount;

  late final Map<String, dynamic> _latest = json['latest'];
  late final Map<String, dynamic> _pubspec = _latest['pubspec'];

  bool get isDiscontinued => options.isDiscontinued;
  bool get isUnlisted => options.isUnlisted;

  RepoInfo? get repoInfo {
    var url = repository ?? homepage;
    return url == null || url.isEmpty ? null : RepoInfo(url);
  }

  String get encodedPubspec {
    return jsonEncode(_pubspec);
  }

  @override
  String toString() => '$name: $version';
}

class RepoInfo {
  final String repository;

  static final RegExp _repoRegex =
      RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

  RepoInfo(this.repository);

  String? get repoOrgAndName {
    var match = _repoRegex.firstMatch(repository);
    if (match == null) {
      return null;
    }

    var org = match.group(1)!;
    var name = match.group(2)!;
    return '$org/$name';
  }

  String? get monoRepoPath {
    var match = _repoRegex.firstMatch(repository);
    if (match == null) {
      return null;
    }

    var path = match.group(3)!;
    if (path.isEmpty) {
      return null;
    }

    // /tree/main/packages/camera/camera
    // /tree/master/pkgs/test
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    return path.split('/').skip(2).join('/');
  }

  String? getDirectFileUrl(String file) {
    var match = _repoRegex.firstMatch(repository);
    if (match == null) {
      return null;
    }

    var org = match.group(1)!;
    var name = match.group(2)!;
    var path = match.group(3);

    if (path == null || path.isEmpty) {
      // TODO: This won't handle repos that use 'main' as the default branch.
      return 'https://raw.githubusercontent.com/$org/$name/master/$file';
    } else {
      path = path.replaceAll('/tree/master/', 'master');
      path = path.replaceAll('/tree/main/', 'main');
      return 'https://raw.githubusercontent.com/$org/$name/$path/$file';
    }
  }
}

class PackageOptions {
  // {"isDiscontinued":false,"replacedBy":null,"isUnlisted":true}

  final Map<String, dynamic> json;

  PackageOptions.from(this.json);

  bool get isDiscontinued => json['isDiscontinued'];
  String? get replacedBy => json['replacedBy'];
  bool get isUnlisted => json['isUnlisted'];
}

class PackageMetrics {
  // https://pub.dev/api/packages/collection/metrics

  final Map<String, dynamic> json;
/* {
  "score":{
    "grantedPoints":130,
    "maxPoints":140,
    "likeCount":648,
    "popularityScore":0.9984576670184269,
*/

  PackageMetrics.from(this.json);

  Map get _score => json['score'];

  int get points {
    int grantedPoints = _score['grantedPoints'];
    int maxPoints = _score['maxPoints'];

    if (maxPoints == 0) {
      return 0;
    }

    return grantedPoints * 100 ~/ maxPoints;
  }

  int get likes => _score['likeCount'];
  int get popularity => ((_score['popularityScore'] as double) * 100).round();
}
