import 'dart:io';

import '../services/provider_image_cache.dart';
import '../type/enum.dart';

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

  PictureType get pictureType {
    final raw = extern['pictureType'];
    if (raw is PictureType) return raw;
    if (raw is String) {
      return PictureType.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => PictureType.page,
      );
    }
    return PictureType.page;
  }
}

class ReaderImageLoader {
  const ReaderImageLoader._();

  static Future<File> cacheFileFor(ReaderImageRequest request) async {
    final filePath = await ProviderImageCache.getCachePicture(
      providerId: request.providerId,
      comicId: request.comicId,
      chapterId: request.chapterId,
      url: request.url,
      path: request.path,
      pictureType: request.pictureType,
      extern: request.extern,
    );
    return File(filePath);
  }
}
