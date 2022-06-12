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

          DateTime? lastUpdated;
          if (map['last_updated'] != null) {
            lastUpdated = DateTime.parse(map['last_updated']);
          }

          return Google3Dependency(
            name: map['name'] as String,
            firstParty: map['is_first_party'] as bool,
            commit: map['version'] as String?,
            lastUpdated: lastUpdated,
            pendingCommits: (map['pending_commits'] as int?) ?? 0,
            latencySeconds: map['latency_seconds'] as int?,
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
  final DateTime? lastUpdated;
  final int pendingCommits;
  final int? latencySeconds;

  Google3Dependency({
    required this.name,
    required this.firstParty,
    required this.commit,
    required this.lastUpdated,
    required this.pendingCommits,
    required this.latencySeconds,
  });

  @override
  String toString() => '$name 0x$commit';
}
