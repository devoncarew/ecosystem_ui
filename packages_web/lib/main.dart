// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url;

import 'data_model.dart';
import 'firebase_options.dart';
import 'table.dart';
import 'theme.dart';
import 'utils.dart';

// todo: flash some part of the screen when a package updates
// todo: have a search / filter field
// todo: google3 data
// todo: remove some state objects?

// todo: dial back firestore notifications? do less work when we're notified?
// it's a bit disruptive in the UI

const String appName = 'Package Dashboard';

void main() async {
  runApp(const PackagesApp());
}

class PackagesApp extends StatefulWidget {
  const PackagesApp({Key? key}) : super(key: key);

  @override
  State<PackagesApp> createState() => _PackagesAppState();
}

class _PackagesAppState extends State<PackagesApp> {
  FirebaseFirestore? firestore;
  DataModel? dataModel;

  @override
  void initState() {
    super.initState();

    // todo: handle errors
    initFirebase();
  }

  void initFirebase() async {
    // Set up firebase.
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    final _firestore = FirebaseFirestore.instance;

    // Set up the datamodel.
    final _dataModel = DataModel(firestore: _firestore);
    await _dataModel.init();
    await _dataModel.loaded();

    // Rebuild the widget.
    setState(() {
      firestore = _firestore;
      dataModel = _dataModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: firestore == null
          ? const LoadingScreen()
          : MultiProvider(
              providers: [
                Provider<FirebaseFirestore>(create: (_) => firestore!),
                Provider<DataModel>(create: (_) => dataModel!)
              ],
              child: ValueListenableBuilder<List<String>>(
                valueListenable: dataModel!.publishers,
                builder: (context, List<String> publishers, _) {
                  return MainPage(
                    publishers: publishers,
                  );
                },
              ),
            ),
    );
  }
}

class MainPage extends StatefulWidget {
  final List<String> publishers;

  const MainPage({
    required this.publishers,
    Key? key,
  }) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  late TabController tabController;

