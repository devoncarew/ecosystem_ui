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

  Future updateStats() async {
    // sdk stats
    DateTime timestampUtc = DateTime.now().toUtc();
    print('updating sdk stats...');
    final sdkDeps = await firestore.getSdkDeps();
    await firestore.logStat(
      category: 'sdk',
      stat: 'depsCount',
      value: sdkDeps.length,
      timestampUtc: timestampUtc,
    );

    // sdk sync latency
    List<int> latencyDays = sdkDeps.map((dep) => dep.syncLatencyDays).toList();

    int p50 = calulatePercentile(latencyDays, 0.5).round();
    print('  p50 sync latency: $p50');
    await firestore.logStat(
      category: 'sdk',
      stat: 'syncLatency.p50',
      value: p50,
      timestampUtc: timestampUtc,
    );

    int p90 = calulatePercentile(latencyDays, 0.9).round();
    print('  p90 sync latency: $p90');
    await firestore.logStat(
      category: 'sdk',
      stat: 'syncLatency.p90',
      value: p90,
      timestampUtc: timestampUtc,
    );

    // publisher stats
    print('updating package stats...');
    timestampUtc = DateTime.now().toUtc();
    final publishers = await firestore.queryPublishers();
    final allPackages = await firestore.queryPackagesForPublishers(publishers);

    for (var publisher in publishers) {
      print('  $publisher');

      final packages =
          allPackages.where((p) => p.publisher == publisher).toList();

      // number of packages
      await firestore.logStat(
        category: 'publisher.packageCount',
        stat: publisher,
        value: packages.length,
        timestampUtc: timestampUtc,
      );

      // unowned packages
      await firestore.logStat(
        category: 'publisher.unownedCount',
        stat: publisher,
        value: packages.where((p) => p.maintainer?.isEmpty ?? true).length,
        timestampUtc: timestampUtc,
      );

      // Publish latency stats - p50, p90.
      List<int> latencyDays =
          packages.map((p) => p.publishLatencyDays).whereType<int>().toList();

      int p50 = calulatePercentile(latencyDays, 0.5).round();
      print('    p50 publish latency: $p50');
      await firestore.logStat(
        category: 'publisher.publishLatency.p50',
        stat: publisher,
        value: p50,
        timestampUtc: timestampUtc,
      );

      int p90 = calulatePercentile(latencyDays, 0.9).round();
      print('    p90 publish latency: $p90');
      await firestore.logStat(
        category: 'publisher.publishLatency.p90',
        stat: publisher,
        value: p90,
        timestampUtc: timestampUtc,
      );
    }
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

    final github = Github();

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

      // These queries depend on the repository information being correct.
      if (!packageInfo.isDiscontinued &&
          packageInfo.repository != null &&
          !packageInfo.repository!.endsWith('.git')) {
        var repoInfo = packageInfo.repoInfo!;

        var commits = await github.queryCommitsAfter(
          repo: RepositoryInfo(path: repoInfo.repoOrgAndName!),
          afterTimestamp: packageInfo.published,
          pathInRepo: repoInfo.monoRepoPath,
        );

        if (commits.isEmpty) {
          packageInfo.unpublishedCommits = 0;
          packageInfo.unpublishedCommitDate = null;
        } else {
          packageInfo.unpublishedCommits = commits.length;

          // TODO: filter dependabot commits? commits into .github?
          commits.sort();
          var oldest = commits.last;
          packageInfo.unpublishedCommitDate = oldest.committedDate;
        }
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
          if (field == 'analysisOptions' ||
              field == 'publishedDate' ||
              field == 'pubspec' ||
              field == 'unpublishedCommitDate' ||
              field == 'unpublishedCommits') {
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

    github.close();
  }

  Future updateFromSdk() async {
    final sdk = await Sdk.fromHttpGet();

    List<SdkDependency> sdkDependencies = sdk.getDartPackages();

    final Github github = Github();

    for (var dep in sdkDependencies) {
      print(dep.repository);

      // Get the info about the given sha.
      RepositoryInfo repo = RepositoryInfo(
        path: dep.repository.substring('https://github.com/'.length),
      );
      var commit = await github.getCommitInfoForSha(
        repo: repo,
        sha: dep.commit!,
      );
      dep.commitInfo = commit;

      print('  synced to: $commit');

      // Find how many newer, unsynced commits there are.
      var unsynced = await github.queryCommitsAfter(
        repo: repo,
        afterTimestamp: commit.committedDate.toIso8601String(),
      );
      // TODO: filter dependabot commits? commits into .github?
      unsynced.sort();
      dep.unsyncedCommits = unsynced;

      print('  unsynced commits: ${unsynced.length}');
      // for (var c in unsynced) {
      //   print('    unsynced: $c');
      // }
    }

    await firestore.updateSdkDependencies(sdkDependencies);

    github.close();
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

    final Github github = Github();

    // TODO: use package:pool for some of our operations
    for (var repo in repositories) {
      print('updating $repo');

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
