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
          // "version": "7621b914e9bde81a12efcf02f1e4227998a64256",
          // "last_updated": "2022-06-02T04:22:31.000",
          // "pending_commits": 6,
          // "latency_seconds": 103895
          // "unsynced_commit_date": "2022-06-02T04:22:31.000",

          DateTime? latencyDate = map.containsKey('unsynced_commit_date')
              ? DateTime.parse(map['unsynced_commit_date'])
              : null;

          return Google3Dependency(
            name: map['name'] as String,
            firstParty: map['is_first_party'] as bool,
            commit: map['version'] as String?,
            pendingCommits: (map['pending_commits'] as int?) ?? 0,
            latencyDate: latencyDate,
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
  final String? error;

  Google3Dependency({
    required this.name,
    required this.firstParty,
    required this.commit,
    required this.pendingCommits,
    required this.latencyDate,
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
