import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url;

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';
import '../utils/utils.dart';

class PackagesPage extends NavPage {
  final List<String> publishers;

  PackagesPage({
    required this.publishers,
  }) : super('Packages');

  @override
  int? get tabPages => publishers.length;

  @override
  PreferredSizeWidget? createBottomBar(BuildContext context) {
    return TabBar(
      // unselectedLabelColor: Colors.white,
      // labelColor: Colors.amber,
      tabs: [
        for (var publisher in publishers) Tab(text: publisher),
      ],
    );
  }

  @override
  Widget createChild(BuildContext context, {Key? key}) {
    return _PubPage(
      publishers: publishers,
      key: key,
    );
  }
}

class _PubPage extends StatefulWidget {
  final List<String> publishers;

  const _PubPage({
    required this.publishers,
    Key? key,
  }) : super(key: key);

  @override
  State<_PubPage> createState() => _PubPageState();
}

class _PubPageState extends State<_PubPage> {
  // @override
  // void didUpdateWidget(covariant PubPage oldWidget) {
  //   super.didUpdateWidget(oldWidget);

  //   tabController.dispose();
  //   tabController = TabController(
  //     length: widget.publishers.length,
  //     initialIndex: tabController.index,
  //     vsync: this,
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        for (var publisher in widget.publishers)
          PublisherPackagesWidget(
            publisher: publisher,
            key: ValueKey(publisher),
          ),
      ],
    );
  }
}

class PublisherPackagesWidget extends StatefulWidget {
  final String publisher;

  const PublisherPackagesWidget({
    required this.publisher,
    Key? key,
  }) : super(key: key);

  @override
  State<PublisherPackagesWidget> createState() =>
      _PublisherPackagesWidgetState();
}

class _PublisherPackagesWidgetState extends State<PublisherPackagesWidget> {
  PackageInfo? selectedPackage;

  @override
  Widget build(BuildContext context) {
    var dataModel = DataModel.of(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: dataModel.getPackagesForPublisher(widget.publisher),
      builder: (context, packages, _) {
        return Column(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: createTable(packages),
              ),
            ),
            // // TODO: Animate showing and hiding this.
            // AnimatedContainer(
            //   duration: const Duration(milliseconds: 200),
            //   height: selectedPackage != null ? 300 : 0,
            //   child: selectedPackage != null
            //       ? ClipRect(
            //           child: PackageDetailsWidget(
            //             package: selectedPackage!,
            //           ),
            //         )
            //       : const SizedBox(),
            // ),
            if (selectedPackage != null)
              Expanded(
                flex: 3,
                child: PackageDetailsWidget(
                  package: selectedPackage!,
                ),
              ),
          ],
        );
      },
    );
  }

  void _onTap(PackageInfo package) {
    setState(() {
      if (selectedPackage == package) {
        selectedPackage = null;
      } else {
        selectedPackage = package;
      }
    });
  }

  VTable createTable(List<PackageInfo> packages) {
    return VTable<PackageInfo>(
      items: packages,
      startsSorted: true,
      supportsSelection: true,
      onTap: _onTap,
      columns: [
        VTableColumn<PackageInfo>(
          label: 'Name',
          width: 140,
          grow: 0.1,
          transformFunction: (package) => package.name,
          styleFunction: PackageInfo.getDisplayStyle,
          compareFunction: PackageInfo.compareWithStatus,
        ),
        VTableColumn<PackageInfo>(
          label: 'Publisher',
          width: 100,
          grow: 0.1,
          transformFunction: PackageInfo.getPublisherDisplayName,
          styleFunction: PackageInfo.getDisplayStyle,
        ),
        VTableColumn<PackageInfo>(
          label: 'Version',
          width: 100,
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
          label: 'Maintainer',
          width: 110,
          grow: 0.1,
          transformFunction: (package) => package.maintainer,
          styleFunction: PackageInfo.getDisplayStyle,
          validators: [
            PackageInfo.validateMaintainers,
          ],
        ),
        // TODO: this should show the time since the first commit after the
        // last publish happened.
        VTableColumn<PackageInfo>(
          label: 'Pub δ',
          width: 80,
          alignment: Alignment.centerRight,
          transformFunction: (package) => relativeDateInDays(
            dateUtc: package.publishedDate.toDate(),
            short: true,
          ),
          compareFunction: (a, b) => a.publishedDate.compareTo(b.publishedDate),
        ),
        VTableColumn<PackageInfo>(
          label: 'Repository',
          width: 250,
          grow: 0.2,
          transformFunction: (package) => package.repository,
          styleFunction: PackageInfo.getDisplayStyle,
          renderFunction: (BuildContext context, PackageInfo package) {
            if (package.repository.isEmpty) {
              return const SizedBox();
            } else {
              return Hyperlink(
                url: package.repository,
                style: PackageInfo.getDisplayStyle(package),
              );
            }
          },
          validators: [
            PackageInfo.validateRepositoryInfo,
          ],
        ),
        // todo: show the # of unpublished commits?
        // VTableColumn<PackageInfo>(
        //   label: 'Git #',
        //   width: 50,
        //   alignment: Alignment.centerRight,
        //   transformFunction: (package) => '50', // todo:
        //   // todo:
        //   compareFunction: (a, b) => a.published.compareTo(b.published),
        // ),
      ],
    );
  }
}

