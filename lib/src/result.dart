/// A playable stream a recipe produced.
class RecipeStream {
  final String title;
  final String url;

  /// Vertical resolution, or null when the recipe doesn't know it.
  final int? height;

  /// What [url] is: `hls`, `mp4` or `dash`, or null when the recipe does not
  /// say (the player then goes by the URL).
  final String? format;

  /// Headers the player must send to fetch [url].
  final Map<String, String> headers;

  /// When the link stops working, in unix seconds, or null when it does not
  /// say. An app may run the recipe again before this time.
  final int? expiresAt;

  /// ISO 639-1 audio language such as `en`, `original` when the recipe says
  /// the audio is the original one, or empty when unknown.
  final String lang;

  /// File size in bytes, or null when unknown.
  final int? size;

  const RecipeStream({
    required this.title,
    required this.url,
    this.height,
    this.format,
    this.headers = const {},
    this.expiresAt,
    this.lang = '',
    this.size,
  });

  @override
  String toString() => 'RecipeStream($title, $url, $height)';
}

class RecipeSubtitle {
  final String url;
  final String lang;
  final Map<String, String> headers;

  const RecipeSubtitle({
    required this.url,
    this.lang = '',
    this.headers = const {},
  });

  @override
  String toString() => 'RecipeSubtitle($lang, $url)';
}

/// What a recipe run produced. A run never throws: a failure gives empty lists
/// and the reason in [error].
class RecipeResult {
  final List<RecipeStream> streams;
  final List<RecipeSubtitle> subtitles;
  final String? error;

  const RecipeResult({
    this.streams = const [],
    this.subtitles = const [],
    this.error,
  });

  static const empty = RecipeResult();
}
