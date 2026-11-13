import 'dart:convert';
import 'dart:io';

import 'package:source_packs/source_packs.dart';

const _usage = '''
Usage: dart run bin/pack.dart <command>

  check                        Validate every recipe in recipes/.
  build --version X.Y.Z [--out dist]
                               Write pack.json.
  live                         Run every recipe against the real sites with a
                               sample movie and episode. Exits 1 when one gives
                               no streams.
''';

List<Map<String, dynamic>> _recipes() {
  final files = Directory('recipes')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  ];
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// The return value of `main` is ignored by the Dart VM, so the exit code is
/// set explicitly. Without it every failure, including a provider that stopped
/// working, exited 0 and the live check never opened its issue.
Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  if (args.isEmpty) {
    stderr.write(_usage);
    return 64;
  }
  switch (args.first) {
    case 'check':
      return _check();
    case 'build':
      return _build(args.skip(1).toList());
    case 'live':
      return _live();
    default:
      stderr.write(_usage);
      return 64;
  }
}

int _check() {
  var bad = 0;
  for (final r in _recipes()) {
    final problems = validateRecipe(r);
    if (problems.isEmpty) {
      stdout.writeln('ok    ${r['id']}');
    } else {
      bad++;
      stdout.writeln('FAIL  ${r['id']}');
      for (final p in problems) {
        stdout.writeln('        $p');
      }
    }
  }
  return bad == 0 ? 0 : 1;
}

int _build(List<String> args) {
  final version = _option(args, '--version');
  if (version == null || parseVersion(version) == null) {
    stderr.writeln('--version X.Y.Z is required');
    return 64;
  }
  final recipes = _recipes();
  for (final r in recipes) {
    final problems = validateRecipe(r);
    if (problems.isNotEmpty) {
      stderr.writeln('${r['id']} is not valid:\n  ${problems.join('\n  ')}');
      return 1;
    }
  }
  final out = Directory(_option(args, '--out') ?? 'dist')
    ..createSync(recursive: true);
  final bytes = encodePack(
    buildPack(recipes,
        version: version.replaceFirst('v', ''), published: DateTime.now()),
  );
  File('${out.path}/pack.json').writeAsBytesSync(bytes);
  stdout.writeln('wrote ${out.path}/pack.json (${bytes.length} bytes)');
  return 0;
}

Future<int> _live() async {
  const samples = {
    'movie': {
      'type': 'movie',
      'id': 'tt0133093',
      'tmdb': '603',
      'title': 'The Matrix',
      'year': '1999',
    },
    'episode': {
      'type': 'series',
      'id': 'tt0944947:1:1',
      'tmdb': '1399',
      'title': 'Game of Thrones',
      'year': '2011',
    },
  };
  var failed = 0;
  for (final recipe in _recipes()) {
    // A recipe for a site with its own catalog may name titles that exist there.
    final own = (recipe['liveSamples'] as Map?)?.cast<String, dynamic>();
    for (final sample in (own ?? samples).entries) {
      final lines = <String>[];
      final result = await RecipeInterpreter(
        PackageHttp(),
        log: lines.add,
        hopTimeout: const Duration(seconds: 15),
      ).run(recipe, sample.value);
      final ok = result.streams.isNotEmpty;
      if (!ok) failed++;
      stdout.writeln(
        '${ok ? 'ok  ' : 'FAIL'}  ${recipe['id']} ${sample.key}: '
        '${result.streams.length} streams, ${result.subtitles.length} subtitles'
        '${result.error == null ? '' : '  (${result.error})'}',
      );
    }
  }
  return failed == 0 ? 0 : 1;
}
