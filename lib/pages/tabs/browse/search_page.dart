import 'package:flutter/material.dart';
import '../../../services/search_aggregator.dart';
import '../../../models/comic.dart';
import '../../../providers/provider_registry.dart';
import '../../comic_detail_page.dart';
import 'provider_search_results_page.dart';

/// 搜索页 - 聚合搜索所有内置源
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _previewLimit = 20;
  static const double _previewListHeight = 174;
  static const double _previewCardWidth = 96;

  final TextEditingController _searchController = TextEditingController();
  final SearchAggregator _searchAggregator = SearchAggregator();
  final ProviderRegistry _providerRegistry = ProviderRegistry();

  Map<String, SearchResult>? _searchResults;
  bool _isLoading = false;
  String _currentKeyword = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _performSearch(String keyword) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) return;

    setState(() {
      _isLoading = true;
      _currentKeyword = trimmedKeyword;
      _searchResults = null;
    });

    try {
      final results = await _searchAggregator.aggregateSearch(
        trimmedKeyword,
        1,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
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
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索漫画...',
              isDense: true,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              prefixIcon: const Icon(Icons.search, size: 20),
              prefixIconConstraints: const BoxConstraints.tightFor(
                width: 40,
                height: 38,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: '清空',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = null;
                          _currentKeyword = '';
                        });
                      },
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 40,
                height: 38,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
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

    final entries = _searchResults!.entries
        .where((entry) => entry.value.items.isNotEmpty)
        .toList(growable: false);

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未找到相关结果',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildProviderSection(entry.key, entry.value);
      },
    );
  }

  Widget _buildProviderSection(String providerId, SearchResult result) {
    final providerName =
        _providerRegistry.getProvider(providerId)?.name ?? providerId;
    final previewItems = result.items.take(_previewLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                providerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: '查看$providerName',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _openProviderResults(providerId, result),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: _previewListHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: previewItems.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final comic = previewItems[index];
              return _buildComicCard(providerId, comic);
            },
          ),
        ),
      ],
    );
  }

  void _openProviderResults(String providerId, SearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderSearchResultsPage(
          providerId: providerId,
          initialKeyword: _currentKeyword,
          initialResult: result,
        ),
      ),
    );
  }

  Widget _buildComicCard(String providerId, Comic comic) {
    return SizedBox(
      width: _previewCardWidth,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComicDetailPage(
                  providerId: providerId,
                  initialComic: comic,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
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
              Padding(
                padding: const EdgeInsets.all(6.0),
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
      ),
    );
  }
}
