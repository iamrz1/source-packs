import 'dart:convert';

import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// The vidcore and vidfast recipes share one chain: scrape the page, two enc
// stages, servers, then one stream per server. These tests walk it with a fake
// network, the way a device would.

/// A network that implements the whole chain for [site] / [slug].
Handler chain(
  String site,
  String slug, {
  bool Function(Seen)? failStream,
  Map<String, String>? pageBody,
}) {
  return (Seen r) {
    final url = r.url.toString();
    if (url.startsWith('$site/movie/') || url.startsWith('$site/tv/')) {
      return ok(
        pageBody?[r.url.path] ??
            r'<html><script>x={\"en\":\"ENTOKEN123\"}</script></html>',
      );
    }
    if (r.url.path == '/api/enc-$slug' &&
        r.url.queryParameters['stage'] == '1') {
      if (r.url.queryParameters['text'] != 'ENTOKEN123') {
        return okJson({'status': 400, 'error': 'bad text'});
      }
      return okJson({
        'status': 200,
        'result': {'stage1': '$site/mo/STAGE1', 'token': 'CSRF_STAGE1'},
      });
    }
    if (url == '$site/mo/STAGE1') {
      if (r.method != 'POST' || r.headers['X-CSRF-Token'] != 'CSRF_STAGE1') {
        return status(403);
      }
      return ok('STAGE1 REPLY+/=');
    }
    if (r.url.path == '/api/enc-$slug' &&
        r.url.queryParameters['stage'] == '2') {
      if (r.url.queryParameters['text'] != 'STAGE1 REPLY+/=') {
        return okJson({'status': 400, 'error': 'bad text'});
      }
      return okJson({
        'status': 200,
        'result': {
          'servers': '$site/mo/SERVERS',
          'stream': '$site/mo/STREAM',
          'token': 'CSRF123',
        },
      });
    }
    if (r.url.path == '/api/dec-$slug') {
      final blob = r.json['text'];
      if (blob == 'SERVERS_BLOB') {
        return okJson({
          'status': 200,
          'result': [
            {'name': 'Prime', 'description': 'Original audio', 'data': 'D_EN'},
            {'name': 'Net', 'description': 'Latino', 'data': 'D_LAT'},
          ],
        });
      }
      if (blob == 'STREAM_D_EN') {
        return okJson({
          'status': 200,
          'result': {'url': 'https://moon.goldenkite.top/v.m3u8?q=EN'},
        });
      }
      if (blob == 'STREAM_D_LAT') {
        // The result may also arrive as a JSON string.
        return okJson({
          'status': 200,
          'result':
              jsonEncode({'url': 'https://moon.goldenkite.top/v.m3u8?q=LAT'}),
        });
      }
      return okJson({'status': 500, 'result': ''});
    }
    if (url == '$site/mo/SERVERS') {
      return r.headers['X-CSRF-Token'] == 'CSRF123'
          ? ok('SERVERS_BLOB')
          : status(403);
    }
    if (url.startsWith('$site/mo/STREAM/')) {
      if (r.headers['X-CSRF-Token'] != 'CSRF123') return status(403);
      if (failStream?.call(r) ?? false) return status(500);
      return ok('STREAM_${url.split('/').last}');
    }
    return status(404);
  };
}

