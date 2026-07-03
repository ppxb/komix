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

  factory ReaderPageImage.fromJson(Map<String, dynamic> json) {
    return ReaderPageImage(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      originalName: json['original_name']?.toString() ?? '',
      extern: _asStringKeyMap(json['extern']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'path': path,
      'original_name': originalName,
      'extern': extern,
    };
  }

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

  factory ReaderChapterSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final rawChapters = json['chapters'];
    return ReaderChapterSnapshot(
      providerId: json['provider_id']?.toString() ?? '',
      comic: Comic.fromJson(_asStringKeyMap(json['comic'])),
      chapter: Chapter.fromJson(_asStringKeyMap(json['chapter'])),
      chapters: rawChapters is List
          ? rawChapters
                .whereType<Map>()
                .map((item) => Chapter.fromJson(_asStringKeyMap(item)))
                .toList(growable: false)
          : const <Chapter>[],
      pages: rawPages is List
          ? rawPages
                .whereType<Map>()
                .map((item) => ReaderPageImage.fromJson(_asStringKeyMap(item)))
                .toList(growable: false)
          : const <ReaderPageImage>[],
      extern: _asStringKeyMap(json['extern']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_id': providerId,
      'comic': comic.toJson(),
      'chapter': chapter.toJson(),
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      'pages': pages.map((page) => page.toJson()).toList(),
      'extern': extern,
    };
  }
}

Map<String, dynamic> _asStringKeyMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}
