import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/constants.dart';

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
                  label: 'Publishers',
                  width: 100,
                  grow: 0.2,
                  transformFunction: (dep) => dep.publishers.join(', '),
                  validators: [
                    (dep) {
                      if (dep.publishers.isEmpty) {
                        return ValidationResult.error('unverified publisher');
                      }

                      const stdPublishers = {
                        'dart.dev',
                        'google.dev',
                        'N/A',
                        'tools.dart.dev',
                      };

                      for (var publisher in dep.publishers) {
                        if (!stdPublishers.contains(publisher)) {
                          return ValidationResult.warning('Atypical publisher');
                        }
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
                        dep.sdkDep.commit.substring(0, commitLength),
                    renderFunction: (BuildContext context, dep) {
                      return Hyperlink(
                        url:
                            '${dep.sdkDep.repository}/commit/${dep.sdkDep.commit}',
                        displayText:
                            dep.sdkDep.commit.substring(0, commitLength),
                      );
                    }),
                VTableColumn(
                  label: 'SDK Sync Latency',
                  width: 100,
                  grow: 0.2,
                  alignment: Alignment.centerRight,
                  transformFunction: (dep) => dep.sdkDep.syncLatencyDescription,
                  compareFunction: (a, b) =>
                      SdkDep.compareUnsyncedDays(a.sdkDep, b.sdkDep),
                  validators: [
                    (dep) => SdkDep.validateSyncLatency(dep.sdkDep),
                  ],
                ),
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

  int? get unsyncedDays => sdkDep.unsyncedDays;

  static const gitDeps = {
    'https://github.com/dart-lang/http_io',
    'https://github.com/dart-lang/pub',
    'https://github.com/dart-archive/web-components',
  };

  List<String> get publishers {
    if (gitDeps.contains(sdkDep.repository)) {
      return ['N/A'];
    } else {
      return packages.map((p) => p.publisher).toSet().toList();
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
