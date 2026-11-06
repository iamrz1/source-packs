import 'package:source_packs/src/template.dart';
import 'package:test/test.dart';

dynamic eval(String expr, [Map<String, dynamic> vars = const {}]) =>
    evalValue(expr, Scope({...vars}));

void main() {
  group('values', () {
    test('a whole expression keeps its type', () {
      expect(eval('{{n}}', {'n': 200}), 200);
      expect(
          eval('{{list}}', {
            'list': [1, 2]
          }),
          [1, 2]);
    });

    test('text around an expression interpolates, a missing value is empty',
        () {
      expect(eval('a-{{x}}-b', {'x': 1}), 'a-1-b');
      expect(eval('a-{{nope}}-b'), 'a--b');
    });

    test('paths walk maps and lists', () {
      final vars = {
        'a': {
          'b': [
            {'c': 'deep'},
          ],
        },
      };
      expect(eval('{{a.b.0.c}}', vars), 'deep');
      expect(eval('{{a.b.5.c}}', vars), isNull);
      expect(eval('{{a.x.y}}', vars), isNull);
    });

    test(r'$join keeps the non-empty parts, trimmed, or the default', () {
      Map join(List parts) => {
            r'$join': parts,
            'sep': ' - ',
            'default': 'fallback',
          };
      expect(evalValue(join(['{{a}}', '{{b}}']), Scope({'a': ' A ', 'b': 'B'})),
          'A - B');
      expect(evalValue(join(['{{a}}', '{{b}}']), Scope({'b': 'B'})), 'B');
      expect(evalValue(join(['{{a}}', '{{b}}']), Scope()), 'fallback');
    });

    test(r'$first is the first non-empty value', () {
      final spec = {
        r'$first': ['{{a}}', '{{b}}'],
      };
      expect(evalValue(spec, Scope({'b': 'B'})), 'B');
      expect(evalValue(spec, Scope({'a': 'A', 'b': 'B'})), 'A');
      expect(evalValue(spec, Scope()), '');
    });

    test('maps and lists are evaluated entry by entry', () {
      expect(
        evalValue({
          'k': '{{v}}',
          'l': ['{{v}}']
        }, Scope({'v': 'x'})),
        {
          'k': 'x',
          'l': ['x']
        },
      );
    });

    test('a child scope reads its parent and writes only to itself', () {
      final parent = Scope({'a': 1});
      final child = parent.child({'b': 2});
      child.set('a', 9);
      expect(child.get('a'), 9);
      expect(parent.get('a'), 1);
      expect(parent.get('b'), isNull);
    });
  });

  group('filters', () {
    test('urlenc',
        () => expect(eval("{{x | urlenc}}", {'x': 'a b&c'}), 'a%20b%26c'));
    test('lower and trim', () {
      expect(eval('{{x | trim | lower}}', {'x': '  AbC '}), 'abc');
    });
    test('capitalize', () {
      expect(eval('{{x | capitalize}}', {'x': 'miami'}), 'Miami');
      expect(eval('{{x | capitalize}}', {'x': ''}), '');
    });
    test('split and at, with a quoted colon', () {
      expect(eval("{{id | split:':' | at:1}}", {'id': 'tt1:2:3'}), '2');
      expect(eval("{{id | split:':' | at:5}}", {'id': 'tt1:2:3'}), isNull);
      expect(eval("{{id | split:':' | at:1}}", {'id': 'tt1'}), isNull);
    });
    test('prefix keeps a value only when it starts with it', () {
      expect(eval("{{x | prefix:'tt'}}", {'x': 'tt123'}), 'tt123');
      expect(eval("{{x | prefix:'tt'}}", {'x': 'nm123'}), '');
    });
    test('digits', () {
      expect(eval('{{x | digits}}', {'x': 'tmdb:550'}), '550');
      expect(eval('{{x | digits}}', {'x': 'abc'}), '');
    });
    test('default covers null, empty and empty lists', () {
      expect(eval("{{x | default:'d'}}", {'x': ''}), 'd');
      expect(eval("{{x | default:'d'}}"), 'd');
      expect(eval("{{x | default:'d'}}", {'x': 'v'}), 'v');
    });
    test('map replaces listed values and passes others through', () {
      expect(eval('{{x | map:series=tv}}', {'x': 'series'}), 'tv');
      expect(eval('{{x | map:series=tv}}', {'x': 'movie'}), 'movie');
    });
    test('height reads quality labels', () {
      for (final c in {
        '1080p': 1080,
        '720P': 720,
        ' 4K ': 2160,
        '4k': 2160,
        'Auto': null,
        'Hindi': null,
        '': null,
      }.entries) {
        expect(eval('{{x | height}}', {'x': c.key}), c.value, reason: c.key);
      }
    });
    test('json parses a string and passes structures through', () {
      expect(eval('{{x | json}}', {'x': '{"a":1}'}), {'a': 1});
      expect(
          eval('{{x | json}}', {
            'x': {'a': 1}
          }),
          {'a': 1});
      expect(eval('{{x | json}}', {'x': 'not json'}), isNull);
    });
    test('errorJson tells a short error object from a payload', () {
      expect(eval('{{x | errorJson}}', {'x': '{"error":"E"}'}), isTrue);
      expect(eval('{{x | errorJson}}', {'x': '{"ok":1}'}), isFalse);
      expect(eval('{{x | errorJson}}', {'x': 'a' * 1000}), isFalse);
      expect(eval('{{x | errorJson}}', {'x': 'plain blob'}), isFalse);
    });
    test('an unknown filter is an error', () {
      expect(() => eval('{{x | nope}}', {'x': 1}), throwsFormatException);
    });
  });

  group('checkTemplates', () {
    test('accepts known filters', () {
      expect(
          checkTemplates({
            'a': ['{{x | lower | default:"y"}}']
          }),
          isEmpty);
    });
    test('reports unknown filters, empty and unclosed expressions', () {
      expect(checkTemplates('{{x | nope}}'),
          ['unknown filter "nope" in "{{x | nope}}"']);
      expect(checkTemplates('{{ }}'), isNotEmpty);
      expect(checkTemplates('oops {{x'), isNotEmpty);
    });
  });
}
