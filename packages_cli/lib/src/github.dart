import 'dart:io';

import 'package:graphql/client.dart';

class Github {
  late final GraphQLClient _client = _initGraphQLClient();

  Future<QueryResult> query(QueryOptions options) {
    return _client.query(options);
  }

  GraphQLClient _initGraphQLClient() {
    final token = Platform.environment['GITHUB_TOKEN'];
    if (token == null) {
      throw 'This tool expects a github access token in the GITHUB_TOKEN '
          'environment variable.';
    }

    final auth = AuthLink(getToken: () async => 'Bearer $token');
    return GraphQLClient(
      cache: GraphQLCache(),
      link: auth.concat(HttpLink('https://api.github.com/graphql')),
    );
  }

  Future<List<Commit>> queryRecentCommits({
    required RepositoryInfo repo,
    required int count,
  }) async {
    final queryString = '''{
      repository(owner: "${repo.org}", name: "${repo.name}") {
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: $count) {
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
    final result = await query(QueryOptions(document: gql(queryString)));
    if (result.hasException) {
      throw result.exception!;
    }
    return _getCommitsFromResult(result);
  }

  // todo: support paging
  Future<List<Commit>> queryCommitsAfter({
    required RepositoryInfo repo,
    required String afterTimestamp,
  }) async {
    final DateTime afterTime = DateTime.parse(afterTimestamp);

    // history parameter:
    // path: String
    //   If non-null, filters history to only show commits touching files under
    //    this path.
    final queryString = '''{
      repository(owner: "${repo.org}", name: "${repo.name}") {
        defaultBranchRef {
          target {
            ... on Commit {
              history(since: "$afterTimestamp") {
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
    final result = await query(QueryOptions(document: gql(queryString)));
    if (result.hasException) {
      throw result.exception!;
    }

    // Filter any commits not newer than afterTime (i.e., the commit ==
    // afterTime).
    return _getCommitsFromResult(result)
        .where((commit) => commit.committedDate != afterTime)
        .toList();
  }

  List<Commit> _getCommitsFromResult(QueryResult result) {
    Map history =
        result.data!['repository']['defaultBranchRef']['target']['history'];
    var edges = (history['edges'] as List).cast<Map>();

    return edges.map<Commit>((Map edge) {
      Map<String, dynamic> node = edge['node'];
      return Commit.fromQuery(node);
    }).toList();
  }
}

class RepositoryInfo {
  /// This is a combined github org and repo name - i.e., `dart-lang/sdk`.
  final String path;
  final List<Commit> commits = [];

  RepositoryInfo({required this.path});

  String get org => path.substring(0, path.indexOf('/'));

  String get name => path.substring(path.indexOf('/') + 1);

  String get firestoreEntityId => path.replaceAll('/', '%2F');

  void addCommits(List<Commit> commits) {
    this.commits.addAll(commits);
  }

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
