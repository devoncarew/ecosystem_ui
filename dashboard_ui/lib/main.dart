import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dashboard_ui/pages/repositories.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'firebase_options.dart';
import 'model/data_model.dart';
import 'pages/changelog.dart';
import 'pages/charts.dart';
import 'pages/google3.dart';
import 'pages/packages.dart';
import 'pages/sdk.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'utils/constants.dart';

// todo: have a search field

// todo: add filtering to the sdk page

// todo: implement a router, and named routes to different areas of the app

void main() async {
  setPathUrlStrategy();

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
    Widget child;

    if (firestore == null) {
      child = const LoadingScreen();
    } else {
      child = MultiProvider(
        providers: [
          Provider<FirebaseFirestore>(create: (_) => firestore!),
          Provider<DataModel>(create: (_) => dataModel!)
        ],
        child: ValueListenableBuilder<List<String>>(
          valueListenable: dataModel!.publishers,
          builder: (context, publishers, _) {
            return ScaffoldContainer(
              dataModel: dataModel!,
              publishers: publishers,
            );
          },
        ),
      );
    }

    return MaterialApp(
      title: appName,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      debugShowCheckedModeBanner: false,
      home: child,
    );
  }
}

class ScaffoldContainer extends StatefulWidget {
  final DataModel dataModel;
  final List<String> publishers;

  const ScaffoldContainer({
    required this.dataModel,
    required this.publishers,
    Key? key,
  }) : super(key: key);

  @override
  State<ScaffoldContainer> createState() => _ScaffoldContainerState();
}

class _ScaffoldContainerState extends State<ScaffoldContainer> {
  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Packages'),
            Tab(text: 'SDK'),
            Tab(text: 'Google3'),
            Tab(text: 'Package Repos'),
          ],
        ),
        actions: [
          _buildActionBar(context),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: TabBarView(
          children: [
            PackagesSheet(publishers: widget.publishers),
            SDKSheet(dataModel: widget.dataModel),
            Google3Sheet(dataModel: widget.dataModel),
            RepositorySheet(dataModel: widget.dataModel),
          ],
        ),
      ),
    );

    return DefaultTabController(
      length: 4,
      child: scaffold,
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        ValueListenableBuilder<bool>(
          valueListenable: widget.dataModel.busy,
          builder: (BuildContext context, bool busy, _) {
            return Center(
              child: SizedBox(
                width: defaultIconSize - 6,
                height: defaultIconSize - 6,
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
    );
  }
}
