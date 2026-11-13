import 'dart:async';
import 'dart:convert';

import 'http.dart';
import 'result.dart';
import 'template.dart';

/// Stops the current scope (the recipe, or one loop iteration) with a reason.
class StepFailure implements Exception {
  final String message;
  const StepFailure(this.message);

  @override
  String toString() => message;
}

/// What one scope emitted. A failed iteration's buffer is thrown away.
class _Out {
  final List<RecipeStream> streams = [];
  final List<RecipeSubtitle> subtitles = [];
  final Set<String> _subtitleUrls = {};

  void addSubtitle(RecipeSubtitle s) {
    if (_subtitleUrls.add(s.url)) subtitles.add(s);
  }

  void commit(_Out into) {
    into.streams.addAll(streams);
    for (final s in subtitles) {
      into.addSubtitle(s);
    }
  }
}

typedef RecipeLog = void Function(String message);

/// What this interpreter can run. A recipe that sets `requires` higher than
/// this is refused cleanly instead of running wrongly. Level 2 added the
/// `entries` filter, `bodyEncoding` and the `base64url` response. Level 3 added
/// `headersAs`.
const recipeRuntimeLevel = 3;

/// Runs a recipe: a list of steps over a set of variables. See
/// docs/RECIPE_SPEC.md for the steps.
class RecipeInterpreter {
  final RecipeHttp http;

  /// Longest a single request may take.
  final Duration hopTimeout;
  final RecipeLog log;

  RecipeInterpreter(
    this.http, {
    this.hopTimeout = const Duration(seconds: 8),
    RecipeLog? log,
  }) : log = log ?? ((_) {});

  /// Runs [recipe] with [inputs] (strings such as `type`, `id`, `tmdb`,
  /// `title`). Never throws.
  Future<RecipeResult> run(
    Map<String, dynamic> recipe,
    Map<String, dynamic> inputs,
  ) async {
    final id = recipe['id']?.toString() ?? '?';
    final needs = recipe['requires'];
    if (needs is int && needs > recipeRuntimeLevel) {
      final message =
          'needs runtime level $needs (this one is $recipeRuntimeLevel)';
      log('$id: $message');
      return RecipeResult(error: message);
    }
    final scope = Scope({
      ...((recipe['vars'] as Map?)?.cast<String, dynamic>() ?? const {}),
      ...inputs,
    });
    final out = _Out();
    try {
      await _steps((recipe['steps'] as List).cast<Map>(), scope, out, id);
      log('$id: ${out.streams.length} streams, ${out.subtitles.length} subtitles');
      return RecipeResult(streams: out.streams, subtitles: out.subtitles);
    } on StepFailure catch (e) {
      log('$id: ${e.message}');
      return RecipeResult(error: e.message);
    } on TimeoutException {
      log('$id: timed out');
      return const RecipeResult(error: 'timed out');
    } catch (e) {
      log('$id: ${e.runtimeType}: $e');
      return RecipeResult(error: '$e');
    }
  }

  Future<void> _steps(List<Map> steps, Scope scope, _Out out, String id) async {
    for (final step in steps) {
      final when = step['when'];
      if (when != null && !_holds(when as Map, scope)) continue;
      await _step(step, scope, out, id);
    }
  }

  /// `{"value": "{{x}}"}` is true when non-empty; `equals` compares as text;
  /// `not` flips the answer.
  bool _holds(Map predicate, Scope scope) {
    final value = evalValue(predicate['value'], scope);
    var result = predicate.containsKey('equals')
        ? '${value ?? ''}' == '${evalValue(predicate['equals'], scope) ?? ''}'
        : !isEmptyValue(value) && value != false;
    if (predicate['not'] == true) result = !result;
    return result;
  }

  Future<void> _step(Map step, Scope scope, _Out out, String id) async {
    switch (step['op']) {
      case 'set':
        scope.set(step['as'] as String, evalValue(step['value'], scope));
      case 'require':
        if (!_holds(step, scope)) {
          throw StepFailure(step['msg']?.toString() ?? 'require failed');
        }
      case 'extract':
        scope.set(step['as'] as String, _extract(step, scope));
      case 'get':
      case 'post':
        await _request(step, scope);
      case 'foreach':
        await _foreach(step, scope, out, id);
      case 'tryEach':
        await _tryEach(step, scope, out, id);
      case 'emit':
        _emit(step, scope, out);
      case 'log':
        log('$id: ${evalValue(step['message'], scope)}');
      default:
        throw StepFailure('unknown step "${step['op']}"');
    }
  }

  String _extract(Map step, Scope scope) {
    final text = '${evalValue(step['from'], scope) ?? ''}';
    final patterns = step['regex'] is List
        ? (step['regex'] as List).cast<String>()
        : [step['regex'] as String];
    final group = (step['group'] as int?) ?? 1;
    for (final pattern in patterns) {
      final m = RegExp(pattern).firstMatch(text);
      if (m != null && group <= m.groupCount) return m.group(group) ?? '';
    }
    return '';
  }

