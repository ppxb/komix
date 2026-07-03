import '../models/comic.dart';
import '../models/reader_snapshot.dart';

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

  /// 获取阅读章节快照。
  ///
  /// Komix 内部用 provider 维护多源能力，这里对齐 Breeze 的阅读快照思路，
  /// 但不引入插件系统。默认实现基于现有章节图片列表构建快照，后续各源可以
  /// 覆盖此方法补充 page id、path、headers 或 extern。
  Future<ReaderChapterSnapshot> getReaderChapterSnapshot({
    required Comic comic,
    required Chapter chapter,
    required List<Chapter> chapters,
  }) async {
    final images = (await getChapterImages(chapter.id))
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    return ReaderChapterSnapshot(
      providerId: id,
      comic: comic,
      chapter: chapter,
      chapters: List<Chapter>.unmodifiable(chapters),
      pages: List<ReaderPageImage>.unmodifiable(
        images.asMap().entries.map((entry) {
          final index = entry.key;
          final url = entry.value;
          return ReaderPageImage(
            id: '${chapter.id}:$index',
            url: url,
            path: url,
            originalName: '${index + 1}',
          );
        }),
      ),
    );
  }

  /// 获取最新更新
  Future<SearchResult> getLatest(int page);

  /// 获取排行榜
  Future<SearchResult> getRanking({
    required String category,
    required String order,
    required int page,
  });
}
