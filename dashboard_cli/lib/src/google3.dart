import 'dart:convert';
import 'dart:io';

class Google3 {
  Future<List<Google3Dependency>> getPackageSyncInfo({
    required Set<String> packages,
  }) async {
    // TODO: read this from a json url
    var dataFile = File('latest.json');
    var json = jsonDecode(dataFile.readAsStringSync()) as Map<String, dynamic>;
    var data = json['packages'] as List;

    return data
        .map((data) {
          var map = data as Map<String, dynamic>;
          final name = map['name'] as String;

          if (!packages.contains(name)) {
            return null;
          }

          // "name": "analyzer",
          // "is_first_party": false,
          // "version": "",
          // "last_updated": null,
          // "pending_commits": 0,
          // "latency_seconds": null,
          // "error": "Cannot find Git URI in package metadata",
          // "has_copybara_config": false,
          // "uses_copybara_service": false,
          // "sdk_package": true,
          // "unbundled_package": false

          DateTime? latencyDate = map.containsKey('unsynced_commit_date')
              ? DateTime.parse(map['unsynced_commit_date'])
              : null;

          return Google3Dependency(
            name: map['name'] as String,
            firstParty: map['is_first_party'] as bool,
            commit: map['version'] as String?,
            pendingCommits: (map['pending_commits'] as int?) ?? 0,
            latencyDate: latencyDate,
            hasCopybaraConfig: map['has_copybara_config'] ?? false,
            usesCopybaraService: map['uses_copybara_service'] ?? false,
            sdkPackage: map['sdk_package'],
            bundledPackage: map['unbundled_package'],
            error:
                map.containsKey('error') ? 'error retrieving git info' : null,
          );
        })
        .whereType<Google3Dependency>()
        .toList();
  }
}

class Google3Dependency {
  final String name;
  final bool firstParty;
  final String? commit;
  final int pendingCommits;
  final DateTime? latencyDate;
  final bool hasCopybaraConfig;
  final bool usesCopybaraService;
  final bool? sdkPackage;
  final bool? bundledPackage;
  final String? error;

  Google3Dependency({
    required this.name,
    required this.firstParty,
    required this.commit,
    required this.pendingCommits,
    required this.latencyDate,
    required this.hasCopybaraConfig,
    required this.usesCopybaraService,
    required this.sdkPackage,
    required this.bundledPackage,
    required this.error,
  });

  int get syncLatencyDays {
    // Up to date.
    if (latencyDate == null) {
      return 0;
    }

    var date = latencyDate;
    if (date == null) {
      return 0;
    } else {
      return DateTime.now().toUtc().difference(date).inDays;
    }
  }

  @override
  String toString() => '$name 0x$commit';
}
