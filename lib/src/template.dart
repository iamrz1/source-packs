import 'dart:convert';

/// Variables visible to a step. A child scope reads through to its parent and
/// writes only to itself, so a `foreach` iteration cannot leak into the next.
class Scope {
  final Map<String, dynamic> _vars;
  final Scope? parent;

  Scope([Map<String, dynamic>? vars, this.parent]) : _vars = vars ?? {};

  Scope child([Map<String, dynamic>? vars]) => Scope(vars, this);

  void set(String name, dynamic value) => _vars[name] = value;

  bool has(String name) =>
      _vars.containsKey(name) || (parent?.has(name) ?? false);

  dynamic get(String name) {
    if (_vars.containsKey(name)) return _vars[name];
    return parent?.get(name);
  }
}

/// Null, an empty string, an empty list or an empty map.
bool isEmptyValue(dynamic v) =>
    v == null ||
    (v is String && v.isEmpty) ||
    (v is Iterable && v.isEmpty) ||
    (v is Map && v.isEmpty);

/// A filter turns one value into another: `{{name | lower | default:'x'}}`.
typedef Filter = dynamic Function(dynamic value, List<String> args);

final Map<String, Filter> filters = {
  'urlenc': (v, _) => Uri.encodeComponent(_str(v)),
  'lower': (v, _) => _str(v).toLowerCase(),
  'capitalize': (v, _) {
    final s = _str(v);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  },
  'trim': (v, _) => _str(v).trim(),
  'json': (v, _) {
    if (v is! String) return v;
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  },
  'split': (v, a) => _str(v).split(a.isEmpty ? ',' : a.first),
  'at': (v, a) {
    final i = int.tryParse(a.isEmpty ? '' : a.first);
    if (v is! List || i == null || i < 0 || i >= v.length) return null;
    return v[i];
  },
  'prefix': (v, a) {
    final s = _str(v);
    return a.isNotEmpty && s.startsWith(a.first) ? s : '';
  },
  'digits': (v, _) => RegExp(r'\d+').firstMatch(_str(v))?.group(0) ?? '',
  'default': (v, a) => isEmptyValue(v) ? (a.isEmpty ? '' : a.first) : v,
  'map': (v, a) {
    final s = _str(v);
    for (final pair in (a.isEmpty ? '' : a.first).split(',')) {
      final i = pair.indexOf('=');
      if (i > 0 && pair.substring(0, i) == s) return pair.substring(i + 1);
    }
    return v;
  },
  // "720p" -> 720, "1080" -> 1080, "4K" -> 2160, anything else (Auto, a
  // language) -> null.
  'height': (v, _) {
    final q = _str(v).trim().toLowerCase();
    if (q == '4k') return 2160;
    final m = RegExp(r'^(\d+)p?$').firstMatch(q);
    return m == null ? null : int.tryParse(m.group(1)!);
  },
  // A map as a list of {key, value}, for looping over keyed results.
  'entries': (v, _) => v is Map
      ? [
          for (final e in v.entries)
            {'key': e.key.toString(), 'value': e.value},
        ]
      : const [],
  // A short JSON object with an `error` key, as opposed to a real payload.
  'errorJson': (v, _) {
    final s = _str(v);
    if (s.length > 500) return false;
    try {
      final j = jsonDecode(s);
      return j is Map && j.containsKey('error');
    } catch (_) {
      return false;
    }
  },
};

/// The names a recipe may use in `{{ ... | filter }}`.
Set<String> get filterNames => filters.keys.toSet();

String _str(dynamic v) => v == null ? '' : v.toString();

final _whole = RegExp(r'^\s*\{\{(.*)\}\}\s*$', dotAll: true);
final _inline = RegExp(r'\{\{(.*?)\}\}', dotAll: true);

