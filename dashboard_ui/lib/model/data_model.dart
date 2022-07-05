// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:pub_semver/pub_semver.dart';
import 'package:collection/collection.dart';

import '../ui/table.dart';
import '../utils/constants.dart';
import '../utils/utils.dart';

typedef SnapshotItems = Map<String, dynamic>;

/// This DataModel class reads from firestore and provides data to the rest of
/// the app.
class DataModel {
  final FirebaseFirestore firestore;

  DataModel({required this.firestore});

  static DataModel of(BuildContext context) {
    return Provider.of<DataModel>(context);
  }

  Future init() async {
    // Get the publishers we care about.
    await _initPublishers();

    // Start the process of loading other data, but don't delay startup (don't
    // wait on the results).
    () async {
      await _initPackagesData();
      await _initChangelog();
      await _initRepositories();
      await _initSdkDeps();
      await _initGoogle3Deps();
    }();
  }

  Future<void> loaded() {
    if (!loading.value) {
      return Future.value();
    } else {
      final completer = Completer();
      listener() {
        loading.removeListener(listener);
        completer.complete();
      }

      loading.addListener(listener);
      return completer.future;
    }
  }

  ValueListenable<bool> get loading => _loading;
  final ValueNotifier<bool> _loading = ValueNotifier(true);

  /// Return the list of pub.dev publishers we should care about (i.e.,
  /// dart.dev, ...).
  ValueListenable<List<String>> get publishers => _publishers;
  final ValueNotifier<List<String>> _publishers =
      ValueNotifier(_defaultPublishers);

  /// todo: doc
  ValueListenable<List<PackageInfo>> getPackagesForPublisher(String publisher) {
    return _publisherNotifiers.putIfAbsent(publisher, () => ValueNotifier([]));
  }

  final Map<String, ValueNotifier<List<PackageInfo>>> _publisherNotifiers = {};

  ValueListenable<List<PackageInfo>> get packages => _packages;
  final ValueNotifier<List<PackageInfo>> _packages = ValueNotifier([]);

  /// todo: doc
  ValueListenable<List<LogItem>> get changeLogItems => _changeLogItems;
  final ValueNotifier<List<LogItem>> _changeLogItems = ValueNotifier([]);

