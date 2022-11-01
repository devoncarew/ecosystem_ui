import 'package:collection/collection.dart';
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

  Profiler profiler;

  Firestore({required this.profiler});

  Future setup() async {
    // Note: for local development, set the GOOGLE_APPLICATION_CREDENTIALS env
    // var to the path containing the cloud console service account key.

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
    ListDocumentsResponse response = await documentsList(
      documentsPath,
      'publishers',
    );
    return response.documents!.map((Document doc) {
      // Return the last segment of the document name.
      return doc.name!.split('/').last;
    }).toList();
  }

  Future<List<String>> queryRespoitories() async {
    ListDocumentsResponse response = await documentsList(
      documentsPath,
      'repositories',
    );
    return response.documents!.map((Document doc) {
      // Return the last segment of the document name.
      var name = doc.name!.split('/').last;
      name = name.replaceAll('%2F', '/');
      return name;
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
      var result = await documentsGet(packagePath);
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
      var result = await documentsGet(packagePath);
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

  Future<Document> documentsGet(String name) async {
    return profiler.run('firebase.read', documents.get(name));
  }

  Future<Map<String, Value>?> getGoogle3DepInfo(String packageName) async {
    try {
      final docPath =
          getDocumentName('google3', firestoreEntityEncode(packageName));
      var result = await documents.get(docPath);
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

  Future<Document> updatePackageInfo(
    String packageName, {
    required String publisher,
    required PackageInfo packageInfo,
    // String? analysisOptions,
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
        'githubVersion': valueStrNullable(packageInfo.githubVersion),
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
        'points': valueIntNullable(packageInfo.metrics?.points),
        'popularity': valueIntNullable(packageInfo.metrics?.popularity),
        'likes': valueIntNullable(packageInfo.metrics?.likes),
      },
    );

    // Make sure we don't write over fields that we're not updating here (like
    // the 'maintainers' field).
    final DocumentMask mask = DocumentMask(
      fieldPaths: doc.fields!.keys.toList(),
    );

    // todo: handle error conditions
    return await documentsPatch(
      doc,
      getDocumentName('packages', packageName),
      updateMaskFieldPaths: mask.fieldPaths,
    );
  }

  Future<List<FirestoreRepositoryInfo>> getFirestoreRepositoryInfo() async {
    int? parseInt(String? val) {
      return val == null ? null : int.parse(val);
    }

    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'repositories',
      pageSize: 300,
    );

    return response.documents!.map((Document doc) {
      final fields = doc.fields!;

      return FirestoreRepositoryInfo(
        org: fields['org']!.stringValue!,
        name: fields['name']!.stringValue!,
        workflows: fields['workflows']!.stringValue,
        hasDependabot: fields['hasDependabot']!.booleanValue!,
        issueCount: parseInt(fields['issueCount']!.integerValue)!,
        prCount: parseInt(fields['prCount']!.integerValue)!,
        defaultBranchName: fields['defaultBranchName']!.stringValue!,
      );
    }).toList();
  }

  Future<Document> updateRepositoryInfo(FirestoreRepositoryInfo repo) async {
    final Document doc = Document(
      fields: {
        'name': valueStr(repo.name),
        'org': valueStr(repo.org),
        'workflows': valueStrNullable(repo.workflows),
        'hasDependabot': valueBool(repo.hasDependabot),
        'issueCount': valueInt(repo.issueCount),
        'prCount': valueInt(repo.prCount),
        'defaultBranchName': valueStr(repo.defaultBranchName),
      },
    );

    return await documentsPatch(
      doc,
      getDocumentName('repositories', repo.orgAndName.replaceAll('/', '%2F')),
    );
  }

  Future removeRepo(String repoPath) async {
    await documents.delete(
      getDocumentName('repositories', repoPath.replaceAll('/', '%2F')),
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
    await profiler.run(
      'firebase.create',
      documents.createDocument(doc, documentsPath, 'log'),
    );
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
    ListDocumentsResponse response = await documentsList(
      documentsPath,
      'sdk_deps',
      pageSize: 100,
    );
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future<ListDocumentsResponse> documentsList(
    String parent,
    String collectionId, {
    int? pageSize,
  }) {
    return profiler.run('firebase.read',
        documents.list(parent, collectionId, pageSize: pageSize));
  }

  Future<List<String>> getGoogle3DepNames() async {
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'google3',
      pageSize: 200,
    );
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future<List<Google3Dependency>> getGoogle3Deps() async {
    int? parseInt(String? val) {
      return val == null ? null : int.parse(val);
    }

    DateTime? parseTimestamp(String? val) {
      return val == null ? null : DateTime.parse(val);
    }

    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'google3',
      pageSize: 300,
    );

    return response.documents!.map((Document doc) {
      final fields = doc.fields!;

      return Google3Dependency(
        name: fields['name']!.stringValue!,
        firstParty: fields['firstParty']!.booleanValue!,
        commit: fields['commit']!.stringValue,
        pendingCommits: parseInt(fields['pendingCommits']!.integerValue)!,
        latencyDate: parseTimestamp(fields['latencyDate']?.timestampValue),
        hasCopybaraConfig: fields['hasCopybaraConfig']!.booleanValue ?? false,
        usesCopybaraService:
            fields['usesCopybaraService']!.booleanValue ?? false,
        error: fields['error']?.stringValue,
      );
    }).toList();
  }

  Future<List<FirestoreSdkDep>> getSdkDeps() async {
    ListDocumentsResponse response = await documentsList(
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
      await log(entity: '[sdk]', change: 'added $dep');
    }

    // Remove any repos which are no longer deps.
    Set<String> oldDeps = currentDeps.toSet()
      ..removeAll(sdkDependencies.map((p) => p.name));
    for (var dep in oldDeps) {
      logger.write('  removing $dep');
      await documents.delete(getDocumentName('sdk_deps', dep));
      await log(entity: '[sdk]', change: 'removing $dep');
    }
  }

  Future updateGoogle3Dependencies(
    List<Google3Dependency> google3Dependencies, {
    required Logger logger,
  }) async {
    // Read current deps
    final List<String> currentDeps = await getGoogle3DepNames();

    // Update commit info
    logger.write('');
    logger.write('updating dep info...');

    var sdkCommit = google3Dependencies
        .firstWhereOrNull((dep) => dep.name == 'analyzer')
        ?.commit;

    for (var dep in google3Dependencies) {
      logger
        ..write('  ${dep.name}')
        ..indent();
      await updateGoogle3Dependency(dep, sdkCommit: sdkCommit);
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

  Future updateSdkDependency(SdkDependency dependency) async {
    var existingInfo = await getSdkRepositoryInfo(dependency.name);
    var commit = dependency.commitInfo!;

    String? unsyncedTimestamp;
    if (dependency.unsyncedCommits.isNotEmpty) {
      dependency.unsyncedCommits.sort();
      var oldest = dependency.unsyncedCommits.last;
      unsyncedTimestamp = oldest.committedDate.toIso8601String();
    }

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
    var updatedInfo = await documentsPatch(
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
            entity: '[sdk] package:${dependency.name}',
            change: '$field => ${printValue(updatedFields[field]!)}',
          );
        }
      }
    }
  }

  Future updateGoogle3Dependency(
    Google3Dependency dependency, {
    String? sdkCommit,
  }) async {
    var existingInfo = await getGoogle3DepInfo(dependency.name);

    final Document doc = Document(
      fields: {
        'name': valueStr(dependency.name),
        'firstParty': valueBool(dependency.firstParty),
        'commit': valueStrNullable(dependency.commit),
        'pendingCommits': valueInt(dependency.pendingCommits),
        'latencyDate': dependency.latencyDate == null
            ? valueNull()
            : Value(
                timestampValue:
                    dependency.latencyDate!.toUtc().toIso8601String(),
              ),
        'hasCopybaraConfig': valueBool(dependency.hasCopybaraConfig),
        'usesCopybaraService': valueBool(dependency.usesCopybaraService),
        if (dependency.error != null)
          'error': valueStrNullable(dependency.error),
      },
    );

    var updatedInfo = await documents.patch(
      doc,
      getDocumentName(
        'google3',
        firestoreEntityEncode(dependency.name),
      ),
    );

    // Record interesting changes in the log.
    if (existingInfo != null) {
      var updatedFields = updatedInfo.fields!;
      for (var field in ['commit']) {
        // Don't both recording the <sdk>/pkg packages ==> google3.
        if (field == 'commit' && dependency.commit == sdkCommit) {
          continue;
        }

        if (updatedFields.keys.contains(field) &&
            !compareValues(existingInfo[field]!, updatedFields[field]!)) {
          log(
            entity: '[google3] package:${dependency.name}',
            change: '$field => ${printValue(updatedFields[field]!)}',
          );
        }
      }
    }
  }

  Future<Document> documentsPatch(
    Document request,
    String name, {
    List<String>? updateMaskFieldPaths,
  }) {
    return profiler.run(
      'firebase.write',
      documents.patch(
        request,
        name,
        updateMask_fieldPaths: updateMaskFieldPaths,
      ),
    );
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

  String? get repoOrgAndName {
    return repository == null ? null : RepoInfo(repository!).repoOrgAndName;
  }
}

class FirestoreRepositoryInfo {
  final String org;
  final String name;
  final String? workflows;
  final bool hasDependabot;
  final int issueCount;
  final int prCount;
  final String defaultBranchName;

  FirestoreRepositoryInfo({
    required this.org,
    required this.name,
    required this.workflows,
    required this.hasDependabot,
    required this.issueCount,
    required this.prCount,
    required this.defaultBranchName,
  });

  String get orgAndName => '$org/$name';
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
