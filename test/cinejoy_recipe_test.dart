import 'dart:convert';
import 'dart:typed_data';

import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// cinejoy: list the servers, then per server enc-dec.app seals a request, the
// request goes to api.wing.st as raw bytes, and the raw reply is opened by
// enc-dec.app. The bytes are not text, so they travel as base64url.

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

// What api.wing.st would be sent for a server, and what it answers.
Uint8List _sealed(String server) =>
    Uint8List.fromList([0xff, 0x00, ...utf8.encode('req-$server')]);
Uint8List _reply(String server) =>
    Uint8List.fromList([0xfe, 0x01, ...utf8.encode('rep-$server')]);

Handler _network({
  List<String> servers = const ['secret', 'Nebula'],
  Set<String> decFails = const {},
  Set<String> playlistFails = const {},
  Map<String, List<Map<String, dynamic>>> captions = const {},
}) {
  return (Seen r) {
    if (r.url.toString() == 'https://api.wing.st/servers') {
      return okJson({
        'servers': [
          for (final s in servers) {'name': s, 'status': 'ok'},
        ],
      });
    }
    if (r.url.path == '/api/enc-cinejoy') {
      final target = Uri.parse(r.url.queryParameters['url']!);
      final server = target.queryParameters['server']!;
      return okJson({
        'status': 200,
        'result': {'data': _b64(_sealed(server)), 'state': 'state-$server'},
      });
    }
    if (r.url.toString() == 'https://api.wing.st/g') {
      final sent = r.bodyBytes!;
      final server = utf8.decode(sent.sublist(2)).replaceFirst('req-', '');
      return RecipeResponse(200, '', bytes: _reply(server));
    }
    if (r.url.path == '/api/dec-cinejoy') {
      final text = r.json['text'] as String;
      final server = utf8
          .decode(base64Url.decode(base64Url.normalize(text)).sublist(2))
          .replaceFirst('rep-', '');
      if (r.json['state'] != 'state-$server') return status(400);
      if (decFails.contains(server)) {
        return RecipeResponse(404, '{"error":"$server: upstream 502"}');
      }
      return okJson({
        'status': 200,
        'result': {
          'data': {
            'stream': [
              {
                'type': 'hls',
                'id': 'primary',
                'playlist': 'https://cdn/$server/master.m3u8',
                'captions': captions[server] ?? [],
              },
            ],
          },
          'status': 200,
        },
      });
    }
    if (r.url.host == 'cdn') {
      final server = r.url.pathSegments.first;
      return playlistFails.contains(server) ? status(502) : ok('#EXTM3U');
    }
    return status(404);
  };
}

const _movie = {
  'type': 'movie',
  'id': 'tt0133093',
  'tmdb': '603',
  'title': 'The Matrix',
  'year': '1999',
};