  Future _initPublishers() async {
    // Listen to the publishers collection.
    FirebaseFirestore.instance
        .collection('publishers')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      var publishers = snapshot.docs.map((doc) => doc.id).toList()..sort();

      for (var pub in defaultPublisherSortOrder.reversed) {
        if (publishers.contains(pub)) {
          publishers.remove(pub);
          publishers.insert(0, pub);
        }
      }

      // todo: sort order
      _publishers.value = publishers;
    });
  }

  ValueListenable<List<SdkDep>> get sdkDependencies => _sdkDependencies;
  final ValueNotifier<List<SdkDep>> _sdkDependencies = ValueNotifier([]);

  Future _initSdkDeps() async {
    FirebaseFirestore.instance
        .collection('sdk_deps')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      var result = snapshot.docs.map((item) {
        return SdkDep(
          name: item.get('name'),
          commit: item.get('commit'),
          repository: item.get('repository'),
          syncedCommitDate: item.get('syncedCommitDate'),
          unsyncedCommits: item.get('unsyncedCommits'),
          unsyncedCommitDate: item.get('unsyncedCommitDate'),
        );
      }).toList();
      _sdkDependencies.value = result;
    });
  }

  ValueListenable<List<Google3Dep>> get googleDependencies =>
      _googleDependencies;
  final ValueNotifier<List<Google3Dep>> _googleDependencies = ValueNotifier([]);

  Future _initGoogle3Deps() async {
    FirebaseFirestore.instance
        .collection('google3')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      var result = snapshot.docs.map((item) {
        return Google3Dep(
          name: item.get('name'),
          firstParty: item.get('firstParty'),
          commit: item.get('commit'),
          lastUpdated: item.get('lastUpdated'),
          pendingCommits: item.get('pendingCommits'),
          latencySeconds: item.get('latencySeconds'),
        );
      }).toList();
      _googleDependencies.value = result;
    });
  }

  /// todo: doc
  ValueListenable<List<RepositoryInfo>> get repositories => _repositories;
  final ValueNotifier<List<RepositoryInfo>> _repositories = ValueNotifier([]);

  Future<List<Stat>> queryStats({
    required String category,
    required Duration timePeriod,
  }) async {
    // time limit
    // category

    //     category
    // "sdk"
    // (string)
    // stat
    // "depsCount"
    // timestamp
    // May 12, 2022 at 3:01:54 PM UTC-7
    // value
    // 68

    final startTime = Timestamp.fromDate(DateTime.now().subtract(timePeriod));

    QuerySnapshot<SnapshotItems> result = await FirebaseFirestore.instance
        .collection('stats')
        .where('category', isEqualTo: category)
        .where('timestamp', isGreaterThanOrEqualTo: startTime)
        // .orderBy('timestamp', descending: true)
        .get();

    final stats = result.docs.map<Stat>(Stat.fromFirestore).toList();
    stats.sort();
    // for (var stat in stats) {
    //   print(stat);
    // }
    return stats;
  }

  RepositoryInfo? getRepositoryForPackage(PackageInfo package) {
    return repositories.value.firstWhereOrNull((repo) {
      return repo.org == package.gitOrgName && repo.name == package.gitRepoName;
    });
  }

  SdkDep? getSdkDepForPackage(PackageInfo package) {
    return sdkDependencies.value.firstWhereOrNull((dep) {
      return dep.repository == package.repoUrl;
    });
  }

  Google3Dep? getGoogle3DepForPackage(PackageInfo package) {
    return googleDependencies.value.firstWhereOrNull((dep) {
      return dep.name == package.name;
    });
  }

  Future _initRepositories() async {
    firestore
        .collection('repositories')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      List<RepositoryInfo> repos =
          snapshot.docs.map((doc) => RepositoryInfo.from(doc)).toList();

      _repositories.value = repos;
    });
  }

  Future _initPackagesData() async {
    firestore
        .collection('packages')
        .orderBy('name')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      Map<String, List<PackageInfo>> packageMap = {};

      // todo: try doing a deep compare here
      List<PackageInfo> allPackages = [];

      for (var data in snapshot.docs) {
        var package = PackageInfo.from(data);
        packageMap.putIfAbsent(package.publisher, () => []);
        packageMap[package.publisher]!.add(package);
        allPackages.add(package);
      }

      for (var publisher in packageMap.keys) {
        _publisherNotifiers.putIfAbsent(publisher, () => ValueNotifier([]));
        _publisherNotifiers[publisher]!.value = packageMap[publisher]!;
      }

      _packages.value = allPackages;

      _loading.value = false;
    });
  }

  Future _initChangelog() async {
    // todo: Have a way to extend the limit of the number of items returned.
    FirebaseFirestore.instance
        .collection('log')
        .limit(200)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      _strobeBusy();
      var result = snapshot.docs.map((item) {
        return LogItem(
          entity: item.get('entity'),
          change: item.get('change'),
          timestamp: item.get('timestamp'),
        );
      }).toList();
      _changeLogItems.value = result;
    });
  }

  ValueListenable<bool> get busy => _busy;
  final ValueNotifier<bool> _busy = ValueNotifier(false);
  int _busyCount = 0;

  void _strobeBusy() {
    _busyCount++;
    if (_busyCount == 1) {
      _busy.value = true;
    }

    Timer(const Duration(milliseconds: 3000), () {
      _busyCount--;
      if (_busyCount == 0) {
        _busy.value = false;
      }
    });
  }
}

class Stat implements Comparable<Stat> {
  final String category;
  final String stat;
  final String? detail;
  final int value;
  final DateTime timestamp;

  Stat({
    required this.category,
    required this.stat,
    required this.detail,
    required this.value,
    required this.timestamp,
  });

