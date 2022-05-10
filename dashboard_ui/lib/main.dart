// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'model/data_model.dart';
import 'pages/changelog_page.dart';
import 'pages/pub_page.dart';
import 'pages/sdk_page.dart';
import 'ui/widgets.dart';
import 'utils/constants.dart';

// todo: make sure the UI is updating when we get new package info
// todo: have a search / filter field
// todo: google3 data
// todo: show days since last publish in the table?
//       days of unpublished work?

// todo: we should be tracking amount of unpublished work, and latency of
//       unpublished work

// todo: identify packages we're using (dep'ing into the sdk, using as a dep of
//       a core package) which are not from a verified publisher

// todo: have a toggle to hide discontinued

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
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
    final child = firestore == null
        ? const LoadingScreen()
        : MultiProvider(
            providers: [
              Provider<FirebaseFirestore>(create: (_) => firestore!),
              Provider<DataModel>(create: (_) => dataModel!)
            ],
            child: ScaffoldContainer(dataModel: dataModel!),
          );

    return MaterialApp(
      title: appName,
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: child,
    );
  }
}

class ScaffoldContainer extends StatefulWidget {
  final DataModel dataModel;

  const ScaffoldContainer({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<ScaffoldContainer> createState() => _ScaffoldContainerState();
}

enum PageTypes {
  packages,
  sdk,
  google3,
  changes,
}

class _ScaffoldContainerState extends State<ScaffoldContainer> {
  PageTypes selectedPageType = PageTypes.packages;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.dataModel.publishers,
      builder: (context, publishers, _) {
        return _build(context, publishers);
      },
    );
  }

  Widget _build(BuildContext context, List<String> publishers) {
    late NavPage page;

    switch (selectedPageType) {
      case PageTypes.packages:
        page = PackagesPage(publishers: publishers);
        break;
      case PageTypes.sdk:
        page = SDKPage(widget.dataModel);
        break;
      case PageTypes.google3:
        page = TempPage('google3');
        break;
      case PageTypes.changes:
        page = ChangelogPage(widget.dataModel);
        break;
    }

    final theme = Theme.of(context);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text('$appName - ${page.title}'),
        actions: [
          Row(
            children: [
              // todo: search box
              const SizedBox(width: 16),
              ValueListenableBuilder<bool>(
                valueListenable: widget.dataModel.busy,
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
              const SizedBox(width: 16),
            ],
          ),
        ],
        bottom: page.createBottomBar(context) ??
            const PreferredSize(
              preferredSize: Size(46, 46),
              child: SizedBox(),
            ),
      ),
      body: AnimatedSwitcher(
        duration: kThemeAnimationDuration,
        child: page.createChild(context, key: ValueKey(selectedPageType)),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.secondary),
              child: Text(
                'Drawer Header',
                style: theme.textTheme.titleLarge!.copyWith(
                  color: theme.colorScheme.onSecondary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Packages'),
              onTap: () {
                Navigator.pop(context);
                setState(() => selectedPageType = PageTypes.packages);
              },
            ),
            ListTile(
              leading: const Icon(Icons.train),
              title: const Text('SDK'),
              onTap: () {
                Navigator.pop(context);
                setState(() => selectedPageType = PageTypes.sdk);
              },
            ),
            ListTile(
              leading: const Icon(Icons.train),
              title: const Text('Google3'),
              onTap: () {
                Navigator.pop(context);
                setState(() => selectedPageType = PageTypes.google3);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.train),
              title: const Text('Changes'),
              onTap: () {
                Navigator.pop(context);
                setState(() => selectedPageType = PageTypes.changes);
              },
            ),
          ],
        ),
      ),
    );

    int? tabPages = page.tabPages;
    if (tabPages == null) {
      return scaffold;
    } else {
      return DefaultTabController(
        length: tabPages,
        child: scaffold,
      );
    }
  }
}
