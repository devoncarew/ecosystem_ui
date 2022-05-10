import 'package:http/http.dart' as http;

import 'src/firestore.dart';
import 'src/github.dart';
import 'src/pub.dart';
import 'src/sdk.dart';
import 'src/sheets.dart';
import 'src/utils.dart';

class PackageManager {
  late final Pub pub;
  late final Firestore firestore;
  http.Client? _httpClient;

  PackageManager() {
    pub = Pub();
    firestore = Firestore();
  }

  Future setup() async {
    await firestore.setup();
  }

  Future updateHealthStats() async {
    // sdk stats
    DateTime timestampUtc = DateTime.now().toUtc();
    print('updating sdk stats...');
    final sdkDeps = await firestore.getSdkDependencies();
    await firestore.logStat(
      category: 'sdk',
      stat: 'depsCount',
      value: sdkDeps.length,
      timestampUtc: timestampUtc,
    );

    // publisher stats
    print('updating package stats...');
    timestampUtc = DateTime.now().toUtc();
    final publishers = await firestore.queryPublishers();

    // todo: get all package info?

    for (var publisher in publishers) {
      print('  $publisher');

      // todo: query firestore here...
      final packages = await pub.packagesForPublisher(
        publisher,
        includeHidden: false,
      );

      // number of packages
      await firestore.logStat(
        category: 'publisher.packageCount',
        stat: publisher,
        value: packages.length,
        timestampUtc: timestampUtc,
      );

      // // unowned packages
      // await firestore.logStat(
      //   category: 'publisher.unownedCount',
      //   stat: publisher,
      //   value: packages.where((p) => p.owner.isEmpty).length,
      //   timestampUtc: timestampUtc,
      // );
    }

    // todo: publish latency stats
  }

  Future updateAllPublisherPackages() async {
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

    _httpClient ??= http.Client();

    final packages = await pub.packagesForPublisher(publisher);

    for (var packageName in packages) {
      print('  package:$packageName');
      var packageInfo = await pub.getPackageInfo(packageName);
      var existingInfo = await firestore.getPackageInfo(packageName);

      var repoInfo = packageInfo.repoInfo;
      var url = repoInfo?.getDirectFileUrl('analysis_options.yaml');

      // Probe for an analysisOptions.yaml file; this depends on the repository
      // field being set correctly.
      String? analysisOptions;
      if (repoInfo != null && url != null) {
        // todo: we should also probe up a directory or two if in a mono-repo
        analysisOptions =
            await _httpClient!.get(Uri.parse(url)).then((response) {
          return response.statusCode == 404 ? null : response.body;
        });
      }

      var updatedInfo = await firestore.updatePackageInfo(
        packageName,
        publisher: publisher,
        packageInfo: packageInfo,
        analysisOptions: analysisOptions,
      );

      if (existingInfo == null) {
        firestore.log(
          entity: 'package:$packageName',
          change: 'added (publisher $publisher)',
        );
      } else {
        var updatedFields = updatedInfo.fields!;
        for (var field in existingInfo.keys) {
          // These fields are noisy.
          if (field == 'pubspec' ||
              field == 'analysisOptions' ||
              field == 'publishedDate') {
            continue;
          }

          if (updatedFields.keys.contains(field) &&
              !compareValues(existingInfo[field]!, updatedFields[field]!)) {
            firestore.log(
              entity: 'package:$packageName',
              change: '$field => ${printValue(updatedFields[field]!)}',
            );
          }
        }
      }
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

    print('Getting repos for $publishers.');
    var repos =
        await firestore.queryRepositoriesForPublishers(publishers.toSet());
    // todo:
    print('retrieved ${repos.length} repos');
    print(repos.map((r) => '  $r').join('\n'));

    // ignore anything ending in '.git'
    repos = repos.where((repo) {
      if (repo.endsWith('.git')) {
        print('* ignoring $repo');
      }
      return !repo.endsWith('.git');
    }).toList();

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

    // TODO: use package:pool for some of our operations
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
        // Prime the info with the last n recent commits.
        var commits = await github.queryRecentCommits(repo: repo, count: 20);
        repo.addCommits(commits);
      }

      // https://raw.githubusercontent.com/dart-lang/usage/master/.github/workflows/build.yaml

      // Look for CI configuration.
      String? actionsConfig;
      String? actionsFile;

      // TODO: look to reduce the number of places to look.
      for (var filePath in [
        '.github/workflows/dart.yaml',
        '.github/workflows/build.yaml',
        '.github/workflows/test.yaml',
        '.github/workflows/test-package.yml',
        '.github/workflows/dart.yml',
        '.github/workflows/ci.yml',
      ]) {
        var contents = await github.retrieveFile(
          orgAndRepo: repo.path,
          filePath: filePath,
        );
        if (contents != null) {
          actionsConfig = contents;
          actionsFile = filePath;
          break;
        }
      }

      repo.actionsConfig = actionsConfig ?? '';
      repo.actionsFile = actionsFile ?? '';

      // Look for dependabot configuration.
      String dependabot = await github.retrieveFile(
              orgAndRepo: repo.path, filePath: '.github/dependabot.yaml') ??
          '';
      repo.dependabotConfig = dependabot;

      // todo: look for an analysis options file for each package

      await firestore.updateRepositoryInfo(repo);
    }

    github.close();
  }

  Future close() async {
    firestore.close();
    pub.close();
    _httpClient?.close();
  }
}
