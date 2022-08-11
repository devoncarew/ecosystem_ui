import 'dart:io';

//import 'package:dashboard_cli/src/pub.dart';
//import 'package:gql/src/language/parser.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import 'utils.dart';

const String userLoginDependabot = 'dependabot[bot]';

class Github {
  late final GraphQLClient _client = _initGraphQLClient();
  Profiler profiler;

  http.Client? _httpClient;

  Github({required this.profiler});

  Future<QueryResult> query(QueryOptions options) {
    return _client.query(options);
  }

  void close() {
    _httpClient?.close();
  }

  GraphQLClient _initGraphQLClient() {
    final token = Platform.environment['GITHUB_TOKEN'];
    if (token == null) {
      throw 'This tool expects a github access token in the GITHUB_TOKEN '
          'environment variable.';
    }

    // print("env['GITHUB_TOKEN']=$token");

    final auth = AuthLink(getToken: () async => 'Bearer $token');
    return GraphQLClient(
      cache: GraphQLCache(),
      link: auth.concat(HttpLink('https://api.github.com/graphql')),
    );
  }

  Future<Commit> getCommitInfoForSha({
    required RepositoryInfo repo,
    required String sha,
  }) async {
    final queryString = '''{
  repository(owner: "${repo.org}", name: "${repo.name}") {
    object(oid: "$sha") {
      ... on Commit {
        oid
        messageHeadline
        committedDate
        author {
          user {
            login
          }
        }
        committer {
          user {
            login
          }
        }
      }
    }
  }
}''';
    final result = await profiler.run(
        'github.query', query(QueryOptions(document: gql(queryString))));
    if (result.hasException) {
      throw result.exception!;
    }
    return _getCommitFromResult(result);
  }

//   Future<List<Commit>> queryRecentCommits({
//     required RepositoryInfo repo,
//     required int count,
//   }) async {
//     final queryString = '''{
//       repository(owner: "${repo.org}", name: "${repo.name}") {
//         defaultBranchRef {
//           target {
//             ... on Commit {
//               history(first: $count) {
//                 edges {
//                   node {
//                     oid
//                     messageHeadline
//                     committedDate
//                     author {
//                       user {
//                         login
//                       }
//                     }
//                     committer {
//                       user {
//                         login
//                       }
//                     }
//                   }
//                 }
//               }
//             }
//           }
//         }
//       }
//     }
// ''';
//     // todo: use a parser function (options.parserFn)?
//     final result = await query(QueryOptions(document: gql(queryString)));
//     if (result.hasException) {
//       throw result.exception!;
//     }
//     return _getCommitsFromResult(result);
//   }

  // todo: support paging?
  Future<List<Commit>> queryCommitsAfter({
    required RepositoryInfo repo,
    required String afterTimestamp,
    bool filterNonContentCommits = true,
    String? pathInRepo,
  }) async {
    final DateTime afterTime = DateTime.parse(afterTimestamp);

    String pathParam = '';
    if (pathInRepo != null) {
      pathParam = 'path: "$pathInRepo"';
    }

    // https://docs.github.com/en/graphql/reference/objects#commit
    final queryString = '''{
      repository(owner: "${repo.org}", name: "${repo.name}") {
        defaultBranchRef {
          target {
            ... on Commit {
              history(since: "$afterTimestamp" $pathParam) {
                edges {
                  node {
                    oid
                    messageHeadline
                    committedDate
                    author {
                      user {
                        login
                      }
                    }
                    committer {
                      user {
                        login
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
''';
    // todo: use a parser function (options.parserFn)?
    final result = await profiler.run(
        'github.query', query(QueryOptions(document: gql(queryString))));
    if (result.hasException) {
      // print(queryString);
      throw result.exception!;
    }

    var commits = _getCommitsFromResult(result);

    // Filter any commits not newer than 'afterTime' (i.e., where the commit ==
    // afterTime).
    commits = commits.where((commit) => commit.committedDate != afterTime);

    // Remove commits to directories like '.github' (which shouldn't affect
    // things like latency stats).
    if (filterNonContentCommits) {
      commits = commits.where((commit) => commit.user != userLoginDependabot);
    }

    return commits.toList();
  }

