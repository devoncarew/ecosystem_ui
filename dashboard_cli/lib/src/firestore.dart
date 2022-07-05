import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'google3.dart';
import 'pub.dart';
import 'sdk.dart';
import 'sheets.dart';
import 'utils.dart';

class Firestore {
  final Config config = Config();

  late AutoRefreshingAuthClient _client;
  late final FirestoreApi firestore;

  Firestore();

  Future setup() async {
    // Set the GOOGLE_APPLICATION_CREDENTIALS env var to the path containing the
    // cloud console service account key.

    // print("env['GOOGLE_APPLICATION_CREDENTIALS']="
    //     "${io.Platform.environment['GOOGLE_APPLICATION_CREDENTIALS']}");

    _client = await clientViaApplicationDefaultCredentials(
      scopes: [FirestoreApi.datastoreScope],
    );
    firestore = FirestoreApi(_client);
  }

  ProjectsDatabasesDocumentsResource get documents =>
      firestore.projects.databases.documents;

  String get databaseId => 'projects/${config.projectId}/databases/(default)';
  String get documentsPath => '$databaseId/documents';

  String getDocumentName(String collection, String entity) {
    return '$documentsPath/$collection/$entity';
  }

  /// Return the publishers we should care about from the firebase datastore.
  Future<List<String>> queryPublishers() async {
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'publishers',
    );
    return response.documents!.map((Document doc) {
      // Return the last segment of the document name.
      return doc.name!.split('/').last;
    }).toList();
  }

  /// Return all the pubspec reported repositories for the packages for the
  /// given set of publishers.
  ///
  /// By default, repositories for discontinued packages are not reported.
  Future<List<String>> queryRepositoriesForPublishers(
    Set<String> publishers, {
    bool excludeDiscontinued = true,
  }) async {
    final Set<String> repositories = {};
    ListDocumentsResponse? response;
    do {
      response = await documents.list(
        documentsPath,
        'packages',
        pageToken: response?.nextPageToken,
      );

      for (var doc in response.documents!) {
        var publisher = doc.fields!['publisher']?.stringValue;
        var repository = doc.fields!['repository']?.stringValue;
        var discontinued = doc.fields!['discontinued']?.booleanValue ?? false;
        if (excludeDiscontinued && discontinued) {
          continue;
        }
        if (publishers.contains(publisher)) {
          if (repository != null && repository.isNotEmpty) {
            repositories.add(repository);
          }
        }
      }
    } while (response.nextPageToken != null);

    return repositories.toList()..sort();
  }

  Future convertOlderStats() async {
    final List<FirestorePackageInfo> packages = [];
    ListDocumentsResponse? response;
    do {
      response = await documents.list(
        documentsPath,
        'stats',
        pageToken: response?.nextPageToken,
      );

      // final Document doc = Document(
      //   fields: {
      //     'category': valueStr(category),
      //     'stat': valueStr(stat),
      //     'value': valueInt(value),
      //     'timestamp': Value(timestampValue: timestampUtc.toIso8601String()),
      //   },
      // );

      for (var doc in response.documents!) {
        final fields = doc.fields!;

        String field(String name) {
          return fields[name]!.stringValue!;
        }

        DateTime? parseTimestamp(String? val) {
          return val == null ? null : DateTime.parse(val);
        }

        String category = field('category');
        String stat = field('stat');
        int value = int.parse(fields['value']!.integerValue!);
        DateTime timestamp =
            parseTimestamp(fields['timestamp']!.timestampValue!)!;

        print('$category,$stat,$value ==>');

        // [publisher.unownedCount,dart.dev] => [package.count,unowned,]
        // [publisher.packageCount,dart.dev] => [package.count,count,]
        if (category == 'publisher.unownedCount') {
          await logStat(
            category: 'package.count',
            stat: 'unowned',
            detail: stat,
            value: value,
            timestampUtc: timestamp,
          );
        } else if (category == 'publisher.packageCount') {
          await logStat(
            category: 'package.count',
            stat: 'count',
            detail: stat,
            value: value,
            timestampUtc: timestamp,
          );
        }

        // [publisher.publishLatency.p50,dart.dev] => [package.latency,p50]
        // [publisher.publishLatency.p90,dart.dev] => [package.latency,p90]
        else if (category == 'publisher.publishLatency.p50') {
          await logStat(
            category: 'package.latency',
            stat: 'p50',
            detail: stat,
            value: value,
            timestampUtc: timestamp,
          );
        } else if (category == 'publisher.publishLatency.p90') {
          await logStat(
            category: 'package.latency',
            stat: 'p90',
            detail: stat,
            value: value,
            timestampUtc: timestamp,
          );
        }

        // [sdk,depsCount] => [sdk.deps,count]
        else if (category == 'sdk' && stat == 'depsCount') {
          await logStat(
            category: 'sdk.deps',
            stat: 'count',
            value: value,
            timestampUtc: timestamp,
          );
        }

        // [sdk,syncLatency.p50] => [sdk.latency,p50]
        // [sdk,syncLatency.p90] => [sdk.latency,p90]
        else if (category == 'sdk' && stat == 'syncLatency.p50') {
          await logStat(
            category: 'sdk.latency',
            stat: 'p50',
            value: value,
            timestampUtc: timestamp,
          );
        } else if (category == 'sdk' && stat == 'syncLatency.p90') {
          await logStat(
            category: 'sdk.latency',
            stat: 'p90',
            value: value,
            timestampUtc: timestamp,
          );
        } else {
          print('  not found');
          continue;
        }

        await documents.delete(doc.name!);
      }
    } while (response.nextPageToken != null);

    return packages;
  }

  Future<List<FirestorePackageInfo>> queryPackagesForPublishers(
    List<String> publishers, {
    bool excludeDiscontinued = true,
  }) async {
    final List<FirestorePackageInfo> packages = [];
    ListDocumentsResponse? response;
    do {
      response = await documents.list(
        documentsPath,
        'packages',
        pageToken: response?.nextPageToken,
      );

      for (var doc in response.documents!) {
        var package = FirestorePackageInfo.from(doc);

        if (excludeDiscontinued && package.discontinued) {
          continue;
        }
        if (publishers.contains(package.publisher)) {
          packages.add(package);
        }
      }
    } while (response.nextPageToken != null);

    return packages;
  }

  Future<Map<String, Value>?> getPackageInfo(String packageName) async {
    try {
      final packagePath = getDocumentName('packages', packageName);
      var result = await documents.get(packagePath);
      return result.fields;
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        // Ignore these - we know some documents won't yet exist.
        return null;
      }
      print(e);
      return null;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<Map<String, Value>?> getSdkRepositoryInfo(String repoName) async {
    try {
      final packagePath = getDocumentName('sdk_deps', repoName);
      var result = await documents.get(packagePath);
      return result.fields;
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        // Ignore these - we know some documents won't yet exist.
        return null;
      }
      print(e);
      return null;
    } catch (e) {
      print(e);
      return null;
    }
  }

  // Future<Map<String, Value>?> getGoogle3RepositoryInfo(String repoName) async {
  //   try {
  //     final packagePath = getDocumentName('google3', repoName);
  //     var result = await documents.get(packagePath);
  //     return result.fields;
  //   } on DetailedApiRequestError catch (e) {
  //     if (e.status == 404) {
  //       // Ignore these - we know some documents won't yet exist.
  //       return null;
  //     }
  //     print(e);
  //     return null;
  //   } catch (e) {
  //     print(e);
  //     return null;
  //   }
  // }

  Future<Document> updatePackageInfo(
    String packageName, {
    required String publisher,
    required PackageInfo packageInfo,
    String? analysisOptions,
  }) async {
    var repository = packageInfo.repository;
    if (repository == null) {
      var homepage = packageInfo.homepage;
      if (homepage != null &&
          homepage.startsWith('https://github.com/') &&
          !homepage.endsWith('.git')) {
        repository = homepage;
      }
    }

    final Document doc = Document(
      fields: {
        'name': valueStr(packageName),
        'publisher': valueStr(publisher),
        'version': valueStr(packageInfo.version),
        'repository': valueStrNullable(repository),
        'issueTracker': valueStrNullable(packageInfo.issueTracker),
        'issueCount': valueIntNullable(packageInfo.issueCount),
        'discontinued': valueBool(packageInfo.isDiscontinued),
        'unlisted': valueBool(packageInfo.isUnlisted),
        'pubspec': valueStr(packageInfo.encodedPubspec),
        'publishedDate': Value(timestampValue: packageInfo.published),
        'unpublishedCommits': packageInfo.unpublishedCommits == null
            ? valueNull()
            : valueInt(packageInfo.unpublishedCommits!),
        'unpublishedCommitDate': packageInfo.unpublishedCommitDate == null
            ? valueNull()
            : Value(
                timestampValue:
                    packageInfo.unpublishedCommitDate!.toIso8601String()),
        if (analysisOptions != null)
          'analysisOptions': valueStr(analysisOptions),
      },
    );

    // Make sure we don't write over fields that we're not updating here (like
    // the 'maintainers' field).
    final DocumentMask mask = DocumentMask(
      fieldPaths: doc.fields!.keys.toList(),
    );

    // todo: handle error conditions
    return await documents.patch(
      doc,
      getDocumentName('packages', packageName),
      updateMask_fieldPaths: mask.fieldPaths,
    );
  }

  Future log({required String entity, required String change}) async {
    final Document doc = Document(
      fields: {
        'entity': valueStr(entity),
        'change': valueStr(change),
        'timestamp': Value(
          timestampValue: DateTime.now().toUtc().toIso8601String(),
        ),
      },
    );

    // todo: handle error conditions
    await documents.createDocument(doc, documentsPath, 'log');
  }

  Future logStat({
    required String category,
    required String stat,
    String? detail,
    required int value,
    DateTime? timestampUtc,
  }) async {
    timestampUtc ??= DateTime.now().toUtc();

    final Document doc = Document(
      fields: {
        'category': valueStr(category),
        'stat': valueStr(stat),
        'detail': valueStrNullable(detail),
        'value': valueInt(value),
        'timestamp': Value(timestampValue: timestampUtc.toIso8601String()),
      },
    );

    // todo: handle error conditions
    await documents.createDocument(doc, documentsPath, 'stats');
  }

  // Future<Map<String, Value>?> getRepoInfo(String repoPath) async {
  //   try {
  //     var repo = RepositoryInfo(path: repoPath);
  //     final repositoryPath =
  //         getDocumentName('repositories', repo.firestoreEntityId);
  //     var result = await documents.get(repositoryPath);
  //     return result.fields;
  //   } catch (e) {
  //     print(e);
  //     return null;
  //   }
  // }

  void close() {
    _client.close();
  }

  /// Remove the publisher field for any package which claims to be part of the
  /// given publisher, but is no longer.
  Future unsetPackagePublishers(
    String publisher, {
    required List<String> currentPackages,
  }) async {
    // todo: implement this
    // todo: query all packages where publisher is the given publisher
    //documents.runQuery();
  }

  Future<List<String>> getSdkDependencies() async {
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'sdk_deps',
      pageSize: 100,
    );
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future<List<String>> getGoogle3Dependencies() async {
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'google3',
      pageSize: 200,
    );
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future<List<FirestoreSdkDep>> getSdkDeps() async {
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'sdk_deps',
      pageSize: 100,
    );
    return response.documents!.map((Document doc) {
      return FirestoreSdkDep.from(doc);
    }).toList();
  }

  Future updateSdkDependencies(
    List<SdkDependency> sdkDependencies, {
    required Logger logger,
  }) async {
    // Read current deps
    final List<String> currentDeps = await getSdkDependencies();

    // Update commit info
    logger.write('');
    logger.write('updating dep info...');

    for (var dep in sdkDependencies) {
      logger
        ..write('  ${dep.repository}')
        ..indent();
      await updateSdkDependency(dep);
      logger.outdent();
    }

    // Log sdk dep additions.
    Set<String> newDeps = Set.from(sdkDependencies.map((p) => p.name))
      ..removeAll(currentDeps);
    for (var dep in newDeps) {
      logger.write('  adding $dep');
      await log(entity: 'SDK dep', change: 'added $dep');
    }

    // Remove any repos which are no longer deps.
    Set<String> oldDeps = currentDeps.toSet()
      ..removeAll(sdkDependencies.map((p) => p.name));
    for (var dep in oldDeps) {
      logger.write('  removing $dep');
      await documents.delete(getDocumentName('sdk_deps', dep));
      await log(entity: 'SDK dep', change: 'removing $dep');
    }
  }

  Future updateGoogle3Dependencies(
    List<Google3Dependency> google3Dependencies, {
    required Logger logger,
  }) async {
    // Read current deps
    final List<String> currentDeps = await getGoogle3Dependencies();

    // Update commit info
    logger.write('');
    logger.write('updating dep info...');

    for (var dep in google3Dependencies) {
      logger
        ..write('  ${dep.name}')
        ..indent();
      await updateGoogle3Dependency(dep);
      logger.outdent();
    }

    // Log google3 dep additions.
    Set<String> newDeps = Set.from(google3Dependencies.map((p) => p.name))
      ..removeAll(currentDeps);
    for (var dep in newDeps) {
      logger.write('  adding $dep');
      await log(entity: 'Google3 dep', change: 'added $dep');
    }

    // Remove any repos which are no longer deps.
    Set<String> oldDeps = currentDeps.toSet()
      ..removeAll(google3Dependencies.map((p) => p.name));
    for (var dep in oldDeps) {
      logger.write('  removing $dep');
      await documents.delete(getDocumentName('google3', dep));
      await log(entity: 'Google3 dep', change: 'removing $dep');
    }
  }

  Future updateMaintainers(
    List<PackageMaintainer> maintainers, {
    required Logger logger,
  }) async {
    logger.write('Upating owners...');

    for (var pkg in maintainers) {
      logger
        ..write('  $pkg')
        ..indent();

      // todo: log ownership changes
      final Document doc = Document(
        fields: {
          'maintainer': valueStr(pkg.maintainer ?? ''),
        },
      );
      final DocumentMask mask = DocumentMask(
        fieldPaths: doc.fields!.keys.toList(),
      );

      // todo: handle error conditions
      await documents.patch(
        doc,
        getDocumentName('packages', pkg.packageName),
        updateMask_fieldPaths: mask.fieldPaths,
      );

      logger.outdent();
    }
  }

  // Future updateRepositoryInfo(RepositoryInfo repo) async {
  //   final Document doc = Document(
  //     fields: {
  //       'org': valueStr(repo.org),
  //       'name': valueStr(repo.name),
  //       'actionsConfig': valueStrNullable(repo.actionsConfig),
  //       'actionsFile': valueStrNullable(repo.actionsFile),
  //       'dependabotConfig': valueStrNullable(repo.dependabotConfig),
  //     },
  //   );

  //   final repositoryPath =
  //       getDocumentName('repositories', repo.firestoreEntityId);

  //   // todo: handle error conditions
  //   await documents.patch(doc, repositoryPath);
  // }

  Future updateSdkDependency(SdkDependency dependency) async {
    var existingInfo = await getSdkRepositoryInfo(dependency.name);
    var commit = dependency.commitInfo!;

    String? unsyncedTimestamp;
    if (dependency.unsyncedCommits.isNotEmpty) {
      dependency.unsyncedCommits.sort();
      var oldest = dependency.unsyncedCommits.last;
      unsyncedTimestamp = oldest.committedDate.toIso8601String();
    }

    // print('  unsynced=$unsyncedTimestamp');

    final Document doc = Document(
      fields: {
        'name': valueStr(dependency.name),
        'commit': valueStr(dependency.commit ?? ''),
        'repository': valueStr(dependency.repository),
        'syncedCommitDate': Value(
          timestampValue: commit.committedDate.toIso8601String(),
        ),
        'unsyncedCommits': valueInt(dependency.unsyncedCommits.length),
        'unsyncedCommitDate': unsyncedTimestamp == null
            ? valueNull()
            : Value(timestampValue: unsyncedTimestamp),
      },
    );

    // todo: handle error conditions
    var updatedInfo = await documents.patch(
      doc,
      getDocumentName('sdk_deps', dependency.name),
    );

    const ignoreKeys = {
      'syncedCommitDate',
      'unsyncedCommits',
      'unsyncedCommitDate',
    };

    if (existingInfo != null) {
      var updatedFields = updatedInfo.fields!;
      for (var field in existingInfo.keys) {
        if (updatedFields.keys.contains(field) &&
            !compareValues(existingInfo[field]!, updatedFields[field]!)) {
          if (ignoreKeys.contains(field)) {
            continue;
          }

          log(
            entity: 'SDK dep package:${dependency.name}',
            change: '$field => ${printValue(updatedFields[field]!)}',
          );
        }
      }
    }
  }

  Future updateGoogle3Dependency(Google3Dependency dependency) async {
    // var existingInfo = await getGoogle3RepositoryInfo(
    //   firestoreEntityEncode(dependency.name),
    // );
    // var commit = dependency.commitInfo!;

    // String? unsyncedTimestamp;
    // if (dependency.unsyncedCommits.isNotEmpty) {
    //   dependency.unsyncedCommits.sort();
    //   var oldest = dependency.unsyncedCommits.last;
    //   unsyncedTimestamp = oldest.committedDate.toIso8601String();
    // }

    // final String name;
    // final bool firstParty;
    // final String commit;
    // final DateTime lastUpdated;
    // final int pendingCommits;
    // final int latencySeconds;

    final Document doc = Document(
      fields: {
        'name': valueStr(dependency.name),
        'firstParty': valueBool(dependency.firstParty),
        'commit': valueStrNullable(dependency.commit),
        'lastUpdated': dependency.lastUpdated == null
            ? valueNull()
            : Value(
                timestampValue:
                    dependency.lastUpdated!.toUtc().toIso8601String(),
              ),
        'pendingCommits': valueInt(dependency.pendingCommits),
        'latencySeconds': dependency.latencySeconds == null
            ? valueNull()
            : valueInt(dependency.latencySeconds!),
      },
    );

    // todo: handle error conditions
    /*var updatedInfo =*/ await documents.patch(
      doc,
      getDocumentName(
        'google3',
        firestoreEntityEncode(dependency.name),
      ),
    );

    // const ignoreKeys = {
    //   'syncedCommitDate',
    //   'unsyncedCommits',
    //   'unsyncedCommitDate',
    // };

    // // Record any interesting changes in the log.
    // if (existingInfo != null) {
    //   var updatedFields = updatedInfo.fields!;
    //   for (var field in existingInfo.keys) {
    //     if (updatedFields.keys.contains(field) &&
    //         !compareValues(existingInfo[field]!, updatedFields[field]!)) {
    //       if (ignoreKeys.contains(field)) {
    //         continue;
    //       }

    //       log(
    //         entity: 'Google3 dep: ${dependency.orgAndName}',
    //         change: '$field => ${printValue(updatedFields[field]!)}',
    //       );
    //     }
    //   }
    // }
  }
}

