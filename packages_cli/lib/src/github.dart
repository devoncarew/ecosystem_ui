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

  // todo: we'll also want something like commits since a certain date
  // todo: or, all commits after commit x?
  //   after: "05eaa07627376626902bd7acde35406edf1bb2f2" ?
  //   we'll want to support paging for the 'after commit' query
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
                    author {
                      user {
                        login
                      }
                    }
                    committedDate
                  }
                }
              }
            }
          }
        }
      }
    }
''';
    final result = await query(QueryOptions(document: gql(queryString)));

    if (result.hasException) {
      throw result.exception!;
    }

    if (result.exception != null) {
      throw result.exception!;
    }

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
    String login = node['author']['user']['login'];
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

  @override
  String toString() => '${oid.substring(0, 8)} $user $message';
}
