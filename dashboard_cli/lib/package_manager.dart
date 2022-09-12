import 'package:http/http.dart' as http;

import 'src/firestore.dart';
import 'src/github.dart';
import 'src/google3.dart';
import 'src/pub.dart';
import 'src/sdk.dart';
import 'src/sheets.dart';
import 'src/utils.dart';

// todo: add information about overall package popularity (rank; # deps)

class PackageManager {
  late final Pub pub;
  late final Firestore firestore;
  http.Client? _httpClient;

  Profiler profiler = Profiler();

  PackageManager() {
    pub = Pub(profiler: profiler);
    firestore = Firestore(profiler: profiler);
  }

  Future setup() async {
    await firestore.setup();
  }

  Future updateStats() async {
    final logger = Logger();

    DateTime timestampUtc = DateTime.now().toUtc();

    // sdk stats
    logger.write('updating sdk stats...');
    final sdkDeps = await firestore.getSdkDeps();
    logger.write('${sdkDeps.length} sdk deps');
    await firestore.logStat(
      category: 'sdk.deps',
      stat: 'count',
      value: sdkDeps.length,
      timestampUtc: timestampUtc,
    );

    // sdk sync latency
    List<int> latencyDays = sdkDeps.map((dep) => dep.syncLatencyDays).toList();

    int p50 = calulatePercentile(latencyDays, 0.5).round();
    logger.write('p50 sync latency: $p50 days');
    await firestore.logStat(
      category: 'sdk.latency',
      stat: 'p50',
      value: p50,
      timestampUtc: timestampUtc,
    );

    int p90 = calulatePercentile(latencyDays, 0.9).round();
    logger.write('p90 sync latency: $p90 days');
    await firestore.logStat(
      category: 'sdk.latency',
      stat: 'p90',
      value: p90,
      timestampUtc: timestampUtc,
    );
    logger.write('');

    // google3 stats
    logger.write('updating google3 stats...');
    final google3Deps = await firestore.getGoogle3Deps();
    logger.write('${google3Deps.length} google3 deps');
    await firestore.logStat(
      category: 'google3.deps',
      stat: 'count',
      value: google3Deps.length,
      timestampUtc: timestampUtc,
    );

    // google3 sync latency
    latencyDays = google3Deps.map((dep) => dep.syncLatencyDays).toList();

    p50 = calulatePercentile(latencyDays, 0.5).round();
    logger.write('p50 sync latency: $p50 days');
    await firestore.logStat(
      category: 'google3.latency',
      stat: 'p50',
      value: p50,
      timestampUtc: timestampUtc,
    );

    p90 = calulatePercentile(latencyDays, 0.9).round();
    logger.write('p90 sync latency: $p90 days');
    await firestore.logStat(
      category: 'google3.latency',
      stat: 'p90',
      value: p90,
      timestampUtc: timestampUtc,
    );
    logger.write('');

    // publisher stats
    print('updating package stats...');
    logger.write('');
    timestampUtc = DateTime.now().toUtc();

    final publishers = await firestore.queryPublishers();

    final allPackages = await firestore.queryPackagesForPublishers(publishers);

    for (var publisher in publishers) {
      logger
        ..write(publisher)
        ..indent();

      final packages =
          allPackages.where((p) => p.publisher == publisher).toList();

      // number of packages
      final unowned =
          packages.where((p) => p.maintainer?.isEmpty ?? true).length;
      logger.write('${packages.length} packages ($unowned unowned)');
      await firestore.logStat(
        category: 'package.count',
        stat: 'count',
        detail: publisher,
        value: packages.length,
        timestampUtc: timestampUtc,
      );
      await firestore.logStat(
        category: 'package.count',
        stat: 'unowned',
        detail: publisher,
        value: unowned,
        timestampUtc: timestampUtc,
      );

      // Publish latency stats - p50, p90.
      List<int> latencyDays =
          packages.map((p) => p.publishLatencyDays).whereType<int>().toList();

      int p50 = calulatePercentile(latencyDays, 0.5).round();
      logger.write('p50 publish latency: $p50 days');
      await firestore.logStat(
        category: 'package.latency',
        stat: 'p50',
        detail: publisher,
        value: p50,
        timestampUtc: timestampUtc,
      );

      int p90 = calulatePercentile(latencyDays, 0.9).round();
      logger.write('p90 publish latency: $p90 days');
      await firestore.logStat(
        category: 'package.latency',
        stat: 'p90',
        detail: publisher,
        value: p90,
        timestampUtc: timestampUtc,
      );

      logger.outdent();
    }

    logger.write('');
    logger.close(printElapsedTime: true);
  }