class Config {
  final String projectId = 'dart-package-dashboard';
}

Value valueStr(String value) => Value(stringValue: value);
Value valueStrNullable(String? value) =>
    value == null ? valueNull() : Value(stringValue: value);
Value valueBool(bool value) => Value(booleanValue: value);
Value valueInt(int value) => Value(integerValue: value.toString());
Value valueIntNullable(int? value) =>
    value == null ? valueNull() : Value(integerValue: value.toString());
Value valueNull() => Value(nullValue: 'NULL_VALUE');

class FirestorePackageInfo {
  final String name;
  final String? publisher;
  final String? maintainer;
  final String? repository;
  final bool discontinued;
  final bool unlisted;
  final int? unpublishedCommits;
  final DateTime? unpublishedCommitDate;

  FirestorePackageInfo({
    required this.name,
    required this.publisher,
    required this.maintainer,
    required this.repository,
    required this.discontinued,
    required this.unlisted,
    required this.unpublishedCommits,
    required this.unpublishedCommitDate,
  });

  factory FirestorePackageInfo.from(Document doc) {
    final fields = doc.fields!;

    String? nullableField(String name) {
      if (!fields.containsKey(name)) {
        return null;
      }
      return fields[name]!.stringValue;
    }

    int? parseInt(String? val) {
      return val == null ? null : int.parse(val);
    }

    DateTime? parseTimestamp(String? val) {
      return val == null ? null : DateTime.parse(val);
    }

    return FirestorePackageInfo(
      name: nullableField('name')!,
      publisher: nullableField('publisher'),
      maintainer: nullableField('maintainer'),
      repository: nullableField('repository'),
      discontinued: fields['discontinued']!.booleanValue!,
      unlisted: fields['unlisted']!.booleanValue!,
      unpublishedCommits: parseInt(fields['unpublishedCommits']?.integerValue),
      unpublishedCommitDate:
          parseTimestamp(fields['unpublishedCommitDate']?.timestampValue),
    );
  }

