import 'src/firestore.dart';
import 'src/github.dart';
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

  final RegExp repoRegex =
      RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

  // todo: switch to having all the commits recorded in the package itself
  //   the commits would be just those that affected the package directory

  Future updateRepositories() async {
    final publishers = await firestore.queryPublishers();

    // todo: ignore discoutinued packages

    print('Getting repos for $publishers.');
    var repos =
        await firestore.queryRepositoriesForPublishers(publishers.toSet());
    // todo:
    print('retrieved ${repos.length} repos');
    print(repos.map((r) => '  $r').join('\n'));

    // todo: fix all these issues upstream
    // ignore anything ending in '.git'
    repos = repos.where((repo) {
      if (repo.endsWith('.git')) {
        print('* ignoring $repo');
      }
      return !repo.endsWith('.git');
    }).toList();

    // todo: fix all these issues upstream
    // ignore 'https://www.' anything
    repos = repos.where((repo) {
      if (repo.startsWith('https://www.')) {
        print('* ignoring $repo');
      }
      return !repo.startsWith('https://www.');
    }).toList();

    // Collapse sub-dir references (handle mono-repos).
    repos = repos
        .map((repo) {
          var match = repoRegex.firstMatch(repo);
          if (match == null) {
            print('Error parsing $repo');
            return null;
          } else {
            return '${match.group(1)}/${match.group(2)}';
          }
        })
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    print('');
    print('${repos.length} sanitized repos');
    print(repos.map((r) => '  $r').join('\n'));

    // Get commit information from github.
    List<RepositoryInfo> repositories = repos.map((name) {
      return RepositoryInfo(path: name);
    }).toList();

    // // TODO: for a monorepo, we'll need to do some work to identity whether a
    // // commit involves specific packages
    // RepositoryInfo r = repositories[1];

    // var commits = await github.queryRecentCommits(repo: r, count: 20);
    // // for (var commit in commits) {
    // //   print(commit);
    // // }
    // r.addCommits(commits);
    // r = repositories.firstWhere((r) => r.name == 'sdk');

    // commits = await github.queryRecentCommits(repo: r, count: 10);
    // r.addCommits(commits);

    final Github github = Github();

    // todo: use package:pool for several operations
    for (var repo in repositories) {
      print('updating $repo');
      var firestoreRepoInfo = await firestore.getRepoInfo(repo.path);
      var lastCommitTimestamp = firestoreRepoInfo?['lastCommitTimestamp'];

      if (firestoreRepoInfo != null && lastCommitTimestamp != null) {
        // Look for new commits.
        var commits = await github.queryCommitsAfter(
          repo: repo,
          afterTimestamp: lastCommitTimestamp.timestampValue!,
        );
        repo.addCommits(commits);
      } else {
        // Load the last n recent commits.
        var commits = await github.queryRecentCommits(repo: repo, count: 20);
        repo.addCommits(commits);
      }

      await firestore.updateRepositoryInfo(repo);
    }
  }

  Future close() async {
    firestore.close();
    pub.close();
  }
}
