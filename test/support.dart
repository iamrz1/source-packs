import 'dart:convert';
import 'dart:io';

import 'package:source_packs/source_packs.dart';

/// A request a recipe made, as the fake network saw it.
class Seen {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  Seen(this.method, this.url, this.headers, this.body);

  Map<String, dynamic> get json => jsonDecode(body ?? '{}');
}

typedef Handler = RecipeResponse Function(Seen request);

class FakeHttp implements RecipeHttp {
  final Handler handler;
  final List<Seen> seen = [];
  FakeHttp(this.handler);

  @override
  Future<RecipeResponse> send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = Seen(method, Uri.parse(url), headers, body);
    seen.add(request);
    return handler(request);
  }
}

RecipeResponse ok(String body) => RecipeResponse(200, body);
RecipeResponse okJson(Object body) => RecipeResponse(200, jsonEncode(body));
RecipeResponse status(int code) => RecipeResponse(code, '');

Map<String, dynamic> loadRecipe(String id) =>
    jsonDecode(File('recipes/$id.json').readAsStringSync())
        as Map<String, dynamic>;

Future<RecipeResult> run(
  String recipe,
  Handler handler,
  Map<String, dynamic> inputs, {
  List<String>? log,
}) =>
    RecipeInterpreter(
      FakeHttp(handler),
      log: log?.add,
    ).run(loadRecipe(recipe), inputs);
