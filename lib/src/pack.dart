import 'dart:convert';

import 'interpreter.dart' show recipeRuntimeLevel;
import 'template.dart';

/// Version of the pack layout. An app that reads a higher `schema` than it
/// knows must ignore the pack.
const packSchema = 1;

const _stepOps = {
  'set',
  'require',
  'extract',
  'get',
  'post',
  'foreach',
  'tryEach',
  'emit',
  'log',
};

/// What is wrong with [recipe], or an empty list when it is fine.
List<String> validateRecipe(Map<String, dynamic> recipe) {
  final problems = <String>[];
  final id = recipe['id'];
  if (id is! String || !RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(id)) {
    problems.add('id must be lower-case letters, digits, "-" or "_"');
  }
  if ((recipe['name'] as String?)?.trim().isEmpty ?? true) {
    problems.add('name is missing');
  }
  final credits = recipe['credits'];
  if (credits is! List || credits.isEmpty) {
    problems.add('credits is missing: name where the steps come from');
  } else {
    for (final c in credits) {
      if (c is! Map || c['author'] == null || c['url'] == null) {
        problems.add('each credit needs an author and a url');
      }
    }
  }
  final steps = recipe['steps'];
  if (steps is! List || steps.isEmpty) {
    problems.add('steps is missing');
  } else {
    _validateSteps(steps, 'steps', problems);
  }
  final rank = recipe['rank'];
  if (rank != null && rank is! int) {
    problems.add('rank must be a whole number');
  }
  final enabled = recipe['defaultEnabled'];
  if (enabled != null && enabled is! bool) {
    problems.add('defaultEnabled must be true or false');
  }
  final description = recipe['description'];
  if (description != null && description is! String) {
    problems.add('description must be text');
  }
  final needs = recipe['requires'];
  if (needs != null && (needs is! int || needs < 1)) {
    problems.add('requires must be a whole number from 1');
  } else if (needs is int && needs > recipeRuntimeLevel) {
    problems.add(
      'needs runtime level $needs, this one is $recipeRuntimeLevel',
    );
  }
  problems.addAll(checkTemplates(recipe['vars']));
  return problems;
}

void _validateSteps(List steps, String where, List<String> problems) {
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final at = '$where[$i]';
    if (step is! Map) {
      problems.add('$at is not an object');
      continue;
    }
    final op = step['op'];
    if (!_stepOps.contains(op)) {
      problems.add('$at: unknown op "$op"');
      continue;
    }
    void need(String key) {
      if (!step.containsKey(key)) problems.add('$at ($op): "$key" is missing');
    }

    switch (op) {
      case 'set':
        need('as');
        need('value');
      case 'require':
        need('value');
      case 'extract':
        need('from');
        need('regex');
        need('as');
        final regex = step['regex'];
        for (final r in regex is List ? regex : [regex]) {
          try {
            RegExp(r as String);
          } catch (_) {
            problems.add('$at (extract): bad regex "$r"');
          }
        }
      case 'get':
      case 'post':
        need('url');
        final response = step['response'];
        if (response != null &&
            !const {'text', 'json', 'base64url'}.contains(response)) {
          problems.add('$at ($op): unknown response "$response"');
        }
        final encoding = step['bodyEncoding'];
        if (encoding != null && encoding != 'base64url') {
          problems.add('$at ($op): unknown bodyEncoding "$encoding"');
        }
      case 'foreach':
      case 'tryEach':
        need('in');
        need('as');
        final inner = step['steps'];
        if (inner is! List || inner.isEmpty) {
          problems.add('$at ($op): "steps" is missing');
        } else {
          _validateSteps(inner, '$at.steps', problems);
        }
      case 'emit':
        if (step['stream'] is! Map && step['subtitle'] is! Map) {
          problems.add('$at (emit): needs "stream" or "subtitle"');
        }
      case 'log':
        need('message');
    }
    problems.addAll(
      checkTemplates(
        {...step}..remove('steps'),
      ).map((p) => '$at: $p'),
    );
  }
}

