import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:packages_cli/src/pub.dart';
import 'package:packages_cli/src/sdk.dart';

import 'sheets.dart';

class Firestore {
  final Config config = Config();

  late AutoRefreshingAuthClient _client;
  late final FirestoreApi firestore;

  Firestore();

  Future setup() async {
    // Set the GOOGLE_APPLICATION_CREDENTIALS env var to the path containing the
    // cloud console service account key.
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
    ListDocumentsResponse response =
        await documents.list(documentsPath, 'publishers');
    return response.documents!.map((doc) {
      // Convert:
      //   projects/dart-package-dashboard/databases/(default)/documents/publishers/dart.dev
      // to:
      //   dart.dev
      final name = doc.name!;
      return name.substring(name.lastIndexOf('/') + 1);
    }).toList();
  }

  Future updatePackageInfo(
    String packageName, {
    required String publisher,
    required PackageInfo packageInfo,
  }) async {
    // todo: include the pubspec? as structured data? as text?

    // todo: make sure we don't write over fields that we're not updating here
    final Document doc = Document(
      fields: {
        'name': valueStr(packageName),
        'publisher': valueStr(publisher),
        'version': valueStr(packageInfo.version),
        'repository': valueStr(packageInfo.repository ?? ''),
        'discontinued': valueBool(packageInfo.isDiscontinued),
        'unlisted': valueBool(packageInfo.isUnlisted),
      },
    );

    final DocumentMask mask = DocumentMask(
      fieldPaths: doc.fields!.keys.toList(),
    );

    // todo: handle error conditions
    await documents.patch(
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
      },
    );

    // todo: handle error conditions
    await documents.createDocument(doc, documentsPath, 'log');
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
    ListDocumentsResponse response =
        await documents.list(documentsPath, 'sdk_deps');
    return response.documents!.map((Document doc) {
      return doc.fields!['name']!.stringValue!;
    }).toList();
  }

  Future updateSdkDependencies(Sdk sdk) async {
    // Read current deps
    final List<String> currentDeps = await getSdkDependencies();

    // Update commit info
    for (var package in sdk.getDartPackages()) {
      // TODO: add logging
      print('  package:${package.name}');
      await updateSdkDependency(package);
    }

    // Remove any repos which are no longer deps.
    Set<String> oldDeps = currentDeps.toSet()
      ..removeAll(sdk.getDartPackages().map((p) => p.name));
    for (var dep in oldDeps) {
      print('  removing $dep');
      await documents.delete(getDocumentName('sdk_deps', dep));
    }
  }

  Future updateMaintainers(List<PackageMaintainer> maintainers) async {
    for (var pkg in maintainers) {
      print('  $pkg');

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

  Future updateSdkDependency(DartPackage package) async {
    final Document doc = Document(
      fields: {
        'name': valueStr(package.name),
        'commit': valueStr(package.commit),
        'repository': valueStr(package.repository),
      },
    );

    // todo: handle error conditions
    await documents.patch(doc, getDocumentName('sdk_deps', package.name));
  }
}

class Config {
  final String projectId = 'dart-package-dashboard';
}

Value valueStr(String value) => Value(stringValue: value);
Value valueBool(bool value) => Value(booleanValue: value);
