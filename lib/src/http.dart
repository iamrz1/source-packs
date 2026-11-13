import 'package:http/http.dart' as http;

class RecipeResponse {
  final int status;
  final String body;

  /// The raw reply, for steps that read a binary body. When null, the UTF-8
  /// bytes of [body] stand in for it.
  final List<int>? bytes;

  /// The reply headers, with lower-case names.
  final Map<String, String> headers;
  const RecipeResponse(
    this.status,
    this.body, {
    this.bytes,
    this.headers = const {},
  });

  bool get ok => status >= 200 && status < 300;
}

/// The one thing a recipe needs from the network. An app passes an adapter
/// over its own HTTP client; [PackageHttp] is the default.
abstract class RecipeHttp {
  ///
  /// [bodyBytes], when given, is sent as the raw body instead of [body].
  Future<RecipeResponse> send(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
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
    List<int>? bodyBytes,
  }) async {
    final request = http.Request(method, Uri.parse(url))
      ..headers.addAll(headers);
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    } else if (body != null) {
      request.body = body;
    }
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return RecipeResponse(
      response.statusCode,
      response.body,
      bytes: response.bodyBytes,
      headers: response.headers,
    );
  }
}