class PackageDetailsWidget extends StatefulWidget {
  final PackageInfo package;

  const PackageDetailsWidget({
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  State<PackageDetailsWidget> createState() => _PackageDetailsWidgetState();
}

class _PackageDetailsWidgetState extends State<PackageDetailsWidget>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

  @override
  void initState() {
    super.initState();

    tabController = TabController(length: 6, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final dataModel = DataModel.of(context);
    final RepositoryInfo? repo =
        dataModel.getRepositoryForPackage(widget.package);

    // todo: use a Divider widget

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey)),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.secondary,
                child: TabBar(
                  indicatorColor: Theme.of(context).colorScheme.onSecondary,
                  controller: tabController,
                  // Metadata, Pubspec, Analysis options, Dependabot, Commits
                  tabs: [
                    Tab(text: 'package:${widget.package.name}'),
                    const Tab(text: 'Pubspec'),
                    const Tab(text: 'Analysis options'),
                    const Tab(text: 'GitHub Actions'),
                    const Tab(text: 'Dependabot'),
                    const Tab(text: 'Commits'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    // Metadata
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child:
                          PackageMetaInfo(package: widget.package, repo: repo),
                    ),
                    // Pubspec
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: PubspecInfoWidget(package: widget.package),
                    ),
                    // Analysis options
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AnalysisOptionsInfo(package: widget.package),
                    ),
                    // GitHub Actions
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GitHubActionsInfo(repo: repo),
                    ),
                    // Dependabot
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DependabotConfigInfo(repo: repo),
                    ),
                    // Commits
                    PackageCommitView(
                      dataModel: dataModel,
                      package: widget.package,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
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
        const OverlayButtons(
          infoText: 'Information from last publish',
          children: [],
        ),
        SingleChildScrollView(
          child: Text(
            _pubspecText,
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
      ],
    );
  }

  String get _pubspecText {
    var printer = const YamlPrinter();
    return printer.print(package.parsedPubspec);
  }
}

class PackageMetaInfo extends StatelessWidget {
  final PackageInfo package;
  final RepositoryInfo? repo;

