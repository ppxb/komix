import 'dart:convert';

DownloadTaskJson downloadTaskJsonFromJson(String str) {
  return DownloadTaskJson.fromJson(json.decode(str) as Map<String, dynamic>);
}

String downloadTaskJsonToJson(DownloadTaskJson data) {
  return json.encode(data.toJson());
}

class DownloadChapterTaskRef {
  final String chapterId;
  final String requestId;
  final String storageChapterId;
  final String logicalKey;
  final String title;
  final int order;
  final Map<String, dynamic> extern;

  const DownloadChapterTaskRef({
    this.chapterId = '',
    this.requestId = '',
    this.storageChapterId = '',
    this.logicalKey = '',
    this.title = '',
    this.order = 0,
    this.extern = const <String, dynamic>{},
  });

  factory DownloadChapterTaskRef.fromJson(Map<String, dynamic> json) {
    return DownloadChapterTaskRef(
      chapterId: json['chapterId'] as String? ?? '',
      requestId: json['requestId'] as String? ?? '',
      storageChapterId: json['storageChapterId'] as String? ?? '',
      logicalKey: json['logicalKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      extern: json['extern'] is Map
          ? Map<String, dynamic>.from(json['extern'] as Map)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'requestId': requestId,
      'storageChapterId': storageChapterId,
      'logicalKey': logicalKey,
      'title': title,
      'order': order,
      'extern': extern,
    };
  }
}

class DownloadTaskJson {
  final String from;
  final String comicId;
  final String comicName;
  final List<DownloadChapterTaskRef> chapterRefs;

  const DownloadTaskJson({
    required this.from,
    required this.comicId,
    required this.comicName,
    required this.chapterRefs,
  });

  factory DownloadTaskJson.fromJson(Map<String, dynamic> json) {
    return DownloadTaskJson(
      from: json['from'] as String? ?? '',
      comicId: json['comicId'] as String? ?? '',
      comicName: json['comicName'] as String? ?? '',
      chapterRefs: (json['chapterRefs'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => DownloadChapterTaskRef.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'comicId': comicId,
      'comicName': comicName,
      'chapterRefs': chapterRefs.map((item) => item.toJson()).toList(),
    };
  }
}
