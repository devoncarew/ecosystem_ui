import 'src/firestore.dart';
import 'src/pub.dart';
import 'src/sdk.dart';
import 'src/sheets.dart';

class PackageManager {
  late final Pub pub;
  late final Firestore firestore;

  PackageManager() {
    pub = Pub();
    firestore = Firestore();
  }

  Future setup() async {
    await firestore.setup();
  }

  Future updateFromPub() async {
    final publishers = await firestore.queryPublishers();
    print('publishers info from firebase:');
    print('  $publishers');

    for (var publisher in publishers) {
      await updatePublisherPackages(publisher);
    }
  }

  Future updatePublisherPackages(String publisher) async {
    // TODO: consider batching these write (documents.batchWrite()).
    print('updating pub.dev info for $publisher packages');

    final packages = await pub.packagesForPublisher(publisher);

    for (var packageName in packages) {
      // TODO: add logging
      print('  package:$packageName');
      var packageInfo = await pub.getPackageInfo(packageName);
      await firestore.updatePackageInfo(
        packageName,
        publisher: publisher,
        packageInfo: packageInfo,
      );
    }

    await firestore.unsetPackagePublishers(
      publisher,
      currentPackages: packages,
    );
  }

  Future updateFromSdk() async {
    final sdk = await Sdk.fromHttpGet();
    await firestore.updateSdkDependencies(sdk);
  }

  Future updateMaintainersFromSheets() async {
    print('Updating maintainers from sheets');

    final Sheets sheets = Sheets();
    await sheets.connect();

    final List<PackageMaintainer> maintainers =
        await sheets.getMaintainersData();

    print('Read data about ${maintainers.length} packages.');
    await firestore.updateMaintainers(maintainers);

    sheets.close();
  }

  Future close() async {
    firestore.close();
    pub.close();
  }
}
