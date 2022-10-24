import 'dart:convert';

import 'package:http/http.dart' as http;

import 'src/firestore.dart';
import 'src/github.dart';
import 'src/google3.dart';
import 'src/pub.dart';
import 'src/sdk.dart';
import 'src/sheets.dart';
import 'src/utils.dart';

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

    // These queries depend on the repository information being correct.
    if (!packageInfo.isDiscontinued &&
        packageInfo.repository != null &&
        !packageInfo.repository!.endsWith('.git') &&
        !packageInfo.repository!.endsWith('/')) {
      var repoInfo = packageInfo.repoInfo!;

      var commits = await github.queryCommitsAfter(
        repo: Repository(path: repoInfo.repoOrgAndName!),
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
            field == 'likes' ||
            field == 'popularity' ||
            field == 'publishedDate' ||
            field == 'pubspec' ||
            field == 'unpublishedCommitDate' ||
            field == 'unpublishedCommits') {
          continue;
        }

        if (updatedFields.keys.contains(field) &&
            !compareValues(existingInfo[field]!, updatedFields[field]!)) {
          final change = '$field: '
              '${printValue(existingInfo[field]!)} => '
              '${printValue(updatedFields[field]!)}';
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
      Repository repo = Repository(
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

    await firestore.updateGoogle3Dependencies(
      google3Dependencies,
      logger: logger,
    );

    logger.write('');
    logger.close(printElapsedTime: true);
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

  Future updateRepositories() async {
    final logger = Logger();
    final publishers = await firestore.queryPublishers();
    final existingRepositories = (await firestore.queryRespoitories()).toSet();

    logger.write('Getting repos for ${publishers.join(', ')}.');
    var packageRepositories =
        await firestore.queryRepositoriesForPublishers(publishers.toSet());
    logger.write('retrieved ${packageRepositories.length} repos');

    var repos = getUniqueRepoNames(packageRepositories);
    logger.write('');
    logger.write('${repos.length} unique repos');

    var repositories = repos.map((name) => Repository(path: name));

    final Github github = Github(profiler: profiler);

    logger.write('');
    logger.write('Updating repositories...');

    for (var repo in repositories) {
      existingRepositories.remove(repo.path);

      logger
        ..write(repo.path)
        ..indent();

      // Look for dependabot configuration.
      var dependabotFileExists = await github.testFileExists(
        orgAndRepo: repo.path,
        filePath: '.github/dependabot.yaml',
      );

      // workflows
      var workflowStr = await github.callRestApi(Uri.parse(
        'https://api.github.com/repos/${repo.org}/${repo.name}/actions/workflows',
      ));
      var workflows = workflowStr == null
          ? <GithubWorkflow>[]
          : GithubWorkflow.parse(workflowStr)
              .where((workflow) => workflow.active)
              .toList();
      var workflowsDesc =
          workflows.isEmpty ? null : workflows.map((w) => w.path).join(',');

      // issues and PRs
      var repoMetadata = await github.queryRepoIssuesPrs(repo);
      var untriagedIssues = await github.queryUntriagedIssues(repo);

      await firestore.updateRepositoryInfo(
        FirestoreRepositoryInfo(
          org: repo.org,
          name: repo.name,
          workflows: workflowsDesc,
          hasDependabot: dependabotFileExists,
          issueCount: untriagedIssues,
          prCount: repoMetadata.openPRs,
          defaultBranchName: repoMetadata.defaultBranchName,
        ),
      );

      logger.outdent();
    }

    // remove orphaned repos
    for (var repoPath in existingRepositories) {
      logger.write('removing $repoPath');
      await firestore.removeRepo(repoPath);
    }

    logger.write('');
    logger.write(profiler.results());
    logger.close(printElapsedTime: true);

    github.close();
  }

  Future close() async {
    firestore.close();
    pub.close();
    _httpClient?.close();
  }
}

final RegExp _repoRegex =
    RegExp(r'https:\/\/github\.com\/([\w\d\-_]+)\/([\w\d\-_\.]+)([\/\S]*)');

List<String> getUniqueRepoNames(List<String> packageRepositories) {
  // ignore anything ending in '.git'
  var repos =
      packageRepositories.where((repo) => !repo.endsWith('.git')).toList();

  // Collapse sub-dir references (handle mono-repos).
  repos = repos
      .map((repo) {
        var match = _repoRegex.firstMatch(repo);
        return match == null ? null : '${match.group(1)}/${match.group(2)}';
      })
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  return repos;
}

class GithubWorkflow {
  static List<GithubWorkflow> parse(String str) {
    var json = jsonDecode(str) as Map;
    var flows = json['workflows'] as List;
    return flows.map((data) => GithubWorkflow.from(data)).toList();
  }

  final Map data;

  GithubWorkflow.from(this.data);

  int get id => data['id'];
  String get name => data['name'];
  String get path => data['path'];
  String get state => data['state'];
  bool get active => state == 'active';
}
