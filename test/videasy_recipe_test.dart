import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// The videasy recipe: a seed, then per server a sources blob, decrypted by
// enc-dec.app into quality-labelled streams and subtitles. The first server
// that yields streams wins.

Map<String, dynamic> dec({List? sources, List? subtitles}) => {
      'status': 200,
      'result': {
        'sources': sources ??
            [
              {
                'url': 'https://moon.goldenkite.top/vd/v.m3u8?q=A',
                'quality': '1080p'
              },
              {
                'url': 'https://moon.goldenkite.top/vd/v.m3u8?q=B',
                'quality': '720p'
              },
              {
                'url': 'https://moon.goldenkite.top/vdb/v.m3u8?q=C',
                'quality': '4K'
              },
            ],
        'subtitles': subtitles ??
            [
              {
                'url': 'https://moon.goldenkite.top/sub.vtt?q=1',
                'lang': 'English'
              },
              {
                'url': 'https://moon.goldenkite.top/sub.vtt?q=2',
                'lang': 'Spanish'
              },
            ],
      },
    };

Handler happy({
  Map<String, RecipeResponse Function(Seen)> servers = const {},
  RecipeResponse Function(Seen)? decrypt,
}) {
  return (Seen r) {
    final url = r.url.toString();
    if (r.url.path == '/seed') {
      return okJson({'seed': 'seed-abc', 'ttlMs': 30000});
    }
    for (final e in servers.entries) {
      if (r.url.path == '/${e.key}/sources') return e.value(r);
    }
    if (r.url.path.endsWith('/sources')) {
      return ok('a9dc44encrypted_blob_hex_data');
    }
    if (url.contains('/api/dec-videasy')) {
      return decrypt?.call(r) ?? okJson(dec());
    }
    return status(404);
  };
}

const movie = {
  'type': 'movie',
  'id': 'tt0133093',
  'tmdb': '603',
  'title': 'The Matrix',
  'year': '1999',
};

