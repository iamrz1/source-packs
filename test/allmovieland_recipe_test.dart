import 'dart:convert';

import 'package:test/test.dart';

import 'support.dart';

// allmovieland: player.js names the player host, the play page of that host
// holds a JSON object with the playlist link and a key, the playlist lists the
// voices, and a POST per voice answers the HLS master. Only Hindi is kept.

const _host = 'https://player.example';

String _playPage(String file) {
  final blob = jsonEncode({
    'file': file,
    'key': 'k3y',
    'rek': {
      'preroll': ['https://ads.example/v.xml'],
    },
  }).replaceAll('/', r'\/');
  return '<html><script>\n  // note\n  let p3 = $blob;\n  var x = 1;\n</script></html>';
}

Handler _network({
  required Object voices,
  List<Seen>? seen,
  String file = '$_host/playlist/abc.txt',
}) =>
    (Seen r) {
      seen?.add(r);
      final path = r.url.path;
      if (r.url.host == 'allmovieland.link') {
        return ok("const AwsIndStreamDomain \t= '$_host/';\n");
      }
      if (path.startsWith('/play/')) return ok(_playPage(file));
      if (path == '/playlist/abc.txt') return okJson(voices);
      if (path.startsWith('/playlist/') && r.method == 'POST') {
        return ok('https://cdn.example/stream/${path.split('/').last}\n');
      }
      return status(404);
    };

void main() {
  test('a movie keeps only the Hindi voice and sends the key and referer',
      () async {
    final seen = <Seen>[];
    final result = await run(
      'allmovieland',
      _network(seen: seen, voices: [
        [],
        {'title': 'Bengali', 'file': 'b1'},
        {'title': 'Hindi', 'file': '~h1'},
      ]),
      const {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'},
    );

    expect(result.error, isNull);
    expect(result.streams, hasLength(1));
    final s = result.streams.single;
    expect(s.title, 'AllMovieLand Hindi');
    expect(s.url, 'https://cdn.example/stream/~h1.txt');
    expect(s.format, 'hls');
    expect(s.height, isNull);
    expect(s.lang, 'hi');
    expect(s.headers['Referer'], 'https://allmovieland.one/');

    final play = seen.firstWhere((r) => r.url.path.startsWith('/play/'));
    expect(play.url.path, '/play/tt0133093');
    expect(play.headers['Referer'], 'https://allmovieland.one/');
    final voice = seen.firstWhere((r) => r.method == 'POST');
    expect(voice.headers['X-CSRF-TOKEN'], 'k3y');
    expect(
        seen
            .firstWhere((r) => r.url.path == '/playlist/abc.txt')
            .headers['X-CSRF-TOKEN'],
        'k3y');
    expect(seen.firstWhere((r) => r.url.host == 'allmovieland.link').url.query,
        'v=60%20128');
  });

  test('an episode picks the season and episode and a relative playlist link',
      () async {
    final result = await run(
      'allmovieland',
      _network(file: '/playlist/abc.txt', voices: [
        {
          'title': 'Season 1',
          'id': '1',
          'folder': [
            {
              'episode': '1',
              'folder': [
                {'title': 'Hindi', 'file': 'e1h!'},
                {'title': 'English', 'file': 'e1e!'},
              ],
            },
            {
              'episode': '2',
              'folder': [
                {'title': 'Hindi', 'file': 'e2h!'},
              ],
            },
          ],
        },
        {
          'title': 'Season 2',
          'id': '2',
          'folder': [
            {
              'episode': '2',
              'folder': [
                {'title': 'Hindi', 'file': 's2e2h!'},
              ],
            },
          ],
        },
      ]),
      const {'type': 'series', 'id': 'tt0944947:1:2', 'tmdb': '1399'},
    );

    expect(result.streams.map((s) => s.url),
        ['https://cdn.example/stream/e2h!.txt']);
  });

  test('a title with no Hindi voice gives no streams', () async {
    final result = await run(
      'allmovieland',
      _network(voices: [
        {'title': 'Tamil', 'file': 't1'},
      ]),
      const {'type': 'movie', 'id': 'tt0133093'},
    );

    expect(result.error, isNull);
    expect(result.streams, isEmpty);
  });

  test('an unknown title is an error, and so is a missing imdb id', () async {
    final unknown = await run(
      'allmovieland',
      (Seen r) => r.url.host == 'allmovieland.link'
          ? ok("const AwsIndStreamDomain = '$_host/';")
          : ok('<html>not found</html>'),
      const {'type': 'movie', 'id': 'tt0000001'},
    );
    expect(unknown.error, isNotNull);

    final noId = await run('allmovieland', _network(voices: []), const {
      'type': 'movie',
      'id': '603',
    });
    expect(noId.error, isNotNull);
  });
}
