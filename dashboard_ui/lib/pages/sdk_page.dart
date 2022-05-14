import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/constants.dart';

class SDKDependenciesWidget extends StatefulWidget {
  final DataModel dataModel;

  const SDKDependenciesWidget({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<SDKDependenciesWidget> createState() => _SDKDependenciesWidgetState();
}

class _SDKDependenciesWidgetState extends State<SDKDependenciesWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: widget.dataModel.packages,
      builder: (context, packages, _) {
        return ValueListenableBuilder<List<SdkDep>>(
          valueListenable: widget.dataModel.sdkDependencies,
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

  @override
  bool get wantKeepAlive => true;
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