  int? get publishLatencyDays {
    // No info.
    if (unpublishedCommits == null) {
      return null;
    }

    // Up to date.
    var date = unpublishedCommitDate;
    if (date == null) {
      return 0;
    }

    return DateTime.now().toUtc().difference(date).inDays;
  }
}

class FirestoreSdkDep {
  final String name;
  final String repository;
  final String commit;
  final DateTime syncedCommitDate;
  final DateTime? unsyncedCommitDate;
  final int? unsyncedCommits;

  FirestoreSdkDep({
    required this.name,
    required this.repository,
    required this.commit,
    required this.syncedCommitDate,
    required this.unsyncedCommitDate,
    required this.unsyncedCommits,
  });

  factory FirestoreSdkDep.from(Document doc) {
    final fields = doc.fields!;

    String? nullableField(String name) {
      if (!fields.containsKey(name)) {
        return null;
      }
      return fields[name]!.stringValue;
    }

    int? parseInt(String? val) {
      return val == null ? null : int.parse(val);
    }

    DateTime? parseTimestamp(String? val) {
      return val == null ? null : DateTime.parse(val);
    }

    return FirestoreSdkDep(
      name: nullableField('name')!,
      repository: nullableField('repository')!,
      commit: nullableField('commit')!,
      syncedCommitDate:
          parseTimestamp(fields['syncedCommitDate']?.timestampValue)!,
      unsyncedCommitDate:
          parseTimestamp(fields['unsyncedCommitDate']?.timestampValue),
      unsyncedCommits: parseInt(fields['unsyncedCommits']?.integerValue),
    );
  }

  int get syncLatencyDays {
    // Up to date.
    if (unsyncedCommits == 0) {
      return 0;
    }

    var date = unsyncedCommitDate;
    if (date == null) {
      return 0;
    } else {
      return DateTime.now().toUtc().difference(date).inDays;
    }
  }
}
