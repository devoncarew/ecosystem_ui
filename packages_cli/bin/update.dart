import 'dart:io';

import 'package:packages_cli/package_manager.dart';
import 'package:args/command_runner.dart';

// todo: support sdk
// todo: support google3
// todo: support scanning repos
// todo: support logging for changes

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
    addCommand(SheetsCommand());
  }
}

class PackagesCommand extends Command<int> {
  @override
  final String name = 'packages';

  @override
  final String description = 'Update information sourced from pub.dev.';

  PackagesCommand() {
    // todo: argsparser - allow for just updating specific publishers, packages,
    // ...
  }

  @override
  Future<int> run() async {
    PackageManager packageManager = PackageManager();
    await packageManager.setup();
    await packageManager.updateFromPub();
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
