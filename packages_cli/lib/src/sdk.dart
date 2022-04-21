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

  List<DartPackage> getDartPackages() {
    // todo: we need to normalize the DEPS file a bit
    return _packages
        .map((String name) {
          String? hash = _repoHash[name];
          String repoTag = '/$name.';
          String? externalRepo = _externalRepos.cast<String?>().firstWhere(
              (repo) => repo!.contains(repoTag),
              orElse: () => null);

          if (externalRepo != null && externalRepo.endsWith('.git')) {
            externalRepo =
                externalRepo.substring(0, externalRepo.length - '.git'.length);
          }

          if (hash == null) {
            print('No hash found for package:$name');
            return null;
          } else {
            return DartPackage(
              name: name,
              commit: hash,
              externalRepo: externalRepo,
            );
          }
        })
        .whereType<DartPackage>()
        .toList();
  }
}

class DartPackage {
  final String name;
  final String commit;
  final String? _externalRepo;

  DartPackage({required this.name, required this.commit, String? externalRepo})
      : _externalRepo = externalRepo;

  String get repository {
    return _externalRepo != null
        ? _externalRepo!
        : 'github.com/dart-lang/$name';
  }

  @override
  String toString() => '$name, 0x$commit, $repository';
}