/// Builds the pack for a release: every recipe by id, plus the credits.
Map<String, dynamic> buildPack(
  List<Map<String, dynamic>> recipes, {
  required String version,
  required DateTime published,
}) {
  final byId = {for (final r in recipes) r['id'] as String: r};
  final ids = byId.keys.toList()..sort();
  final credits = <String, Map<String, dynamic>>{};
  for (final id in ids) {
    for (final c in (byId[id]!['credits'] as List).cast<Map>()) {
      credits['${c['author']}/${c['project'] ?? ''}'] = {
        'author': c['author'],
        if (c['project'] != null) 'project': c['project'],
        'url': c['url'],
        if (c['license'] != null) 'license': c['license'],
      };
    }
  }
  return {
    'schema': packSchema,
    'version': version,
    'published': published.toUtc().toIso8601String(),
    'credits': credits.values.toList(),
    'providers': {for (final id in ids) id: byId[id]},
  };
}

/// The bytes written to `pack.json`. Two spaces, a trailing
/// newline, keys in the order [buildPack] made them.
List<int> encodePack(Map<String, dynamic> pack) =>
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(pack)}\n');

/// What a list of sources shows about one recipe, without running it.
class RecipeInfo {
  /// [rank] of a recipe that sets none: it sorts after every ranked one.
  static const unranked = 1000000;

  final String id;
  final String name;
  final String description;

  /// Lower sorts first. The default order of the sources.
  final int rank;

  /// Whether the source starts on, before the user changes it.
  final bool defaultEnabled;

  const RecipeInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.rank = unranked,
    this.defaultEnabled = true,
  });

  /// Reads the metadata of [recipe]. A field of the wrong type counts as
  /// absent, so a bad recipe still lists.
  factory RecipeInfo.fromRecipe(String id, Map<String, dynamic> recipe) {
    final name = recipe['name'];
    final description = recipe['description'];
    final rank = recipe['rank'];
    final enabled = recipe['defaultEnabled'];
    return RecipeInfo(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name : id,
      description: description is String ? description : '',
      rank: rank is int ? rank : unranked,
      defaultEnabled: enabled is bool ? enabled : true,
    );
  }
}

/// A pack that has been read.
class Pack {
  final int schema;
  final String version;
  final DateTime published;
  final Map<String, Map<String, dynamic>> providers;

  const Pack({
    required this.schema,
    required this.version,
    required this.published,
    required this.providers,
  });

  /// The metadata of every recipe, in the default order: by `rank`, then id.
  List<RecipeInfo> get infos {
    final all = [
      for (final e in providers.entries) RecipeInfo.fromRecipe(e.key, e.value),
    ];
    all.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.id.compareTo(b.id);
    });
    return all;
  }

  /// Throws [FormatException] when the bytes are not a pack this version of
  /// the library can read.
  factory Pack.parse(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('pack is not JSON');
    }
    if (json is! Map) throw const FormatException('pack is not an object');
    final schema = json['schema'];
    if (schema is! int || schema > packSchema) {
      throw FormatException('unsupported pack schema $schema');
    }
    final version = json['version'];
    if (version is! String || parseVersion(version) == null) {
      throw FormatException('bad pack version $version');
    }
    final providers = json['providers'];
    if (providers is! Map) throw const FormatException('no providers');
    return Pack(
      schema: schema,
      version: version,
      published: DateTime.tryParse('${json['published']}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      providers: {
        for (final e in providers.entries)
          e.key as String: (e.value as Map).cast<String, dynamic>(),
      },
    );
  }
}

/// `1.2.3` (an optional leading `v`) as [major, minor, patch], or null.
List<int>? parseVersion(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Negative when [a] is older than [b], zero when equal, positive when newer.
/// A version that does not parse counts as older than any that does.
int compareVersions(String a, String b) {
  final pa = parseVersion(a);
  final pb = parseVersion(b);
  if (pa == null || pb == null) {
    return pa == null ? (pb == null ? 0 : -1) : 1;
  }
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}
