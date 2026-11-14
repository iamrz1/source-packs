import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// vixsrc: an API call names the embed page, and the page holds an inline
// window.masterPlaylist object with the playlist url and a signed token.

const _page = '''
<script>
    window.masterPlaylist = {
        params: {
            'token': 'tok123',
            'expires': '1799769664',
            'asn': '',
        },
        url: 'https://vixsrc.to/playlist/214325',
    }
</script>
''';

Handler _network({String page = _page, Object? api}) => (Seen r) {
      if (r.url.path.startsWith('/api/')) {
        return okJson(api ?? {'src': '/embed/214325?x=1'});
      }
      if (r.url.path.startsWith('/embed/')) return ok(page);
      return status(404);
    };

const _movie = {'type': 'movie', 'id': 'tt0133093', 'tmdb': '603'};

void main() {
  test('gives one adaptive HLS stream with its expiry and language', () async {
    final result = await run('vixsrc', _network(), _movie);

    expect(result.error, isNull);
    expect(result.streams, hasLength(1));
    final s = result.streams.single;
    expect(
      s.url,
      'https://vixsrc.to/playlist/214325'
      '?token=tok123&expires=1799769664&h=1&lang=en',
    );
    expect(s.format, 'hls');
    expect(s.height, isNull);
    expect(s.expiresAt, 1799769664);
    expect(s.lang, 'en');
    expect(s.headers['Referer'], 'https://vixsrc.to/');
  });

  test('a movie and an episode use their own api path', () async {
    final movie = FakeHttp(_network());
    await RecipeInterpreter(movie).run(loadRecipe('vixsrc'), _movie);
    expect(movie.seen.first.url.path, '/api/movie/603');

    final episode = FakeHttp(_network());
    await RecipeInterpreter(episode).run(loadRecipe('vixsrc'), {
      'type': 'series',
      'id': 'tt0944947:2:5',
      'tmdb': '1399',
    });
    expect(episode.seen.first.url.path, '/api/tv/1399/2/5');
  });

  test('an embed page without a token gives nothing and says so', () async {
    final result = await run(
      'vixsrc',
      _network(page: '<html>nothing here</html>'),
      _movie,
    );

    expect(result.streams, isEmpty);
    expect(result.error, 'embed page has no token');
  });

  test('an api reply without an embed path gives nothing', () async {
    final result = await run('vixsrc', _network(api: {}), _movie);

    expect(result.error, 'no embed path');
  });

  test('a title without a tmdb id or a series without an episode is skipped',
      () async {
    for (final inputs in [
      {'type': 'movie', 'id': 'tt0133093'},
      {'type': 'series', 'id': 'tt0944947', 'tmdb': '1399'},
    ]) {
      final http = FakeHttp(_network());
      final result =
          await RecipeInterpreter(http).run(loadRecipe('vixsrc'), inputs);

      expect(result.streams, isEmpty, reason: '$inputs');
      expect(http.seen, isEmpty, reason: '$inputs');
    }
  });
}
