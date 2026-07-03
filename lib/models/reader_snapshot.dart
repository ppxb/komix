import 'comic.dart';

class ReaderPageImage {
  final String id;
  final String url;
  final String path;
  final String originalName;
  final Map<String, dynamic> extern;

  const ReaderPageImage({
    required this.id,
    required this.url,
    this.path = '',
    this.originalName = '',
    this.extern = const <String, dynamic>{},
  });

  String get cacheKey {
    if (id.trim().isNotEmpty) return id;
    if (path.trim().isNotEmpty) return path;
    return url;
  }
}

class ReaderChapterSnapshot {
  final String providerId;
  final Comic comic;
  final Chapter chapter;
  final List<Chapter> chapters;
  final List<ReaderPageImage> pages;
  final Map<String, dynamic> extern;

  const ReaderChapterSnapshot({
    required this.providerId,
    required this.comic,
    required this.chapter,
    required this.chapters,
    required this.pages,
    this.extern = const <String, dynamic>{},
  });

  int get pageCount => pages.length;
}
