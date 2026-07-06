import 'dart:convert';

import '../config/bika/bika_setting.dart';
import '../main.dart';
import '../models/comic.dart';
import '../models/reader_snapshot.dart';
import '../object_box/model.dart';
import '../src/rust/bridge.dart' as rust;
import 'base_provider.dart';

class BikaProvider extends BaseProvider {
  static const String _id = '0a0e5858-a467-4702-994a-79e608a4589d';
  static const String _name = '哔咔漫画';
  static const String _iconUrl = 'https://img.picacomic.com/static/favicon.ico';

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  String get iconUrl => _iconUrl;

  BikaSettingState get setting {
    return _userSetting().bikaSetting;
  }

  bool get hasAuthorization => setting.authorization.trim().isNotEmpty;

  Future<void> loginWithPassword({
    required String account,
    required String password,
  }) async {
    final email = account.trim();
    if (email.isEmpty || password.isEmpty) {
      throw StateError('账号或密码不能为空');
    }

    final token = await rust.bikaLogin(email: email, password: password);
    final current = setting;
    _saveSetting(
      BikaSettingState(
        account: email,
        password: password,
        authorization: token.trim(),
        level: current.level,
        proxy: current.proxy,
        imageQuality: current.imageQuality,
        shieldCategoryMap: current.shieldCategoryMap,
        shieldHomePageCategoriesMap: current.shieldHomePageCategoriesMap,
        signIn: current.signIn,
        brevity: current.brevity,
        slowDownload: current.slowDownload,
      ),
    );
  }

  Future<void> clearSession() async {
    final current = setting;
    _saveSetting(
      BikaSettingState(
        account: current.account,
        password: current.password,
        authorization: '',
        level: current.level,
        proxy: current.proxy,
        imageQuality: current.imageQuality,
        shieldCategoryMap: current.shieldCategoryMap,
        shieldHomePageCategoriesMap: current.shieldHomePageCategoriesMap,
        signIn: current.signIn,
        brevity: current.brevity,
        slowDownload: current.slowDownload,
      ),
    );
  }

  @override
  Future<SearchResult> search(String keyword, int page) async {
    final raw = await rust.bikaSearch(
      keyword: keyword,
      page: page,
      authorization: await _authorization(),
    );
    return SearchResult.fromJson(_decodeMap(raw));
  }

  @override
  Future<Comic> getComicDetail(String comicId) async {
    final raw = await rust.bikaGetComicDetail(
      comicId: comicId,
      authorization: await _authorization(),
    );
    return Comic.fromJson(_decodeMap(raw));
  }

  @override
  Future<List<Chapter>> getChapters(String comicId) async {
    final raw = await rust.bikaGetChapters(
      comicId: comicId,
      authorization: await _authorization(),
    );
    return _decodeList(raw).map((item) => Chapter.fromJson(item)).toList();
  }

  @override
  Future<List<String>> getChapterImages(String chapterId) async {
    final ref = _parseChapterId(chapterId);
    final raw = await rust.bikaGetChapterImages(
      comicId: ref.comicId,
      chapterOrder: ref.order,
      authorization: await _authorization(),
    );
    return _decodeList(raw)
        .map((item) => item['url']?.toString() ?? '')
        .where((url) => url.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<ReaderChapterSnapshot> getReaderChapterSnapshot({
    required Comic comic,
    required Chapter chapter,
    required List<Chapter> chapters,
  }) async {
    final raw = await rust.bikaGetChapterImages(
      comicId: comic.id,
      chapterOrder: chapter.order,
      authorization: await _authorization(),
    );
    final pages = _decodeList(raw).asMap().entries.map((entry) {
      final index = entry.key;
      final map = entry.value;
      final url = map['url']?.toString() ?? '';
      final path = map['path']?.toString() ?? _imageNameFromUrl(url, index);
      final originalName =
          map['original_name']?.toString() ??
          map['originalName']?.toString() ??
          path;
      return ReaderPageImage(
        id: map['id']?.toString() ?? '${chapter.id}:$index',
        url: url,
        path: path,
        originalName: originalName,
        extern: Map<String, dynamic>.from(
          map['extern'] as Map? ?? const <String, dynamic>{},
        ),
      );
    }).toList(growable: false);

    return ReaderChapterSnapshot(
      providerId: id,
      comic: comic,
      chapter: chapter,
      chapters: List<Chapter>.unmodifiable(chapters),
      pages: List<ReaderPageImage>.unmodifiable(pages),
    );
  }

  @override
  Future<SearchResult> getLatest(int page) async {
    final raw = await rust.bikaGetLatest(
      page: page,
      authorization: await _authorization(),
    );
    return SearchResult.fromJson(_decodeMap(raw));
  }

  @override
  Future<SearchResult> getRanking({
    required String category,
    required String order,
    required int page,
  }) async {
    final raw = await rust.bikaGetRanking(
      category: category,
      order: order,
      page: page,
      authorization: await _authorization(),
    );
    return SearchResult.fromJson(_decodeMap(raw));
  }

  Future<String> _authorization() async {
    final current = setting;
    final authorization = current.authorization.trim();
    if (authorization.isNotEmpty) {
      return authorization;
    }

    if (current.account.trim().isNotEmpty && current.password.isNotEmpty) {
      await loginWithPassword(
        account: current.account,
        password: current.password,
      );
      final nextAuthorization = setting.authorization.trim();
      if (nextAuthorization.isNotEmpty) {
        return nextAuthorization;
      }
    }

    throw StateError('哔咔需要先登录');
  }

  UserSetting _userSetting() {
    var userSetting = objectbox.userSettingBox.get(1);
    if (userSetting == null) {
      userSetting = UserSetting(id: 1);
      objectbox.userSettingBox.put(userSetting);
    }
    return userSetting;
  }

  void _saveSetting(BikaSettingState next) {
    final userSetting = _userSetting();
    userSetting.bikaSetting = next;
    objectbox.userSettingBox.put(userSetting);
  }

  _BikaChapterRef _parseChapterId(String chapterId) {
    final parts = chapterId.split(':');
    if (parts.length >= 2) {
      final order = int.tryParse(parts.last) ?? 0;
      final comicId = parts.take(parts.length - 1).join(':');
      if (comicId.trim().isNotEmpty && order > 0) {
        return _BikaChapterRef(comicId: comicId, order: order);
      }
    }
    throw StateError('哔咔章节 ID 无效: $chapterId');
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected JSON object from Rust Bika provider', raw);
  }

  List<Map<String, dynamic>> _decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Expected JSON list from Rust Bika provider', raw);
    }
    return decoded.map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }
      throw FormatException('Expected JSON object item from Rust Bika provider');
    }).toList(growable: false);
  }

  String _imageNameFromUrl(String url, int index) {
    final parsed = Uri.tryParse(url);
    final pathSegments = parsed?.pathSegments;
    if (pathSegments != null && pathSegments.isNotEmpty) {
      final name = pathSegments.last.trim();
      if (name.isNotEmpty) return name;
    }
    return '${index + 1}.jpg';
  }
}

class _BikaChapterRef {
  final String comicId;
  final int order;

  const _BikaChapterRef({required this.comicId, required this.order});
}
