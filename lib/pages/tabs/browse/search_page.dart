import 'package:flutter/material.dart';
import '../../../services/search_aggregator.dart';
import '../../../models/comic.dart';
import '../../../providers/provider_registry.dart';
import '../../comic_detail_page.dart';

/// 搜索页 - 聚合搜索所有内置源
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final SearchAggregator _searchAggregator = SearchAggregator();
  final ProviderRegistry _providerRegistry = ProviderRegistry();

  Map<String, SearchResult>? _searchResults;
  final Map<String, int> _providerPages = {};
  final Set<String> _loadingMoreProviders = {};
  bool _isLoading = false;
  String _currentKeyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _currentKeyword = keyword;
    });

    try {
      final results = await _searchAggregator.aggregateSearch(keyword, 1);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _providerPages
          ..clear()
          ..addEntries(
            results.entries.map(
              (entry) => MapEntry(entry.key, entry.value.page),
            ),
          );
        _loadingMoreProviders.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('搜索失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索漫画...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = null;
                          _currentKeyword = '';
                          _providerPages.clear();
                          _loadingMoreProviders.clear();
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            onSubmitted: _performSearch,
          ),
        ),

        // 搜索结果
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults == null || _searchResults!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _currentKeyword.isEmpty ? '输入关键词开始搜索' : '未找到相关结果',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults!.length,
      itemBuilder: (context, index) {
        final providerId = _searchResults!.keys.elementAt(index);
        final result = _searchResults![providerId]!;

        return _buildProviderSection(providerId, result);
      },
    );
  }

  Widget _buildProviderSection(String providerId, SearchResult result) {
    final providerName =
        _providerRegistry.getProvider(providerId)?.name ?? providerId;
    final loadedCount = result.items.length;
    final totalCount = result.total;
    final isLoadingMore = _loadingMoreProviders.contains(providerId);
    final canLoadMore =
        !isLoadingMore &&
        (result.hasMore || (totalCount > 0 && loadedCount < totalCount));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数据源标题
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  providerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$totalCount 个结果',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // 漫画网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: result.items.length,
          itemBuilder: (context, index) {
            final comic = result.items[index];
            return _buildComicCard(providerId, comic);
          },
        ),

        if (canLoadMore || isLoadingMore)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: FilledButton.icon(
                onPressed: canLoadMore ? () => _loadMore(providerId) : null,
                icon: isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(isLoadingMore ? '加载中' : '加载更多'),
              ),
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _loadMore(String providerId) async {
    final currentResults = _searchResults;
    final current = currentResults?[providerId];
    final keyword = _currentKeyword;
    if (current == null || keyword.trim().isEmpty) return;
    if (_loadingMoreProviders.contains(providerId)) return;

    final nextPage = (_providerPages[providerId] ?? current.page) + 1;
    setState(() {
      _loadingMoreProviders.add(providerId);
    });

    SearchResult? result;
    try {
      result = await _searchAggregator.searchFromProvider(
        providerId,
        keyword,
        nextPage,
      );
    } finally {
      if (mounted && keyword == _currentKeyword) {
        setState(() {
          _loadingMoreProviders.remove(providerId);
        });
      }
    }

    if (!mounted || keyword != _currentKeyword) return;

    setState(() {
      if (result == null) {
        return;
      }

      _providerPages[providerId] = result.page;
      _searchResults?[providerId] = SearchResult(
        items: [...current.items, ...result.items],
        total: result.total,
        page: result.page,
        hasMore: result.hasMore,
      );
    });

    if (result == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载更多失败')));
    }
  }

  Widget _buildComicCard(String providerId, Comic comic) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ComicDetailPage(providerId: providerId, initialComic: comic),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[300],
                child: Image.network(
                  comic.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(child: Icon(Icons.broken_image));
                  },
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                comic.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
