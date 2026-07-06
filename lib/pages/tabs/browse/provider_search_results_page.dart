import 'package:flutter/material.dart';

import '../../../models/comic.dart';
import '../../../providers/provider_registry.dart';
import '../../../services/search_aggregator.dart';
import '../../comic_detail_page.dart';

class ProviderSearchResultsPage extends StatefulWidget {
  final String providerId;
  final String initialKeyword;
  final SearchResult initialResult;

  const ProviderSearchResultsPage({
    super.key,
    required this.providerId,
    required this.initialKeyword,
    required this.initialResult,
  });

  @override
  State<ProviderSearchResultsPage> createState() =>
      _ProviderSearchResultsPageState();
}

class _ProviderSearchResultsPageState extends State<ProviderSearchResultsPage> {
  final SearchAggregator _searchAggregator = SearchAggregator();
  final ProviderRegistry _providerRegistry = ProviderRegistry();
  final ScrollController _scrollController = ScrollController();

  late final TextEditingController _searchController;
  late SearchResult _result;
  late String _keyword;

  bool _isSearching = false;
  bool _isLoadingMore = false;
  _ProviderSearchFilters _filters = const _ProviderSearchFilters();

  String get _providerName =>
      _providerRegistry.getProvider(widget.providerId)?.name ??
      widget.providerId;

  bool get _canRequestMore =>
      !_isSearching &&
      !_isLoadingMore &&
      (_result.hasMore ||
          (_result.total > 0 && _result.items.length < _result.total));

  List<Comic> get _filteredItems {
    final titleFilter = _filters.title.trim().toLowerCase();
    final metaFilter = _filters.meta.trim().toLowerCase();
    if (titleFilter.isEmpty && metaFilter.isEmpty) {
      return _result.items;
    }

    return _result.items.where((comic) {
      final titleMatches =
          titleFilter.isEmpty ||
          comic.title.toLowerCase().contains(titleFilter);
      final metaText = [
        ...comic.author,
        ...comic.tags,
      ].join(' ').toLowerCase();
      final metaMatches =
          metaFilter.isEmpty || metaText.contains(metaFilter);
      return titleMatches && metaMatches;
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword;
    _result = widget.initialResult;
    _searchController = TextEditingController(text: widget.initialKeyword)
      ..addListener(_onSearchTextChanged);
    _scrollController.addListener(_onResultsScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onResultsScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onResultsScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.extentAfter < 480) {
      _loadMore();
    }
  }

  Future<void> _search(String keyword) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty || _isSearching) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _keyword = trimmedKeyword;
      _filters = const _ProviderSearchFilters();
    });

    final result = await _searchAggregator.searchFromProvider(
      widget.providerId,
      trimmedKeyword,
      1,
    );
    if (!mounted) return;

    setState(() {
      _isSearching = false;
      if (result != null) {
        _result = result;
      }
    });

    _jumpResultsToTop();

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('搜索失败')));
    }
  }

  Future<void> _refresh() async {
    final keyword = _keyword;
    if (keyword.trim().isEmpty) return;

    final result = await _searchAggregator.searchFromProvider(
      widget.providerId,
      keyword,
      1,
    );
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刷新失败')));
      return;
    }

    setState(() {
      _result = result;
    });
  }

  Future<void> _loadMore() async {
    if (!_canRequestMore) return;

    final keyword = _keyword;
    final current = _result;
    setState(() {
      _isLoadingMore = true;
    });

    SearchResult? result;
    try {
      result = await _searchAggregator.searchFromProvider(
        widget.providerId,
        keyword,
        current.page + 1,
      );
    } finally {
      if (mounted && keyword == _keyword) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }

    if (!mounted || keyword != _keyword) return;

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载失败')));
      return;
    }

    final nextResult = result;
    setState(() {
      _result = SearchResult(
        items: [...current.items, ...nextResult.items],
        total: nextResult.total,
        page: nextResult.page,
        hasMore: nextResult.hasMore,
      );
    });
  }

  void _jumpResultsToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController.jumpTo(0);
    });
  }

  Future<void> _showFilterSheet() async {
    final filters = await showModalBottomSheet<_ProviderSearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _SearchFilterSheet(initialFilters: _filters);
      },
    );
    if (!mounted || filters == null) return;

    setState(() {
      _filters = filters;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_providerName),
        actions: [
          IconButton(
            tooltip: '筛选',
            color: _filters.isEmpty ? null : theme.colorScheme.primary,
            icon: const Icon(Icons.tune),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (!_filters.isEmpty) _buildFilterSummary(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '在${_providerName}中搜索...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        ),
        onSubmitted: _search,
      ),
    );
  }

  Widget _buildFilterSummary() {
    final chips = <Widget>[
      if (_filters.title.trim().isNotEmpty)
        InputChip(
          label: Text('标题: ${_filters.title}'),
          onDeleted: () {
            setState(() {
              _filters = _filters.copyWith(title: '');
            });
          },
        ),
      if (_filters.meta.trim().isNotEmpty)
        InputChip(
          label: Text('作者/标签: ${_filters.meta}'),
          onDeleted: () {
            setState(() {
              _filters = _filters.copyWith(meta: '');
            });
          },
        ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_result.items.isEmpty) {
      return _buildEmptyState(Icons.search_off, '未找到相关结果');
    }

    final filteredItems = _filteredItems;
    if (filteredItems.isEmpty) {
      return _buildEmptyState(Icons.filter_alt_off, '没有符合筛选的结果');
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 720
              ? 5
              : constraints.maxWidth >= 520
              ? 4
              : 3;

          return CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.6,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildComicCard(filteredItems[index]),
                    childCount: filteredItems.length,
                  ),
                ),
              ),
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildComicCard(Comic comic) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ComicDetailPage(
                providerId: widget.providerId,
                initialComic: comic,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

class _ProviderSearchFilters {
  final String title;
  final String meta;

  const _ProviderSearchFilters({this.title = '', this.meta = ''});

  bool get isEmpty => title.trim().isEmpty && meta.trim().isEmpty;

  _ProviderSearchFilters copyWith({String? title, String? meta}) {
    return _ProviderSearchFilters(
      title: title ?? this.title,
      meta: meta ?? this.meta,
    );
  }
}

class _SearchFilterSheet extends StatefulWidget {
  final _ProviderSearchFilters initialFilters;

  const _SearchFilterSheet({required this.initialFilters});

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _metaController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialFilters.title,
    );
    _metaController = TextEditingController(text: widget.initialFilters.meta);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _metaController.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.of(context).pop(
      _ProviderSearchFilters(
        title: _titleController.text.trim(),
        meta: _metaController.text.trim(),
      ),
    );
  }

  void _reset() {
    Navigator.of(context).pop(const _ProviderSearchFilters());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '筛选',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题包含',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _metaController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '作者或标签包含',
                prefixIcon: Icon(Icons.sell_outlined),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
