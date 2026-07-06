import 'package:flutter/material.dart';

import '../../../models/comic.dart';
import '../../../providers/jm_provider.dart';
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
  _JmBrowseFilter _jmFilter = const _JmBrowseFilter();

  String get _providerName =>
      _providerRegistry.getProvider(widget.providerId)?.name ??
      widget.providerId;

  bool get _supportsJmFilters => widget.providerId == JmProvider.providerId;

  bool get _isFilterActive => _supportsJmFilters
      ? _jmFilter.mode != _JmBrowseMode.search
      : !_filters.isEmpty;

  String get _requestKey => _buildRequestKey();

  bool get _canRequestMore =>
      !_isSearching &&
      !_isLoadingMore &&
      (_result.hasMore ||
          (_result.total > 0 && _result.items.length < _result.total));

  List<Comic> get _filteredItems {
    if (_supportsJmFilters) {
      return _result.items;
    }

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

  String _buildRequestKey({_JmBrowseFilter? jmFilter, String? keyword}) {
    final resolvedKeyword = keyword ?? _keyword;
    if (!_supportsJmFilters) {
      return 'search|$resolvedKeyword';
    }

    final resolvedFilter = jmFilter ?? _jmFilter;
    return [
      resolvedFilter.mode.name,
      resolvedKeyword,
      resolvedFilter.category.value,
      resolvedFilter.order.value,
    ].join('|');
  }

  Future<SearchResult?> _requestPage(
    int page, {
    _JmBrowseFilter? jmFilter,
    String? keyword,
  }) async {
    final resolvedKeyword = keyword ?? _keyword;
    final resolvedFilter = jmFilter ?? _jmFilter;

    if (!_supportsJmFilters || resolvedFilter.mode == _JmBrowseMode.search) {
      if (resolvedKeyword.trim().isEmpty) {
        return null;
      }
      return _searchAggregator.searchFromProvider(
        widget.providerId,
        resolvedKeyword,
        page,
      );
    }

    final provider = _providerRegistry.getProvider(widget.providerId);
    if (provider == null) {
      return null;
    }

    try {
      switch (resolvedFilter.mode) {
        case _JmBrowseMode.search:
          return null;
        case _JmBrowseMode.latest:
          return await provider.getLatest(page);
        case _JmBrowseMode.ranking:
          return await provider.getRanking(
            category: resolvedFilter.category.value,
            order: resolvedFilter.order.value,
            page: page,
          );
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _search(String keyword) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty || _isSearching) return;

    final nextJmFilter = _supportsJmFilters
        ? _jmFilter.copyWith(mode: _JmBrowseMode.search)
        : _jmFilter;
    final requestKey = _buildRequestKey(
      jmFilter: nextJmFilter,
      keyword: trimmedKeyword,
    );

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _keyword = trimmedKeyword;
      _filters = const _ProviderSearchFilters();
      _jmFilter = nextJmFilter;
    });

    final result = await _requestPage(
      1,
      keyword: trimmedKeyword,
      jmFilter: nextJmFilter,
    );
    if (!mounted || requestKey != _requestKey) return;

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
    if (!_supportsJmFilters && keyword.trim().isEmpty) return;

    final requestKey = _requestKey;
    final result = await _requestPage(1);
    if (!mounted || requestKey != _requestKey) return;

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

    final requestKey = _requestKey;
    final current = _result;
    setState(() {
      _isLoadingMore = true;
    });

    SearchResult? result;
    try {
      result = await _requestPage(current.page + 1);
    } finally {
      if (mounted && requestKey == _requestKey) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }

    if (!mounted || requestKey != _requestKey) return;

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
    if (_supportsJmFilters) {
      final filters = await showModalBottomSheet<_JmBrowseFilter>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return _JmFilterSheet(initialFilter: _jmFilter);
        },
      );
      if (!mounted || filters == null) return;

      await _applyJmFilter(filters);
      return;
    }

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

  Future<void> _applyJmFilter(_JmBrowseFilter filter) async {
    final keyword = filter.mode == _JmBrowseMode.search
        ? _searchController.text.trim()
        : '';
    if (filter.mode == _JmBrowseMode.search && keyword.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入关键词')));
      return;
    }

    final previousKeyword = _keyword;
    final previousFilter = _jmFilter;
    final previousSearchText = _searchController.text;
    final requestKey = _buildRequestKey(jmFilter: filter, keyword: keyword);
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _keyword = keyword;
      _jmFilter = filter;
      _filters = const _ProviderSearchFilters();
    });
    if (filter.mode != _JmBrowseMode.search) {
      _searchController.clear();
    }

    final result = await _requestPage(1, jmFilter: filter, keyword: keyword);
    if (!mounted || requestKey != _requestKey) return;

    setState(() {
      _isSearching = false;
      if (result != null) {
        _result = result;
      } else {
        _keyword = previousKeyword;
        _jmFilter = previousFilter;
      }
    });
    if (result == null) {
      _searchController.text = previousSearchText;
    }

    if (result != null) {
      _jumpResultsToTop();
    }

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载失败')));
    }
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
            color: _isFilterActive ? theme.colorScheme.primary : null,
            icon: const Icon(Icons.tune),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_isFilterActive) _buildFilterSummary(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: '在${_providerName}中搜索...',
          isDense: true,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 40,
            height: 38,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
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
        onSubmitted: _search,
      ),
    );
  }

  Widget _buildFilterSummary() {
    if (_supportsJmFilters) {
      return _buildJmFilterSummary();
    }

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

  Widget _buildJmFilterSummary() {
    final chips = <Widget>[
      Chip(label: Text(_jmFilter.mode.label)),
      if (_jmFilter.mode == _JmBrowseMode.ranking) ...[
        Chip(label: Text(_jmFilter.category.label)),
        Chip(label: Text(_jmFilter.order.label)),
      ],
    ];

    return SizedBox(
      height: 40,
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

enum _JmBrowseMode { search, latest, ranking }

extension _JmBrowseModeLabel on _JmBrowseMode {
  String get label {
    switch (this) {
      case _JmBrowseMode.search:
        return '搜索';
      case _JmBrowseMode.latest:
        return '最新';
      case _JmBrowseMode.ranking:
        return '排行榜';
    }
  }

  IconData get icon {
    switch (this) {
      case _JmBrowseMode.search:
        return Icons.search;
      case _JmBrowseMode.latest:
        return Icons.update;
      case _JmBrowseMode.ranking:
        return Icons.leaderboard_outlined;
    }
  }
}

class _JmRankingOption {
  final String label;
  final String value;

  const _JmRankingOption(this.label, this.value);
}

const _defaultJmRankingCategory = _JmRankingOption('最新a漫', '0');
const _defaultJmRankingOrder = _JmRankingOption('最新', 'new');

const _jmRankingCategories = <_JmRankingOption>[
  _defaultJmRankingCategory,
  _JmRankingOption('同人', 'doujin'),
  _JmRankingOption('同人 / 汉化', 'doujin_chinese'),
  _JmRankingOption('同人 / 日语', 'doujin_japanese'),
  _JmRankingOption('同人 / CG图集', 'doujin_CG'),
  _JmRankingOption('单本', 'single'),
  _JmRankingOption('单本 / 汉化', 'single_chinese'),
  _JmRankingOption('单本 / 日语', 'single_japanese'),
  _JmRankingOption('单本 / 青年漫', 'single_youth'),
  _JmRankingOption('短篇', 'short'),
  _JmRankingOption('短篇 / 汉化', 'short_chinese'),
  _JmRankingOption('短篇 / 日语', 'short_japanese'),
  _JmRankingOption('其他类', 'another'),
  _JmRankingOption('其他类 / 其他漫画', 'another_other'),
  _JmRankingOption('其他类 / 3D', 'another_3d'),
  _JmRankingOption('其他类 / 角色扮演', 'another_cosplay'),
  _JmRankingOption('韩漫', 'hanman'),
  _JmRankingOption('韩漫 / 汉化', 'hanman_chinese'),
  _JmRankingOption('English Manga', 'meiman'),
  _JmRankingOption('English Manga / IRODORI', 'meiman_irodori'),
  _JmRankingOption('English Manga / FAKKU', 'meiman_fakku'),
  _JmRankingOption('English Manga / 18scan', 'meiman_18scan'),
  _JmRankingOption('English Manga / Manhwa', 'meiman_manhwa'),
  _JmRankingOption('English Manga / Comic', 'meiman_comic'),
  _JmRankingOption('English Manga / Other', 'meiman_other'),
  _JmRankingOption('Cosplay', 'another_cosplay'),
  _JmRankingOption('3D', '3D'),
  _JmRankingOption('禁漫汉化组', '禁漫汉化组'),
];

const _jmRankingOrders = <_JmRankingOption>[
  _defaultJmRankingOrder,
  _JmRankingOption('最多点赞', 'tf'),
  _JmRankingOption('总排行', 'mv'),
  _JmRankingOption('月排行', 'mv_m'),
  _JmRankingOption('周排行', 'mv_w'),
  _JmRankingOption('日排行', 'mv_t'),
];

class _JmBrowseFilter {
  final _JmBrowseMode mode;
  final _JmRankingOption category;
  final _JmRankingOption order;

  const _JmBrowseFilter({
    this.mode = _JmBrowseMode.search,
    this.category = _defaultJmRankingCategory,
    this.order = _defaultJmRankingOrder,
  });

  _JmBrowseFilter copyWith({
    _JmBrowseMode? mode,
    _JmRankingOption? category,
    _JmRankingOption? order,
  }) {
    return _JmBrowseFilter(
      mode: mode ?? this.mode,
      category: category ?? this.category,
      order: order ?? this.order,
    );
  }
}

class _JmFilterSheet extends StatefulWidget {
  final _JmBrowseFilter initialFilter;

  const _JmFilterSheet({required this.initialFilter});

  @override
  State<_JmFilterSheet> createState() => _JmFilterSheetState();
}

class _JmFilterSheetState extends State<_JmFilterSheet> {
  late _JmBrowseFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  void _apply() {
    Navigator.of(context).pop(_filter);
  }

  void _reset() {
    setState(() {
      _filter = const _JmBrowseFilter(mode: _JmBrowseMode.ranking);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
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
            const Text(
              '模式',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _JmBrowseMode.values.map((mode) {
                return ChoiceChip(
                  avatar: Icon(mode.icon, size: 18),
                  label: Text(mode.label),
                  selected: _filter.mode == mode,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _filter = _filter.copyWith(mode: mode);
                    });
                  },
                );
              }).toList(growable: false),
            ),
            if (_filter.mode == _JmBrowseMode.ranking) ...[
              const SizedBox(height: 16),
              const Text(
                '分类',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _jmRankingCategories.map((category) {
                  return ChoiceChip(
                    label: Text(category.label),
                    selected: _filter.category.value == category.value,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _filter = _filter.copyWith(category: category);
                      });
                    },
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 16),
              const Text(
                '排序',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _jmRankingOrders.map((order) {
                  return ChoiceChip(
                    label: Text(order.label),
                    selected: _filter.order.value == order.value,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _filter = _filter.copyWith(order: order);
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            ],
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
