import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/provider_registry.dart';
import '../../../providers/base_provider.dart';
import '../../../models/comic.dart';

/// 订阅页 - 管理和浏览不同的内置源
class SubscribePage extends StatefulWidget {
  const SubscribePage({super.key});

  @override
  State<SubscribePage> createState() => _SubscribePageState();
}

class _SubscribePageState extends State<SubscribePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _selectedProviderIndex = 0;
  final Map<String, List<Comic>> _latestCache = {};
  final Map<String, bool> _loadingStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLatestForCurrentProvider();
    });
  }

  Future<void> _loadLatestForCurrentProvider() async {
    final registry = context.read<ProviderRegistry>();
    final providers = registry.getSubscribedProviders();
    if (providers.isEmpty) return;

    final provider = providers[_selectedProviderIndex];
    if (_latestCache.containsKey(provider.id)) return;

    setState(() {
      _loadingStates[provider.id] = true;
    });

    try {
      final result = await provider.getLatest(1);
      setState(() {
        _latestCache[provider.id] = result.items;
        _loadingStates[provider.id] = false;
      });
    } catch (e) {
      setState(() {
        _loadingStates[provider.id] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer<ProviderRegistry>(
      builder: (context, registry, child) {
        final subscribedProviders = registry.getSubscribedProviders();

        if (subscribedProviders.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            // 数据源选择器
            _buildProviderSelector(subscribedProviders),

            // 内容区域
            Expanded(
              child: _buildContent(subscribedProviders[_selectedProviderIndex]),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无订阅的数据源',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              // TODO: 导航到数据源管理页面
            },
            child: const Text('去订阅'),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(List<BaseProvider> providers) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: providers.length,
        itemBuilder: (context, index) {
          final provider = providers[index];
          final isSelected = index == _selectedProviderIndex;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(provider.name),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedProviderIndex = index;
                  });
                  _loadLatestForCurrentProvider();
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BaseProvider provider) {
    final isLoading = _loadingStates[provider.id] ?? false;
    final comics = _latestCache[provider.id];

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (comics == null || comics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无内容',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _latestCache.remove(provider.id);
        await _loadLatestForCurrentProvider();
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: comics.length,
        itemBuilder: (context, index) {
          return _buildComicCard(comics[index]);
        },
      ),
    );
  }

  Widget _buildComicCard(Comic comic) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          // TODO: 导航到详情页
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${comic.views} 浏览',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
