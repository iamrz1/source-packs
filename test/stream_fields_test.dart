import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

import 'support.dart';

// What level 4 added: the stream fields expiresAt, lang and size, and the
// limits on `extract`.

Map<String, dynamic> _recipe(
  List<Map<String, dynamic>> steps, {
  int? requires,
}) =>
    {
      'id': 'x',
      'name': 'X',
      if (requires != null) 'requires': requires,
      'credits': [
        {'author': 'a', 'url': 'https://u'},
      ],
      'steps': steps,
    };

Map<String, dynamic> _emit(Map<String, dynamic> stream) => {
      'op': 'emit',
      'stream': {'title': 't', 'url': 'https://h/v', ...stream},
    };

Future<RecipeStream> _stream(Map<String, dynamic> fields) async {
  final result = await RecipeInterpreter(FakeHttp((_) => status(404)))
      .run(_recipe([_emit(fields)], requires: 4), {});
  return result.streams.single;
}

void main() {
  test('numbers and numeric text are read, other values are dropped', () async {
    final a = await _stream({
      'expiresAt': '1799769664',
      'size': 1048576,
      'lang': 'EN',
    });
    expect([a.expiresAt, a.size, a.lang], [1799769664, 1048576, 'en']);

    final b = await _stream({
      'expiresAt': 'soon',
      'size': '-5',
      'lang': 'english',
    });
    expect([b.expiresAt, b.size, b.lang], [null, null, '']);

    final c = await _stream({'lang': 'original'});
    expect(c.lang, 'original');
  });

  test('a recipe that emits them must require level 4', () {
    final steps = [
      _emit({'expiresAt': '1', 'lang': 'en', 'size': '2'}),
    ];

    expect(validateRecipe(_recipe(steps, requires: 4)), isEmpty);
    final problems = validateRecipe(_recipe(steps, requires: 3)).join('\n');
    expect(problems, contains('"expiresAt" needs "requires": 4'));
    expect(problems, contains('"lang" needs "requires": 4'));
    expect(problems, contains('"size" needs "requires": 4'));
  });

  test('extract reads only the first megabyte and refuses a long pattern',
      () async {
    // The "b" sits past the cap, so the pattern cannot find it.
    final http = FakeHttp((_) => ok('${'a' * maxExtractText}b'));
    final recipe = _recipe([
      {'op': 'get', 'url': 'https://h/x', 'as': 'page'},
      {'op': 'extract', 'from': '{{page}}', 'regex': '(b)', 'as': 'found'},
      _emit({'url': 'https://h/{{found}}end'}),
    ]);
    final result = await RecipeInterpreter(http).run(recipe, {});
    expect(result.streams.single.url, 'https://h/end');

    final bad = _recipe([
      {
        'op': 'extract',
        'from': 'aaa',
        'regex': 'a' * (maxRegexLength + 1),
        'as': 'x',
      },
    ]);
    expect(validateRecipe(bad).join(), contains('longer than'));
    final failed = await RecipeInterpreter(http).run(bad, {});
    expect(failed.error, 'regex is too long');
  });
}
