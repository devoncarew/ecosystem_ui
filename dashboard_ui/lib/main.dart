// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'model/data_model.dart';
import 'pages/changelog_page.dart';
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
    return MaterialApp(
      title: appName,
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
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
                  return NavigationRailContainer(dataModel: dataModel!);
                },
              ),
            ),
    );
  }
}

class NavigationRailContainer extends StatefulWidget {
  final DataModel dataModel;

  const NavigationRailContainer({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<NavigationRailContainer> createState() =>
      _NavigationRailContainerState();
}

class _NavigationRailContainerState extends State<NavigationRailContainer> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    late Widget page;

    switch (_selectedIndex) {
      case 0:
        page = const Text('todo: pub');
        break;
      case 1:
        page = const Text('todo: repos');
        break;
      case 2:
        page = SDKPage(dataModel: widget.dataModel);
        break;
      case 3:
        page = const Text('todo: google3');
        break;
      case 4:
        page = ChangelogPage(dataModel: widget.dataModel);
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
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
      ),
      body: Row(children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
          destinations: const <NavigationRailDestination>[
            NavigationRailDestination(
              icon: Icon(Icons.newspaper),
              label: Text('Pub'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.filter_hdr),
              label: Text('Repositories'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.list_alt),
              label: Text('SDK'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.dashboard),
              label: Text('Google3'),
            ),
            // todo: separator
            NavigationRailDestination(
              icon: Icon(Icons.insert_chart_outlined_outlined),
              label: Text('Changelog'),
            ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: AnimatedSwitcher(
            // todo: use a transitionBuilder
            // transitionBuilder: slideTransitionBuilder,
            duration: kThemeAnimationDuration,
            child: page,
          ),
        )
      ]),
    );
  }

  // static Widget slideTransitionBuilder(
  //     Widget child, Animation<double> animation) {
  //   return SlideTransition(position: null,);
  // }
}
