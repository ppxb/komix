import '../models/comic.dart';

/// 数据源基类
abstract class BaseProvider {
  /// 数据源唯一标识
  String get id;

  /// 数据源名称
  String get name;

  /// 数据源图标 URL
  String get iconUrl;

  /// 搜索漫画
  Future<SearchResult> search(String keyword, int page);

  /// 获取漫画详情
  Future<Comic> getComicDetail(String comicId);

  /// 获取章节列表
  Future<List<Chapter>> getChapters(String comicId);

  /// 获取章节图片列表
  Future<List<String>> getChapterImages(String chapterId);

  /// 获取最新更新
  Future<SearchResult> getLatest(int page);

  /// 获取排行榜
  Future<SearchResult> getRanking({
    required String category,
    required String order,
    required int page,
  });
}
