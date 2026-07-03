import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../src/rust/bridge.dart' as rust;
import '../type/enum.dart';
import '../util/get_path.dart';

const _jmProviderId = 'bf99008d-010b-4f17-ac7c-61a9b57dc3d9';

class ProviderImageCache {
  const ProviderImageCache._();

  static Future<String> getCachePicture({
    required String providerId,
    required String comicId,
    required String chapterId,
    required String url,
    required String path,
    PictureType pictureType = PictureType.page,
    Map<String, dynamic> extern = const <String, dynamic>{},
    Future<void>? cancelSignal,
  }) async {
    final resolvedProviderId = providerId.trim();
    if (resolvedProviderId.isEmpty) {
      throw StateError('getCachePicture missing providerId');
    }

    final directPath = path.trim();
    if (directPath.isNotEmpty && p.isAbsolute(directPath)) {
      final directFile = File(directPath);
      if (await _isReadableFile(directFile)) {
        return directPath;
      }
    }

    final storedName = _storedFileName(path: path, url: url);
    if (storedName.isEmpty) {
      throw Exception('404');
    }

    final cachePath = await getCachePath();
    final downloadPath = await getDownloadPath();
    final cacheFilePath = _buildStoredFilePath(
      cachePath,
      resolvedProviderId,
      storedName,
      comicId,
      pictureType == PictureType.cover ? '' : chapterId,
    );
    final downloadFilePath = _buildStoredFilePath(
      downloadPath,
      resolvedProviderId,
      storedName,
      comicId,
      pictureType == PictureType.cover ? '' : chapterId,
      rootFolder: 'original',
    );

    final existingFilePath = await _checkFileExists(
      cacheFilePath,
      downloadFilePath,
    );
    if (existingFilePath.isNotEmpty) {
      return existingFilePath;
    }

    if (url.trim().isEmpty) {
      throw Exception('404');
    }

    final imageData = await _downloadImageWithRetry(
      url.trim(),
      headers: _headersFromExtern(extern),
      maxRetries: 3,
      cancelSignal: cancelSignal,
    );

    if (_needsJmDecode(
      providerId: resolvedProviderId,
      pictureType: pictureType,
      extern: extern,
    )) {
      final jmChapterId = _resolveJmChapterId(chapterId, extern);
      if (jmChapterId == null) {
        throw StateError('JM image decode requires numeric chapterId');
      }
      await rust.decodeJmImageToDisk(
        imageData: imageData,
        chapterId: jmChapterId,
        fileName: cacheFilePath,
        url: url,
      );
    } else {
      await _saveImage(imageData, cacheFilePath);
    }

    final cacheFile = File(cacheFilePath);
    if (await _isReadableFile(cacheFile)) {
      return cacheFilePath;
    }
    throw Exception('图片保存失败');
  }

  static Future<String> downloadPicture({
    required String providerId,
    required String comicId,
    required String chapterId,
    required String url,
    required String path,
    PictureType pictureType = PictureType.page,
    Map<String, dynamic> extern = const <String, dynamic>{},
    Future<void>? cancelSignal,
  }) async {
    final cachedPath = await getCachePicture(
      providerId: providerId,
      comicId: comicId,
      chapterId: chapterId,
      url: url,
      path: path,
      pictureType: pictureType,
      extern: extern,
      cancelSignal: cancelSignal,
    );

    final storedName = _storedFileName(path: path, url: url);
    if (storedName.isEmpty) {
      throw Exception('404');
    }

    final downloadPath = await getDownloadPath();
    final downloadFilePath = _buildStoredFilePath(
      downloadPath,
      providerId.trim(),
      storedName,
      comicId,
      pictureType == PictureType.cover ? '' : chapterId,
      rootFolder: 'original',
    );

    if (p.equals(cachedPath, downloadFilePath)) {
      return downloadFilePath;
    }

    final source = File(cachedPath);
    if (!await _isReadableFile(source)) {
      throw Exception('图片缓存不可读');
    }

    await Directory(p.dirname(downloadFilePath)).create(recursive: true);
    await source.copy(downloadFilePath);
    return downloadFilePath;
  }
}

String _buildStoredFilePath(
  String basePath,
  String providerId,
  String storedName,
  String comicId,
  String chapterId, {
  String? rootFolder,
}) {
  final segments = <String>[basePath, providerId];
  if (rootFolder != null && rootFolder.isNotEmpty) {
    segments.add(rootFolder);
  }
  if (comicId.trim().isNotEmpty) {
    segments.add(_sanitizeStoredPath(comicId));
  }
  if (chapterId.trim().isNotEmpty) {
    segments.add(_sanitizeStoredPath(chapterId));
  }
  segments.add(_sanitizeStoredPath(storedName));
  return p.joinAll(segments);
}