void main() {
  test('a movie gives streams with quality labels, and subtitles', () async {
    final result = await run('videasy', happy(), movie);

    expect(result.error, isNull);
    expect(result.streams.map((s) => s.height), [1080, 720, 2160]);
    expect(
        result.streams.map((s) => s.title).toSet(), {'Miami - Original audio'});
    expect(result.subtitles.map((s) => s.lang), ['english', 'spanish']);
  });

  test('streams and subtitles carry the origin the CDN requires', () async {
    final result = await run('videasy', happy(), movie);

    for (final headers in [
      ...result.streams.map((s) => s.headers),
      ...result.subtitles.map((s) => s.headers),
    ]) {
      expect(headers['Origin'], 'https://vidy.st');
      expect(headers['Referer'], 'https://vidy.st/');
      expect(headers['User-Agent'], contains('Chrome'));
    }
  });

  test('the title is double url-encoded and the other params follow', () async {
    final http = FakeHttp(happy());
    await RecipeInterpreter(http).run(loadRecipe('videasy'), {
      ...movie,
      'title': 'Game of Thrones',
    });

    final sources = http.seen.firstWhere((r) => r.url.path == '/miami/sources');
    expect(
      sources.url.toString(),
      'https://api.wecollege.net/miami/sources'
      '?title=Game%2520of%2520Thrones&mediaType=movie&year=1999'
      '&tmdbId=603&imdbId=tt0133093&enc=2&seed=seed-abc',
    );
  });

  test('a series adds seasonId and episodeId and uses mediaType tv', () async {
    final http = FakeHttp(happy());
    await RecipeInterpreter(http).run(loadRecipe('videasy'), {
      'type': 'series',
      'id': 'tt0944947:2:5',
      'tmdb': '1399',
      'title': 'Game of Thrones',
      'year': '2011',
    });

    final url = http.seen.firstWhere((r) => r.url.path == '/miami/sources').url;
    expect(url.queryParameters['mediaType'], 'tv');
    expect(url.queryParameters['seasonId'], '2');
    expect(url.queryParameters['episodeId'], '5');
    expect(url.queryParameters['imdbId'], 'tt0944947');
  });

  test('empty params are left out', () async {
    final http = FakeHttp(happy());
    await RecipeInterpreter(http).run(loadRecipe('videasy'), {
      'type': 'movie',
      'id': 'nm0001',
      'tmdb': '603',
      'title': 'The Matrix',
    });

    final url = http.seen.firstWhere((r) => r.url.path == '/miami/sources').url;
    expect(url.queryParameters.keys, [
      'title',
      'mediaType',
      'tmdbId',
      'enc',
      'seed',
    ]);
  });

  test('the dec call sends the blob, the tmdb id and the seed', () async {
    final http = FakeHttp(happy());
    await RecipeInterpreter(http).run(loadRecipe('videasy'), movie);

    final decrypt =
        http.seen.firstWhere((r) => r.url.path == '/api/dec-videasy');
    expect(decrypt.method, 'POST');
    expect(decrypt.json, {
      'text': 'a9dc44encrypted_blob_hex_data',
      'id': '603',
      'seed': 'seed-abc',
    });
    expect(decrypt.headers['Content-Type'], 'application/json');
    expect(decrypt.headers['Origin'], 'https://vidy.st');
  });

  test('the next server is tried when the first has nothing', () async {
    final result = await run(
      'videasy',
      happy(servers: {'miami': (_) => status(500)}),
      movie,
    );

    expect(
        result.streams.map((s) => s.title).toSet(), {'Boise - Original audio'});
  });

  test('the next server is tried when the first decrypts to no sources',
      () async {
    var calls = 0;
    final result = await run(
      'videasy',
      happy(decrypt: (_) => okJson(++calls == 1 ? dec(sources: []) : dec())),
      movie,
    );

    expect(
        result.streams.map((s) => s.title).toSet(), {'Boise - Original audio'});
    expect(result.subtitles, hasLength(2), reason: 'the empty one is dropped');
  });

  test('it stops at the first server that works and reuses one seed', () async {
    final http = FakeHttp(happy());
    await RecipeInterpreter(http).run(loadRecipe('videasy'), movie);

    expect(http.seen.where((r) => r.url.path == '/seed'), hasLength(1));
    expect(
        http.seen.where((r) => r.url.path.endsWith('/sources')), hasLength(1));
  });

  test('every server is tried before giving up', () async {
    final http = FakeHttp(
      happy(
          servers: {'miami': (_) => status(500), 'boise': (_) => status(500)}),
    );
    final result =
        await RecipeInterpreter(http).run(loadRecipe('videasy'), movie);

    expect(result.streams, isEmpty);
    expect(
        http.seen.where((r) => r.url.path.endsWith('/sources')), hasLength(2));
  });

  test('an error JSON from a server counts as nothing', () async {
    final result = await run(
      'videasy',
      happy(
        servers: {
          'miami': (_) => ok('{"error":"Error","message":"Unable to load"}'),
        },
      ),
      movie,
    );

    expect(
        result.streams.map((s) => s.title).toSet(), {'Boise - Original audio'});
  });

  test('a non-200 status from dec-videasy counts as nothing', () async {
    final result = await run(
      'videasy',
      happy(decrypt: (_) => okJson({'status': 500, 'result': ''})),
      movie,
    );

    expect(result.streams, isEmpty);
  });

  test('sources without a url are skipped and a missing quality is Auto',
      () async {
    final result = await run(
      'videasy',
      happy(
        decrypt: (_) => okJson(
          dec(
            sources: [
              {'quality': '1080p'},
              {'url': 'https://h/a.m3u8'},
              {'url': 'https://h/b.m3u8', 'quality': 'Hindi'},
            ],
          ),
        ),
      ),
      movie,
    );

    expect(result.streams.map((s) => s.url),
        ['https://h/a.m3u8', 'https://h/b.m3u8']);
    expect(result.streams.map((s) => s.height), [null, null]);
  });

  test('subtitles are de-duplicated by url, with the language lower-cased',
      () async {
    final result = await run(
      'videasy',
      happy(
        decrypt: (_) => okJson(
          dec(
            subtitles: [
              {'url': 'https://h/1.vtt', 'lang': 'English'},
              {'url': 'https://h/1.vtt', 'lang': 'English'},
              {'url': 'https://h/2.vtt', 'language': 'FRENCH'},
              {'lang': 'English'},
            ],
          ),
        ),
      ),
      movie,
    );

    expect(result.subtitles.map((s) => '${s.lang} ${s.url}'), [
      'english https://h/1.vtt',
      'french https://h/2.vtt',
    ]);
  });

  test('missing sources and subtitles give an empty result, not a crash',
      () async {
    final result = await run(
      'videasy',
      happy(decrypt: (_) => okJson({'status': 200, 'result': {}})),
      movie,
    );

    expect(result.streams, isEmpty);
    expect(result.subtitles, isEmpty);
  });

  group('skips without a request', () {
    for (final c in [
      (name: 'no tmdb id', inputs: {...movie}..remove('tmdb'), why: 'tmdb'),
      (name: 'no title', inputs: {...movie}..remove('title'), why: 'title'),
      (name: 'a blank title', inputs: {...movie, 'title': '   '}, why: 'title'),
      (
        name: 'a series without season and episode',
        inputs: {...movie, 'type': 'series'},
        why: 'season',
      ),
    ]) {
      test(c.name, () async {
        final http = FakeHttp(happy());
        final result = await RecipeInterpreter(http).run(
          loadRecipe('videasy'),
          c.inputs,
        );

        expect(result.streams, isEmpty);
        expect(result.error, contains(c.why));
        expect(http.seen, isEmpty);
      });
    }
  });

  test('a failed seed gives nothing and tries no server', () async {
    final http =
        FakeHttp((r) => r.url.path == '/seed' ? status(500) : happy()(r));
    final result =
        await RecipeInterpreter(http).run(loadRecipe('videasy'), movie);

    expect(result.streams, isEmpty);
    expect(http.seen.where((r) => r.url.path.endsWith('/sources')), isEmpty);
  });

  test('a network error gives nothing and does not throw', () async {
    final result = await RecipeInterpreter(
      FakeHttp((_) => throw StateError('offline')),
    ).run(loadRecipe('videasy'), movie);

    expect(result.streams, isEmpty);
    expect(result.error, isNotNull);
  });
}
