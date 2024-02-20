import 'github.dart';
import 'utils.dart';

final RegExp _packageNames = RegExp(r'"\/third_party\/pkg\/(\w+)"');
final RegExp _repositoryHashes = RegExp(r'"(\w+)_rev"\s*:\s*"([\w\d]+)"');

class Sdk {
  static Future<Sdk> fromHttpGet() async {
    final depsData = await httpGet(
        Uri.parse('https://raw.githubusercontent.com/dart-lang/sdk/main/DEPS'));
    final lines = depsData.split('\n');

    // Var("dart_root") + "/third_party/pkg/args":
    // Var("dart_root") + "/third_party/pkg/package_config":
    Set<String> packages = {};
    for (var line in lines) {
      Match? match = _packageNames.firstMatch(line);
      if (match != null) {
        // collection_rev = e1407da23b9f17400b3a905aafe2b8fa10db3d86
        packages.add(match.group(1)!);
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

    return Sdk._(packages, repoHash);
  }

  final Set<String> _packages;
  final Map<String, String> _repoHash;

  Sdk._(this._packages, this._repoHash);

  List<SdkDependency> getDartPackages() {
    // See https://github.com/dart-lang/sdk/issues/48830 for some of the
    // hard-coded repo mappings here.
    const specialCases = {
      'file': 'https://github.com/google/file.dart',
      'material_color_utilities':
          'https://github.com/material-foundation/material-color-utilities',
      'protobuf': 'https://github.com/google/protobuf.dart',
      'sync_http': 'https://github.com/google/sync_http.dart',
      'tar': 'https://github.com/simolus3/tar',
      'vector_math': 'https://github.com/google/vector_math.dart',
      'web_components': 'https://github.com/dart-archive/web-components',
      'webkit_inspection_protocol':
          'https://github.com/google/webkit_inspection_protocol.dart',
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
  final String repository;
  final String? commit;

  // Note that this information is populated after construction.
  Commit? commitInfo;
  List<Commit> unsyncedCommits = [];

  SdkDependency({
    required this.name,
    required this.repository,
    required this.commit,
  });

  @override
  String toString() => '$name, 0x$commit, $repository';
}
