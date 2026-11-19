import 'package:test/test.dart';

import 'support.dart';

// hexa: the site hands out a challenge, enc-dec.app solves it, the site gives a
// token, and the encrypted source list comes back as text for enc-dec.app.

Handler _network({bool noToken = false, List<Map<String, String>>? sources}) =>
    (Seen r) {
      if (r.url.host == 'cap.hexa.su' && r.url.path.endsWith('/challenge')) {
        return okJson({
          'challenge': {'c': 1},
          'token': 'CH'
        });
      }
      if (r.url.path == '/api/enc-hexa') {
        return r.json['challenge_data']['token'] == 'CH'
            ? okJson({
                'status': 200,
                'result': {
                  'solutions': [1],
                  'token': 'CH'
                },
              })
            : okJson({'status': 400, 'error': 'bad'});
      }
      if (r.url.host == 'cap.hexa.su' && r.url.path.endsWith('/redeem')) {
        return okJson(noToken ? {'success': false} : {'token': 'CAPTOKEN'});
      }
      if (r.url.host == 'theemoviedb.hexa.su') {
        final ok_ = r.headers['X-Cap-Token'] == 'CAPTOKEN' &&
            (r.headers['X-Api-Key'] ?? '').length == 64;
        return ok_ ? ok('ENCRYPTED:${r.url.path}') : status(401);
      }
      if (r.url.path == '/api/dec-hexa') {
        if ('${r.json['key']}'.length != 64) {
          return okJson({'status': 400, 'error': 'bad key'});
        }
        return okJson({
          'status': 200,
          'result': {
            'sources': sources ??
                [
                  {'server': 'alpha', 'url': 'https://cdn/a.m3u8'},
                  {'server': 'bravo', 'url': 'https://cdn/proxy?data=1'},
                ],
            'path': r.json['text'],
          },
        });
      }
      return status(404);
    };

void main() {
  test('a movie asks for the images path and gives one stream per server',
      () async {
    final seen = <Seen>[];
    final result = await run(
      'hexa',
      (r) {
        seen.add(r);
        return _network()(r);
      },
      {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );

    expect(result.error, isNull);
    expect(
        result.streams.map((s) => s.title), ['Hexa - Alpha', 'Hexa - Bravo']);
    expect(result.streams.first.format, 'hls');
    expect(result.streams.first.headers['Referer'], 'https://hexa.su/');
    final data = seen.firstWhere((r) => r.url.host == 'theemoviedb.hexa.su');
    expect(data.url.path, '/api/tmdb/movie/603/images');
    expect(data.headers['X-Fingerprint-Lite'], isNotEmpty);
  });

  test('an episode uses the season and episode path', () async {
    final seen = <Seen>[];
    await run(
      'hexa',
      (r) {
        seen.add(r);
        return _network()(r);
      },
      {'type': 'series', 'id': 'tt0944947:2:3', 'tmdb': '1399'},
    );
    final data = seen.firstWhere((r) => r.url.host == 'theemoviedb.hexa.su');
    expect(data.url.path, '/api/tmdb/tv/1399/season/2/episode/3/images');
  });

  test('no token from the site gives an error', () async {
    final result = await run(
      'hexa',
      _network(noToken: true),
      {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );
    expect(result.streams, isEmpty);
    expect(result.error, 'the site gave no token');
  });

  test('a title without a TMDB id gives an error', () async {
    final result = await run(
      'hexa',
      _network(),
      {'type': 'movie', 'id': 'tt0133093'},
    );
    expect(result.error, 'no tmdb id');
  });
}
