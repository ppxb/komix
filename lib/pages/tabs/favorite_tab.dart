import 'dart:async';

import 'package:flutter/material.dart';

import '../../providers/provider_registry.dart';
import '../../services/favorite_service.dart';
import '../comic_detail_page.dart';

/// 收藏 Tab
class FavoriteTab extends StatefulWidget {
  const FavoriteTab({super.key});

  @override
  State<FavoriteTab> createState() => _FavoriteTabState();
}

class _FavoriteTabState extends State<FavoriteTab> {
  late Future<List<FavoriteComic>> _favoriteFuture;

  @override
  void initState() {
    super.initState();
    _favoriteFuture = _loadFavorites();
    FavoriteService.instance.revision.addListener(_handleFavoritesChanged);
  }

  @override
  void dispose() {
    FavoriteService.instance.revision.removeListener(_handleFavoritesChanged);
    super.dispose();
  }

  Future<List<FavoriteComic>> _loadFavorites() {
    return FavoriteService.instance.getAllFavorites();
  }

  Future<void> _refreshFavorites() {
    final future = _loadFavorites();
    setState(() {
      _favoriteFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  void _handleFavoritesChanged() {
    if (!mounted) return;
    unawaited(_refreshFavorites());
  }

  void _openFavorite(FavoriteComic favorite) {
    final provider = ProviderRegistry().getProvider(favorite.providerId);
    if (provider == null) {
      _showMessage('未找到数据源: ${favorite.providerId}');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComicDetailPage(
          providerId: favorite.providerId,
          initialComic: favorite.toComic(),
        ),
      ),
    );
  }

  Future<void> _removeFavorite(FavoriteComic favorite) async {
    await FavoriteService.instance.removeFavorite(
      providerId: favorite.providerId,
      comicId: favorite.comicId,
    );
    if (!mounted) return;
    _showMessage('已取消收藏');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: FutureBuilder<List<FavoriteComic>>(
        future: _favoriteFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <FavoriteComic>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && items.isEmpty) {
            return _FavoriteMessage(
              icon: Icons.error_outline,
              text: snapshot.error.toString(),
            );
          }

          if (items.isEmpty) {
            return const _FavoriteMessage(
              icon: Icons.favorite_outline,
              text: '暂无收藏',
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: _refreshFavorites,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final providerName =
                    ProviderRegistry().getProvider(item.providerId)?.name ??
                    item.providerId;
                final subtitle = item.creator.isEmpty
                    ? providerName
                    : '$providerName · ${item.creator}';

                return ListTile(
                  leading: _FavoriteCover(url: item.coverUrl),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '取消收藏',
                    icon: const Icon(Icons.favorite),
                    onPressed: () => _removeFavorite(item),
                  ),
                  onTap: () => _openFavorite(item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteCover extends StatelessWidget {
  final String url;

  const _FavoriteCover({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 60,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            );
          },
        ),
      ),
    );
  }
}

class _FavoriteMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FavoriteMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
