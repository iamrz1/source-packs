import 'dart:convert';
import 'dart:typed_data';

import 'package:source_packs/source_packs.dart';
import 'package:source_packs/src/template.dart';
import 'package:test/test.dart';

import 'support.dart';

// What level 2 of the runtime added: the `entries` filter, a `height` filter
// that reads bare numbers, binary request and reply bodies (base64url) and the
// `requires` check that keeps a recipe from running on a runtime too old for it.

Map<String, dynamic> _recipe(List<Map<String, dynamic>> steps,
        {int? requires}) =>
    {
      'id': 'x',
      'name': 'X',
      if (requires != null) 'requires': requires,
      'credits': [
        {'author': 'a', 'url': 'https://u'},
      ],
      'steps': steps,
    };

void main() {
  group('entries', () {
    test('turns a map into key and value pairs in order', () {
      final v = evalValue(
        '{{m | entries}}',
        Scope({
          'm': {'360': 'a', '1080': 'b'},
        }),
      );
      expect(v, [
        {'key': '360', 'value': 'a'},
        {'key': '1080', 'value': 'b'},
      ]);
    });

    test('anything else is an empty list', () {
      expect(evalValue('{{m | entries}}', Scope({'m': 'text'})), isEmpty);
      expect(evalValue('{{m | entries}}', Scope()), isEmpty);
    });
  });

  test('height reads a bare number too', () {
    for (final c
        in {'1080': 1080, '720p': 720, '4K': 2160, 'hindi': null}.entries) {
      expect(evalValue('{{x | height}}', Scope({'x': c.key})), c.value);
    }
  });

  group('binary bodies', () {
    // Bytes that are not valid UTF-8, so a text round trip would corrupt them.
    final raw = Uint8List.fromList([0xff, 0xfe, 0x00, 0x01, 0x80, 0xc3, 0x28]);
    final encoded = base64Url.encode(raw).replaceAll('=', '');

    test('a base64url body is sent as the raw bytes', () async {
      final http = FakeHttp((_) => ok('done'));
      await RecipeInterpreter(http).run(
        _recipe([
          {
            'op': 'post',
            'url': 'https://h/p',
            'body': '{{blob}}',
            'bodyEncoding': 'base64url',
          },
        ], requires: 2),
        {'blob': encoded},
      );

      expect(http.seen.single.bodyBytes, raw);
      expect(http.seen.single.body, isNull);
    });

    test('a base64url reply is the raw bytes, encoded without padding',
        () async {
      final http = FakeHttp((_) => RecipeResponse(200, '', bytes: raw));
      final result = await RecipeInterpreter(http).run(
        _recipe([
          {
            'op': 'post',
            'url': 'https://h/p',
            'response': 'base64url',
            'as': 'blob',
          },
          {
            'op': 'emit',
            'stream': {'title': 't', 'url': 'https://h/{{blob}}'},
          },
        ], requires: 2),
        {},
      );

      expect(result.streams.single.url, 'https://h/$encoded');
    });

    test('what is received can be sent back unchanged', () async {
      final http = FakeHttp((r) {
        if (r.url.path == '/get') return RecipeResponse(200, '', bytes: raw);
        return okJson(
            {'echo': base64Url.encode(r.bodyBytes!).replaceAll('=', '')});
      });
      final result = await RecipeInterpreter(http).run(
        _recipe([
          {
            'op': 'get',
            'url': 'https://h/get',
            'response': 'base64url',
            'as': 'b'
          },
          {
            'op': 'post',
            'url': 'https://h/post',
            'body': '{{b}}',
            'bodyEncoding': 'base64url',
            'response': 'json',
            'as': 'r',
          },
          {
            'op': 'emit',
            'stream': {'title': 't', 'url': 'https://h/{{r.echo}}'},
          },
        ], requires: 2),
        {},
      );

      expect(result.streams.single.url, 'https://h/$encoded');
    });

    test('a body that is not base64url stops the run with a reason', () async {
      final http = FakeHttp((_) => ok(''));
      final result = await RecipeInterpreter(http).run(
        _recipe([
          {
            'op': 'post',
            'url': 'https://h/p',
            'body': 'not base64 !!',
            'bodyEncoding': 'base64url',
          },
        ], requires: 2),
        {},
      );

      expect(result.error, 'body is not base64url');
      expect(http.seen, isEmpty);
    });
  });

  group('requires', () {
    test('a recipe for a newer runtime is refused without any request',
        () async {
      final http = FakeHttp((_) => ok(''));
      final result = await RecipeInterpreter(http).run(
        _recipe([
          {'op': 'get', 'url': 'https://h/x'},
        ], requires: recipeRuntimeLevel + 1),
        {},
      );

      expect(result.error, contains('needs runtime level'));
      expect(http.seen, isEmpty);
    });

    test('the current level runs', () async {
      final result = await RecipeInterpreter(FakeHttp((_) => ok(''))).run(
        _recipe([
          {'op': 'get', 'url': 'https://h/x'},
        ], requires: recipeRuntimeLevel),
        {},
      );
      expect(result.error, isNull);
    });

    test('validation flags a newer level and a bad value', () {
      expect(
        validateRecipe(_recipe([
          {'op': 'set', 'as': 'a', 'value': '1'},
        ], requires: recipeRuntimeLevel + 1))
            .join(),
        contains('needs runtime level'),
      );
      final bad = _recipe([
        {'op': 'set', 'as': 'a', 'value': '1'},
      ])
        ..['requires'] = 'two';
      expect(validateRecipe(bad).join(), contains('requires must be'));
    });

    test('validation flags an unknown response or body encoding', () {
      final problems = validateRecipe(
        _recipe([
          {'op': 'get', 'url': 'https://h', 'response': 'xml'},
          {
            'op': 'post',
            'url': 'https://h',
            'body': 'x',
            'bodyEncoding': 'hex'
          },
        ]),
      ).join('\n');

      expect(problems, contains('unknown response "xml"'));
      expect(problems, contains('unknown bodyEncoding "hex"'));
    });
  });
}
