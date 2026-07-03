import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageSizeCacheStore {
  final String sourceTag;
  final List<String> pageKeys;

  const ImageSizeCacheStore({required this.sourceTag, required this.pageKeys});

  Future<Map<int, Size>> readIndexedSizes({
    required List<String> pageKeys,
    required int count,
  }) async {
    final persisted = await _readFromDisk();
    if (persisted.isEmpty) return const <int, Size>{};

    final out = <int, Size>{};
    final max = count < pageKeys.length ? count : pageKeys.length;
    for (var i = 0; i < max; i++) {
      final size = persisted[_hashKey64(pageKeys[i])];
      if (size != null) {
        out[i] = size;
      }
    }
    return out;
  }

  Future<void> write({
    required List<String> pageKeys,
    required Map<int, Size> sizeCache,
    required Set<int> resolvedIndices,
    required int count,
  }) async {
    if (resolvedIndices.isEmpty) return;

    final records = <Map<String, Object>>[];
    final max = count < pageKeys.length ? count : pageKeys.length;
    for (var i = 0; i < max; i++) {
      if (!resolvedIndices.contains(i)) continue;
      final size = sizeCache[i];
      if (size == null || size.width <= 0 || size.height <= 0) continue;
      records.add({
        'key': _hashKey64(pageKeys[i]).toString(),
        'width': size.width.round().clamp(1, 65535),
        'height': size.height.round().clamp(1, 65535),
      });
    }
    if (records.isEmpty) return;

    final filePath = await cacheFilePath();
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final payload = jsonEncode({'version': 1, 'records': records});
    final tmpFile = File('$filePath.tmp');
    await tmpFile.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(filePath);
  }

  Future<({int recordCount, int fileBytes, String filePath})> getStats() async {
    final filePath = await cacheFilePath();
    final file = File(filePath);
    if (!await file.exists()) {
      return (recordCount: 0, fileBytes: 0, filePath: filePath);
    }

    final persisted = await _readFromDisk();
    return (
      recordCount: persisted.length,
      fileBytes: await file.length(),
      filePath: filePath,
    );
  }

  Future<String> cacheFilePath() async {
    final root = await getApplicationSupportDirectory();
    final dir = p.join(root.path, 'readerImageSizeCache');
    final fileName = '${_hashIdentityHex(sourceTag, pageKeys)}.json';
    return p.join(dir, fileName);
  }

  Future<Map<int, Size>> _readFromDisk() async {
    final file = File(await cacheFilePath());
    if (!await file.exists()) return const <int, Size>{};

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const <int, Size>{};
      final records = decoded['records'];
      if (records is! List) return const <int, Size>{};

      final out = <int, Size>{};
      for (final record in records) {
        if (record is! Map) continue;
        final key = int.tryParse(record['key']?.toString() ?? '');
        final width = (record['width'] as num?)?.toDouble();
        final height = (record['height'] as num?)?.toDouble();
        if (key == null || width == null || height == null) continue;
        if (width <= 0 || height <= 0) continue;
        out[key] = Size(width, height);
      }
      return out;
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return const <int, Size>{};
    }
  }

  String _hashIdentityHex(String source, List<String> keys) {
    var hash = _hashKey64(source);
    for (final key in keys) {
      hash = _combineHash(hash, _hashKey64(key));
    }
    return hash.toRadixString(16);
  }

  int _combineHash(int left, int right) {
    const mask = 0xFFFFFFFFFFFFFFFF;
    return ((left ^ right) * 0x100000001b3) & mask;
  }

  int _hashKey64(String value) {
    const offsetBasis = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;

    var hash = offsetBasis;
    final bytes = utf8.encode(value);
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * prime) & mask;
    }
    return hash;
  }
}
