import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
// ignore: implementation_imports
import 'package:googleapis_auth/src/adc_utils.dart';
import 'package:http/http.dart';

import 'utils.dart';

class Sheets {
  late AutoRefreshingAuthClient _client;
  late SheetsApi sheetsApi;

  Future connect() async {
    // Set the GOOGLE_SHEETS_CREDENTIALS env var to the path containing the
    // cloud console service account key.
    final credsEnv = Platform.environment['GOOGLE_SHEETS_CREDENTIALS'];
    if (credsEnv == null) {
      print('Set the GOOGLE_SHEETS_CREDENTIALS to the path containing the '
          'cloud console service account key');
      return Future.error('credentials not found');
    }
    _client = await fromApplicationsCredentialsFile(
      File(credsEnv),
      'GOOGLE_SHEETS_CREDENTIALS',
      [SheetsApi.spreadsheetsScope],
      Client(),
    );

    sheetsApi = SheetsApi(_client);
  }

  Future<List<PackageMaintainer>> getMaintainersData(Logger logger) async {
    final List<PackageMaintainer> maintainers = [];

    Spreadsheet mainSheet = await sheetsApi.spreadsheets.get(
      // '1S0gBRbUjF1YuvwRWwfVVvaMCH_Pa-qfxxvnLsJQBoCU',
      '1g8g9Bo-N-3UxVSgHDSXdZNKAHDZRVr4huN99Lt89iUw',
      includeGridData: true,
    );
    logger.write("reading the '${mainSheet.properties!.title}' sheet");

    for (var sheet in mainSheet.sheets!) {
      logger.write("tab '${sheet.properties!.title}'");
      GridData data = sheet.data!.first;

      // Validate that this sheet is well-formed.
      if (data.getCellValueAsString(0, 0) == 'Package' &&
          data.getCellValueAsString(2, 0) == 'Maintainer') {
        for (var row in data.rowData!.skip(1)) {
          String? packageName = row.values![0].formattedValue;
          if (packageName == null) {
            continue;
          }

          if (row.values!.length >= 3) {
            String? maintainer = row.values![2].formattedValue;
            maintainers.add(
              PackageMaintainer(
                packageName: packageName,
                maintainer: maintainer,
              ),
            );
          }
        }
      }
    }

    return maintainers;
  }

  void close() {
    _client.close();
  }
}

class PackageMaintainer {
  final String packageName;
  final String? maintainer;

  PackageMaintainer({required this.packageName, required this.maintainer});

  @override
  String toString() => 'package:$packageName: ${maintainer ?? ''}';
}

extension GridDataValue on GridData {
  String? getCellValueAsString(int col, int row) {
    col -= startColumn ?? 0;
    row -= startRow ?? 0;

    return rowData![row].values![col].formattedValue;
  }
}
