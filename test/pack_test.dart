import 'dart:convert';
import 'dart:io';

import 'package:source_packs/source_packs.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> recipes() => [
      for (final f in Directory('recipes')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json')))
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    ];

void main() {
  group('the shipped recipes', () {
    test('are valid', () {
      for (final r in recipes()) {
        expect(validateRecipe(r), isEmpty, reason: '${r['id']}');
      }
    });

    test('each credits where its steps come from', () {
      for (final r in recipes()) {
        final credits = (r['credits'] as List).cast<Map>();
        expect(credits.map((c) => c['author']), contains('smy778'),
            reason: '${r['id']}');
        expect(
            credits.first['url'], 'https://github.com/smy778/EncDecEndpoints');
      }
    });

    test('are named after their file', () {
      for (final f in Directory('recipes').listSync().whereType<File>()) {
        final id = (jsonDecode(f.readAsStringSync()) as Map)['id'];
        expect(f.path, endsWith('/$id.json'));
      }
    });
  });

  group('validateRecipe', () {
    Map<String, dynamic> base() => {
          'id': 'x',
          'name': 'X',
          'credits': [
            {'author': 'a', 'url': 'https://u'},
          ],
          'steps': [
            {'op': 'set', 'as': 'a', 'value': '1'},
          ],
        };

    test('accepts a minimal recipe',
        () => expect(validateRecipe(base()), isEmpty));

    test('names every problem', () {
      final bad = base()
        ..['id'] = 'Bad Id'
        ..['credits'] = []
        ..['steps'] = [
          {'op': 'jump'},
          {'op': 'get'},
          {'op': 'extract', 'from': 'x', 'regex': '(', 'as': 'a'},
          {
            'op': 'foreach',
            'in': '{{a}}',
            'as': 'i',
            'steps': [
              {'op': 'emit'},
            ],
          },
          {'op': 'set', 'as': 'a', 'value': '{{x | nope}}'},
        ];
      final problems = validateRecipe(bad).join('\n');

      expect(problems, contains('id must be'));
      expect(problems, contains('credits is missing'));
      expect(problems, contains('unknown op "jump"'));
      expect(problems, contains('"url" is missing'));
      expect(problems, contains('bad regex'));
      expect(problems, contains('steps[3].steps[0] (emit)'));
      expect(problems, contains('unknown filter "nope"'));
    });
  });

  group('the pack', () {
    final published = DateTime.utc(2026, 11, 7, 12);

    test('holds every recipe by id, with the credits once', () {
      final pack = buildPack(recipes(), version: '1.2.3', published: published);

      expect(pack['schema'], packSchema);
      expect(pack['version'], '1.2.3');
      expect(pack['published'], '2026-11-07T12:00:00.000Z');
      expect(
          (pack['providers'] as Map).keys, ['vidcore', 'videasy', 'vidfast']);
      expect(pack['credits'], hasLength(1));
      expect((pack['credits'] as List).single['author'], 'smy778');
    });

    test('is the same bytes every time', () {
      final a = encodePack(
          buildPack(recipes(), version: '1.0.0', published: published));
      final b = encodePack(buildPack(recipes().reversed.toList(),
          version: '1.0.0', published: published));
      expect(a, b);
    });

    test('reads back', () {
      final bytes = encodePack(
          buildPack(recipes(), version: '1.2.3', published: published));
      final pack = Pack.parse(bytes);

      expect(pack.version, '1.2.3');
      expect(pack.providers.keys, ['vidcore', 'videasy', 'vidfast']);
      expect(pack.published, published);
    });

    test('refuses what it cannot read', () {
      expect(() => Pack.parse(utf8.encode('nope')), throwsFormatException);
      expect(() => Pack.parse(utf8.encode('[]')), throwsFormatException);
      expect(
        () => Pack.parse(
            utf8.encode('{"schema":99,"version":"1.0.0","providers":{}}')),
        throwsFormatException,
      );
      expect(
        () => Pack.parse(
            utf8.encode('{"schema":1,"version":"x","providers":{}}')),
        throwsFormatException,
      );
      expect(
        () => Pack.parse(utf8.encode('{"schema":1,"version":"1.0.0"}')),
        throwsFormatException,
      );
    });
  });

  group('versions', () {
    test('compare as numbers', () {
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('v2.0.0', '1.99.99'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('0.1.0', '0.1.1'), lessThan(0));
    });
    test('one that does not parse is older', () {
      expect(compareVersions('x', '0.0.1'), lessThan(0));
      expect(compareVersions('0.0.1', 'x'), greaterThan(0));
      expect(compareVersions('x', 'y'), 0);
    });
  });
}
