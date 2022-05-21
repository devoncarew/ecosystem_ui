import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/constants.dart';
import '../utils/utils.dart';

class Google3Widget extends StatefulWidget {
  final DataModel dataModel;

  const Google3Widget({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<Google3Widget> createState() => _Google3WidgetState();
}

class _Google3WidgetState extends State<Google3Widget>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: widget.dataModel.packages,
      builder: (context, packages, _) {
        return ValueListenableBuilder<List<Google3Dep>>(
          valueListenable: widget.dataModel.googleDependencies,
          builder: (context, google3Deps, _) {
            final deps = _calculateDeps(google3Deps, packages);

            return VTable<Google3PackagesDep>(
              items: deps,
              tableDescription: '${google3Deps.length} repos',
              columns: [
                VTableColumn(
                  label: 'Repository',
                  width: 175,
                  grow: 0.2,
                  transformFunction: (dep) => dep.dep.repository,
                  renderFunction: (BuildContext context, dep) {
                    return Hyperlink(
                      url: dep.dep.repository,
                      displayText: trimPrefix(dep.dep.repository, 'https://'),
                    );
                  },
                ),
                VTableColumn(
                  label: 'Packages',
                  width: 175,
                  grow: 0.2,
                  transformFunction: (dep) =>
                      dep.packages.map((p) => p.name).join(', '),
                ),
                VTableColumn(
                  label: 'Publishers',
                  width: 100,
                  grow: 0.2,
                  transformFunction: (dep) => dep.publishers.join(', '),
                ),
                VTableColumn(
                  label: 'Copybara',
                  width: 100,
                  grow: 0.2,
                  // todo:
                  transformFunction: (dep) => 'todo:',
                  // compareFunction: (a, b) =>
                  //     SdkDep.compareUnsyncedDays(a.sdkDep, b.sdkDep),
                  // validators: [
                  //   (dep) => SdkDep.validateSyncLatency(dep.sdkDep),
                  // ],
                ),
                VTableColumn(
                  label: 'Synced to Commit',
                  width: 75,
                  grow: 0.1,
                  alignment: Alignment.centerRight,
                  transformFunction: (dep) =>
                      dep.dep.commit.substring(0, commitLength),
                  renderFunction: (BuildContext context, dep) {
                    return Hyperlink(
                      url: '${dep.dep.repository}/commit/${dep.dep.commit}',
                      displayText: dep.dep.commit.substring(0, commitLength),
                    );
                  },
                ),
                VTableColumn(
                  label: 'Google3 Sync Latency',
                  width: 100,
                  grow: 0.2,
                  alignment: Alignment.centerRight,
                  transformFunction: (dep) => dep.dep.syncLatencyDescription,
                  compareFunction: (a, b) =>
                      Google3Dep.compareUnsyncedDays(a.dep, b.dep),
                  validators: [
                    (dep) => Google3Dep.validateSyncLatency(dep.dep),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  static List<PackageInfo> _filterPackages(
    List<PackageInfo> packages,
    String repo,
  ) {
    packages = packages.where((p) => p.repoUrl == repo).toList();

    // Remove the discontinued packages.
    packages = packages.where((p) => !p.discontinued).toList();

    packages.sort((a, b) => a.name.compareTo(b.name));

    return packages;
  }

  static List<Google3PackagesDep> _calculateDeps(
    List<Google3Dep> deps,
    List<PackageInfo> packages,
  ) {
    return deps.map((dep) {
      return Google3PackagesDep(
        dep: dep,
        packages: _filterPackages(packages, dep.repository),
      );
    }).toList();
  }

  @override
  bool get wantKeepAlive => true;
}

class Google3PackagesDep {
  final Google3Dep dep;
  final List<PackageInfo> packages;

  Google3PackagesDep({required this.dep, required this.packages});

  List<String> get publishers {
    return packages.map((p) => p.publisher).toSet().toList();
  }
}