  const PackageMetaInfo({
    required this.package,
    required this.repo,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'package:${package.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_packageDescription),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _details('Maintainer', package.maintainer),
                        const SizedBox(height: 8),
                        _details('Publisher', package.publisher),
                        const SizedBox(height: 8),
                        _details('SDK constraint', _sdkConstraintDisplay),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _details('Version', package.version.toString()),
                        const SizedBox(height: 8),
                        _details(
                          'Last commit',
                          repo == null || repo!.lastCommitTimestamp == null
                              ? ''
                              : relativeDateInDays(
                                  dateUtc: repo!.lastCommitTimestamp!.toDate(),
                                ),
                        ),
                        const SizedBox(height: 8),
                        _details(
                          'Last published',
                          relativeDateInDays(
                            dateUtc: package.publishedDate.toDate(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const Divider(),
              ...package.validatePackage().map((validation) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        validation.icon,
                        size: 20,
                        color: validation.colorForSeverity.withAlpha(255),
                      ),
                      const SizedBox(width: 8),
                      Text(validation.message),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        OverlayButtons(
          children: [
            IconButton(
              splashRadius: 20,
              onPressed: () {
                url.launchUrl(
                    Uri.parse('https://pub.dev/packages/${package.name}'));
              },
              icon: Image.asset('resources/images/dart_logo_128.png'),
              tooltip: 'pub.dev',
            ),
            IconButton(
              splashRadius: 20,
              onPressed: package.repoUrl == null
                  ? null
                  : () => url.launchUrl(Uri.parse('${package.repoUrl}/issues')),
              icon: const Icon(Icons.bug_report),
              tooltip: 'Package issues',
            ),
            IconButton(
              splashRadius: 20,
              onPressed: package.repository.isEmpty
                  ? null
                  : () => url.launchUrl(Uri.parse(package.repository)),
              icon: const Icon(Icons.launch),
              tooltip: 'Package repo',
            ),
          ],
        ),
      ],
    );
  }

  Widget _details(String title, String value) {
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 100),
          child: Text(
            '$title: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SelectableText(value),
      ],
    );
  }

  String get _packageDescription {
    return package.parsedPubspec['description'] ?? '';
  }

  String get _sdkConstraintDisplay {
    final dep = package.sdkDep;
    if (dep == null) {
      return '';
    }
    return dep.contains(' ') ? "'$dep'" : dep;
  }
}

class AnalysisOptionsInfo extends StatelessWidget {
  final PackageInfo package;

  const AnalysisOptionsInfo({
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (package.analysisOptions == null || package.analysisOptions!.isEmpty) {
      return Stack(
        children: const [
          OverlayButtons(
            infoText: 'analysis_options.yaml',
            children: [],
          ),
          Center(
            child: Text('Analysis options file not found.'),
          ),
        ],
      );
    } else {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          SingleChildScrollView(
            child: Text(
              package.analysisOptions!,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
          OverlayButtons(
            infoText: 'analysis_options.yaml',
            children: [
              IconButton(
                splashRadius: 20,
                onPressed: () {
                  url.launchUrl(
                    Uri.parse(
                        '${package.repository}/blob/master/analysis_options.yaml'),
                  );
                },
                icon: const Icon(Icons.launch),
              ),
            ],
          ),
        ],
      );
    }
  }
}

class GitHubActionsInfo extends StatelessWidget {
  final RepositoryInfo? repo;

