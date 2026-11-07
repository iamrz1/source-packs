import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// vidlink: enc-dec.app encrypts the TMDB id, vidlink.pro returns progressive MP4
// files by quality plus subtitles. Its file host rejects any Referer and any
// browser User-Agent, so the streams carry no headers at all.

Map<String, dynamic> _payload() => {
      'sourceId': 'mwVault',
      'stream': {
        'id': 'primary',
        'type': 'file',
        'qualities': {
          '360': {
            'type': 'mp4',
            'url': 'https://cdn/360.mp4',
            'codecName': 'hevc'
          },
          '720': {
            'type': 'mp4',
            'url': 'https://cdn/720.mp4',
            'codecName': 'hevc'
          },
          '1080': {
            'type': 'mp4',
            'url': 'https://cdn/1080.mp4',
            'codecName': 'hevc'
          },
        },
        'captions': [
          {'url': 'https://sub/en.srt', 'language': 'English', 'type': 'srt'},
          {'url': 'https://sub/fr.srt', 'language': 'French', 'type': 'srt'},
        ],
        'TTL': 3600,
      },
    };

Handler _network({Object? payload, bool encFails = false}) => (Seen r) {
      if (r.url.path == '/api/enc-vidlink') {
        return encFails
            ? okJson({'status': 400, 'error': 'bad'})
            : okJson({
                'status': 200,
                'result': 'ENC${r.url.queryParameters['text']}'
              });
      }
      if (r.url.host == 'vidlink.pro') {
        return RecipeResponse(
            200, payload == null ? 'null' : _jsonText(payload));
      }
      return status(404);
    };

String _jsonText(Object o) => okJson(o).body;

const _movie = {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'};

void main() {
  test('a movie gives every quality as an MP4 with its height', () async {
    final result = await run('vidlink', _network(payload: _payload()), _movie);

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.height), [360, 720, 1080]);
    expect(result.streams.map((s) => s.url), [
      'https://cdn/360.mp4',
      'https://cdn/720.mp4',
      'https://cdn/1080.mp4',
    ]);
    expect(result.streams.first.title, 'VidLink - Original audio');
  });

  test('the streams carry no headers: the file host rejects a Referer',
      () async {
    final result = await run('vidlink', _network(payload: _payload()), _movie);

    for (final s in result.streams) {
      expect(s.headers, isEmpty);
    }
  });

  test('subtitles keep their url and a lower-case language', () async {
    final result = await run('vidlink', _network(payload: _payload()), _movie);

    expect(result.subtitles.map((s) => '${s.lang} ${s.url}'), [
      'english https://sub/en.srt',
      'french https://sub/fr.srt',
    ]);
  });

  test('the encrypted id goes into the movie path', () async {
    final http = FakeHttp(_network(payload: _payload()));
    await RecipeInterpreter(http).run(loadRecipe('vidlink'), _movie);

    expect(http.seen.first.url.queryParameters['text'], '603');
    expect(http.seen.last.url.toString(),
        'https://vidlink.pro/api/b/movie/ENC603');
  });

  test('a series adds the season and episode to the path', () async {
    final http = FakeHttp(_network(payload: _payload()));
    await RecipeInterpreter(http).run(loadRecipe('vidlink'), {
      'type': 'series',
      'id': 'tt0944947:2:5',
      'tmdb': 'tmdb:1399',
    });

    expect(http.seen.first.url.queryParameters['text'], '1399');
    expect(http.seen.last.url.path, '/api/b/tv/ENC1399/2/5');
  });

  test('vidlink answering null gives nothing and says so', () async {
    final result = await run('vidlink', _network(), _movie);

    expect(result.streams, isEmpty);
    expect(result.error, 'vidlink returned no streams');
  });

  test('enc-dec.app refusing the id gives nothing', () async {
    final result = await run('vidlink', _network(encFails: true), _movie);

    expect(result.error, 'enc-vidlink gave no id');
  });

  test('a stream without a url is skipped', () async {
    final payload = _payload();
    ((payload['stream'] as Map)['qualities'] as Map)['720'] = {'type': 'mp4'};
    final result = await run('vidlink', _network(payload: payload), _movie);

    expect(result.streams.map((s) => s.height), [360, 1080]);
  });

  test('a series without season and episode, or without tmdb, is skipped',
      () async {
    for (final inputs in [
      {'type': 'series', 'id': 'tt0944947', 'tmdb': '1399'},
      {'type': 'movie', 'id': 'tt0133093'},
    ]) {
      final http = FakeHttp(_network(payload: _payload()));
      final result =
          await RecipeInterpreter(http).run(loadRecipe('vidlink'), inputs);

      expect(result.streams, isEmpty, reason: '$inputs');
      expect(http.seen, isEmpty, reason: '$inputs');
    }
  });

  test('a network error gives nothing and does not throw', () async {
    final result = await RecipeInterpreter(
      FakeHttp((_) => throw StateError('offline')),
    ).run(loadRecipe('vidlink'), _movie);

    expect(result.streams, isEmpty);
    expect(result.error, isNotNull);
  });
}