void main() {
  test('a movie gives one stream per working server', () async {
    final result = await run('cinejoy', _network(), _movie);

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.title),
        ['Cinejoy secret', 'Cinejoy Nebula']);
    expect(result.streams.map((s) => s.url), [
      'https://cdn/secret/master.m3u8',
      'https://cdn/Nebula/master.m3u8',
    ]);
  });

  test('the bytes survive the trip to api.wing.st and back', () async {
    final http = FakeHttp(_network(servers: ['secret']));
    await RecipeInterpreter(http).run(loadRecipe('cinejoy'), _movie);

    final post = http.seen.firstWhere((r) => r.url.path == '/g');
    expect(post.method, 'POST');
    expect(post.bodyBytes, _sealed('secret'));
    final dec = http.seen.firstWhere((r) => r.url.path == '/api/dec-cinejoy');
    expect(dec.json['text'], _b64(_reply('secret')));
    expect(dec.json['state'], 'state-secret');
  });

  test('the request to the server list carries the site origin', () async {
    final http = FakeHttp(_network(servers: ['secret']));
    await RecipeInterpreter(http).run(loadRecipe('cinejoy'), _movie);

    final headers = http.seen.first.headers;
    expect(headers['Origin'], 'https://cinejoy.pk');
    expect(headers['Referer'], 'https://cinejoy.pk/');
  });

  test('the sealed request names the title, ids and server', () async {
    final http = FakeHttp(_network(servers: ['Nebula']));
    await RecipeInterpreter(http).run(loadRecipe('cinejoy'), {
      ..._movie,
      'title': 'Game of Thrones',
    });

    final target = Uri.parse(
      http.seen
          .firstWhere((r) => r.url.path == '/api/enc-cinejoy')
          .url
          .queryParameters['url']!,
    );
    expect(target.host, 'api.wing.st');
    expect(target.queryParameters, {
      'title': 'Game of Thrones',
      'type': 'movie',
      'year': '1999',
      'imdb': 'tt0133093',
      'tmdb': '603',
      'server': 'Nebula',
    });
  });

  test('a series adds the season and episode', () async {
    final http = FakeHttp(_network(servers: ['secret']));
    await RecipeInterpreter(http).run(loadRecipe('cinejoy'), {
      'type': 'series',
      'id': 'tt0944947:1:2',
      'tmdb': '1399',
      'title': 'Game of Thrones',
      'year': '2011',
    });

    final target = Uri.parse(
      http.seen
          .firstWhere((r) => r.url.path == '/api/enc-cinejoy')
          .url
          .queryParameters['url']!,
    );
    expect(target.queryParameters['type'], 'series');
    expect(target.queryParameters['season'], '1');
    expect(target.queryParameters['episode'], '2');
  });

  test('streams carry the playback headers the 4K server needs', () async {
    final result = await run('cinejoy', _network(servers: ['secret']), _movie);

    final headers = result.streams.single.headers;
    expect(headers['Referer'], 'https://cinejoy.pk/');
    expect(headers['Origin'], 'https://cinejoy.pk');
    expect(headers['User-Agent'], contains('Chrome'));
  });

  test('a server enc-dec.app cannot open is skipped, the rest stay', () async {
    final result = await run(
      'cinejoy',
      _network(servers: ['secret', 'Lisbon', 'Nebula'], decFails: {'Lisbon'}),
      _movie,
    );

    expect(result.streams.map((s) => s.title),
        ['Cinejoy secret', 'Cinejoy Nebula']);
  });

  test('a server whose playlist does not load is skipped', () async {
    final result = await run(
      'cinejoy',
      _network(
          servers: ['secret', 'Solara', 'Nebula'], playlistFails: {'Solara'}),
      _movie,
    );

    expect(result.streams.map((s) => s.title),
        ['Cinejoy secret', 'Cinejoy Nebula']);
  });

  test('subtitles come with the stream and the playback headers', () async {
    final result = await run(
      'cinejoy',
      _network(
        servers: ['secret'],
        captions: {
          'secret': [
            {
              'type': 'vtt',
              'id': 'en',
              'url': 'https://cdn/secret/en.vtt',
              'language': 'EN'
            },
          ],
        },
      ),
      _movie,
    );

    final sub = result.subtitles.single;
    expect(sub.url, 'https://cdn/secret/en.vtt');
    expect(sub.lang, 'en');
    expect(sub.headers['Referer'], 'https://cinejoy.pk/');
  });

  test('no servers listed gives nothing and says so', () async {
    final result = await run('cinejoy', _network(servers: []), _movie);

    expect(result.streams, isEmpty);
    expect(result.error, 'cinejoy listed no servers');
  });

  test('every server failing gives an empty result', () async {
    final result = await run(
      'cinejoy',
      _network(decFails: {'secret', 'Nebula'}),
      _movie,
    );

    expect(result.streams, isEmpty);
  });

  test('missing title, tmdb id or episode is skipped without a request',
      () async {
    for (final inputs in [
      {..._movie}..remove('title'),
      {..._movie}..remove('tmdb'),
      {
        'type': 'series',
        'id': 'tt1',
        'tmdb': '1',
        'title': 'X',
        'year': '2000'
      },
    ]) {
      final http = FakeHttp(_network());
      final result =
          await RecipeInterpreter(http).run(loadRecipe('cinejoy'), inputs);

      expect(result.streams, isEmpty, reason: '$inputs');
      expect(http.seen, isEmpty, reason: '$inputs');
    }
  });

  test('a network error gives nothing and does not throw', () async {
    final result = await RecipeInterpreter(
      FakeHttp((_) => throw StateError('offline')),
    ).run(loadRecipe('cinejoy'), _movie);

    expect(result.streams, isEmpty);
    expect(result.error, isNotNull);
  });
}
