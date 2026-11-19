import 'package:test/test.dart';

import 'support.dart';

// hdhub: a Stremio stream request answers a list of file links. Only direct
// PixelDrain and signed R2 files whose description says Hindi are kept, one per
// host and quality, and an episode request keeps only the matching SxxEyy.

const _drain = 'https://pixeldrain.dev/api/file/';
const _r2 = 'https://abc123.r2.cloudflarestorage.com/f.mkv?X-Amz-Signature=x';

Map<String, dynamic> _file(
  String name,
  String url,
  String file,
  String language, {
  int size = 1000,
}) =>
    {
      'name': name,
      'description': '[PixelDrain] [💾 1 GB] $file\n$language\npixeldrain | x',
      'url': url,
      'behaviorHints': {'notWebReady': true, 'videoSize': size},
    };

Handler _network(List<Map<String, dynamic>> streams, [List<Uri>? seen]) =>
    (Seen r) {
      seen?.add(r.url);
      return okJson({'streams': streams});
    };

void main() {
  test('keeps one Hindi file per host and quality and drops the rest',
      () async {
    final seen = <Uri>[];
    final result = await run(
      'hdhub',
      _network([
        {
          'name': 'Donation needed.',
          'description': 'donate',
          'externalUrl': 'https://x/donation.html',
          'url': '',
        },
        _file(
            'HdHub 1080p', '${_drain}A1', 'Film.2023.1080p.Hindi.mkv', 'Hindi',
            size: 5000),
        _file('HdHub 1080p', '${_drain}A2', 'Film.2023.1080p.Hindi.v2.mkv',
            'Hindi'),
        _file('HdHub 720p', '${_drain}A3', 'Film.2023.720p.English.mkv',
            'English'),
        _file('HdHub 720p', '${_drain}A4', 'Film.2023.720p.Hin.Eng.mkv', ''),
        _file('4KHDHub 4K', _r2, 'Film.2023.2160p.mkv', 'Hindi'),
        _file('HdHub 1080p', 'https://pixel.hubcloud.mov/?id=a::b',
            'Film.2023.1080p.Hindi.mkv', 'Hindi'),
      ], seen),
      const {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );

    expect(result.error, isNull);
    expect(seen.single.path, endsWith('/stream/movie/tt0133093.json'));
    expect(
      result.streams.map((s) => '${s.title}:${s.height}:${s.url}').toList(),
      [
        'HdHub PixelDrain Hindi:1080:${_drain}A1',
        'HdHub PixelDrain Hindi:720:${_drain}A4',
        'HdHub FSL Hindi:2160:$_r2',
      ],
    );
    expect(result.streams.first.lang, 'hi');
    expect(result.streams.first.format, 'mp4');
    expect(result.streams.first.size, 5000);
    expect(result.streams.first.headers, isEmpty);
  });

  test('an episode request keeps the matching episode and pads the numbers',
      () async {
    final seen = <Uri>[];
    final result = await run(
      'hdhub',
      _network([
        _file('HdHub 1080p', '${_drain}B1', 'Show.S01E10.1080p.Hindi.mkv',
            'Hindi'),
        _file('HdHub 1080p', '${_drain}B2', 'Show.S01E01.1080p.Hindi.mkv',
            'Hindi'),
        _file('HdHub 720p', '${_drain}B3', 'Show S02E01 720p', 'Hindi'),
      ], seen),
      const {
        'type': 'series',
        'id': 'tt4574334:1:1',
        'tmdb': '66732',
        'title': 'Show',
      },
    );

    expect(seen.single.path, endsWith('/stream/series/tt4574334:1:1.json'));
    expect(result.streams.map((s) => s.url), ['${_drain}B2']);
  });

  test('a two digit episode is matched without padding', () async {
    final result = await run(
      'hdhub',
      _network([
        _file(
            'HdHub 720p', '${_drain}C1', 'Show.S01E01.720p.Hindi.mkv', 'Hindi'),
        _file(
            'HdHub 720p', '${_drain}C2', 'Show.S01E12.720p.Hindi.mkv', 'Hindi'),
      ]),
      const {
        'type': 'series',
        'id': 'tt1:1:12',
        'tmdb': '1',
        'title': 'Show',
      },
    );

    expect(result.streams.map((s) => s.url), ['${_drain}C2']);
  });

  test('a spin-off with the same start of the name is not the show', () async {
    final result = await run(
      'hdhub',
      _network([
        _file('HdHub 1080p', '${_drain}E1',
            'Stranger.Things.Tales.From.85.S01E01.1080p.Hindi.mkv', 'Hindi'),
        _file(
            '4KHDHub 1080p',
            '${_drain}E2',
            'Stranger Things (2016) S01E01 1080p BluRay [Hindi DDP 5.1]',
            'Hindi'),
      ]),
      const {
        'type': 'series',
        'id': 'tt4574334:1:1',
        'tmdb': '66732',
        'title': 'Stranger Things',
      },
    );

    expect(result.streams.map((s) => s.url), ['${_drain}E2']);
  });

  test('an episode request without a title skips only the show check',
      () async {
    final result = await run(
      'hdhub',
      _network([
        _file('HdHub 1080p', '${_drain}F1', 'Any.Show.S01E01.1080p.Hindi.mkv',
            'Hindi'),
      ]),
      const {'type': 'series', 'id': 'tt1:1:1', 'tmdb': '1'},
    );

    expect(result.streams.map((s) => s.url), ['${_drain}F1']);
  });

  test('a title with no Hindi file gives no streams', () async {
    final result = await run(
      'hdhub',
      _network([
        _file(
            'HdHub 1080p', '${_drain}D1', 'Film.1080p.English.mkv', 'English'),
      ]),
      const {'type': 'movie', 'id': 'tt0133093'},
    );

    expect(result.streams, isEmpty);
  });

  test('an imdb id is required and a failing addon is an error', () async {
    final noId = await run('hdhub', _network([]), const {
      'type': 'movie',
      'id': '603',
    });
    expect(noId.error, isNotNull);

    final down = await run('hdhub', (Seen r) => status(502), const {
      'type': 'movie',
      'id': 'tt0133093',
    });
    expect(down.error, isNotNull);
    expect(down.streams, isEmpty);
  });
}
