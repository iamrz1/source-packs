import 'package:test/test.dart';

import 'support.dart';

// vidup: the page gives a token, enc-dec.app turns it into two stages, and the
// servers and streams come back encrypted. The stage tokens may be empty.

const _site = 'https://vidup.to';

Handler _network({List<Map<String, String>>? tracks, bool noServers = false}) =>
    (Seen r) {
      final url = r.url.toString();
      if (url.startsWith('$_site/movie/') || url.startsWith('$_site/tv/')) {
        return ok(r'<html><script>x={\"en\":\"ENTOKEN\"}</script></html>');
      }
      if (r.url.path == '/api/enc-vidup') {
        return r.url.queryParameters['stage'] == '1'
            ? okJson({
                'status': 200,
                'result': {'stage1': '$_site/x/ONE', 'token': ''},
              })
            : okJson({
                'status': 200,
                'result': {
                  'servers': '$_site/x/SERVERS',
                  'stream': '$_site/x/STREAM',
                  'token': '',
                },
              });
      }
      if (url == '$_site/x/ONE') return ok('REPLY');
      if (url == '$_site/x/SERVERS') return ok('SERVERS_BLOB');
      if (url.startsWith('$_site/x/STREAM/')) {
        return ok('STREAM_${url.split('/').last}');
      }
      if (r.url.path == '/api/dec-vidup') {
        final blob = r.json['text'];
        if (blob == 'SERVERS_BLOB') {
          return okJson({
            'status': 200,
            'result': noServers
                ? []
                : [
                    {
                      'name': 'Euro',
                      'description': 'Original audio',
                      'data': 'A'
                    },
                    {
                      'name': 'Zenith',
                      'description': 'Original audio',
                      'data': 'B'
                    },
                  ],
          });
        }
        final which = '$blob'.endsWith('A') ? 'A' : 'B';
        return okJson({
          'status': 200,
          'result': {
            'url': 'https://cdn/$which.m3u8',
            'tracks': [
              for (final t in tracks ?? const <Map<String, String>>[])
                {'file': '${t['file']}$which', 'label': t['label']},
            ],
          },
        });
      }
      return status(404);
    };

const _movie = {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'};

void main() {
  test('one HLS stream per server, subtitles from the first server only',
      () async {
    final result = await run(
      'vidup',
      _network(tracks: [
        {'file': 'https://sub/en.vtt?', 'label': 'English'},
        {'file': 'https://sub/fr.vtt?', 'label': 'French'},
        {'file': 'https://sub/thumbs.vtt?', 'label': 't13'},
      ]),
      _movie,
    );

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.title),
        ['Euro - Original audio', 'Zenith - Original audio']);
    expect(result.streams.every((s) => s.format == 'hls'), isTrue);
    expect(result.streams.first.lang, 'original');
    expect(result.streams.first.headers['Referer'], 'https://vidup.to/');
    expect(result.subtitles.map((s) => s.lang), ['english', 'french']);
  });

  test('an episode asks the page for the season and episode', () async {
    final seen = <String>[];
    final result = await run(
      'vidup',
      (r) {
        seen.add(r.url.path);
        return _network()(r);
      },
      {'type': 'series', 'id': 'tt0944947:1:2', 'tmdb': '1399'},
    );
    expect(result.error, isNull);
    expect(seen.first, '/tv/1399/1/2/');
  });

  test('no servers gives an error', () async {
    final result = await run('vidup', _network(noServers: true), _movie);
    expect(result.streams, isEmpty);
    expect(result.error, 'dec gave no servers');
  });
}
