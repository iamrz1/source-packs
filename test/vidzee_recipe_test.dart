import 'package:test/test.dart';

import 'support.dart';

// vidzee: GET /streams/{path}?s={server} answers plain JSON with a url. A
// server that fails is skipped. Playback needs the player Referer and Origin.

Handler _network({String hindi = 'https://cdn/h.m3u8'}) => (Seen r) {
      if (!r.url.path.startsWith('/streams/')) return status(404);
      final server = r.url.queryParameters['s'];
      if (server == 'tik') return status(502);
      final url = server == 'v6:Hindi' ? hindi : 'https://cdn/$server.m3u8';
      return okJson({'language': 'Auto', 'url': url, 'headers': {}});
    };

void main() {
  test('lists a stream per working server with the player headers', () async {
    final result = await run('vidzee', _network(), const {
      'type': 'movie',
      'id': 'tt0133093',
      'tmdb': '603',
    });

    expect(result.error, isNull);
    expect(
        result.streams.map((s) => s.title),
        unorderedEquals([
          'VidZee dcloud',
          'VidZee v6:English',
          'VidZee v6:Hindi',
        ]));
    expect(
        result.streams.first.headers['Referer'], 'https://player.vidzee.wtf/');
    expect(result.streams.first.headers['Origin'], 'https://player.vidzee.wtf');
    expect(result.streams.map((s) => s.format).toSet(), {'hls'});
  });

  test('a file link is an mp4 stream and an episode uses the tv path',
      () async {
    final seen = <String>[];
    final result = await run(
      'vidzee',
      (Seen r) {
        seen.add(r.url.path);
        return okJson({'url': 'https://cdn/a.mp4?x=1', 'headers': {}});
      },
      const {'type': 'series', 'id': 'tt0944947:2:5', 'tmdb': '1399'},
    );

    expect(seen.toSet(), {
      '/streams/tv/1399/2/5',
      '/streams/languages/tv/1399/2/5',
    });
    expect(result.streams.map((s) => s.format).toSet(), {'mp4'});
  });

  test('no tmdb id is an error', () async {
    final result = await run('vidzee', _network(), const {
      'type': 'movie',
      'id': 'tt0133093',
    });

    expect(result.error, isNotNull);
    expect(result.streams, isEmpty);
  });

  test(
      'a language list adds one labelled stream per language, with the '
      'headers the reply asks for', () async {
    final result = await run(
      'vidzee',
      (Seen r) {
        final path = r.url.path;
        if (path.startsWith('/streams/languages/')) {
          return okJson({
            'languages': ['Hindi', 'Tamil'],
          });
        }
        final server = r.url.queryParameters['s'] ?? '';
        if (server.startsWith('v4:')) {
          final language = server.substring(3);
          return okJson({
            'language': language,
            'url': 'https://cdn/$language.m3u8',
            'headers': {'Referer': 'https://cdn/'},
          });
        }
        return status(502);
      },
      const {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );

    expect(
      result.streams.map((s) => '${s.title}:${s.lang}'),
      unorderedEquals(['VidZee Hindi:hi', 'VidZee Tamil:ta']),
    );
    expect(result.streams.first.headers['Referer'], 'https://cdn/');
    expect(result.streams.first.headers.containsKey('Origin'), isFalse);
  });
}
