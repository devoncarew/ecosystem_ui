import 'github.dart';
import 'utils.dart';

final RegExp _packageNames = RegExp(r'"\/third_party\/pkg(_tested)?\/(\w+)"');
final RegExp _repositoryHashes = RegExp(r'"(\w+)_rev"\s*:\s*"([\w\d]+)"');
final RegExp _externalRepo = RegExp(r'"external\/(\S+)"');

class Sdk {
  static Future<Sdk> fromHttpGet() async {
    final depsData = await httpGet(
        Uri.parse('https://raw.githubusercontent.com/dart-lang/sdk/main/DEPS'));
    final lines = depsData.split('\n');

    // Var("dart_root") + "/third_party/pkg/args":
    // Var("dart_root") + "/third_party/pkg_tested/package_config":
    Set<String> packages = {};
    for (var line in lines) {
      Match? match = _packageNames.firstMatch(line);
      if (match != null) {
        // collection_rev = e1407da23b9f17400b3a905aafe2b8fa10db3d86
        packages.add(match.group(2)!);
      }
    }

    // "collection_rev": "e1407da23b9f17400b3a905aafe2b8fa10db3d86",
    Map<String, String> repoHash = {};
    for (var line in lines) {
      Match? match = _repositoryHashes.firstMatch(line);
      if (match != null) {
        repoHash[match.group(1)!] = match.group(2)!;
      }
    }

    // Var("dart_git") + "external/github.com/google/vector_math.dart.git" +
    Set<String> externalRepos = {};
    for (var line in lines) {
      Match? match = _externalRepo.firstMatch(line);
      if (match != null) {
        externalRepos.add(match.group(1)!);
      }
    }

    return Sdk._(packages, repoHash, externalRepos);
  }

  final Set<String> _packages;
  final Map<String, String> _repoHash;
  final Set<String> _externalRepos;

  Sdk._(this._packages, this._repoHash, this._externalRepos);

  List<SdkDependency> getDartPackages() {
    // See https://github.com/dart-lang/sdk/issues/48830 for some of the
    // hard-coded repo mappings here.
    const specialCases = {
      'charcode': 'https://github.com/lrhn/charcode',
      'platform': 'https://github.com/google/platform.dart',
      'process': 'https://github.com/google/process.dart',
      'protobuf': 'https://github.com/google/protobuf.dart',
      'web_components': 'https://github.com/dart-archive/web-components',
    };

    List<SdkDependency> deps = [];

    for (String name in _packages) {
      // Default to a dart-lang github url.
      String repo = 'https://github.com/dart-lang/$name';

      // Check for special case repos - ones which had been in dart-lang/ when
      // their mirrors were set up, but have since moved to other github orgs.
      if (specialCases.containsKey(name)) {
        repo = specialCases[name]!;
      }

      // Check for explicit external dependency urls in the DEPS file.
      String? externalRepo = _externalRepos
          .cast<String?>()
          .firstWhere((repo) => repo!.contains('/$name'), orElse: () => null);
      if (externalRepo != null) {
        if (externalRepo.endsWith('.git')) {
          externalRepo =
              externalRepo.substring(0, externalRepo.length - '.git'.length);
        }
        repo = 'https://$externalRepo';
      }

      deps.add(SdkDependency(
        name: name,
        commit: _repoHash[name],
        repository: repo,
      ));
    }

    return deps;
  }
}

class SdkDependency {
  final String name;
  final String? commit;
  final String repository;

  Commit? commitInfo;
  List<Commit> unsyncedCommits = [];

  SdkDependency({
    required this.name,
    required this.commit,
    required this.repository,
  });

  @override
  String toString() => '$name, 0x$commit, $repository';
}
