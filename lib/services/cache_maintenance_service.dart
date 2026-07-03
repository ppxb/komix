import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../util/get_path.dart';

class CacheStats {
  final String path;
  final int bytes;

  const CacheStats({required this.path, required this.bytes});

  String get displaySize => _formatBytes(bytes);
}

class CacheMaintenanceService {
  static final CacheMaintenanceService instance = CacheMaintenanceService._();

  CacheMaintenanceService._();

  Future<CacheStats> getStats() async {
    final path = await getCachePath();
    var bytes = await _directorySize(Directory(path));
    for (final directory in await _additionalCacheDirectories(path)) {
      bytes += await _directorySize(directory);
    }
    return CacheStats(path: path, bytes: bytes);
  }

  Future<void> clearCache() async {
    final path = await getCachePath();
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    } else {
      await for (final entity in directory.list(followLinks: false)) {
        await entity.delete(recursive: true);
      }
      await directory.create(recursive: true);
    }

    for (final extraDirectory in await _additionalCacheDirectories(path)) {
      if (!await extraDirectory.exists()) continue;
      await extraDirectory.delete(recursive: true);
    }
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {
        // Ignore files that disappear while stats are being calculated.
      }
    }
    return total;
  }

  Future<List<Directory>> _additionalCacheDirectories(String cachePath) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final imageSizeCacheDirectory = Directory(
      p.join(supportDirectory.path, 'readerImageSizeCache'),
    );
    if (_isSameOrInside(cachePath, imageSizeCacheDirectory.path)) {
      return const <Directory>[];
    }
    return <Directory>[imageSizeCacheDirectory];
  }
}

bool _isSameOrInside(String parent, String child) {
  final normalizedParent = p.normalize(parent);
  final normalizedChild = p.normalize(child);
  return p.equals(normalizedParent, normalizedChild) ||
      p.isWithin(normalizedParent, normalizedChild);
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final decimals = unitIndex == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}
