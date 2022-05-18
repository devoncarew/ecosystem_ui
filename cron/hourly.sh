export $(grep -v '^#' .env | xargs)

pushd dashboard_cli

dart bin/update.dart sdk
dart bin/update.dart packages

popd