/// Evaluates a recipe value:
///  * `"{{expr}}"` (the whole string) keeps the result's type;
///  * `"text {{expr}} text"` interpolates (a missing value becomes "");
///  * `{"$join": [...], "sep": " - ", "default": ...}` joins the non-empty parts;
///  * `{"$first": [...]}` is the first non-empty part;
///  * any other map or list is evaluated entry by entry.
dynamic evalValue(dynamic spec, Scope scope) {
  if (spec is String) {
    final whole = _whole.firstMatch(spec);
    if (whole != null && !whole.group(1)!.contains('{{')) {
      return evalExpression(whole.group(1)!, scope);
    }
    return spec.replaceAllMapped(
      _inline,
      (m) => _str(evalExpression(m.group(1)!, scope)),
    );
  }
  if (spec is List) return [for (final e in spec) evalValue(e, scope)];
  if (spec is Map) {
    if (spec.containsKey(r'$join')) {
      final parts = [
        for (final p in (spec[r'$join'] as List))
          _str(evalValue(p, scope)).trim(),
      ].where((s) => s.isNotEmpty);
      if (parts.isEmpty) {
        return spec.containsKey('default')
            ? evalValue(spec['default'], scope)
            : '';
      }
      return parts.join(spec['sep']?.toString() ?? ' ');
    }
    if (spec.containsKey(r'$first')) {
      for (final p in (spec[r'$first'] as List)) {
        final v = evalValue(p, scope);
        if (!isEmptyValue(v)) return v;
      }
      return '';
    }
    return {
      for (final e in spec.entries) e.key.toString(): evalValue(e.value, scope)
    };
  }
  return spec;
}

/// `path | filter | filter:arg:arg`. The path is dotted (`server.name`,
/// `servers.0`), or a quoted literal (`'x'`).
dynamic evalExpression(String source, Scope scope) {
  final parts = _splitOutsideQuotes(source, '|');
  var value = _resolve(parts.first.trim(), scope);
  for (final raw in parts.skip(1)) {
    final pieces = _splitOutsideQuotes(raw.trim(), ':');
    final name = pieces.first.trim();
    final filter = filters[name];
    if (filter == null) throw FormatException('unknown filter "$name"');
    value = filter(value, [for (final a in pieces.skip(1)) _unquote(a.trim())]);
  }
  return value;
}

dynamic _resolve(String path, Scope scope) {
  if (path.isEmpty) return null;
  if (path.startsWith("'") && path.endsWith("'") && path.length >= 2) {
    return _unquote(path);
  }
  final num = int.tryParse(path);
  if (num != null) return num;
  final segments = path.split('.');
  dynamic current = scope.get(segments.first);
  for (final seg in segments.skip(1)) {
    if (current is Map) {
      current = current[seg];
    } else if (current is List) {
      final i = int.tryParse(seg);
      current = i != null && i >= 0 && i < current.length ? current[i] : null;
    } else {
      return null;
    }
  }
  return current;
}

String _unquote(String s) =>
    s.length >= 2 && s.startsWith("'") && s.endsWith("'")
        ? s.substring(1, s.length - 1)
        : s;

List<String> _splitOutsideQuotes(String s, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == "'") quoted = !quoted;
    if (c == sep && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

/// Checks every `{{ ... }}` in [spec] (any nesting) and returns what is wrong:
/// an unknown filter or a malformed expression. For recipe validation.
List<String> checkTemplates(dynamic spec) {
  final problems = <String>[];
  void visit(dynamic v) {
    if (v is String) {
      for (final m in _inline.allMatches(v)) {
        final expr = m.group(1)!;
        for (final raw in _splitOutsideQuotes(expr, '|').skip(1)) {
          final name = _splitOutsideQuotes(raw.trim(), ':').first.trim();
          if (!filters.containsKey(name)) {
            problems.add('unknown filter "$name" in "{{$expr}}"');
          }
        }
        if (_splitOutsideQuotes(expr, '|').first.trim().isEmpty) {
          problems.add('empty expression in "{{$expr}}"');
        }
      }
      if (_inline.allMatches(v).isEmpty && v.contains('{{')) {
        problems.add('unclosed "{{" in "$v"');
      }
    } else if (v is List) {
      v.forEach(visit);
    } else if (v is Map) {
      v.values.forEach(visit);
    }
  }

  visit(spec);
  return problems;
}
