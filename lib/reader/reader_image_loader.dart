import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

class ReaderImageRequest {
  final String providerId;
  final String comicId;
  final String chapterId;
  final String pageId;
  final String url;
  final String path;
  final Map<String, dynamic> extern;

  const ReaderImageRequest({
    required this.providerId,
    required this.comicId,
    required this.chapterId,
    required this.pageId,
    required this.url,
    this.path = '',
    this.extern = const <String, dynamic>{},
  });

  String get cacheKey {
    if (pageId.trim().isNotEmpty) return pageId;
    if (path.trim().isNotEmpty) return path;
    return url;
  }

  Map<String, String> get headers {
    final raw = extern['headers'];
    if (raw is! Map) return const <String, String>{};
    return raw.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }
}

class ReaderImageLoader {
  const ReaderImageLoader._();

  static ImageProvider providerFor(ReaderImageRequest request) {
    return CachedNetworkImageProvider(
      request.url,
      cacheKey: request.cacheKey,
      headers: request.headers,
    );
  }
}
