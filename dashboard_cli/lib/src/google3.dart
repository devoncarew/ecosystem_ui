import 'package:dashboard_cli/src/pub.dart';

import 'github.dart';

class Google3 {
  // TODO: This is mocked out for now.
  Future<List<Google3Dependency>> getSyncedPackageRepos({
    required Set<String> repositories,
  }) async {
    // TODO: The intent here is only to return information about the given
    // repositories.

    return [
      // TODO: also collect info about copybara (has a config, ...)
      Google3Dependency(
        repository: 'https://github.com/dart-lang/args',
        commit: '862d929b980b993334974d38485a39d891d83918',
      ),
      Google3Dependency(
        repository: 'https://github.com/dart-lang/logging',
        commit: 'dfbe88b890c3b4f7bc06da5a7b3b43e9e263b688',
      ),
      Google3Dependency(
        repository: 'https://github.com/dart-lang/path',
        commit: '3d41ea582f5b0b18de3d90008809b877ff3f69bc',
      ),
    ];
  }
}

class Google3Dependency {
  final String repository;
  final String commit;

  // Note that this information is populated after construction.
  Commit? commitInfo;
  List<Commit> unsyncedCommits = [];

  Google3Dependency({
    required this.repository,
    required this.commit,
  });

  String get orgAndName {
    return RepoInfo(repository).repoOrgAndName!;
  }

  @override
  String toString() => '$repository 0x$commit';
}
