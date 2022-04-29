// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:pub_semver/pub_semver.dart';
import 'package:collection/collection.dart';

import 'table.dart';

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
      // todo: read sdk data
      // todo: read repository data
      // todo: read google3 data
      await _initPackagesData();
      await _initChangelog();
      await _initRepositories();
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

  Future<List<Commit>> getCommitsFor({
    required String org,
    required String repo,
    int quantity = 100,
  }) {
    return FirebaseFirestore.instance
        .collection('repositories')
        .doc('$org%2F$repo')
        .collection('commits')
        .orderBy('committedDate', descending: true)
        .limit(quantity)
        .get()
        .then((QuerySnapshot<SnapshotItems> snapshot) {
      return snapshot.docs.map((doc) => Commit.from(doc)).toList();
    });
  }

  final Map<String, ValueNotifier<List<PackageInfo>>> _publisherNotifiers = {};

  /// todo: doc
  ValueListenable<List<LogItem>> get changeLogItems => _changeLogItems;
  final ValueNotifier<List<LogItem>> _changeLogItems = ValueNotifier([]);

  Future _initPublishers() async {
    // Listen to the publishers collection.
    FirebaseFirestore.instance
        .collection('publishers')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
      var result = snapshot.docs.map((doc) => doc.id).toList()..sort();
      _publishers.value = result;
    });
  }

  /// todo: doc
  ValueListenable<List<RepositoryInfo>> get repositories => _repositories;
  final ValueNotifier<List<RepositoryInfo>> _repositories = ValueNotifier([]);

  RepositoryInfo? getRepositoryForPackage(PackageInfo package) {
    return repositories.value.firstWhereOrNull((repo) {
      return repo.org == package.gitOrgName && repo.name == package.gitRepoName;
    });
  }

  Future _initRepositories() async {
    firestore
        .collection('repositories')
        .snapshots()
        .listen((QuerySnapshot<SnapshotItems> snapshot) {
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
      Map<String, List<PackageInfo>> packageMap = {};

      // todo: try doing a deep compare here

      for (var data in snapshot.docs) {
        var package = PackageInfo.from(data);
        packageMap.putIfAbsent(package.publisher, () => []);
        packageMap[package.publisher]!.add(package);
      }

      for (var publisher in packageMap.keys) {
        _publisherNotifiers.putIfAbsent(publisher, () => ValueNotifier([]));
        _publisherNotifiers[publisher]!.value = packageMap[publisher]!;
      }

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
}

class PackageInfo {
  final String name;
  final String publisher;
  final String maintainer;
  final String repository;
  final Version version;
  final bool discontinued;
  final bool unlisted;
  final String pubspec;
  final Timestamp published;

  // todo: monorepo?
  // todo: repoPath

  Map<String, dynamic>? _parsedPubspec;

  factory PackageInfo.from(QueryDocumentSnapshot<SnapshotItems> snapshot) {
    var data = snapshot.data();
    var maintainer = data.containsKey('maintainer') ? data['maintainer'] : '';
    return PackageInfo(
      name: data['name'],
      publisher: data['publisher'],
      maintainer: maintainer,
      repository: data['repository'],
      version: Version.parse(data['version']),
      discontinued: data['discontinued'],
      unlisted: data['unlisted'],
      pubspec: data['pubspec'],
      published: data['published'] ?? Timestamp.fromMillisecondsSinceEpoch(0),
    );
  }

  PackageInfo({
    required this.name,
    required this.publisher,
    required this.maintainer,
    required this.repository,
    required this.version,
    required this.discontinued,
    required this.unlisted,
    required this.pubspec,
    required this.published,
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
    var match = _repoRegex.firstMatch(repository);
    return match != null && match.group(3)!.isNotEmpty;
  }

  String? get repoUrl {
    var match = _repoRegex.firstMatch(repository);
    return match == null
        ? null
        : 'https://github.com/${match.group(1)}/${match.group(2)}';
  }

  String? get gitOrgName {
    var match = _repoRegex.firstMatch(repository);
    return match?.group(1);
  }

  String? get gitRepoName {
    var match = _repoRegex.firstMatch(repository);
    return match?.group(2);
  }

  String? get repoPath {
    var match = _repoRegex.firstMatch(repository);
    var path = match?.group(3);
    if (path == null) {
      return null;
    } else if (path.startsWith('/tree/master/')) {
      return path.substring('/tree/master/'.length);
    } else {
      return path;
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

    if (package.repository.isEmpty) {
      return ValidationResult(
        'No repository url set',
        Severity.info,
      );
    } else if (package.repository.endsWith('.git')) {
      return ValidationResult(
        "Repository url ends with '.git'",
        Severity.info,
      );
    } else if (package.repository.contains('/blob/')) {
      return ValidationResult(
        "Repository url not well-formed (contains a 'blob' path)",
        Severity.info,
      );
    } else if (!package.repository.startsWith('https://github.com/')) {
      return ValidationResult(
        "Repository url doesn't start with 'https://github.com/'",
        Severity.info,
      );
    }

    // Validate that the pubspec explicitly has a 'repository' key (not just a
    // homepage with a github link).
    final pubspec = package.parsedPubspec;
    if (pubspec.containsKey('homepage') && !pubspec.containsKey('repository')) {
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
    buffer.writeln('published: ${published.toDate().toIso8601String()}');

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

  String get oidDisplay => oid.substring(0, 7);

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
