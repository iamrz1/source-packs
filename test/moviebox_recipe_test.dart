import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// The moviebox recipe: a guest token from the x-user header of /home, the
// player domain, a search for the title, then play and caption for the hit.

const token = 'guest-jwt';

RecipeResponse home() => RecipeResponse(
      200,
      '{"data":{}}',
      headers: {'x-user': '{"token":"$token","userId":"1"}'},
    );

Map<String, dynamic> item(
  String title,
  String date, {
  int type = 1,
  bool hasResource = true,
  String id = '10',
}) =>
    {
      'subjectId': id,
      'subjectType': type,
      'title': title,
      'releaseDate': date,
      'detailPath': 'slug-$id',
      'hasResource': hasResource,
    };

Handler happy({
  List<Map<String, dynamic>>? items,
  RecipeResponse Function(Seen)? play,
}) {
  return (Seen r) {
    switch (r.url.path) {
      case '/wefeed-h5api-bff/home':
        return home();
      case '/wefeed-h5api-bff/media-player/get-domain':
        // The site answers with a trailing slash.
        return okJson({'data': 'https://player.example/'});
      case '/wefeed-h5api-bff/subject/search':
        return okJson({
          'data': {
            'items': items ?? [item('The Dark Knight', '2008-07-18')],
          },
        });
      case '/wefeed-h5api-bff/subject/play':
        return play?.call(r) ??
            okJson({
              'data': {
                'streams': [
                  {
                    'id': 's360',
                    'url': 'https://cdn/a.mp4?sign=1',
                    'resolutions': '360'
                  },
                  {
                    'id': 's720',
                    'url': 'https://cdn/b.mp4?sign=2',
                    'resolutions': '720'
                  },
                ],
              },
            });
      case '/wefeed-h5api-bff/subject/caption':
        return okJson({
          'data': {
            'captions': [
              {'lan': 'en', 'lanName': 'English', 'url': 'https://sub/en.srt'},
              {'lan': 'FR', 'lanName': 'Francais', 'url': 'https://sub/fr.srt'},
            ],
          },
        });
    }
    return status(404);
  };
}

const movie = {
  'type': 'movie',
  'id': 'tt0468569',
  'title': 'The Dark Knight',
  'year': '2008',
};

void main() {
  test('a movie gives streams with quality labels, and subtitles', () async {
    final http = FakeHttp(happy());
    final result =
        await RecipeInterpreter(http).run(loadRecipe('moviebox'), movie);

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.height), [360, 720]);
    expect(result.streams.map((s) => s.title), ['360p MP4', '720p MP4']);
    expect(result.subtitles.map((s) => s.lang), ['en', 'fr']);

    final search = http.seen.firstWhere((r) => r.url.path.endsWith('/search'));
    expect(search.json, {
      'keyword': 'The Dark Knight',
      'page': 1,
      'perPage': 20,
      'subjectType': 1,
    });
    expect(search.headers['Authorization'], 'Bearer $token');
    expect(search.url.queryParameters['host'], 'moviebox.ph');

    final play = http.seen.firstWhere((r) => r.url.path.endsWith('/play'));
    expect(play.url.queryParameters['se'], '0');
    expect(play.url.queryParameters['ep'], '0');
  });

  test('the token request is bare and each stream carries the player headers',
      () async {
    final http = FakeHttp(happy());
    final result =
        await RecipeInterpreter(http).run(loadRecipe('moviebox'), movie);

    final first = http.seen.first;
    expect(first.url.path, '/wefeed-h5api-bff/home');
    expect(first.headers.keys, ['User-Agent', 'Referer']);

    for (final s in result.streams) {
      expect(
        s.headers['Referer'],
        'https://player.example/spa/videoPlayPage/movies/slug-10'
        '?id=10&type=/movie/detail&detailSe=0&detailEp=0&lang=en',
        reason: 'one slash after the domain',
      );
      expect(s.headers['User-Agent'], contains('Chrome/148'));
      expect(s.headers['sec-fetch-mode'], 'cors');
      expect(s.headers['sec-ch-ua-platform'], '"Windows"');
      expect(s.headers['X-Client-Info'], '{"timezone":"Asia/Dhaka"}');
    }
  });

  test('an episode picks the plain series item, not a dub or a movie',
      () async {
    final http = FakeHttp(
      happy(items: [
        item('Rick and Morty [Hindi] S1-S9', '2013-12-02', type: 2, id: '1'),
        item('Rick and Morty', '2013-12-02', id: '2'),
        item('Rick and Morty S1-S9', '2013-12-02', type: 2, id: '3'),
      ]),
    );
    final result = await RecipeInterpreter(http).run(loadRecipe('moviebox'), {
      'type': 'series',
      'id': 'tt2861424:1:1',
      'title': 'Rick and Morty',
      'year': '2013',
    });

    expect(result.streams, hasLength(2));
    final search = http.seen.firstWhere((r) => r.url.path.endsWith('/search'));
    expect(search.json['subjectType'], 2);
    final play = http.seen.firstWhere((r) => r.url.path.endsWith('/play'));
    expect(play.url.queryParameters['subjectId'], '3');
    expect(play.url.queryParameters['se'], '1');
    expect(play.url.queryParameters['ep'], '1');
    expect(play.url.queryParameters['detailPath'], 'slug-3');
  });

  test('a title that is not in the catalog gives nothing and no play call',
      () async {
    final http = FakeHttp(
      happy(items: [
        item('The Dark Knight Falls', '2015-02-18'),
        item('The Dark Knight', '1999-01-01'),
        item('The Dark Knight', '2008-07-18', hasResource: false),
      ]),
    );
    final result =
        await RecipeInterpreter(http).run(loadRecipe('moviebox'), movie);

    expect(result.streams, isEmpty);
    expect(result.error, isNull, reason: 'a clean miss');
    expect(http.seen.where((r) => r.url.path.endsWith('/play')), isEmpty);
  });

  test('no token in the x-user header stops before the search', () async {
    final http = FakeHttp(
      (r) => r.url.path.endsWith('/home') ? ok('{}') : happy()(r),
    );
    final result =
        await RecipeInterpreter(http).run(loadRecipe('moviebox'), movie);

    expect(result.streams, isEmpty);
    expect(result.error, contains('token'));
    expect(http.seen, hasLength(1));
  });

  test('failed captions keep the streams', () async {
    final result = await run(
      'moviebox',
      (r) => r.url.path.endsWith('/caption') ? status(500) : happy()(r),
      movie,
    );

    expect(result.streams, hasLength(2));
    expect(result.subtitles, isEmpty);
  });
}