  @override
  void initState() {
    super.initState();

    tabController = TabController(
      length: widget.publishers.length,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    tabController.dispose();
    tabController = TabController(
      length: widget.publishers.length,
      initialIndex: tabController.index,
      vsync: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataModel = DataModel.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: dataModel.busy,
            builder: (BuildContext context, bool busy, _) {
              return Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: busy
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : null,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            splashRadius: 20,
            tooltip: 'Send feedback',
            onPressed: () {
              url.launchUrl(
                Uri.parse('https://github.com/dart-lang/repo_manager/issues'),
              );
            },
          ),
        ],
        bottom: TabBar(
          unselectedLabelColor: Colors.white,
          labelColor: Colors.amber,
          tabs: [
            for (var publisher in widget.publishers)
              Tab(
                text: '$publisher ('
                    '${dataModel.getPackagesForPublisher(publisher).value.length})',
              ),
          ],
          controller: tabController,
        ),
      ),
      body: TabBarView(
        children: [
          for (var publisher in widget.publishers)
            PublisherPackagesWidget(
              publisher: publisher,
              key: ValueKey(publisher),
            ),
        ],
        controller: tabController,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Custom reports',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Recent changes'),
              onTap: () {
                Navigator.pop(context);
                _showChangeLogDialog(dataModel);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeLogDialog(DataModel dataModel) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return LargeDialog(
          title: 'Recent changes',
          child: ValueListenableBuilder<List<LogItem>>(
            valueListenable: dataModel.changeLogItems,
            builder: (context, items, _) {
              return VTable<LogItem>(
                items: items,
                columns: [
                  VTableColumn(
                    label: 'Entity',
                    width: 150,
                    grow: 0.2,
                    transformFunction: (item) => item.entity,
                  ),
                  VTableColumn(
                    label: 'Change',
                    width: 250,
                    grow: 0.4,
                    transformFunction: (item) => item.change,
                  ),
                  VTableColumn(
                    label: 'Timestamp',
                    width: 150,
                    grow: 0.1,
                    transformFunction: (item) {
                      return item.timestamp
                          .toDate()
                          .toIso8601String()
                          .replaceAll('T', ' ');
                    },
                    compareFunction: (a, b) {
                      return a.timestamp.compareTo(b.timestamp);
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
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
    const discontinuedStyle = TextStyle(color: Colors.grey);
    const unlistedStyle = TextStyle(fontStyle: FontStyle.italic);

    TextStyle? fn(PackageInfo package) {
      if (package.discontinued) {
        return discontinuedStyle;
      }
      return package.unlisted ? unlistedStyle : null;
    }

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
          styleFunction: fn,
          compareFunction: PackageInfo.compareWithStatus,
        ),
        VTableColumn<PackageInfo>(
          label: 'Publisher',
          width: 100,
          grow: 0.1,
          transformFunction: (package) {
            String publisher = package.publisher;
            if (package.discontinued) {
              publisher += ' (discontinued)';
            }
            if (package.unlisted) {
              publisher += ' (unlisted)';
            }
            return publisher;
          },
          styleFunction: fn,
        ),
        VTableColumn<PackageInfo>(
          label: 'Version',
          width: 100,
          alignment: Alignment.centerRight,
          transformFunction: (package) => package.version.toString(),
          styleFunction: fn,
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
          styleFunction: fn,
          validators: [
            PackageInfo.validateMaintainers,
          ],
        ),
        VTableColumn<PackageInfo>(
          label: 'Repository',
          width: 250,
          grow: 0.2,
          transformFunction: (package) => package.repository,
          styleFunction: fn,
          renderFunction: (BuildContext context, PackageInfo package) {
            if (package.repository.isEmpty) {
              return const SizedBox();
            } else {
              return Hyperlink(
                url: package.repository,
                style: fn(package),
              );
            }
          },
          validators: [
            PackageInfo.validateRepositoryInfo,
          ],
        ),
      ],
    );
  }
}

class Hyperlink extends StatefulWidget {
  final String url;
  final TextStyle? style;

  const Hyperlink({
    required this.url,
    this.style,
    Key? key,
  }) : super(key: key);

  @override
  State<Hyperlink> createState() => _HyperlinkState();
}

class _HyperlinkState extends State<Hyperlink> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    const underline = TextStyle(decoration: TextDecoration.underline);

    return MouseRegion(
      onEnter: (event) {
        setState(() => hovered = true);
      },
      onExit: (event) {
        setState(() => hovered = false);
      },
      child: GestureDetector(
        onTap: () => url.launchUrl(Uri.parse(widget.url)),
        child: Text(
          widget.url,
          style: hovered ? underline.merge(widget.style) : widget.style,
        ),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
      ),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class LargeDialog extends StatelessWidget {
  final String title;
  final Widget child;

  const LargeDialog({
    required this.title,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth - 48 * 2;
      var height = constraints.maxHeight - 48 * 2;

      return AlertDialog(
        title: Text(title),
        contentTextStyle: Theme.of(context).textTheme.bodyText2,
        content: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey)),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    });
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
                  // Metadata, Pubspec, Analysis options, Commits
                  // todo: add CI info
                  // todo: add dependabot info
                  tabs: [
                    Tab(text: 'package:${widget.package.name}'),
                    const Tooltip(
                      waitDuration: tooltipDelay,
                      message:
                          'Generated from pub.dev information at last publish',
                      child: Tab(text: 'Pubspec'),
                    ),
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
                      child: PackageMetaInfo(package: widget.package),
                    ),
                    // Pubspec
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        child: Text(
                          pubspecText,
                          style: const TextStyle(fontFamily: 'RobotoMono'),
                        ),
                      ),
                    ),
                    // Analysis options
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AnalysisOptionsInfo(
                        package: widget.package,
                      ),
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

  String get pubspecText {
    var printer = const YamlPrinter();
    return printer.print(widget.package.parsedPubspec);
  }
}

class PackageMetaInfo extends StatelessWidget {
  final PackageInfo package;

  const PackageMetaInfo({
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      OverlayButtons(
        children: [
          IconButton(
            splashRadius: 20,
            onPressed: package.repoUrl == null
                ? null
                : () => url.launchUrl(Uri.parse('${package.repoUrl}/issues')),
            icon: const Icon(Icons.bug_report),
          ),
          IconButton(
            splashRadius: 20,
            onPressed: package.repository.isEmpty
                ? null
                : () => url.launchUrl(Uri.parse(package.repository)),
            icon: const Icon(Icons.launch),
          ),
        ],
      ),
      Text(package.debugDump()),
    ]);
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

class OverlayButtons extends StatelessWidget {
  final String? infoText;
  final List<Widget> children;

  const OverlayButtons({
    this.infoText,
    required this.children,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox()),
            if (infoText != null)
              Opacity(
                opacity: 0.5,
                child: Chip(label: Text(infoText!)),
              ),
            ...children,
          ],
        ),
        const Expanded(child: SizedBox()),
      ],
    );
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
