// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'model/data_model.dart';
import 'pages/changelog.dart';
import 'pages/charts.dart';
import 'pages/google3_page.dart';
import 'pages/pub_page.dart';
import 'pages/sdk_page.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'utils/constants.dart';

// todo: have a search / filter field

// todo: google3 data

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
    // ignore: no_leading_underscores_for_local_identifiers
    final _firestore = FirebaseFirestore.instance;

    // Set up the datamodel.
    // ignore: no_leading_underscores_for_local_identifiers
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

class _ScaffoldContainerState extends State<ScaffoldContainer> {
  // todo: move to stateless?

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
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        // todo: use leading for the search + busy indicator?
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Packages'),
            Tab(text: 'SDK'),
            Tab(text: 'Google3'),
          ],
        ),
        // todo: build this is a separate method
        actions: [
          Row(
            children: [
              // todo: search box
              const SizedBox(width: 8),
              ValueListenableBuilder<bool>(
                valueListenable: widget.dataModel.busy,
                builder: (BuildContext context, bool busy, _) {
                  return Center(
                    child: SizedBox(
                      width: defaultIconSize,
                      height: defaultIconSize,
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
              IconButton(
                icon: const Icon(Icons.table_chart),
                tooltip: 'Recent Changes',
                splashRadius: defaultSplashRadius,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return LargeDialog(
                        title: 'Recent Changes',
                        child: ChangelogView(dataModel: widget.dataModel),
                      );
                    },
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.area_chart_sharp),
                tooltip: 'Charts',
                splashRadius: defaultSplashRadius,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return LargeDialog(
                        title: 'Charts',
                        child: ChartsPage(dataModel: widget.dataModel),
                      );
                    },
                  );
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: TabBarView(
          children: [
            PublisherPackagesWidget(publishers: publishers),
            SDKDependenciesWidget(dataModel: widget.dataModel),
            const Google3Widget(),
          ],
        ),
      ),
    );

    return DefaultTabController(
      length: 3,
      child: scaffold,
    );
  }
}
