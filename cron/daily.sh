export $(grep -v '^#' .env | xargs)

pushd dashboard_cli

dart bin/update.dart sheets
dart bin/update.dart google3
dart bin/update.dart stats

popd
