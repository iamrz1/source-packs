import 'package:http/http.dart' as http;

class RecipeResponse {
  final int status;
  final String body;
  const RecipeResponse(this.status, this.body);

  bool get ok => status >= 200 && status < 300;
}

/// The one thing a recipe needs from the network. An app passes an adapter
/// over its own HTTP client; [PackageHttp] is the default.
abstract class RecipeHttp {
  Future<RecipeResponse> send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });
}

class PackageHttp implements RecipeHttp {
  final http.Client _client;
  PackageHttp([http.Client? client]) : _client = client ?? http.Client();

  @override
  Future<RecipeResponse> send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = http.Request(method, Uri.parse(url))
      ..headers.addAll(headers);
    if (body != null) request.body = body;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return RecipeResponse(response.statusCode, response.body);
  }
}
