import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'jm_crypto.dart';

/// JM API 客户端
/// 参考 Breeze-plugin-JmComic 实现
class JmApiClient {
  late final Dio _dio;

  static const String _version = '2.0.20';
  static const List<String> _aesSeeds = [
    '185Hcomic3PAPP7R',
    '18comicAPPContent',
  ];

  final String _baseUrl = 'https://www.cdnhjk.net';
  final String _imageUrl = 'https://cdn-msp3.jmdanjonproxy.vip';

  JmApiClient() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        validateStatus: (status) => true,
      ),
    );

    // 请求拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final ts = DateTime.now().millisecondsSinceEpoch.toString();
          final token = JmCrypto.md5Hash('$ts$_version');

          options.extra['jm_ts'] = ts;
          options.headers.addAll({
            'token': token,
            'tokenparam': '$ts,$_version',
            'user-agent': 'okhttp/3.12.1',
          });

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // 解密响应
          if (response.data != null) {
            final ts =
                response.requestOptions.extra['jm_ts']?.toString() ??
                DateTime.now().millisecondsSinceEpoch.toString();
            final decoded = await _decodeResponse(response.data, ts);
            response.data = decoded;
          }
          return handler.next(response);
        },
      ),
    );
  }

  Future<dynamic> _decodeResponse(dynamic data, String ts) async {
    if (data == null) return null;

    if (data is String) {
      final raw = data.trim();
      if (raw.isEmpty) return '';

      try {
        return await _decodeResponse(json.decode(raw), ts);
      } catch (_) {
        return data;
      }
    }

    // 如果是 Map 且包含 data 字段，尝试解密
    if (data is Map) {
      final decodedMap = data.map((key, value) {
        return MapEntry(key.toString(), value);
      });
      final dataField = decodedMap['data'];
      if (dataField is String && dataField.isNotEmpty) {
        final decrypted = JmCrypto.tryDecryptWithSeeds(
          dataField,
          ts,
          _aesSeeds,
        );

        if (decrypted != null) {
          return _decodeResponse(decrypted, ts);
        }

        try {
          return await _decodeResponse(json.decode(dataField), ts);
        } catch (e) {
          developer.log('JSON 解析失败', error: e, name: 'JmApiClient');
        }
      }

      return decodedMap;
    }

    return data;
  }

  Map<String, dynamic> _expectMap(dynamic data, String action) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    throw Exception('$action 失败: 响应格式异常 (${data.runtimeType})');
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 搜索漫画
  Future<Map<String, dynamic>> search(String keyword, int page) async {
    final response = await _dio.get(
      '$_baseUrl/search',
      queryParameters: {'search_query': keyword, 'page': page, 'o': ''},
    );

    if (response.statusCode != 200) {
      throw Exception('搜索失败: ${response.statusCode}');
    }

    final data = _expectMap(response.data, '搜索');
    final content = data['content'] as List? ?? [];
    final total = _parseInt(data['total']);

    return {
      'items': content,
      'total': total,
      'page': page,
      'has_more': content.length >= 80,
    };
  }

  /// 获取漫画详情
  Future<Map<String, dynamic>> getComicDetail(String comicId) async {
    final response = await _dio.get(
      '$_baseUrl/album',
      queryParameters: {'id': comicId},
    );

    if (response.statusCode != 200) {
      throw Exception('获取详情失败: ${response.statusCode}');
    }

    return _expectMap(response.data, '获取详情');
  }

  /// 获取章节列表（包含在详情中）
  List<Map<String, dynamic>> extractChapters(Map<String, dynamic> detail) {
    final series = detail['series'] as List? ?? [];
    if (series.isEmpty) {
      // 单话漫画
      return [
        {
          'id': detail['id'].toString(),
          'comic_id': detail['id'].toString(),
          'name': '第1话',
          'order': 1,
        },
      ];
    }

    return series
        .where((item) => item['sort'] != '0' && item['sort'] != 0)
        .toList()
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key + 1;
          final item = entry.value;
          return {
            'id': item['id'].toString(),
            'comic_id': detail['id'].toString(),
            'name': '第$index话 ${item['name'] ?? ''}',
            'order': index,
          };
        })
        .toList();
  }

  /// 获取章节图片
  Future<List<String>> getChapterImages(String chapterId) async {
    final response = await _dio.get(
      '$_baseUrl/chapter',
      queryParameters: {'id': chapterId, 'skip': ''},
    );

    if (response.statusCode != 200) {
      throw Exception('获取章节失败: ${response.statusCode}');
    }

    final data = _expectMap(response.data, '获取章节');
    final images = data['images'] as List? ?? [];

    return images.map((image) {
      return '$_imageUrl/media/photos/$chapterId/$image';
    }).toList();
  }

  /// 获取最新更新
  Future<Map<String, dynamic>> getLatest(int page) async {
    final response = await _dio.get(
      '$_baseUrl/latest',
      queryParameters: {'page': page},
    );

    if (response.statusCode != 200) {
      throw Exception('获取最新失败: ${response.statusCode}');
    }

    final items = response.data as List? ?? [];

    return {
      'items': items,
      'total': items.length,
      'page': page,
      'has_more': items.length >= 80,
    };
  }

  /// 获取排行榜
  Future<Map<String, dynamic>> getRanking({
    required String category,
    required String order,
    required int page,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/categories/filter',
      queryParameters: {'page': page, 'c': category, 'o': order},
    );

    if (response.statusCode != 200) {
      throw Exception('获取排行榜失败: ${response.statusCode}');
    }

    final data = _expectMap(response.data, '获取排行榜');
    final content = data['content'] as List? ?? [];
    final total = _parseInt(data['total']);

    return {
      'items': content,
      'total': total,
      'page': page,
      'has_more': content.length >= 80,
    };
  }

  String buildCoverUrl(Map<String, dynamic> item) {
    final image = item['image']?.toString() ?? '';
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }

    if (image.startsWith('/')) {
      return '$_imageUrl$image';
    }

    if (image.startsWith('media/')) {
      return '$_imageUrl/$image';
    }

    final id = item['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      return '$_imageUrl/media/albums/${id}_3x4.jpg';
    }

    return '';
  }
}