  const GitHubActionsInfo({
    required this.repo,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (repo == null) {
      return const Center(child: Text('No associated repository.'));
    } else if (repo!.actionsConfig == null || repo!.actionsConfig!.isEmpty) {
      return const Center(
        child: Text('GitHub Actions configuration not found.'),
      );
    } else {
      final r = repo!;

      return Stack(
        fit: StackFit.passthrough,
        children: [
          SingleChildScrollView(
            child: Text(
              r.actionsConfig!,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
          OverlayButtons(
            infoText: r.actionsFile,
            children: [
              IconButton(
                splashRadius: 20,
                onPressed: () {
                  url.launchUrl(
                    Uri.parse(
                      'https://github.com/${r.repoName}/blob/master/${r.actionsFile}',
                    ),
                  );
                },
                icon: const Icon(Icons.launch),
              ),
            ],
          ),
        ],
      );
    }
  }
}

class DependabotConfigInfo extends StatelessWidget {
  final RepositoryInfo? repo;

  const DependabotConfigInfo({
    required this.repo,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (repo == null) {
      return const Center(child: Text('No associated repository.'));
    } else if (repo!.dependabotConfig == null ||
        repo!.dependabotConfig!.isEmpty) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          OverlayButtons(
            infoText: '.github/dependabot.yaml',
            children: [
              IconButton(
                splashRadius: 20,
                onPressed: _createDependabotIssue,
                icon: const Icon(Icons.add_circle_rounded),
              ),
            ],
          ),
          const Center(
            child: Text('Dependabot configuration not found.'),
          ),
        ],
      );
    } else {
      final r = repo!;

      return Stack(
        fit: StackFit.passthrough,
        children: [
          OverlayButtons(
            infoText: '.github/dependabot.yaml',
            children: [
              IconButton(
                splashRadius: 20,
                onPressed: () {
                  url.launchUrl(
                    Uri.parse(
                      'https://github.com/${r.repoName}/blob/master/.github/dependabot.yaml',
                    ),
                  );
                },
                icon: const Icon(Icons.launch),
              ),
            ],
          ),
          SingleChildScrollView(
            child: Text(
              repo!.dependabotConfig!,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
        ],
      );
    }
  }

  void _createDependabotIssue() {
    var title = 'Enable dependabot for this repo';
    var body =
        'Please enable dependabot for this repo (for an example configuration, see '
        'https://github.com/dart-lang/usage/blob/master/.github/dependabot.yaml).';

    final uri = Uri(
      host: 'github.com',
      path: '${repo!.repoName}/issues/new',
      queryParameters: {
        'title': title,
        'body': body,
      },
    );
    url.launchUrl(uri);
  }
}

class PackageCommitView extends StatefulWidget {
  final DataModel dataModel;
  final PackageInfo package;

  const PackageCommitView({
    required this.dataModel,
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  State<PackageCommitView> createState() => _PackageCommitViewState();
}

class _PackageCommitViewState extends State<PackageCommitView> {
  final Completer<List<Commit>> completer = Completer();

  @override
  void initState() {
    super.initState();

    // Validate that this has a github repo.
    if (widget.package.gitOrgName == null ||
        widget.package.gitRepoName == null) {
      if (widget.package.repoUrl == null) {
        completer.completeError('No listed repository');
      } else {
        completer.completeError('Unable to parse repository url');
      }
    } else {
      widget.dataModel
          .getCommitsFor(
        org: widget.package.gitOrgName!,
        repo: widget.package.gitRepoName!,
      )
          .then((results) {
        completer.complete(results);
      }).catchError((error) {
        completer.completeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Commit>>(
      future: completer.future,
      builder: (BuildContext context, AsyncSnapshot<List<Commit>> snapshot) {
        if (snapshot.hasError) {
          return Text('${snapshot.error}');
        } else if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        } else {
          return VTable<Commit>(
            items: snapshot.data!,
            hideHeader: true,
            columns: [
              VTableColumn(
                label: 'Commit',
                width: 60,
                grow: 0.1,
                transformFunction: (commit) => commit.oidDisplay,
              ),
              VTableColumn(
                label: 'User',
                width: 100,
                grow: 0.1,
                transformFunction: (commit) => commit.user,
              ),
              VTableColumn(
                label: 'Message',
                width: 100,
                grow: 1,
                transformFunction: (commit) => commit.message,
              ),
              VTableColumn(
                label: 'Date',
                width: 140,
                grow: 0.1,
                transformFunction: (commit) {
                  return commit.committedDate
                      .toDate()
                      .toIso8601String()
                      .replaceAll('T', ' ');
                },
                compareFunction: (a, b) {
                  return a.committedDate.compareTo(b.committedDate);
                },
              ),
            ],
          );
        }
      },
    );
  }
}

class PackageRepoDep {
  final String? packageName;
  final String? packagePublisher;
  final String commit;
  final String repoUrl;

  PackageRepoDep({
    this.packageName,
    this.packagePublisher,
    required this.commit,
    required this.repoUrl,
  });
}
