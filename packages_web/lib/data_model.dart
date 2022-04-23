import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:pub_semver/pub_semver.dart';

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
        .orderBy('timestamp')
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
  });

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
