import 'dart:io' as io;

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'github.dart';
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

    print("env['GOOGLE_APPLICATION_CREDENTIALS']="
        "${io.Platform.environment['GOOGLE_APPLICATION_CREDENTIALS']}");

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

  Future<Map<String, Value>?> getRepositoryInfo(String repoName) async {
    try {
      final packagePath = getDocumentName('sdk_deps', repoName);
      var result = await documents.get(packagePath);
      return result.fields;
    } catch (e) {
      // todo: ignore these - we know some documents won't yet exist
      print(e);
      return null;
    }
  }

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
        'repository': valueStr(repository ?? ''),
        'issueTracker': valueStr(packageInfo.issueTracker ?? ''),
        'discontinued': valueBool(packageInfo.isDiscontinued),
        'unlisted': valueBool(packageInfo.isUnlisted),
        'pubspec': valueStr(packageInfo.encodedPubspec),
        if (analysisOptions != null)
          'analysisOptions': valueStr(analysisOptions),
        if (packageInfo.published != null)
          'publishedDate': Value(timestampValue: packageInfo.published),
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
    required int value,
    DateTime? timestampUtc,
  }) async {
    timestampUtc ??= DateTime.now().toUtc();

    final Document doc = Document(
      fields: {
        'category': valueStr(category),
        'stat': valueStr(stat),
        'value': valueInt(value),
        'timestamp': Value(timestampValue: timestampUtc.toIso8601String()),
      },
    );

    // todo: handle error conditions
    await documents.createDocument(doc, documentsPath, 'stats');
  }

  Future<Map<String, Value>?> getRepoInfo(String repoPath) async {
    try {
      var repo = RepositoryInfo(path: repoPath);
      final repositoryPath =
          getDocumentName('repositories', repo.firestoreEntityId);
      var result = await documents.get(repositoryPath);
      return result.fields;
    } catch (e) {
      print(e);
      return null;
    }
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
    ListDocumentsResponse response = await documents.list(
      documentsPath,
      'sdk_deps',
      pageSize: 100,
    );
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future updateSdkDependencies(Sdk sdk) async {
    // Read current deps
    final List<String> currentDeps = await getSdkDependencies();

    // Update commit info
    for (var dep in sdk.getDartPackages()) {
      print('  ${dep.repository}');
      await updateSdkDependency(dep);
    }

    // Log sdk dep additions.
    Set<String> newDeps = Set.from(sdk.getDartPackages().map((p) => p.name))
      ..removeAll(currentDeps);
    for (var dep in newDeps) {
      print('  adding $dep');
      await log(entity: 'SDK dep', change: 'added $dep');
    }

    // Remove any repos which are no longer deps.
    Set<String> oldDeps = currentDeps.toSet()
      ..removeAll(sdk.getDartPackages().map((p) => p.name));
    for (var dep in oldDeps) {
      print('  removing $dep');
      await documents.delete(getDocumentName('sdk_deps', dep));
      await log(entity: 'SDK dep', change: 'removing $dep');
    }
  }

  Future updateMaintainers(List<PackageMaintainer> maintainers) async {
    for (var pkg in maintainers) {
      print('  $pkg');

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
    }
  }

  Future updateRepositoryInfo(RepositoryInfo repo) async {
    final Document doc = Document(
      fields: {
        'org': valueStr(repo.org),
        'name': valueStr(repo.name),
        if (repo.dependabotConfig != null)
          'dependabotConfig': valueStr(repo.dependabotConfig!),
        if (repo.actionsConfig != null)
          'actionsConfig': valueStr(repo.actionsConfig!),
        if (repo.actionsFile != null)
          'actionsFile': valueStr(repo.actionsFile!),
      },
    );

    // lastCommitTimestamp
    List<Commit> commits = repo.commits.toList()..sort();
    if (commits.isNotEmpty) {
      doc.fields!['lastCommitTimestamp'] = Value(
        timestampValue: commits.first.committedDate.toIso8601String(),
      );
    }

    final repositoryPath =
        getDocumentName('repositories', repo.firestoreEntityId);

    final DocumentMask mask = DocumentMask(
      fieldPaths: doc.fields!.keys.toList(),
    );

    // todo: handle error conditions
    await documents.patch(
      doc,
      repositoryPath,
      updateMask_fieldPaths: mask.fieldPaths,
    );

    // Handle commit information.
    for (var commit in commits) {
      final Document doc = Document(
        fields: {
          'oid': valueStr(commit.oid),
          'user': valueStr(commit.user),
          'message': valueStr(commit.message),
          'committedDate': Value(
            timestampValue: commit.committedDate.toIso8601String(),
          ),
        },
      );

      print('  $commit');
      // todo: handle error conditions
      await documents.patch(
        doc,
        '$repositoryPath/commits/${commit.oid}',
      );
    }
  }

  Future updateSdkDependency(SdkDependency dependency) async {
    var existingInfo = await getRepositoryInfo(dependency.name);

    final Document doc = Document(
      fields: {
        'name': valueStr(dependency.name),
        'commit': valueStr(dependency.commit ?? ''),
        'repository': valueStr(dependency.repository),
      },
    );

    // todo: handle error conditions
    var updatedInfo = await documents.patch(
      doc,
      getDocumentName('sdk_deps', dependency.name),
    );

    if (existingInfo != null) {
      var updatedFields = updatedInfo.fields!;
      for (var field in existingInfo.keys) {
        if (updatedFields.keys.contains(field) &&
            !compareValues(existingInfo[field]!, updatedFields[field]!)) {
          log(
            entity: 'SDK dep package:${dependency.name}',
            change: '$field => ${printValue(updatedFields[field]!)}',
          );
        }
      }
    }
  }
}

class Config {
  final String projectId = 'dart-package-dashboard';
}

Value valueStr(String value) => Value(stringValue: value);
Value valueBool(bool value) => Value(booleanValue: value);
Value valueInt(int value) => Value(integerValue: value.toString());
