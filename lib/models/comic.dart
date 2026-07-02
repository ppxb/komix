class Comic {
  final String id;
  final String title;
  final List<String> author;
  final String coverUrl;
  final String description;
  final List<String> tags;
  final int likes;
  final int views;
  final String updatedAt;

  Comic({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.description,
    required this.tags,
    required this.likes,
    required this.views,
    required this.updatedAt,
  });

  factory Comic.fromJson(Map<String, dynamic> json) {
    return Comic(
      id: json['id'] as String,
      title: json['title'] as String,
      author: (json['author'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      coverUrl: json['cover_url'] as String,
      description: json['description'] as String,
      tags: (json['tags'] as List<dynamic>).map((e) => e as String).toList(),
      likes: json['likes'] as int,
      views: json['views'] as int,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'cover_url': coverUrl,
      'description': description,
      'tags': tags,
      'likes': likes,
      'views': views,
      'updated_at': updatedAt,
    };
  }
}

class Chapter {
  final String id;
  final String comicId;
  final String name;
  final int order;

  Chapter({
    required this.id,
    required this.comicId,
    required this.name,
    required this.order,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      comicId: json['comic_id'] as String,
      name: json['name'] as String,
      order: json['order'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'comic_id': comicId, 'name': name, 'order': order};
  }
}

class SearchResult {
  final List<Comic> items;
  final int total;
  final int page;
  final bool hasMore;

  SearchResult({
    required this.items,
    required this.total,
    required this.page,
    required this.hasMore,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      items: (json['items'] as List<dynamic>)
          .map((e) => Comic.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      hasMore: json['has_more'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
      'page': page,
      'has_more': hasMore,
    };
  }
}
