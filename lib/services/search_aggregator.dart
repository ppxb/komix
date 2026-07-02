import 'dart:developer' as developer;

import '../models/comic.dart';
import '../providers/provider_registry.dart';

/// 聚合搜索服务
/// 跨所有已订阅的数据源进行搜索
class SearchAggregator {
  final ProviderRegistry _registry = ProviderRegistry();

  /// 聚合搜索
  /// 返回所有已订阅数据源的搜索结果
  Future<Map<String, SearchResult>> aggregateSearch(
    String keyword,
    int page,
  ) async {
    final subscribedProviders = _registry.getSubscribedProviders();
    final results = <String, SearchResult>{};

    // 并发搜索所有已订阅的数据源
    await Future.wait(
      subscribedProviders.map((provider) async {
        try {
          final result = await provider.search(keyword, page);
          results[provider.id] = result;
        } catch (e) {
          // 单个源失败不影响其他源
          developer.log(
            '搜索失败 [${provider.name}]',
            error: e,
            name: 'SearchAggregator',
          );
        }
      }),
    );

    return results;
  }

  /// 获取单个数据源的搜索结果
  Future<SearchResult?> searchFromProvider(
    String providerId,
    String keyword,
    int page,
  ) async {
    final provider = _registry.getProvider(providerId);
    if (provider == null) {
      return null;
    }

    try {
      return await provider.search(keyword, page);
    } catch (e) {
      developer.log(
        '搜索失败 [${provider.name}]',
        error: e,
        name: 'SearchAggregator',
      );
      return null;
    }
  }
}