  Future<void> _request(Map step, Scope scope) async {
    final method = (step['op'] as String).toUpperCase();
    var url = '${evalValue(step['url'], scope)}';
    final query = step['query'];
    if (query is Map) {
      final params = <String>[];
      for (final e in query.entries) {
        final v = evalValue(e.value, scope);
        if (isEmptyValue(v)) continue;
        params.add('${e.key}=${Uri.encodeComponent('$v')}');
      }
      if (params.isNotEmpty) {
        url += '${url.contains('?') ? '&' : '?'}${params.join('&')}';
      }
    }
    final headers = <String, String>{};
    final rawHeaders = step['headers'];
    if (rawHeaders is Map) {
      for (final e in rawHeaders.entries) {
        final v = evalValue(e.value, scope);
        if (!isEmptyValue(v)) headers['${e.key}'] = '$v';
      }
    }
    String? body;
    List<int>? bodyBytes;
    if (step.containsKey('body')) {
      final value = evalValue(step['body'], scope);
      if (step['bodyEncoding'] == 'base64url' && value != null) {
        bodyBytes = _base64UrlDecode('$value');
      } else if (value is Map || value is List) {
        body = jsonEncode(value);
        headers.putIfAbsent('Content-Type', () => 'application/json');
      } else if (value != null) {
        body = '$value';
      }
    }
    final response = await http
        .send(method, url, headers: headers, body: body, bodyBytes: bodyBytes)
        .timeout(hopTimeout);
    if (!response.ok) {
      throw StepFailure('$method ${_shorten(url)} -> HTTP ${response.status}');
    }
    dynamic result = response.body;
    if (step['response'] == 'base64url') {
      result = base64Url
          .encode(response.bytes ?? utf8.encode(response.body))
          .replaceAll('=', '');
    } else if (step['response'] == 'json') {
      try {
        result = jsonDecode(response.body);
      } catch (_) {
        throw StepFailure('$method ${_shorten(url)} -> reply is not JSON');
      }
    }
    final name = step['as'];
    if (name is String) scope.set(name, result);
    final headersName = step['headersAs'];
    if (headersName is String) {
      scope.set(headersName, {
        for (final e in response.headers.entries) e.key.toLowerCase(): e.value,
      });
    }
  }

  static List<int> _base64UrlDecode(String text) {
    try {
      return base64Url.decode(base64Url.normalize(text));
    } on FormatException {
      throw const StepFailure('body is not base64url');
    }
  }

  String _shorten(String url) {
    final i = url.indexOf('?');
    final s = i < 0 ? url : url.substring(0, i);
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }

  List _items(Map step, Scope scope) {
    final items = evalValue(step['in'], scope);
    return items is List ? items : const [];
  }

  /// One pass of a loop body in its own scope and buffer.
  Future<_Out?> _iteration(
    Map step,
    Scope scope,
    dynamic item,
    String id,
  ) async {
    final retries = (step['retryOnTimeout'] as int?) ?? 0;
    for (var attempt = 0;; attempt++) {
      final child = scope.child({step['as'] as String: item});
      final buffer = _Out();
      try {
        await _steps((step['steps'] as List).cast<Map>(), child, buffer, id);
        return buffer;
      } on TimeoutException {
        if (attempt < retries) continue;
        log('$id: iteration timed out');
        return null;
      } on StepFailure catch (e) {
        log('$id: iteration skipped: ${e.message}');
        return null;
      } catch (e) {
        log('$id: iteration failed: ${e.runtimeType}: $e');
        return null;
      }
    }
  }

  /// Runs the body for every item and keeps what the successful ones emitted.
  /// A failed iteration is skipped, not fatal.
  Future<void> _foreach(Map step, Scope scope, _Out out, String id) async {
    final items = _items(step, scope);
    final buffers = step['parallel'] == true
        ? await Future.wait([
            for (final item in items) _iteration(step, scope, item, id),
          ])
        : [
            for (final item in items) await _iteration(step, scope, item, id),
          ];
    for (final buffer in buffers) {
      buffer?.commit(out);
    }
  }

  /// Tries the items in order and stops at the first iteration that succeeds
  /// and emits at least one stream.
  Future<void> _tryEach(Map step, Scope scope, _Out out, String id) async {
    for (final item in _items(step, scope)) {
      final buffer = await _iteration(step, scope, item, id);
      if (buffer != null && buffer.streams.isNotEmpty) {
        buffer.commit(out);
        return;
      }
    }
  }

  void _emit(Map step, Scope scope, _Out out) {
    final stream = step['stream'];
    if (stream is Map) {
      final v = evalValue(stream, scope) as Map;
      final url = '${v['url'] ?? ''}';
      if (url.isEmpty) return;
      out.streams.add(
        RecipeStream(
          title: '${v['title'] ?? ''}',
          url: url,
          height: v['height'] is int ? v['height'] as int : null,
          format: const {'hls', 'mp4', 'dash'}.contains(v['format'])
              ? v['format'] as String
              : null,
          headers: _headers(v['headers']),
        ),
      );
    }
    final subtitle = step['subtitle'];
    if (subtitle is Map) {
      final v = evalValue(subtitle, scope) as Map;
      final url = '${v['url'] ?? ''}';
      if (url.isEmpty) return;
      out.addSubtitle(
        RecipeSubtitle(
          url: url,
          lang: '${v['lang'] ?? ''}',
          headers: _headers(v['headers']),
        ),
      );
    }
  }

  Map<String, String> _headers(dynamic raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (!isEmptyValue(e.value)) '${e.key}': '${e.value}',
        }
      : const {};
}