String _storedFileName({required String path, required String url}) {
  final rawPath = path.trim();
  if (rawPath.isNotEmpty) {
    return p.isAbsolute(rawPath) ? p.basename(rawPath) : rawPath;
  }

  final uri = Uri.tryParse(url.trim());
  final segments = uri?.pathSegments;
  if (segments != null && segments.isNotEmpty) {
    final name = segments.last.trim();
    if (name.isNotEmpty) return name;
  }

  return '';
}

String _sanitizeStoredPath(String rawPath) {
  final raw = rawPath.trim();
  if (raw.isEmpty) {
    throw StateError('normalizeStoredAssetPath requires non-empty path');
  }
  final candidate = p.isAbsolute(raw) ? p.basename(raw) : raw;
  final sanitized = candidate.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  if (sanitized.isEmpty) {
    throw StateError(
      'normalizeStoredAssetPath received invalid path: $rawPath',
    );
  }
  return sanitized;
}

Future<String> _checkFileExists(String cachePath, String downloadPath) async {
  if (await _isReadableFile(File(downloadPath))) {
    return downloadPath;
  }
  if (await _isReadableFile(File(cachePath))) {
    return cachePath;
  }
  return '';
}

Future<bool> _isReadableFile(File file) async {
  try {
    if (!await file.exists()) return false;
    return await file.length() > 0;
  } catch (_) {
    return false;
  }
}

Map<String, String> _headersFromExtern(Map<String, dynamic> extern) {
  final raw = extern['headers'];
  if (raw is! Map) return const <String, String>{};
  return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
}

bool _needsJmDecode({
  required String providerId,
  required PictureType pictureType,
  required Map<String, dynamic> extern,
}) {
  if (pictureType != PictureType.page) return false;
  final decode = extern['decode'] ?? extern['pictureDecode'];
  return providerId == _jmProviderId || decode == true || decode == 'jm';
}

int? _resolveJmChapterId(String chapterId, Map<String, dynamic> extern) {
  final raw = extern['chapterId'] ?? chapterId;
  if (raw is int) return raw;
  return int.tryParse(raw.toString());
}

Future<Uint8List> _downloadImageWithRetry(
  String url, {
  required Map<String, String> headers,
  required int maxRetries,
  Future<void>? cancelSignal,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= maxRetries; attempt += 1) {
    try {
      return await _downloadImage(
        url,
        headers: headers,
        cancelSignal: cancelSignal,
      );
    } catch (error) {
      if (error is _ImageDownloadCancelled) rethrow;
      lastError = error;
      logger.w(
        'download image failed attempt=$attempt/$maxRetries url=$url',
        error: error,
      );
      if (attempt < maxRetries) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
  }
  throw lastError ?? Exception('下载图片失败');
}

Future<Uint8List> _downloadImage(
  String url, {
  required Map<String, String> headers,
  Future<void>? cancelSignal,
}) async {
  final uri = Uri.parse(url);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final future = _downloadImageWithClient(client, uri: uri, headers: headers);
    if (cancelSignal == null) {
      return await future;
    }
    return await Future.any<Uint8List>([
      future,
      cancelSignal.then<Uint8List>((_) {
        client.close(force: true);
        throw const _ImageDownloadCancelled();
      }),
    ]);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _downloadImageWithClient(
  HttpClient client, {
  required Uri uri,
  required Map<String, String> headers,
}) async {
  final request = await client.getUrl(uri);
  request.followRedirects = true;
  request.headers.set(HttpHeaders.hostHeader, uri.host);
  for (final entry in headers.entries) {
    if (entry.key.trim().isEmpty) continue;
    request.headers.set(entry.key, entry.value);
  }

  final response = await request.close().timeout(const Duration(seconds: 30));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('status=${response.statusCode}', uri: uri);
  }
  return consolidateHttpClientResponseBytes(response);
}

class _ImageDownloadCancelled implements Exception {
  const _ImageDownloadCancelled();
}

Future<void> _saveImage(Uint8List imageData, String filePath) async {
  if (imageData.isEmpty) {
    throw Exception('图片数据为空');
  }

  final targetFile = File(filePath);
  try {
    await Directory(p.dirname(filePath)).create(recursive: true);
    await targetFile.writeAsBytes(imageData, flush: true);
  } catch (error) {
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    rethrow;
  }
}