  static Stat fromFirestore(DocumentSnapshot<SnapshotItems> snapshot) {
    final data = snapshot.data()!;
    return Stat(
      category: data['category'],
      stat: data['stat'],
      detail: data['detail'],
      value: data['value'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  @override
  int compareTo(Stat other) {
    return timestamp.compareTo(other.timestamp);
  }

  @override
  String toString() => '$category:$stat:$value:$timestamp';
}

class PackageInfo {
  final String name;
  final String publisher;
  final String maintainer;
  final String? repository;
  final String? issueTracker;
  // todo: issueCount
  final Version version;
  final bool discontinued;
  final bool unlisted;
  final String pubspec;
  final String? analysisOptions;
  final Timestamp publishedDate;
  final int? unpublishedCommits;
  final Timestamp? unpublishedCommitDate;

  Map<String, dynamic>? _parsedPubspec;
  String? _pubspecDisplay;

  factory PackageInfo.from(QueryDocumentSnapshot<SnapshotItems> snapshot) {
    var data = snapshot.data();
    var maintainer = data.containsKey('maintainer') ? data['maintainer'] : '';
    return PackageInfo(
      name: data['name'],
      publisher: data['publisher'],
      maintainer: maintainer,
      repository: data['repository'],
      issueTracker:
          data.containsKey('issueTracker') ? data['issueTracker'] : null,
      version: Version.parse(data['version']),
      discontinued: data['discontinued'],
      unlisted: data['unlisted'],
      pubspec: data['pubspec'],
      analysisOptions:
          data.containsKey('analysisOptions') ? data['analysisOptions'] : null,
      publishedDate:
          data['publishedDate'] ?? Timestamp.fromMillisecondsSinceEpoch(0),
      unpublishedCommits: data['unpublishedCommits'],
      unpublishedCommitDate: data['unpublishedCommitDate'],
    );
  }

  PackageInfo({
    required this.name,
    required this.publisher,
    required this.maintainer,
    required this.repository,
    required this.issueTracker,
    required this.version,
    required this.discontinued,
    required this.unlisted,
    required this.pubspec,
    required this.analysisOptions,
    required this.publishedDate,
    required this.unpublishedCommits,
    required this.unpublishedCommitDate,
  });

  String? get sdkDep => (parsedPubspec['environment'] ?? const {})['sdk'];

  Map<String, dynamic> get parsedPubspec {
    if (_parsedPubspec == null) {
      yaml.YamlMap map = yaml.loadYaml(pubspec);
      _parsedPubspec = map.value.cast<String, dynamic>();
    }
    return _parsedPubspec!;
  }

  final RegExp _repoRegex =
      RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

  bool get isMonoRepo {
    if (repository == null) return false;

    var match = _repoRegex.firstMatch(repository!);
    return match != null && match.group(3)!.isNotEmpty;
  }

  String? get repoUrl {
    if (repository == null) return null;

    var match = _repoRegex.firstMatch(repository!);
    return match == null
        ? null
        : 'https://github.com/${match.group(1)}/${match.group(2)}';
  }

  String? get gitOrgName {
    if (repository == null) return null;

    var match = _repoRegex.firstMatch(repository!);
    return match?.group(1);
  }

  String? get gitRepoName {
    if (repository == null) return null;

    var match = _repoRegex.firstMatch(repository!);
    return match?.group(2);
  }

  String? get repoPath {
    if (repository == null) return null;

    var match = _repoRegex.firstMatch(repository!);
    var path = match?.group(3);
    if (path == null) {
      return null;
    } else if (path.startsWith('/tree/master')) {
      return path.substring('/tree/master'.length);
    } else if (path.startsWith('/tree/main')) {
      return path.substring('/tree/main'.length);
    } else {
      return path;
    }
  }

  String? get issuesUrl {
    if (issueTracker != null) {
      return issueTracker!;
    }
    if (repository != null) {
      return '$repository/issues';
    }
    return null;
  }

  int? get unpublishedDays {
    if (unpublishedCommits == null) {
      return null;
    }

    var date = unpublishedCommitDate;
    if (date == null) {
      return 0;
    }

    return DateTime.now().toUtc().difference(date.toDate()).inDays;
  }

  String get publishedDateDisplay {
    var str = publishedDate.toDate().toIso8601String();
    return str.split('T').first;
  }

  String get pubspecDisplay {
    if (_pubspecDisplay == null) {
      var printer = const YamlPrinter();
      _pubspecDisplay = printer.print(parsedPubspec);
    }
    return _pubspecDisplay!;
  }

  bool matchesFilter(String filter) {
    if (name.contains(filter)) {
      return true;
    }

    if (publisher.contains(filter) ||
        maintainer.contains(filter) ||
        (repository != null && repository!.contains(filter)) ||
        version.toString().contains(filter)) {
      return true;
    }

    if (pubspecDisplay.contains(filter) ||
        (analysisOptions?.contains(filter) ?? false)) {
      return true;
    }

    // todo: github actions, dependabot

    return false;
  }

  static TextStyle? getDisplayStyle(PackageInfo package) {
    const discontinuedStyle = TextStyle(color: Colors.grey);
    const unlistedStyle = TextStyle(fontStyle: FontStyle.italic);

    if (package.discontinued) {
      return discontinuedStyle;
    }
    return package.unlisted ? unlistedStyle : null;
  }

  static String getPublisherDisplayName(PackageInfo package) {
    String publisher = package.publisher;
    if (package.discontinued) {
      publisher += ' (discontinued)';
    }
    if (package.unlisted) {
      publisher += ' (unlisted)';
    }
    return publisher;
  }

  static int compareUnsyncedDays(PackageInfo a, PackageInfo b) {
    var diffDays = (a.unpublishedDays ?? -1) - (b.unpublishedDays ?? -1);
    if (diffDays == 0) {
      return (a.unpublishedCommits ?? 0) - (b.unpublishedCommits ?? 0);
    } else {
      return diffDays;
    }
  }

  static final _version100 = Version.parse('1.0.0');

  static ValidationResult? validateVersion(PackageInfo package) {
    if (package.discontinued) {
      return null;
    }

    if (package.publisher == 'dart.dev') {
      if (package.version < _version100) {
        return ValidationResult(
          'Package version for a dart.dev package is pre-release',
          Severity.warning,
        );
      }
    }
    return null;
  }

  static ValidationResult? validatePublishLatency(PackageInfo package) {
    if (package.discontinued) {
      return null;
    }

    if (package.unpublishedCommits == null) {
      return ValidationResult.info('Publish info not available');
    }

    if ((package.unpublishedDays ?? 0) > 180) {
      return ValidationResult.error(
        'Greater than 180 days of latency',
      );
    }

    if ((package.unpublishedDays ?? 0) > 60) {
      return ValidationResult.warning(
        'Greater than 60 days of latency',
      );
    }

    return null;
  }

  static ValidationResult? validateMaintainers(PackageInfo package) {
    if (package.discontinued) {
      return null;
    }

    if (package.publisher == 'dart.dev') {
      if (package.maintainer.isEmpty) {
        return ValidationResult('No package maintainer', Severity.error);
      }
    } else if (package.publisher == 'tools.dart.dev') {
      if (package.maintainer.isEmpty) {
        return ValidationResult('No package maintainer', Severity.warning);
      }
    } else if (package.publisher == 'labs.dart.dev') {
      if (package.maintainer.isEmpty) {
        return ValidationResult('No package maintainer', Severity.warning);
      }
    }
    return null;
  }

  static ValidationResult? validateRepositoryInfo(PackageInfo package) {
    if (package.discontinued) {
      return null;
    }

    if (package.repository == null) {
      return ValidationResult(
        'No repository url set',
        Severity.info,
      );
    } else if (package.repository!.endsWith('.git')) {
      return ValidationResult(
        "Repository url ends with '.git'",
        Severity.info,
      );
    } else if (package.repository!.contains('/blob/')) {
      return ValidationResult(
        "Repository url not well-formed (contains a 'blob' path)",
        Severity.info,
      );
    } else if (!package.repository!.startsWith('https://github.com/')) {
      return ValidationResult(
        "Repository url doesn't start with 'https://github.com/'",
        Severity.info,
      );
    }

    // Validate that the pubspec explicitly has a 'repository' key (not just a
    // homepage with a github link).
    final pubspec = package.parsedPubspec;
    if (!pubspec.containsKey('repository')) {
      return ValidationResult(
        "'repository' pubspec field not populated",
        Severity.info,
      );
    }

    return null;
  }

  static int compareWithStatus(PackageInfo a, PackageInfo b) {
    bool aDiscontinued = a.discontinued;
    bool bDiscontinued = b.discontinued;

    if (aDiscontinued == bDiscontinued) {
      bool aUnlisted = a.unlisted;
      bool bUnlisted = b.unlisted;

      if (aUnlisted == bUnlisted) {
        return a.name.compareTo(b.name);
      } else {
        return aUnlisted ? 1 : -1;
      }
    } else {
      return aDiscontinued ? 1 : -1;
    }
  }

  String debugDump() {
    StringBuffer buffer = StringBuffer();

    buffer.writeln('name: $name');
    buffer.writeln('publisher: $publisher');
    buffer.writeln('sdkDep: $sdkDep');
    buffer.writeln('maintainer: $maintainer');
    buffer.writeln('version: $version');
    buffer.writeln('repoUrl: $repoUrl');
    // buffer.writeln('monorepo: $isMonoRepo');
    if (isMonoRepo) {
      buffer.writeln('repoPath: $repoPath');
    }
    if (discontinued) {
      buffer.writeln('discontinued');
    }
    if (unlisted) {
      buffer.writeln('unlisted');
    }
    buffer.writeln('published: ${publishedDate.toDate().toIso8601String()}');

    buffer.writeln();

    var validation = validateVersion(this);
    if (validation != null) {
      buffer.writeln('validation issue: ${validation.message}');
    }
    validation = validateMaintainers(this);
    if (validation != null) {
      buffer.writeln('validation issue: ${validation.message}');
    }
    validation = validateRepositoryInfo(this);
    if (validation != null) {
      buffer.writeln('validation issue: ${validation.message}');
    }

    return buffer.toString().trim();
  }

  List<ValidationResult> validatePackage() {
    return [
      validateVersion(this),
      validateMaintainers(this),
      validateRepositoryInfo(this),
    ].whereType<ValidationResult>().toList();
  }

  @override
  bool operator ==(other) {
    return other is PackageInfo && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '$name $publisher $version';
}

class LogItem {
  final String entity;
  final String change;
  final Timestamp timestamp;

  LogItem({
    required this.entity,
    required this.change,
    required this.timestamp,
  });

  @override
  String toString() => '$entity: $change';
}

const _defaultPublishers = [
  'dart.dev',
  'tools.dart.dev',
  'labs.dart.dev',
];

// If these publishers are in the set we want to display, show them in this
// order (roughly, the SLO order).
const defaultPublisherSortOrder = [
  'dart.dev',
  'flutter.dev',
  'tools.dart.dev',
  'google.dev',
];

class Commit implements Comparable<Commit> {
  final String oid;
  final String message;
  final String user;
  final Timestamp committedDate;

  Commit({
    required this.oid,
    required this.message,
    required this.user,
    required this.committedDate,
  });

  String get oidDisplay => oid.substring(0, commitLength);

  factory Commit.from(QueryDocumentSnapshot<SnapshotItems> doc) {
    return Commit(
      oid: doc.get('oid'),
      message: doc.get('message'),
      user: doc.get('user'),
      committedDate: doc.get('committedDate'),
    );
  }

  @override
  int compareTo(Commit other) {
    return other.committedDate.compareTo(committedDate);
  }
}

class RepositoryInfo {
  final String org;
  final String name;
  final String? dependabotConfig;
  final String? actionsConfig;
  final String? actionsFile;

  RepositoryInfo({
    required this.org,
    required this.name,
    required this.dependabotConfig,
    required this.actionsConfig,
    required this.actionsFile,
  });

  String get repoName => '$org/$name';

  factory RepositoryInfo.from(QueryDocumentSnapshot<SnapshotItems> doc) {
    final data = doc.data();

    return RepositoryInfo(
      org: doc.get('org'),
      name: doc.get('name'),
      dependabotConfig: data.containsKey('dependabotConfig')
          ? doc.get('dependabotConfig')
          : null,
      actionsConfig:
          data.containsKey('actionsConfig') ? doc.get('actionsConfig') : null,
      actionsFile:
          data.containsKey('actionsFile') ? doc.get('actionsFile') : null,
    );
  }
}

class SdkDep {
  final String name;
  final String commit;
  final String repository;
  final Timestamp syncedCommitDate;
  final int unsyncedCommits;
  final Timestamp? unsyncedCommitDate;

  SdkDep({
    required this.name,
    required this.commit,
    required this.repository,
    required this.syncedCommitDate,
    required this.unsyncedCommits,
    required this.unsyncedCommitDate,
  });

  int? get unsyncedDays {
    var date = unsyncedCommitDate;
    if (date == null) {
      return null;
    }

    return DateTime.now().toUtc().difference(date.toDate()).inDays;
  }

  String get syncLatencyDescription {
    var latencyDays = unsyncedDays;
    if (latencyDays == null) {
      return '';
    }
    return '$unsyncedCommits commits, $unsyncedDays days';
  }

  static int compareUnsyncedDays(SdkDep a, SdkDep b) {
    var dayDiff = (a.unsyncedDays ?? 0) - (b.unsyncedDays ?? 0);
    if (dayDiff == 0) {
      return (a.unsyncedCommits) - (b.unsyncedCommits);
    } else {
      return dayDiff;
    }
  }

  static ValidationResult? validateSyncLatency(SdkDep dep) {
    if ((dep.unsyncedDays ?? 0) > 365) {
      return ValidationResult.error(
        'Greater than 365 days of latency',
      );
    }

    if ((dep.unsyncedDays ?? 0) > 30) {
      return ValidationResult.warning(
        'Greater than 30 days of latency',
      );
    }

    return null;
  }

  @override
  String toString() => '$repository $commit';
}

class Google3Dep {
  final String name;
  final bool firstParty;
  final String? commit;
  // We don't use this field.
  final Timestamp? lastUpdated;
  final int pendingCommits;
  // TODO: Instead, here we want a date for the oldest unsynced commit
  final int? latencySeconds;

  Google3Dep({
    required this.name,
    required this.firstParty,
    required this.commit,
    required this.lastUpdated,
    required this.pendingCommits,
    required this.latencySeconds,
  });

  int? get unsyncedDays {
    const secondsInDays = 24 * 60 * 60;

    if (latencySeconds == null) {
      return null;
    }

    return latencySeconds! ~/ secondsInDays;
  }

  String get syncLatencyDescription {
    if (pendingCommits == 0) return '';

    var latencyDays = unsyncedDays;
    if (latencyDays == null) return '';

    return '$pendingCommits commits, $unsyncedDays days';
  }

  static int compareUnsyncedDays(Google3Dep a, Google3Dep b) {
    var dayDiff = (a.unsyncedDays ?? 0) - (b.unsyncedDays ?? 0);
    if (dayDiff == 0) {
      return a.pendingCommits - b.pendingCommits;
    } else {
      return dayDiff;
    }
  }

  static ValidationResult? validateSyncLatency(Google3Dep dep) {
    if ((dep.unsyncedDays ?? 0) > 365) {
      return ValidationResult.error(
        'Greater than 365 days of latency',
      );
    }

    if ((dep.unsyncedDays ?? 0) > 30) {
      return ValidationResult.warning(
        'Greater than 30 days of latency',
      );
    }

    return null;
  }

  @override
  String toString() => '$name $commit';
}
