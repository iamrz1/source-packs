import 'package:test/test.dart';

import 'support.dart';

// vidspark: GET /api/vidora/v1/{movie|tv/...} with a player key header
// answers {result, sources[{url}]}; a title it does not hold says so.

Handler _network(Object body) => (Seen r) =>
    r.url.path.startsWith('/api/vidora/v1/') ? okJson(body) : status(404);

void main() {
  test('emits the playlist with the site headers and sends the key', () async {
    final seen = <Seen>[];
    final result = await run(
      'vidspark',
      (Seen r) {
        seen.add(r);
        return _network({
          'result': true,
          'sources': [
            {'url': 'https://cdn/a.m3u8'},
          ],
        })(r);
      },
      const {'type': 'movie', 'id': 'tt0137523', 'tmdb': '550'},
    );

    expect(result.error, isNull);
    expect(seen.single.url.path, '/api/vidora/v1/movie/550');
    expect(seen.single.headers['x-player-key'], hasLength(64));
    expect(result.streams.single.format, 'hls');
    expect(result.streams.single.headers['Referer'], 'https://vidspark.to/');
    expect(result.streams.single.headers['Origin'], 'https://vidspark.to');
  });

  test('an episode uses the tv path', () async {
    final seen = <String>[];
    await run(
      'vidspark',
      (Seen r) {
        seen.add(r.url.path);
        return okJson({
          'result': true,
          'sources': [
            {'url': 'https://cdn/a.m3u8'},
          ],
        });
      },
      const {'type': 'series', 'id': 'tt0944947:1:1', 'tmdb': '1399'},
    );

    expect(seen.single, '/api/vidora/v1/tv/1399/1/1');
  });

  test('a title it does not hold is an error', () async {
    final result = await run(
      'vidspark',
      _network({'result': false, 'message': 'Movie not yet encoded'}),
      const {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );

    expect(result.streams, isEmpty);
    expect(result.error, contains('not available'));
  });
}
