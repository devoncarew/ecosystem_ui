import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';

import 'src/firestore.dart';
import 'src/github.dart';
import 'src/pub.dart';
import 'src/sdk.dart';
import 'src/sheets.dart';
import 'src/utils.dart';

// todo: improve the performance of this script
//   - make fewer calls
//   - pool some processing
//   - await several calls at once
//   - print the run-time at the end

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
    final logger = Logger();

    // sdk stats
    DateTime timestampUtc = DateTime.now().toUtc();
    logger.write('updating sdk stats...');
    final sdkDeps = await firestore.getSdkDeps();
    logger.write('${sdkDeps.length} sdk deps');
    await firestore.logStat(
      category: 'sdk',
      stat: 'depsCount',
      value: sdkDeps.length,
      timestampUtc: timestampUtc,
    );

    // sdk sync latency
    List<int> latencyDays = sdkDeps.map((dep) => dep.syncLatencyDays).toList();

    int p50 = calulatePercentile(latencyDays, 0.5).round();
    logger.write('p50 sync latency: $p50 days');
    await firestore.logStat(
      category: 'sdk',
      stat: 'syncLatency.p50',
      value: p50,
      timestampUtc: timestampUtc,
    );

    int p90 = calulatePercentile(latencyDays, 0.9).round();
    logger.write('p90 sync latency: $p90 days');
    await firestore.logStat(
      category: 'sdk',
      stat: 'syncLatency.p90',
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

    final pool = Pool(4);

    await pool.forEach<String, void>(publishers, (publisher) async {
      var log = logger.subLogger(publisher);

      final packages =
          allPackages.where((p) => p.publisher == publisher).toList();

      // number of packages
      final unowned =
          packages.where((p) => p.maintainer?.isEmpty ?? true).length;
      log.write('${packages.length} packages ($unowned unowned)');
      await firestore.logStat(
        category: 'publisher.packageCount',
        stat: publisher,
        value: packages.length,
        timestampUtc: timestampUtc,
      );
      await firestore.logStat(
        category: 'publisher.unownedCount',
        stat: publisher,
        value: unowned,
        timestampUtc: timestampUtc,
      );

      // Publish latency stats - p50, p90.
      List<int> latencyDays =
          packages.map((p) => p.publishLatencyDays).whereType<int>().toList();

      int p50 = calulatePercentile(latencyDays, 0.5).round();
      log.write('p50 publish latency: $p50 days');
      await firestore.logStat(
        category: 'publisher.publishLatency.p50',
        stat: publisher,
        value: p50,
        timestampUtc: timestampUtc,
      );

      int p90 = calulatePercentile(latencyDays, 0.9).round();
      log.write('p90 publish latency: $p90 days');
      await firestore.logStat(
        category: 'publisher.publishLatency.p90',
        stat: publisher,
        value: p90,
        timestampUtc: timestampUtc,
      );

      log.close();
    }).toList();

    logger.write('');
    logger.close(printElapsedTime: true);
  }

  Future updatePublisherPackages({List<String>? publishers}) async {
    final logger = Logger();

    publishers ??= await firestore.queryPublishers();
    logger.write('Updating info for publishers: ${publishers.join(', ')}');
    logger.write('');

    for (var publisher in publishers) {
      await _updatePublisherPackages(publisher, logger: logger);
    }

    logger.close(printElapsedTime: true);
  }

  Future _updatePublisherPackages(
    String publisher, {
    required Logger logger,
  }) async {
    // TODO: consider batching these write (documents.batchWrite()).
    logger.write('Updating pub.dev info for $publisher packages...');

    _httpClient ??= http.Client();

    final packages = await pub.packagesForPublisher(publisher);

    final github = Github();

    final pool = Pool(4);

    await pool.forEach<String, void>(packages, (packageName) async {
      final log = logger.subLogger('package:$packageName');

      var packageInfo = await pub.getPackageInfo(packageName);
      var existingInfo = await firestore.getPackageInfo(packageName);

      log.write(packageInfo.version);

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

        log.write('unpublished commits: ${packageInfo.unpublishedCommits}');
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
            final change = '$field => ${printValue(updatedFields[field]!)}';
            log.write(change);
            firestore.log(entity: 'package:$packageName', change: change);
          }
        }
      }

      log.close();
    }).toList();

    await firestore.unsetPackagePublishers(
      publisher,
      currentPackages: packages,
    );

    github.close();
    logger.write('');
  }

  Future updateFromSdk() async {
    final logger = Logger();

    logger.write('Retrieving SDK DEPS...');
    final sdk = await Sdk.fromHttpGet();

    List<SdkDependency> sdkDependencies = sdk.getDartPackages();
    logger.write('${sdkDependencies.length} deps found.');
    logger.write('');

    final Github github = Github();
    final pool = Pool(4);

    await pool.forEach<SdkDependency, void>(sdkDependencies,
        (SdkDependency dep) async {
      final repoLogger = logger.subLogger(dep.repository);

      // Get the info about the given sha.
      RepositoryInfo repo = RepositoryInfo(
          path: dep.repository.substring('https://github.com/'.length));
      dep.commitInfo =
          await github.getCommitInfoForSha(repo: repo, sha: dep.commit!);
      repoLogger.write('${dep.commitInfo}');

      // Find how many newer, unsynced commits there are.
      dep.unsyncedCommits = await github.queryCommitsAfter(
          repo: repo,
          afterTimestamp: dep.commitInfo!.committedDate.toIso8601String())
        ..sort();
      repoLogger.write('unsynced commits: ${dep.unsyncedCommits.length}');

      repoLogger.close();
    }).toList();

    await firestore.updateSdkDependencies(sdkDependencies, logger: logger);

    logger.write('');
    logger.close(printElapsedTime: true);

    github.close();
  }

  Future updateMaintainersFromSheets() async {
    final logger = Logger();

    logger.write('Updating maintainers from sheets');

    final Sheets sheets = Sheets();
    await sheets.connect();

    logger.write('');
    final log = logger.subLogger('Getting maintainers data...');
    final List<PackageMaintainer> maintainers =
        await sheets.getMaintainersData(log);
    log.close();
    logger.write('Read data about ${maintainers.length} packages.');
    logger.write('');

    await firestore.updateMaintainers(maintainers, logger: logger);

    sheets.close();

    logger.write('');
    logger.close(printElapsedTime: true);
  }

  final RegExp repoRegex =
      RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

  Future updateRepositories() async {
    final logger = Logger();
    final publishers = await firestore.queryPublishers();

    logger.write('Getting repos for ${publishers.join(', ')}.');
    var repos =
        await firestore.queryRepositoriesForPublishers(publishers.toSet());
    logger.write('retrieved ${repos.length} repos');

    // ignore anything ending in '.git'
    repos = repos.where((repo) {
      if (repo.endsWith('.git')) {
        logger.write('* ignoring $repo');
      }
      return !repo.endsWith('.git');
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

    logger.write('');
    logger.write('${repos.length} sanitized repos');
    Map<String, int> counts = {};
    for (var repo in repos) {
      final key = repo.split('/').first;
      counts[key] = counts.putIfAbsent(key, () => 0) + 1;
    }
    logger.write(counts.keys.map((key) => '  $key: ${counts[key]}').join('\n'));

    // Get commit information from github.
    List<RepositoryInfo> repositories = repos.map((name) {
      return RepositoryInfo(path: name);
    }).toList();

    final Github github = Github();

    logger.write('');
    logger.write('Updating repositories...');

    final pool = Pool(4);

    await pool.forEach<RepositoryInfo, void>(repositories, (repo) async {
      final log = logger.subLogger(repo.path);

      // Look for CI configuration.
      // TODO: look to reduce the number of places to look.
      for (var filePath in [
        '.github/workflows/test-package.yml', // 61
        '.github/workflows/dart.yml', // 15
        '.github/workflows/ci.yml', // 9
        '.github/workflows/build.yaml', // 8
        // '.github/workflows/test.yaml', // 1
      ]) {
        var contents = await github.retrieveFile(
          orgAndRepo: repo.path,
          filePath: filePath,
        );

        if (contents != null) {
          var lines = contents.split('\n');
          if (lines.length >= 100) {
            lines = lines.take(99).toList()..add('...');
          }

          repo.actionsConfig = lines.join('\n');
          repo.actionsFile = filePath;
          log.write('found ${repo.actionsFile}');

          break;
        }
      }

      // todo: we should remove this filtering
      // Look for dependabot configuration.
      repo.dependabotConfig = await github.retrieveFile(
        orgAndRepo: repo.path,
        filePath: '.github/dependabot.yaml',
      );
      if (repo.dependabotConfig != null) {
        log.write('found .github/dependabot.yaml');
      }

      await firestore.updateRepositoryInfo(repo);

      log.close();
    }).toList();

    github.close();

    logger.write('');
    logger.close(printElapsedTime: true);
  }

  Future close() async {
    firestore.close();
    pub.close();
    _httpClient?.close();
  }
}
