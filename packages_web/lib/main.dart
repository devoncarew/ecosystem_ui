// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url;
import 'package:pub_semver/pub_semver.dart';

import 'firebase_options.dart';
import 'table.dart';

// todo: flash some part of the screen when a package updates
// todo: show maintainers
// todo: have a search / filter field

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
  List<String>? publishers;

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

    QuerySnapshot<SnapshotItems> snapshot =
        await FirebaseFirestore.instance.collection('publishers').get();
    setState(() {
      firestore = FirebaseFirestore.instance;
      publishers = snapshot.docs.map((doc) => doc.id).toList()..sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: addName,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: firestore == null
          ? const LoadingScreen()
          : Provider.value(
              value: firestore!,
              child: MainPage(
                publishers: publishers!,
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

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
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
  Widget build(BuildContext context) {
    final FirebaseFirestore firestore = Provider.of<FirebaseFirestore>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(addName),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            splashRadius: 20,
            tooltip: 'Send feedback',
            onPressed: () {
              url.launch('https://github.com/dart-lang/repo_manager/issues');
            },
          ),
        ],
        bottom: TabBar(
          unselectedLabelColor: Colors.white,
          labelColor: Colors.amber,
          tabs: [
            for (var publisher in widget.publishers)
              Tab(
                text: publisher,
              ),
          ],
          controller: tabController,
        ),
      ),
      body: TabBarView(
        children: [
          for (var publisher in widget.publishers)
            PublisherPackagesWidget(publisher: publisher, firestore: firestore),
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
            for (var tmp in [
              'SDK Packages',
              'Google3 Packages',
              'Changelog',
            ])
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: Text(tmp),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return ChangeLogWidget(title: tmp);
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

typedef SnapshotItems = Map<String, dynamic>;

class PublisherPackagesWidget extends StatefulWidget {
  final String publisher;
  final FirebaseFirestore firestore;

  const PublisherPackagesWidget({
    required this.publisher,
    required this.firestore,
    Key? key,
  }) : super(key: key);

  @override
  State<PublisherPackagesWidget> createState() =>
      _PublisherPackagesWidgetState();
}

class _PublisherPackagesWidgetState extends State<PublisherPackagesWidget> {
  late final Stream<QuerySnapshot<SnapshotItems>> stream;

  // todo: save the query results as state
  // todo: I think that means I have to move the stream stuff above this widget
  // in the tree

  @override
  void initState() {
    super.initState();

    stream = widget.firestore
        .collection('packages')
        .where('publisher', isEqualTo: widget.publisher)
        .orderBy('name')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<SnapshotItems>>(
      stream: stream,
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<SnapshotItems>> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Something went wrong: ${snapshot.error}'),
          );
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        } else {
          // todo: use docChanges to flash affected packages
          final docs = snapshot.data!.docs;

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
                        child: Text('${docs.length} packages'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: createTable(docs),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  PicnicTable createTable(List<QueryDocumentSnapshot<SnapshotItems>> docs) {
    // todo: move sorting into the table
    // docs.sort((a, b) {
    //   bool aDiscontinued =
    //       a.data().containsKey('discontinued') ? a['discontinued'] : false;
    //   bool bDiscontinued =
    //       b.data().containsKey('discontinued') ? b['discontinued'] : false;
    //   if (aDiscontinued == bDiscontinued) {
    //     return (a['name'] as String).compareTo(b['name']);
    //   } else {
    //     return aDiscontinued ? 1 : -1;
    //   }
    // });

    fn(QueryDocumentSnapshot<SnapshotItems> snapshot) {
      const discontinuedStyle = TextStyle(color: Colors.grey);

      final data = snapshot.data();
      bool discontinued =
          data.containsKey('discontinued') ? data['discontinued'] : false;
      return discontinued ? discontinuedStyle : null;
    }

    return PicnicTable(
      items: docs,
      columns: <PicnicColumn>[
        PicnicColumn<QueryDocumentSnapshot<SnapshotItems>>(
          label: 'Name',
          width: 140,
          grow: 0.1,
          transformFunction: (data) => data.get('name'),
          styleFunction: fn,
          compareFunction: (a, b) {
            bool aDiscontinued = a.data().containsKey('discontinued')
                ? a['discontinued']
                : false;
            bool bDiscontinued = b.data().containsKey('discontinued')
                ? b['discontinued']
                : false;
            if (aDiscontinued == bDiscontinued) {
              return (a['name'] as String).compareTo(b['name']);
            } else {
              return aDiscontinued ? 1 : -1;
            }
          },
        ),
        PicnicColumn<QueryDocumentSnapshot<SnapshotItems>>(
          label: 'Publisher',
          width: 100,
          grow: 0.1,
          transformFunction: (snapshot) {
            String publisher = snapshot.get('publisher');
            var data = snapshot.data();
            bool discontinued = data.containsKey('discontinued')
                ? snapshot['discontinued']
                : false;
            bool unlisted =
                data.containsKey('unlisted') ? snapshot['unlisted'] : false;
            if (discontinued) {
              publisher += ' (discontinued)';
            }
            if (unlisted) {
              publisher += ' (unlisted)';
            }
            return publisher;
          },
          styleFunction: fn,
        ),
        PicnicColumn<QueryDocumentSnapshot<SnapshotItems>>(
          label: 'Version',
          width: 100,
          transformFunction: (data) => data.get('version'),
          styleFunction: fn,
          compareFunction: (QueryDocumentSnapshot<SnapshotItems> a,
              QueryDocumentSnapshot<SnapshotItems> b) {
            var strA = a.get('version');
            var strB = b.get('version');
            // todo: handle bad versions
            var versionA = Version.parse(strA);
            var versionB = Version.parse(strB);
            return versionA.compareTo(versionB);
          },
        ),
        PicnicColumn<QueryDocumentSnapshot<SnapshotItems>>(
          label: 'Maintainer',
          width: 110,
          grow: 0.1,
          transformFunction: (snapshot) {
            var data = snapshot.data();
            return data.containsKey('maintainer')
                ? snapshot.get('maintainer')
                : '';
          },
          styleFunction: fn,
        ),
        PicnicColumn<QueryDocumentSnapshot<SnapshotItems>>(
          label: 'Repository',
          width: 250,
          grow: 0.2,
          transformFunction: (data) => data.get('repository'),
          styleFunction: fn,
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

class ChangeLogWidget extends StatelessWidget {
  final String title;

  const ChangeLogWidget({
    required this.title,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth - 48 * 2;
      var height = constraints.maxHeight - 48 * 2;

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: width,
          height: height,
          child: PicnicTable(
            items: List.generate(100, (index) => index),
            columns: [
              PicnicColumn(label: 'One', width: 100),
              PicnicColumn(label: 'Two', width: 100),
              PicnicColumn(label: 'Three', width: 100, grow: 1),
            ],
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
