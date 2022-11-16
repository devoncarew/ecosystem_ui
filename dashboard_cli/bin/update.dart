import 'dart:io';

import 'package:dashboard_cli/package_manager.dart';
import 'package:args/command_runner.dart';

void main(List<String> arguments) async {
  final runner = UpdateRunner();

  try {
    final code = await runner.run(arguments) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln('$e');
    exit(1);
  }
}

class UpdateRunner extends CommandRunner<int> {
  UpdateRunner()
      : super(
          'update',
          'A tool to update the information for the packages health dashboard.',
        ) {
    addCommand(PackagesCommand());
    addCommand(SdkCommand());
    addCommand(Google3Command());
    addCommand(RepositoriesCommand());
    addCommand(SheetsCommand());
    addCommand(StatsCommand());
  }
}

class PackagesCommand extends Command<int> {
  @override
  final String name = 'packages';

  @override
  List<String> get aliases => const ['pub'];

  @override
  final String description = 'Update information sourced from pub.dev.';

  PackagesCommand() {
    argParser.addMultiOption(
      'publisher',
      valueHelp: 'publisher',
      help: 'Just update the info for the given publisher(s).',
    );
  }

  @override
  Future<int> run() async {
    List<String> specificPublishers = argResults!['publisher'];

    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    if (specificPublishers.isEmpty) {
      await packageManager.updatePublisherPackages();
    } else {
      await packageManager.updatePublisherPackages(
        publishers: specificPublishers,
      );
    }
    await packageManager.close();
    return 0;
  }
}

class StatsCommand extends Command<int> {
  @override
  final String name = 'stats';

  @override
  final String description = 'Calculate and update daily package stats.';

  StatsCommand();

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateStats();
    await packageManager.close();
    return 0;
  }
}

class RepositoriesCommand extends Command<int> {
  @override
  final String name = 'repos';

  @override
  final String description =
      'Update information about the package repositories.';

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateRepositories();
    await packageManager.close();
    return 0;
  }
}

class SdkCommand extends Command<int> {
  @override
  final String name = 'sdk';

  @override
  final String description =
      'Update information sourced from the Dart SDK repo.';

  SdkCommand();

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateFromSdk();
    await packageManager.close();
    return 0;
  }
}

class Google3Command extends Command<int> {
  @override
  final String name = 'google3';

  @override
  final String description =
      'Update information sourced from packages synced into google3.';

  Google3Command();

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateFromGoogle3();
    await packageManager.close();
    return 0;
  }
}

class SheetsCommand extends Command<int> {
  @override
  final String name = 'sheets';

  @override
  final String description =
      'Update maintainer information sourced from a Google sheet.';

  SheetsCommand();

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateMaintainersFromSheets();
    await packageManager.close();
    return 0;
  }
}
