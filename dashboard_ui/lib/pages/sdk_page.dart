import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';

class SDKPage extends NavPage {
  final DataModel dataModel;

  SDKPage(this.dataModel) : super('SDK');

  @override
  Widget createChild(BuildContext context, {Key? key}) {
    return _SDKPage(dataModel: dataModel, key: key);
  }
}

class _SDKPage extends StatelessWidget {
  final DataModel dataModel;

  const _SDKPage({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SDKDependenciesWidget(dataModel: dataModel);
  }
}

class SDKDependenciesWidget extends StatelessWidget {
  final DataModel dataModel;

  const SDKDependenciesWidget({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: dataModel.packages,
      builder: (context, packages, _) {
        return ValueListenableBuilder<List<SdkDep>>(
          valueListenable: dataModel.sdkDependencies,
          builder: (context, sdkDeps, _) {
            List<PackageRepoDep> deps = _calculateDeps(sdkDeps, packages);

            return VTable<PackageRepoDep>(
              items: deps,
              tableDescription: '${sdkDeps.length} repos',
              actions: const [
                Hyperlink(
                  displayText: 'DEPS',
                  url: 'https://github.com/dart-lang/sdk/blob/main/DEPS',
                ),
              ],
              columns: [
                VTableColumn(
                  label: 'Repo',
                  width: 275,
                  grow: 0.2,
                  transformFunction: (dep) => dep.sdkDep.repository,
                  renderFunction: (BuildContext context, dep) {
                    return Hyperlink(url: dep.sdkDep.repository);
                  },
                ),
                VTableColumn(
                  label: 'Packages',
                  width: 125,
                  grow: 0.2,
                  transformFunction: (dep) =>
                      dep.packages.map((p) => p.name).join(', '),
                ),
                VTableColumn(
                  label: 'Publisher',
                  width: 100,
                  grow: 0.2,
                  transformFunction: (dep) => dep.publisher,
                  validators: [
                    (dep) {
                      if (dep.publisher.isEmpty) {
                        return ValidationResult.error('unverified publisher');
                      }

                      const stdPublishers = {
                        'dart.dev',
                        'google.dev',
                        'N/A',
                        'tools.dart.dev',
                      };

                      if (!stdPublishers.contains(dep.publisher)) {
                        return ValidationResult.warning('Atypical publisher');
                      }

                      return null;
                    },
                  ],
                ),
                VTableColumn(
                    label: 'Synced to Commit',
                    width: 75,
                    grow: 0.2,
                    alignment: Alignment.centerRight,
                    transformFunction: (dep) =>
                        dep.sdkDep.commit.substring(0, 7),
                    renderFunction: (BuildContext context, dep) {
                      return Hyperlink(
                        url:
                            '${dep.sdkDep.repository}/commit/${dep.sdkDep.commit}',
                        displayText: dep.sdkDep.commit.substring(0, 7),
                      );
                    }),
                VTableColumn(
                    label: 'Sync Latency',
                    width: 100,
                    grow: 0.2,
                    alignment: Alignment.centerRight,
                    transformFunction: (dep) {
                      var latencyDays = dep.unsyncedDays;
                      if (latencyDays == null) {
                        return '';
                      }
                      return '${dep.unsyncedCommits} commits, '
                          '${dep.unsyncedDays} days';
                    },
                    compareFunction: (a, b) {
                      return (a.unsyncedDays ?? 0) - (b.unsyncedDays ?? 0);
                    },
                    validators: [
                      (dep) {
                        if ((dep.unsyncedDays ?? 0) > 365) {
                          return ValidationResult.error(
                            'Greater than 365 days of latency',
                          );
                        }
                        if ((dep.unsyncedDays ?? 0) > 30) {
                          return ValidationResult.warning(
                            'Greater than 30 days of latency',
                          );
                        }
                        return null;
                      }
                    ]),
              ],
            );
          },
        );
      },
    );
  }

  List<PackageInfo> _filterPackages(List<PackageInfo> packages, String repo) {
    packages = packages.where((p) => p.repoUrl == repo).toList();

    // Remove the discontinued packages.
    packages = packages.where((p) => !p.discontinued).toList();

    packages.sort((a, b) => a.name.compareTo(b.name));

    return packages;
  }

  List<PackageRepoDep> _calculateDeps(
    List<SdkDep> sdkDeps,
    List<PackageInfo> allPackages,
  ) {
    return sdkDeps.map((dep) {
      final packages = _filterPackages(allPackages, dep.repository);
      return PackageRepoDep(
        packages: packages,
        sdkDep: dep,
      );
    }).toList();
  }
}

class PackageRepoDep {
  final List<PackageInfo> packages;
  final SdkDep sdkDep;

  PackageRepoDep({
    required this.packages,
    required this.sdkDep,
  });

  int get unsyncedCommits => sdkDep.unsyncedCommits;

  int? get unsyncedDays {
    var date = sdkDep.unsyncedCommitDate;
    if (date == null) {
      return null;
    }

    return DateTime.now().toUtc().difference(date.toDate()).inDays;
  }

  static const gitDeps = {
    'https://github.com/dart-lang/http_io',
    'https://github.com/dart-lang/pub',
    'https://github.com/dart-archive/web-components',
  };

  String get publisher {
    if (gitDeps.contains(sdkDep.repository)) {
      return 'N/A';
    } else {
      return packages.isEmpty ? '' : packages.first.publisher;
    }
  }
}

// class SDKPackagesWidget extends StatelessWidget {
//   final DataModel dataModel;

//   const SDKPackagesWidget({
//     required this.dataModel,
//     Key? key,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return ValueListenableBuilder<List<PackageInfo>>(
//       valueListenable: dataModel.packages,
//       builder: (context, packages, _) {
//         return VTable<PackageInfo>(
//           items: _filterPackages(packages),
//           columns: [
//             VTableColumn(
//               label: 'Package',
//               width: 125,
//               grow: 0.2,
//               transformFunction: (p) => p.name,
//               styleFunction: PackageInfo.getDisplayStyle,
//             ),
//             VTableColumn(
//               label: 'Publisher',
//               width: 125,
//               grow: 0.2,
//               transformFunction: PackageInfo.getPublisherDisplayName,
//               styleFunction: PackageInfo.getDisplayStyle,
//             ),
//             VTableColumn(
//               label: 'Maintainer',
//               width: 125,
//               grow: 0.2,
//               transformFunction: (p) => p.maintainer,
//               styleFunction: PackageInfo.getDisplayStyle,
//             ),
//             VTableColumn(
//               label: 'Version',
//               alignment: Alignment.centerRight,
//               width: 100,
//               transformFunction: (p) => p.version.toString(),
//               compareFunction: (a, b) {
//                 return a.version.compareTo(b.version);
//               },
//               styleFunction: PackageInfo.getDisplayStyle,
//             ),
//           ],
//         );
//       },
//     );
//   }

//   List<PackageInfo> _filterPackages(List<PackageInfo> packages) {
//     // Just SDK packages.
//     packages = packages
//         .where((p) => p.repoUrl == 'https://github.com/dart-lang/sdk')
//         .toList();

//     // Remove the discontinued packages.
//     packages = packages.where((p) => !p.discontinued).toList();

//     packages.sort((a, b) => a.name.compareTo(b.name));

//     return packages;
//   }
// }