  Future updatePublisherPackages({List<String>? publishers}) async {
    final logger = Logger();

    try {
      publishers ??= await firestore.queryPublishers();
      logger.write('Updating info for publishers: ${publishers.join(', ')}');
      logger.write('');

      for (var publisher in publishers) {
        await _updatePublisherPackages(publisher, logger: logger);
      }
    } finally {
      logger.write(profiler.results());
      logger.close(printElapsedTime: true);
    }
  }

  Future _updatePublisherPackages(
    String publisher, {
    required Logger logger,
  }) async {
    // TODO: consider batching these write (documents.batchWrite()).
    logger.write('Updating pub.dev info for $publisher packages...');

    _httpClient ??= http.Client();

    final packages = await pub.packagesForPublisher(publisher);

    final github = Github(profiler: profiler);

    for (var packageName in packages) {
      logger
        ..write('package:$packageName')
        ..indent();

      await _updatePackage(packageName, logger, github, publisher);

      logger.outdent();
    }

    await firestore.unsetPackagePublishers(
      publisher,
      currentPackages: packages,
    );

    github.close();
    logger.write('');
  }

  Future<void> _updatePackage(
    String packageName,
    Logger log,
    Github github,
    String publisher,
  ) async {
    var packageInfo = await pub.getPackageInfo(packageName);
    var existingInfo = await firestore.getPackageInfo(packageName);

    log.write(packageInfo.version);
    if (packageInfo.repository != null) {
      log.write(packageInfo.repository!);
    }

    // var repoInfo = packageInfo.repoInfo;
    // var url = repoInfo?.getDirectFileUrl('analysis_options.yaml');
    // // Probe for an analysisOptions.yaml file; this depends on the repository
    // // field being set correctly.
    // String? analysisOptions;
    // if (repoInfo != null && url != null) {
    //   // TODO: we should also probe up a directory or two if in a mono-repo
    //   analysisOptions = await _httpClient!.get(Uri.parse(url)).then((response) {
    //     return response.statusCode == 404 ? null : response.body;
    //   });
    // }

    // These queries depend on the repository information being correct.
    if (!packageInfo.isDiscontinued &&
        packageInfo.repository != null &&
        !packageInfo.repository!.endsWith('.git') &&
        !packageInfo.repository!.endsWith('/')) {
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

      log.write('unpublished commits: ${packageInfo.unpublishedCommits}');
    }

    if (!packageInfo.isDiscontinued && packageInfo.issueTracker != null) {
      packageInfo.issueCount =
          await github.queryIssueCount(packageInfo.issueTracker!);
    }

    var updatedInfo = await firestore.updatePackageInfo(
      packageName,
      publisher: publisher,
      packageInfo: packageInfo,
      // analysisOptions: analysisOptions,
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
          final change = '$field => ${printValue(updatedFields[field]!)}';
          log.write(change);
          firestore.log(entity: 'package:$packageName', change: change);
        }
      }
    }
  }

  Future updateFromSdk() async {
    final logger = Logger();

    logger.write('Retrieving SDK DEPS...');
    final sdk = await profiler.run('sdk.readDeps', Sdk.fromHttpGet());

    List<SdkDependency> sdkDependencies = sdk.getDartPackages();
    logger.write('${sdkDependencies.length} deps found.');
    logger.write('');

    final Github github = Github(profiler: profiler);

    for (var dep in sdkDependencies) {
      logger
        ..write(dep.repository)
        ..indent();

      // Get the info about the given sha.
      RepositoryInfo repo = RepositoryInfo(
          path: dep.repository.substring('https://github.com/'.length));
      dep.commitInfo =
          await github.getCommitInfoForSha(repo: repo, sha: dep.commit!);
      logger.write('${dep.commitInfo}');

      // Find how many newer, unsynced commits there are.
      dep.unsyncedCommits = await github.queryCommitsAfter(
          repo: repo,
          afterTimestamp: dep.commitInfo!.committedDate.toIso8601String())
        ..sort();
      logger.write('unsynced commits: ${dep.unsyncedCommits.length}');

      logger.outdent();
    }

    await firestore.updateSdkDependencies(sdkDependencies, logger: logger);

    logger.write('');
    logger.write(profiler.results());
    logger.close(printElapsedTime: true);

    github.close();
  }

  Future updateFromGoogle3() async {
    final logger = Logger();

    logger.write('Retrieving info about Google3 synced packages...');
    final google3 = Google3();

    final publishers = await firestore.queryPublishers();

    final allPackages = await firestore.queryPackagesForPublishers(publishers);
    final packages = allPackages.map((p) => p.name);

    var google3Dependencies =
        await google3.getPackageSyncInfo(packages: packages.toSet());

    logger.write('${google3Dependencies.length} deps found.');
    logger.write('');

    await firestore.updateGoogle3Dependencies(
      google3Dependencies,
      logger: logger,
    );

    logger.write('');
    logger.close(printElapsedTime: true);

    // github.close();
  }

  Future updateMaintainersFromSheets() async {
    final logger = Logger();

    logger.write('Updating maintainers from sheets');

    final Sheets sheets = Sheets();
    await sheets.connect();

    logger.write('');
    logger
      ..write('Getting maintainers data...')
      ..indent();
    final List<PackageMaintainer> maintainers =
        await sheets.getMaintainersData(logger);
    logger.outdent();
    logger.write('Read data about ${maintainers.length} packages.');
    logger.write('');

    await firestore.updateMaintainers(maintainers, logger: logger);

    sheets.close();

    logger.write('');
    logger.close(printElapsedTime: true);
  }

  // final RegExp repoRegex =
  //     RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

  // Future updateRepositories() async {
  //   final logger = Logger();
  //   final publishers = await firestore.queryPublishers();

  //   logger.write('Getting repos for ${publishers.join(', ')}.');
  //   var repos =
  //       await firestore.queryRepositoriesForPublishers(publishers.toSet());
  //   logger.write('retrieved ${repos.length} repos');

  //   // ignore anything ending in '.git'
  //   repos = repos.where((repo) {
  //     if (repo.endsWith('.git')) {
  //       logger.write('* ignoring $repo');
  //     }
  //     return !repo.endsWith('.git');
  //   }).toList();

  //   // Collapse sub-dir references (handle mono-repos).
  //   repos = repos
  //       .map((repo) {
  //         var match = repoRegex.firstMatch(repo);
  //         if (match == null) {
  //           print('Error parsing $repo');
  //           return null;
  //         } else {
  //           return '${match.group(1)}/${match.group(2)}';
  //         }
  //       })
  //       .whereType<String>()
  //       .toSet()
  //       .toList()
  //     ..sort();

  //   logger.write('');
  //   logger.write('${repos.length} sanitized repos');
  //   Map<String, int> counts = {};
  //   for (var repo in repos) {
  //     final key = repo.split('/').first;
  //     counts[key] = counts.putIfAbsent(key, () => 0) + 1;
  //   }
  //   logger.write(counts.keys.map((key) => '  $key: ${counts[key]}').join('\n'));

  //   // Get commit information from github.
  //   List<RepositoryInfo> repositories = repos.map((name) {
  //     return RepositoryInfo(path: name);
  //   }).toList();

  //   final Github github = Github();

  //   logger.write('');
  //   logger.write('Updating repositories...');

  //   for (var repo in repositories) {
  //     logger
  //       ..write(repo.path)
  //       ..indent();

  //     // Look for CI configuration.
  //     // TODO: look to reduce the number of places to look.
  //     for (var filePath in [
  //       '.github/workflows/test-package.yml', // 61
  //       '.github/workflows/dart.yml', // 15
  //       '.github/workflows/ci.yml', // 9
  //       '.github/workflows/build.yaml', // 8
  //       // '.github/workflows/test.yaml', // 1
  //     ]) {
  //       var contents = await github.retrieveFile(
  //         orgAndRepo: repo.path,
  //         filePath: filePath,
  //       );

  //       if (contents != null) {
  //         var lines = contents.split('\n');
  //         if (lines.length >= 100) {
  //           lines = lines.take(99).toList()..add('...');
  //         }

  //         repo.actionsConfig = lines.join('\n');
  //         repo.actionsFile = filePath;
  //         logger.write('found ${repo.actionsFile}');

  //         break;
  //       }
  //     }

  //     // todo: we should remove this filtering
  //     // Look for dependabot configuration.
  //     repo.dependabotConfig = await github.retrieveFile(
  //       orgAndRepo: repo.path,
  //       filePath: '.github/dependabot.yaml',
  //     );
  //     if (repo.dependabotConfig != null) {
  //       logger.write('found .github/dependabot.yaml');
  //     }

  //     await firestore.updateRepositoryInfo(repo);

  //     logger.outdent();
  //   }

  //   github.close();

  //   logger.write('');
  //   logger.close(printElapsedTime: true);
  // }

  Future close() async {
    firestore.close();
    pub.close();
    _httpClient?.close();
  }
}
