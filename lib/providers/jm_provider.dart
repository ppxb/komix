import 'dart:convert';

import '../models/comic.dart';
import '../src/rust/bridge.dart' as rust;
import 'base_provider.dart';

/// 禁漫天堂内置数据源。
class JmProvider extends BaseProvider {
  static const String _id = 'bf99008d-010b-4f17-ac7c-61a9b57dc3d9';
  static const String _name = '禁漫天堂';
  static const String _iconUrl = 'https://example.com/jm_icon.png';

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  String get iconUrl => _iconUrl;

  @override
  Future<SearchResult> search(String keyword, int page) async {
    final raw = await rust.jmSearch(keyword: keyword, page: page);
    return SearchResult.fromJson(_decodeMap(raw));
  }

  @override
  Future<Comic> getComicDetail(String comicId) async {
    final raw = await rust.jmGetComicDetail(comicId: comicId);
    return Comic.fromJson(_decodeMap(raw));
  }

  @override
  Future<List<Chapter>> getChapters(String comicId) async {
    final raw = await rust.jmGetChapters(comicId: comicId);
    return _decodeList(raw).map((item) => Chapter.fromJson(item)).toList();
  }

  @override
  Future<List<String>> getChapterImages(String chapterId) async {
    final raw = await rust.jmGetChapterImages(chapterId: chapterId);
    return _decodeRawList(raw).map((item) => item.toString()).toList();
  }

  @override
  Future<SearchResult> getLatest(int page) async {
    final raw = await rust.jmGetLatest(page: page);
    return SearchResult.fromJson(_decodeMap(raw));
  }

  @override
  Future<SearchResult> getRanking({
    required String category,
    required String order,
    required int page,
  }) async {
    final raw = await rust.jmGetRanking(
      category: category,
      order: order,
      page: page,
    );
    return SearchResult.fromJson(_decodeMap(raw));
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected JSON object from Rust JM provider', raw);
  }

  List<Map<String, dynamic>> _decodeList(String raw) {
    return _decodeRawList(raw).map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }
      throw FormatException('Expected JSON object item from Rust JM provider');
    }).toList();
  }

  List<dynamic> _decodeRawList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
    throw FormatException('Expected JSON list from Rust JM provider', raw);
  }
}