void main() {
  for (final site in [
    (id: 'vidcore', name: 'Vidcore', url: 'https://vidcore.io'),
    (id: 'vidfast', name: 'Vidfast', url: 'https://vidfast.vc'),
  ]) {
    group(site.id, () {
      Future<RecipeResult> resolve(
        Map<String, dynamic> inputs, {
        Handler? handler,
        List<String>? log,
      }) =>
          run(site.id, handler ?? chain(site.url, site.id), inputs, log: log);

      test('a movie gives one stream per server, with the playback headers',
          () async {
        final result = await resolve({
          'type': 'movie',
          'id': 'tt0137523',
          'tmdb': '550',
        });

        expect(result.error, isNull);
        expect(result.streams.map((s) => s.title), [
          'Prime - Original audio',
          'Net - Latino',
        ]);
        expect(result.streams.map((s) => s.url), [
          'https://moon.goldenkite.top/v.m3u8?q=EN',
          'https://moon.goldenkite.top/v.m3u8?q=LAT',
        ]);
        for (final s in result.streams) {
          expect(s.height, isNull);
          expect(s.headers['Referer'], '${site.url}/');
          expect(s.headers['Origin'], site.url);
          expect(s.headers['User-Agent'], contains('Chrome'));
        }
      });

      test('the page path uses the TMDB id, or the IMDB id without one',
          () async {
        final http = FakeHttp(chain(site.url, site.id));
        final interpreter = RecipeInterpreter(http);
        final recipe = loadRecipe(site.id);

        await interpreter.run(
            recipe, {'type': 'movie', 'id': 'tt0137523', 'tmdb': 'tmdb:550'});
        await interpreter.run(recipe, {'type': 'movie', 'id': 'tt0137523'});

        final pages = http.seen.where(
            (r) => r.url.host == Uri.parse(site.url).host && r.method == 'GET');
        expect(
            pages.map((r) => r.url.path), ['/movie/550/', '/movie/tt0137523/']);
      });

      test('a series builds the /tv/{id}/{season}/{episode}/ path', () async {
        final http = FakeHttp(chain(site.url, site.id));
        await RecipeInterpreter(http).run(loadRecipe(site.id), {
          'type': 'series',
          'id': 'tt0944947:2:5',
          'tmdb': '1399',
        });

        expect(http.seen.first.url.path, '/tv/1399/2/5/');
      });

      test('a series without season and episode is skipped', () async {
        final http = FakeHttp(chain(site.url, site.id));
        final result = await RecipeInterpreter(http).run(loadRecipe(site.id), {
          'type': 'series',
          'id': 'tt0944947',
          'tmdb': '1399',
        });

        expect(result.streams, isEmpty);
        expect(result.error, contains('season'));
        expect(http.seen, isEmpty);
      });

      test('no usable id is skipped without a request', () async {
        final http = FakeHttp(chain(site.url, site.id));
        final result = await RecipeInterpreter(http).run(loadRecipe(site.id), {
          'type': 'movie',
          'id': 'nm0000',
        });

        expect(result.error, 'no usable id');
        expect(http.seen, isEmpty);
      });

      test('the token is read from the plain form of the page too', () async {
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: chain(
            site.url,
            site.id,
            pageBody: {'/movie/1/': '{"token":"ENTOKEN123"}'},
          ),
        );

        expect(result.streams, hasLength(2));
      });

      test('no token on the page gives nothing', () async {
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: chain(site.url, site.id,
              pageBody: {'/movie/1/': '<html></html>'}),
        );

        expect(result.streams, isEmpty);
        expect(result.error, contains('token'));
      });

      test('a refused stage-1 POST gives nothing and says why', () async {
        final log = <String>[];
        final base = chain(site.url, site.id);
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: (r) => r.url.toString() == '${site.url}/mo/STAGE1'
              ? status(404)
              : base(r),
          log: log,
        );

        expect(result.streams, isEmpty);
        expect(result.error, contains('HTTP 404'));
        expect(log.join('\n'), contains('${site.id}: POST'));
      });

      test('stage 2 reporting an error gives nothing', () async {
        final base = chain(site.url, site.id);
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: (r) => r.url.queryParameters['stage'] == '2'
              ? okJson({'status': 400, 'error': 'stage required'})
              : base(r),
        );

        expect(result.streams, isEmpty);
        expect(result.error, contains('servers URL'));
      });

      test('the stage-1 reply is url-encoded into stage 2', () async {
        final http = FakeHttp(chain(site.url, site.id));
        await RecipeInterpreter(http).run(loadRecipe(site.id), {
          'type': 'movie',
          'id': 'tt1',
          'tmdb': '1',
        });

        final stage2 =
            http.seen.firstWhere((r) => r.url.queryParameters['stage'] == '2');
        expect(stage2.url.query, contains('text=STAGE1%20REPLY%2B%2F%3D'));
      });

      test('a server whose stream fails is skipped, the others stay', () async {
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: chain(site.url, site.id,
              failStream: (r) => r.url.path.endsWith('/D_LAT')),
        );

        expect(result.streams.map((s) => s.title), ['Prime - Original audio']);
      });

      test('a server with only a name or only a description is still labelled',
          () async {
        final base = chain(site.url, site.id);
        final result = await resolve(
          {'type': 'movie', 'id': 'tt1', 'tmdb': '1'},
          handler: (r) => r.url.path == '/api/dec-${site.id}' &&
                  r.json['text'] == 'SERVERS_BLOB'
              ? okJson({
                  'status': 200,
                  'result': [
                    {'name': 'OnlyName', 'data': 'D_EN'},
                    {'description': 'OnlyDesc', 'data': 'D_LAT'},
                    {'data': 'D_EN'},
                  ],
                })
              : base(r),
        );

        expect(result.streams.map((s) => s.title), [
          'OnlyName',
          'OnlyDesc',
          site.name,
        ]);
      });

      test('every enc-dec.app call carries a browser user agent', () async {
        final http = FakeHttp(chain(site.url, site.id));
        await RecipeInterpreter(http).run(loadRecipe(site.id), {
          'type': 'movie',
          'id': 'tt1',
          'tmdb': '1',
        });

        final encDec = http.seen.where((r) => r.url.host == 'enc-dec.app');
        expect(encDec, isNotEmpty);
        for (final r in encDec) {
          expect(r.headers['User-Agent'], contains('Chrome'));
          expect(r.headers['Origin'], site.url);
        }
      });

      test('a network error gives nothing and does not throw', () async {
        final result = await RecipeInterpreter(
          FakeHttp((_) => throw StateError('offline')),
        ).run(loadRecipe(site.id), {'type': 'movie', 'id': 'tt1', 'tmdb': '1'});

        expect(result.streams, isEmpty);
        expect(result.error, isNotNull);
      });
    });
  }
}
