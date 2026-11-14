import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// notorrent: a Stremio addon. GET /stream/{type}/{id}.json lists streams with
// a url; the quality is in `name`, the audio language only in the title.

Map<String, dynamic> _stream(
  String name,
  String title,
  String? url, {
  Map<String, dynamic>? hints,
  List<Map<String, String>>? subtitles,
}) =>
    {
      'name': name,
      'title': title,
      if (url != null) 'url': url,
      if (hints != null) 'behaviorHints': hints,
      if (subtitles != null) 'subtitles': subtitles,
    };

Handler _network(List<Map<String, dynamic>> streams) =>
    (Seen r) => r.url.path.startsWith('/stream/')
        ? okJson({'streams': streams})
        : status(404);

const _movie = {'type': 'movie', 'id': 'tt0133093'};

void main() {
  test('reads quality from the name and size from the hints', () async {
    final result = await run(
      'notorrent',
      _network([
        _stream(
          'NoTorrent 1080p',
          'Matrix',
          'https://cdn/a.m3u8',
          hints: {'videoSize': 2147483648},
        ),
        _stream('NoTorrent 4K', 'Matrix', 'https://cdn/b.m3u8'),
      ]),
      _movie,
    );

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.height), [1080, 2160]);
    expect(result.streams.map((s) => s.format).toSet(), {'hls'});
    expect(result.streams.first.size, 2147483648);
    expect(result.streams.last.size, isNull);
  });

  test('maps a dub named in the title to a language code', () async {
    final result = await run(
      'notorrent',
      _network([
        _stream('NoTorrent 720p', 'Matrix Latino', 'https://cdn/a.m3u8'),
        _stream('NoTorrent 720p', 'Matrix Original', 'https://cdn/b.m3u8'),
        _stream('NoTorrent 720p', 'Matrix', 'https://cdn/c.m3u8'),
      ]),
      _movie,
    );

    expect(result.streams.map((s) => s.lang), ['es', 'original', '']);
  });

  test('an entry without a url is dropped and proxy headers are kept',
      () async {
    final result = await run(
      'notorrent',
      _network([
        _stream('NoTorrent 720p', 'No link', null),
        _stream(
          'NoTorrent 720p',
          'Linked',
          'https://cdn/a.m3u8',
          hints: {
            'proxyHeaders': {
              'request': {'Referer': 'https://cdn/'},
            },
          },
        ),
      ]),
      _movie,
    );

    expect(result.streams.map((s) => s.title), ['Linked']);
    expect(result.streams.single.headers, {'Referer': 'https://cdn/'});
  });

  test('subtitles keep their url and a lower-case language', () async {
    final result = await run(
      'notorrent',
      _network([
        _stream(
          'NoTorrent 720p',
          'Matrix',
          'https://cdn/a.m3u8',
          subtitles: [
            {'url': 'https://sub/en.vtt', 'lang': 'EN'},
          ],
        ),
      ]),
      _movie,
    );

    expect(result.subtitles.single.lang, 'en');
    expect(result.subtitles.single.url, 'https://sub/en.vtt');
  });

  test('the id is url-encoded in the path and a non-imdb id is skipped',
      () async {
    final http = FakeHttp(_network([]));
    await RecipeInterpreter(http).run(loadRecipe('notorrent'), {
      'type': 'series',
      'id': 'tt0944947:1:2',
    });
    expect(http.seen.single.url.toString(), contains('tt0944947%3A1%3A2.json'));

    final none = FakeHttp(_network([]));
    await RecipeInterpreter(none)
        .run(loadRecipe('notorrent'), {'type': 'movie', 'id': '603'});
    expect(none.seen, isEmpty);
  });

  test('an addon that returns no streams gives nothing', () async {
    final result = await run('notorrent', _network([]), _movie);

    expect(result.streams, isEmpty);
  });
}
