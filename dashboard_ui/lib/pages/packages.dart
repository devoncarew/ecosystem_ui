import 'package:dashboard_ui/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart' as url;

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/utils.dart';

class PackagesSheet extends StatefulWidget {
  final List<String> publishers;

  const PackagesSheet({
    required this.publishers,
    Key? key,
  }) : super(key: key);

  @override
  State<PackagesSheet> createState() => _PackagesSheetState();
}

class _PackagesSheetState extends State<PackagesSheet>
    with AutomaticKeepAliveClientMixin {
  final Set<String> visiblePublishers = {};
  bool showUnlisted = true;
  bool showDiscontinued = false;
  String? filterText;

  @override
  void initState() {
    super.initState();

    visiblePublishers.add(widget.publishers.first);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    var dataModel = DataModel.of(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: dataModel.packages,
      builder: (context, packages, _) {
        final filteredPackages = _filterPackages(packages);

        return createTable(
          filteredPackages,
          dataModel: dataModel,
          allPackages: packages,
        );
      },
    );
  }

  void _onDoubleClick(DataModel dataModel, PackageInfo package) {
    showDialog(
      context: context,
      builder: (context) {
        return LargeDialog(
          title: 'package:${package.name}',
          medium: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PubspecInfoWidget(package: package),
          ),
        );
      },
    );
  }

  VTable createTable(
    List<PackageInfo> packages, {
    required DataModel dataModel,
    required List<PackageInfo> allPackages,
  }) {
    var description = '${packages.length} packages';
    var allFromPublisher = allPackages.where((p) {
      return visiblePublishers.contains(p.publisher);
    }).toList();
    if (allFromPublisher.length > packages.length) {
      description = '$description ('
          '${allFromPublisher.length - packages.length} not shown)';
    }

    return VTable<PackageInfo>(
      items: packages,
      sortedIndex: 0,
      supportsSelection: true,
      onDoubleTap: (item) => _onDoubleClick(dataModel, item),
      tableDescription: description,
      actions: [
        SearchField(
          hintText: 'Filter',
          height: toolbarHeight,
          // TODO: fix the notification here
          //showClearAction: filterText != null,
          onChanged: (value) {
            _updateFilter(value);
          },
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: toolbarHeight),
          child: ToggleButtons(
            borderRadius: BorderRadius.circular(6),
            textStyle: Theme.of(context).textTheme.titleMedium,
            isSelected: [
              ...widget.publishers.map((p) => visiblePublishers.contains(p)),
            ],
            onPressed: (index) {
              setState(() {
                var publisher = widget.publishers[index];
                visiblePublishers.toggle(publisher);
              });
            },
            children: [
              ...widget.publishers.map((p) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(p),
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: toolbarHeight),
          child: ToggleButtons(
            borderRadius: BorderRadius.circular(6),
            isSelected: [
              showUnlisted,
              showDiscontinued,
            ],
            onPressed: (index) {
              setState(() {
                if (index == 0) {
                  showUnlisted = !showUnlisted;
                } else {
                  showDiscontinued = !showDiscontinued;
                }
              });
            },
            children: [
              Tooltip(
                message: '${showUnlisted ? 'Hide' : 'Show'} Unlisted Packages',
                child: const Icon(Icons.remove_red_eye, size: defaultIconSize),
              ),
              Tooltip(
                message:
                    '${showDiscontinued ? 'Hide' : 'Show'} Discontinued Packages',
                child: const Icon(Icons.no_accounts, size: defaultIconSize),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const SizedBox(
          height: toolbarHeight,
          child: VerticalDivider(),
        ),
      ],
      columns: [
        VTableColumn<PackageInfo>(
          label: 'Name',
          width: 110,
          grow: 0.2,
          transformFunction: (package) => package.name,
          styleFunction: PackageInfo.getDisplayStyle,
          compareFunction: PackageInfo.compare,
        ),
        VTableColumn<PackageInfo>(
          label: 'Publisher',
          width: 85,
          grow: 0.1,
          transformFunction: PackageInfo.getPublisherDisplayName,
          styleFunction: PackageInfo.getDisplayStyle,
        ),
        VTableColumn<PackageInfo>(
          label: 'Maintainer',
          width: 100,
          grow: 0.2,
          transformFunction: (package) => package.maintainer,
          styleFunction: PackageInfo.getDisplayStyle,
          validators: [
            PackageInfo.validateMaintainers,
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Repository',
          width: 150,
          grow: 0.2,
          transformFunction: (package) => package.repository ?? '',
          styleFunction: PackageInfo.getDisplayStyle,
          renderFunction:
              (BuildContext context, PackageInfo package, String out) {
            if (package.repository == null) return null;

            return Hyperlink(
              url: package.repository!,
              displayText: trimPrefix(package.repository!, 'https://'),
              style: PackageInfo.getDisplayStyle(package),
            );
          },
          validators: [
            PackageInfo.validateRepositoryInfo,
          ],
        ),
        //   label: 'Issues',
        //   width: 80,
        //   alignment: Alignment.centerRight,
        //   transformFunction: (PackageInfo package) => package.issuesUrl ?? '',
        //   renderFunction:
        //       (BuildContext context, PackageInfo package, String out) {
        //     var url = package.issuesUrl;
        //     if (url == null) return null;

        //     return Hyperlink(
        //       url: url,
        //       displayText: 'link',
        //       style: PackageInfo.getDisplayStyle(package),
        //     );
        //   },
        // ),
        VTableColumn(
          label: 'SDK Latency',
          width: 80,
          grow: 0.2,
          alignment: Alignment.centerRight,
          transformFunction: (package) {
            var dep = dataModel.getSdkDepForPackage(package);
            return dep == null ? 'n/a' : dep.syncLatencyDescription;
          },
          compareFunction: (a, b) {
            var aDep = dataModel.getSdkDepForPackage(a);
            var bDep = dataModel.getSdkDepForPackage(b);
            if (aDep == null && bDep == null) {
              return 0;
            } else if (aDep != null && bDep == null) {
              return 1;
            } else if (aDep == null && bDep != null) {
              return -1;
            } else {
              return SdkDep.compareUnsyncedDays(aDep!, bDep!);
            }
          },
          validators: [
            (package) {
              var dep = dataModel.getSdkDepForPackage(package);
              return dep == null ? null : SdkDep.validateSyncLatency(dep);
            },
          ],
        ),
        VTableColumn(
          label: 'Google3 Latency',
          width: 80,
          grow: 0.2,
          alignment: Alignment.centerRight,
          transformFunction: (package) {
            var dep = dataModel.getGoogle3DepForPackage(package);
            return dep == null ? 'n/a' : dep.syncLatencyDescription;
          },
          compareFunction: (a, b) {
            var aDep = dataModel.getGoogle3DepForPackage(a);
            var bDep = dataModel.getGoogle3DepForPackage(b);
            if (aDep == null && bDep == null) {
              return 0;
            } else if (aDep != null && bDep == null) {
              return 1;
            } else if (aDep == null && bDep != null) {
              return -1;
            } else {
              return Google3Dep.compareUnsyncedDays(aDep!, bDep!);
            }
          },
          validators: [
            (package) {
              var dep = dataModel.getGoogle3DepForPackage(package);
              return dep == null ? null : Google3Dep.validateSyncLatency(dep);
            },
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Repo Version',
          width: 90,
          alignment: Alignment.centerRight,
          transformFunction: (package) =>
              package.githubVersion?.toString() ?? '',
          styleFunction: PackageInfo.getDisplayStyle,
          compareFunction: (a, b) {
            var aVersion = a.githubVersion ?? Version.none;
            var bVersion = b.githubVersion ?? Version.none;
            return aVersion.compareTo(bVersion);
          },
          validators: [
            PackageInfo.needsPublishValidator,
          ],
        ), // VTableColumn<PackageInfo>(
        VTableColumn(
          label: 'Publish Latency',
          width: 80,
          grow: 0.2,
          alignment: Alignment.centerRight,
          transformFunction: (package) {
            var latencyDays = package.unpublishedDays;
            if (latencyDays == null || package.unpublishedCommits == 0) {
              return '';
            }
            return '${package.unpublishedCommits} commits, '
                '${package.unpublishedDays} days';
          },
          compareFunction: PackageInfo.compareUnsyncedDays,
          validators: [PackageInfo.validatePublishLatency],
        ),
        VTableColumn<PackageInfo>(
          label: 'Pub Version',
          width: 80,
          alignment: Alignment.centerRight,
          transformFunction: (package) => package.version.toString(),
          styleFunction: PackageInfo.getDisplayStyle,
          compareFunction: (a, b) {
            return a.version.compareTo(b.version);
          },
          validators: [
            PackageInfo.validateVersion,
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Score',
          width: 50,
          icon: Icons.numbers,
          alignment: Alignment.centerRight,
          transformFunction: (package) => package.score.toString(),
          compareFunction: (a, b) {
            return b.score.compareTo(a.score);
          },
          validators: [
            (PackageInfo package) {
              if (package.score < 85) {
                return ValidationResult.warning('low package score');
              }
              return null;
            }
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Popularity',
          width: 50,
          icon: Icons.show_chart,
          alignment: Alignment.centerRight,
          transformFunction: (package) => package.popularity.toString(),
          compareFunction: (a, b) {
            return b.popularity.compareTo(a.popularity);
          },
          validators: [
            (PackageInfo package) {
              if (package.popularity <= 40) {
                return ValidationResult.warning('low package popularity');
              }
              return null;
            }
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Likes',
          icon: Icons.thumb_up,
          width: 50,
          alignment: Alignment.centerRight,
          transformFunction: (package) => package.likes.toString(),
          compareFunction: (a, b) {
            return b.likes.compareTo(a.likes);
          },
        ),
      ],
    );
  }

  void _updateFilter(String filter) {
    filter = filter.trim().toLowerCase();

    setState(() {
      filterText = filter.isEmpty ? null : filter;
    });
  }

  List<PackageInfo> _filterPackages(
    List<PackageInfo> packages,
  ) {
    return packages
        .where((p) => visiblePublishers.contains(p.publisher))
        .where((p) => showUnlisted ? true : !p.unlisted)
        .where((p) => showDiscontinued ? true : !p.discontinued)
        .where((p) => filterText == null ? true : p.matchesFilter(filterText!))
        .toList();
  }

  @override
  bool get wantKeepAlive => true;
}

class PubspecInfoWidget extends StatelessWidget {
  final PackageInfo package;

  const PubspecInfoWidget({
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        SingleChildScrollView(
          child: SelectableText(
            package.pubspecDisplay,
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
        OverlayButtons(
          infoText: 'Package data from ${package.publishedDateDisplay} publish',
          children: [
            IconButton(
              icon: const Icon(Icons.launch),
              tooltip: 'pub.dev/${package.name}',
              iconSize: defaultIconSize,
              splashRadius: defaultSplashRadius,
              onPressed: () {
                url.launchUrl(
                    Uri.parse('https://pub.dev/packages/${package.name}'));
              },
            ),
          ],
        ),
      ],
    );
  }
}
