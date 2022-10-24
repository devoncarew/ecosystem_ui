import 'package:flutter/material.dart';

import '../model/data_model.dart';
import '../ui/table.dart';
import '../ui/widgets.dart';

class RepositorySheet extends StatefulWidget {
  final DataModel dataModel;

  const RepositorySheet({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  State<RepositorySheet> createState() => _RepositorySheetState();
}

class _RepositorySheetState extends State<RepositorySheet>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<List<PackageInfo>>(
      valueListenable: widget.dataModel.packages,
      builder: (context, packages, _) {
        return ValueListenableBuilder<List<RepositoryInfo>>(
          valueListenable: widget.dataModel.repositories,
          builder: (context, repositories, _) {
            return VTable<RepositoryInfo>(
              items: repositories,
              tableDescription: '${repositories.length} repos',
              columns: [
                VTableColumn(
                  label: 'Repository',
                  width: 125,
                  grow: 0.2,
                  transformFunction: (repo) => repo.url,
                  renderFunction: (BuildContext context, repo, _) {
                    return Hyperlink(url: repo.url, displayText: repo.repoName);
                  },
                  validators: [
                    (repo) {
                      const knownOrgs = {
                        'dart-lang',
                        'flutter',
                        'google-pay',
                        'google',
                        'googleads',
                        'grpc',
                        'material-components',
                        'material-foundation',
                      };
                      if (!knownOrgs.contains(repo.org)) {
                        return ValidationResult.error('GitHub org not known');
                      }
                      return null;
                    }
                  ],
                ),
                VTableColumn(
                  label: '#',
                  width: 50,
                  grow: 0.0,
                  alignment: Alignment.centerRight,
                  transformFunction: (repo) {
                    var packages =
                        widget.dataModel.getPackagesForRepository(repo.url);
                    return packages.length.toString();
                  },
                  compareFunction: (a, b) {
                    var packagesA =
                        widget.dataModel.getPackagesForRepository(a.url);
                    var packagesB =
                        widget.dataModel.getPackagesForRepository(b.url);
                    return packagesB.length - packagesA.length;
                  },
                ),
                VTableColumn(
                  label: 'Packages',
                  width: 250,
                  grow: 0.2,
                  transformFunction: (repo) {
                    var packages =
                        widget.dataModel.getPackagesForRepository(repo.url);
                    return packages.map((p) => p.name).join(', ');
                  },
                ),
                VTableColumn(
                  label: 'Publishers',
                  width: 60,
                  grow: 0.2,
                  transformFunction: (repo) {
                    var packages =
                        widget.dataModel.getPackagesForRepository(repo.url);
                    var publishers = packages
                        .map((package) => package.publisher)
                        .toSet()
                        .toList();
                    publishers.sort();
                    return publishers.join(', ');
                  },
                ),
                VTableColumn(
                  label: 'Issues',
                  width: 50,
                  grow: 0.1,
                  alignment: Alignment.centerRight,
                  transformFunction: (repo) => '${repo.issueCount}',
                  compareFunction: (a, b) => a.issueCount - b.issueCount,
                  renderFunction: (BuildContext context, repo, out) {
                    return Hyperlink(
                      url: '${repo.url}/issues',
                      displayText: out,
                    );
                  },
                ),
                VTableColumn(
                  label: 'PRs',
                  width: 50,
                  grow: 0.1,
                  alignment: Alignment.centerRight,
                  transformFunction: (repo) => '${repo.prCount}',
                  compareFunction: (a, b) => a.prCount - b.prCount,
                  renderFunction: (BuildContext context, repo, out) {
                    return Hyperlink(
                      url: '${repo.url}/pulls',
                      displayText: out,
                    );
                  },
                ),
                VTableColumn(
                  label: 'Workflows',
                  width: 100,
                  grow: 0.2,
                  transformFunction: (repo) {
                    return repo.workflows
                        .map((w) => w.split('/').last)
                        .join(', ');
                  },
                  renderFunction: (BuildContext context, repo, out) {
                    return Hyperlink(
                      url: '${repo.url}/tree/${repo.defaultBranchName}'
                          '/.github/workflows',
                      displayText: out,
                    );
                  },
                  validators: [
                    (RepositoryInfo repo) {
                      if (repo.workflows.isEmpty) {
                        return ValidationResult.error('no CI configured');
                      }
                      return null;
                    }
                  ],
                ),
                VTableColumn(
                  label: 'Dependabot',
                  // icon: Icons.developer_board,
                  width: 130,
                  grow: 0.0,
                  transformFunction: (repo) =>
                      repo.hasDependabot ? 'dependabot.yaml' : '',
                  renderFunction: (BuildContext context, repo, out) {
                    if (!repo.hasDependabot) return null;
                    return Hyperlink(
                      url: '${repo.url}/blob/${repo.defaultBranchName}'
                          '/.github/dependabot.yaml',
                      displayText: out,
                    );
                  },
                  validators: [
                    (RepositoryInfo repo) {
                      if (!repo.hasDependabot) {
                        return ValidationResult.warning(
                            'dependabot not configured');
                      }
                      return null;
                    }
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
