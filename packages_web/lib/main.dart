// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url;

import 'data_model.dart';
import 'firebase_options.dart';
import 'table.dart';
import 'utils.dart';

// todo: flash some part of the screen when a package updates
// todo: have a search / filter field
// todo: google3 data
// todo: remove some state objects?

const String addName = 'Package Dashboard';

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
      title: addName,
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
        title: const Text(addName),
        actions: [
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
            for (var publisher in widget.publishers) Tab(text: publisher),
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
              title: const Text('Log'),
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
          title: 'Changelog',
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
        // todo: flash affected packages
        // todo: move this into a toolbar widget
        return Column(
          children: [
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: SizedBox(),
                    ),
                    Center(
                      child: Text('${packages.length} packages'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: createTable(packages),
              ),
            ),
            if (selectedPackage != null)
              Expanded(
                flex: 3,
                child: PackageDetailsWidget(
                  key: ValueKey(selectedPackage!.name),
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
    fn(PackageInfo package) {
      const discontinuedStyle = TextStyle(color: Colors.grey);
      return package.discontinued ? discontinuedStyle : null;
    }

    return VTable<PackageInfo>(
      items: packages,
      startsSorted: true,
      onTap: _onTap,
      columns: [
        VTableColumn<PackageInfo>(
          label: 'Name',
          width: 140,
          grow: 0.1,
          transformFunction: (package) => package.name,
          styleFunction: fn,
          compareFunction: (a, b) {
            bool aDiscontinued = a.discontinued;
            bool bDiscontinued = b.discontinued;
            if (aDiscontinued == bDiscontinued) {
              return (a.name.compareTo(b.name));
            } else {
              return aDiscontinued ? 1 : -1;
            }
          },
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
          validators: [
            PackageInfo.validateRepositoryInfo,
          ],
        ),
      ],
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(addName),
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
        content: SizedBox(
          width: width,
          height: height,
          child: child,
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

    tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
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
                  tabs: const [
                    Tab(text: 'Metadata'),
                    Tab(text: 'Pubspec'),
                    Tab(text: 'Commits'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(widget.package.debugDump()),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SingleChildScrollView(
                        child: Text(
                          pubspecText,
                          style: const TextStyle(fontFamily: 'RobotoMono'),
                        ),
                      ),
                    ),
                    PackageCommitView(package: widget.package),
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

class PackageCommitView extends StatelessWidget {
  final PackageInfo package;

  const PackageCommitView({
    required this.package,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //  final String oid;
    // final String message;
    // final String user;
    // final DateTime committedDate;

    return VTable(
      items: List.generate(100, (i) => '${i * i}'),
      columns: [
        VTableColumn(label: 'Commit', width: 100, grow: 0.1),
        VTableColumn(label: 'User', width: 100, grow: 0.1),
        VTableColumn(label: 'Message', width: 100, grow: 1),
        VTableColumn(label: 'Date', width: 100, grow: 0.1),
      ],
    );
  }
}
