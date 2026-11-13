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

  const RecipeStream({
    required this.title,
    required this.url,
    this.height,
    this.format,
    this.headers = const {},
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