  Commit _getCommitFromResult(QueryResult result) {
// {
//   "data": {
//     "repository": {
//       "object": {
//         "oid": "7479783f0493f6717e1d7ae31cb37d39a91026b2",
//         "messageHeadline": "Update Common Mark tests to v0.30.2 (#383)",
//         "committedDate": "2021-11-16T17:40:43Z",
//         "author": {
//           "user": {
//             "login": "kevmoo"
//           }
//         },
//         "committer": {
//           "user": null
//         }
//       }
//     }
//   }
// }

    return Commit.fromQuery(result.data!['repository']['object']);
  }

  Future<int?> queryIssueCount(String issuesUrl) async {
    // todo:
    return null;

    // // We expect this url to be in a specific form:
    // // https://github.com/flutter/flutter/issues?q=is%3Aissue+is%3Aopen+label%3A%22p%3A+camera%22

    // const querySeparator = '/issues?q=';
    // if (!issuesUrl.contains(querySeparator)) {
    //   return null;
    // }

    // // todo: file an issue about the quote escaping for package:gcl
    // final repo =
    //     RepoInfo(issuesUrl.substring(0, issuesUrl.indexOf(querySeparator)));
    // var queryParameter = Uri.parse(issuesUrl).queryParameters['q']!;
    // queryParameter = queryParameter.replaceAll('"', r'\"');

    // var r = parseString('{ search( query: "label:\\"p: animations\\" ") } ');
    // print(r);
    // for (var d in r.definitions) {
    //   print(d);
    // }

    // final queryString = '''{
    //   search(
    //     query: "repo:${repo.repoOrgAndName} $queryParameter "
    //     type: ISSUE
    //   ) {
    //     issueCount
    //   }
    // }''';

    // // todo:
    // print(queryString);

    // final result = await query(QueryOptions(document: gql(queryString)));
    // if (result.hasException) {
    //   throw result.exception!;
    // }

    // // todo:
    // print(result.data);

    // // {
    // //   "data": {
    // //     "search": { "issueCount": 28 }
    // //   }
    // // }
    // return result.data!['search']['issueCount'];
  }

  Iterable<Commit> _getCommitsFromResult(QueryResult result) {
    Map history =
        result.data!['repository']['defaultBranchRef']['target']['history'];
    var edges = (history['edges'] as List).cast<Map>();

    return edges.map<Commit>((Map edge) {
      Map<String, dynamic> node = edge['node'];
      return Commit.fromQuery(node);
    });
  }

  /// Attempt to return the contents of the github repo file at the given url.
  /// Returns `null` if no such file exists.
  Future<String?> retrieveFile({
    required String orgAndRepo,
    required String filePath,
  }) {
    _httpClient ??= http.Client();
    var url = 'https://raw.githubusercontent.com/$orgAndRepo/master/$filePath';
    return _httpClient!.get(Uri.parse(url)).then((response) {
      return response.statusCode == 404 ? null : response.body;
    });
  }
}

class RepositoryInfo {
  /// This is a combined github org and repo name - i.e., `dart-lang/sdk`.
  final String path;

  // String? dependabotConfig;
  // String? actionsConfig;
  // String? actionsFile;

  RepositoryInfo({required this.path});

  String get org => path.substring(0, path.indexOf('/'));

  String get name => path.substring(path.indexOf('/') + 1);

  // String get firestoreEntityId => firestoreEntityEncode(path);

  @override
  String toString() => path;
}

class Commit implements Comparable<Commit> {
  final String oid;
  final String message;
  final String user;
  final DateTime committedDate;

  Commit({
    required this.oid,
    required this.message,
    required this.user,
    required this.committedDate,
  });

  factory Commit.fromQuery(Map<String, dynamic> node) {
    String oid = node['oid'];
    String messageHeadline = node['messageHeadline'];
    Map? user = node['author']['user'] ?? node['committer']['user'];
    String login = user == null ? '' : user['login'];
    // 2021-07-23T18:37:57Z
    String committedDate = node['committedDate'];

    return Commit(
      oid: oid,
      message: messageHeadline,
      user: login,
      committedDate: DateTime.parse(committedDate),
    );
  }

  @override
  int compareTo(Commit other) {
    return other.committedDate.compareTo(committedDate);
  }

  String get _shortDate => committedDate.toIso8601String().substring(0, 10);

  @override
  String toString() => '${oid.substring(0, 8)} $_shortDate $user $message';
}
