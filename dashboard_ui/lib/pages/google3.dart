import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/constants.dart';

class Google3Sheet extends StatefulWidget {
  final DataModel dataModel;

  const Google3Sheet({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<Google3Sheet> createState() => _Google3SheetState();
}

class _Google3SheetState extends State<Google3Sheet>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: widget.dataModel.packages,
      builder: (context, packages, _) {
        return ValueListenableBuilder<List<Google3Dep>>(
          valueListenable: widget.dataModel.googleDependencies,
          builder: (context, deps, _) {
            Map<String, PackageInfo?> packageNameMap = {};
            for (var package in widget.dataModel.packages.value) {
              packageNameMap[package.name] = package;
            }

            return VTable<Google3Dep>(
              items: deps,
              tableDescription: '${deps.length} packages',
              columns: [
                VTableColumn(
                  label: 'Package',
                  width: 175,
                  grow: 0.2,
                  transformFunction: (dep) {
                    return dep.name;
                  },
                  validators: [
                    (Google3Dep dep) {
                      if (dep.error != null) {
                        return ValidationResult.error(dep.error!);
                      }
                      return null;
                    }
                  ],
                ),
                VTableColumn(
                  label: 'Publisher',
                  width: 100,
                  grow: 0.2,
                  transformFunction: (dep) {
                    return packageNameMap[dep.name]?.publisher ?? '';
                  },
                ),
                // VTableColumn(
                //   label: 'Copybara',
                //   width: 100,
                //   grow: 0.2,
                //   // todo:
                //   transformFunction: (dep) => 'todo:',
                //   // compareFunction: (a, b) =>
                //   //     SdkDep.compareUnsyncedDays(a.sdkDep, b.sdkDep),
                //   // validators: [
                //   //   (dep) => SdkDep.validateSyncLatency(dep.sdkDep),
                //   // ],
                // ),
                VTableColumn(
                  label: 'Location',
                  width: 60,
                  grow: 0.1,
                  transformFunction: (dep) =>
                      dep.firstParty ? 'Google3' : 'GitHub',
                ),
                VTableColumn(
                  label: 'Synced to Commit',
                  width: 75,
                  grow: 0.1,
                  alignment: Alignment.centerRight,
                  transformFunction: (dep) {
                    if (dep.firstParty) {
                      return 'N/A';
                    }
                    if (dep.commit == null || dep.commit!.isEmpty) {
                      return '';
                    }
                    return dep.commit!.substring(0, commitLength);
                  },
                  renderFunction: (BuildContext context, dep) {
                    var packageInfo = packageNameMap[dep.name];
                    if (packageInfo == null) return null;

                    if (dep.commit == null || dep.commit!.isEmpty) {
                      return null;
                    }

                    return Hyperlink(
                      url: '${packageInfo.repoUrl}/commit/${dep.commit}',
                      displayText: dep.commit!.substring(0, commitLength),
                    );
                  },
                ),
                VTableColumn(
                  label: 'Google3 Sync Latency',
                  width: 100,
                  grow: 0.2,
                  alignment: Alignment.centerRight,
                  transformFunction: (dep) => dep.syncLatencyDescription,
                  compareFunction: (a, b) =>
                      Google3Dep.compareUnsyncedDays(a, b),
                  validators: [
                    (dep) => Google3Dep.validateSyncLatency(dep),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
