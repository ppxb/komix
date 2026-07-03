import 'dart:async';

import 'package:flutter/material.dart';

import '../../object_box/model.dart';
import '../../providers/provider_registry.dart';
import '../../services/comic_folder_service.dart';
import '../../services/comic_link_service.dart';
import '../../services/favorite_service.dart';
import '../comic_detail_page.dart';

class FavoriteTab extends StatefulWidget {
  const FavoriteTab({super.key});

  @override
  State<FavoriteTab> createState() => _FavoriteTabState();
}

class _FavoriteTabState extends State<FavoriteTab> {
  late Future<_FavoriteShelfData> _shelfFuture;
  String _currentPath = kComicFolderRootPath;

  @override
  void initState() {
    super.initState();
    _shelfFuture = _loadShelf();
    FavoriteService.instance.revision.addListener(_handleFavoritesChanged);
  }

  @override
  void dispose() {
    FavoriteService.instance.revision.removeListener(_handleFavoritesChanged);
    super.dispose();
  }

  Future<_FavoriteShelfData> _loadShelf() async {
    final folders = ComicFolderService.listChildFolders(
      _currentPath,
      ComicFolderType.favorite,
    );
    final favorites = await FavoriteService.instance.getFavoritesInFolder(
      _currentPath,
    );
    return _FavoriteShelfData(folders: folders, favorites: favorites);
  }

  Future<void> _refreshShelf() {
    final future = _loadShelf();
    setState(() {
      _shelfFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  void _handleFavoritesChanged() {
    if (!mounted) return;
    unawaited(_refreshShelf());
  }

  void _openFolder(ComicFolder folder) {
    setState(() {
      _currentPath = ComicFolderService.folderPath(folder);
      _shelfFuture = _loadShelf();
    });
  }

  void _goParentFolder() {
    if (_currentPath == kComicFolderRootPath) return;
    setState(() {
      _currentPath = _parentPath(_currentPath);
      _shelfFuture = _loadShelf();
    });
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

  Future<void> _createFolder() async {
    final name = await _promptFolderName(title: '新建文件夹', actionText: '创建');
    if (name == null) return;

    try {
      ComicFolderService.createFolder(
        _currentPath,
        name,
        ComicFolderType.favorite,
      );
      await _refreshShelf();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  Future<void> _renameFolder(ComicFolder folder) async {
    final path = ComicFolderService.folderPath(folder);
    final name = await _promptFolderName(
      title: '重命名文件夹',
      actionText: '保存',
      initialValue: folder.name,
    );
    if (name == null || name == folder.name) return;

    try {
      ComicFolderService.renameFolder(path, name, ComicFolderType.favorite);
      await _refreshShelf();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  Future<void> _deleteFolder(ComicFolder folder) async {
    final confirmed = await _confirmDeleteFolder(folder.name);
    if (!confirmed) return;

    final path = ComicFolderService.folderPath(folder);
    try {
      ComicLinkService.removeLinksInFolderTree(path, ComicFolderType.favorite);
      ComicFolderService.deleteFolder(path, ComicFolderType.favorite);
      await _refreshShelf();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  Future<void> _moveFavorite(FavoriteComic favorite) async {
    final targetPath = await _chooseTargetFolder();
    if (targetPath == null || targetPath == _currentPath) return;

    ComicLinkService.moveComic(
      favorite.uniqueKey,
      _currentPath,
      targetPath,
      ComicFolderType.favorite,
    );
    await _refreshShelf();
  }

  Future<void> _removeFavorite(FavoriteComic favorite) async {
    await FavoriteService.instance.removeFavorite(
      providerId: favorite.providerId,
      comicId: favorite.comicId,
    );
    if (!mounted) return;
    _showMessage('已取消收藏');
  }

  Future<String?> _promptFolderName({
    required String title,
    required String actionText,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              Navigator.of(context).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: Text(actionText),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<bool> _confirmDeleteFolder(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除文件夹'),
          content: Text('删除 "$name" 后，其中仅存在于该文件夹的收藏也会被移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<String?> _chooseTargetFolder() async {
    final folders = ComicFolderService.listAllFolders(
      ComicFolderType.favorite,
      sortAscending: true,
    );
    final targets = <_FolderTarget>[
      const _FolderTarget(path: kComicFolderRootPath, label: '根目录'),
      ...folders.map((folder) {
        final path = ComicFolderService.folderPath(folder);
        return _FolderTarget(path: path, label: path);
      }),
    ];

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: targets.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final target = targets[index];
              final isCurrent = target.path == _currentPath;
              return ListTile(
                selected: isCurrent,
                leading: Icon(
                  target.path == kComicFolderRootPath
                      ? Icons.home_outlined
                      : Icons.folder_outlined,
                ),
                title: Text(
                  target.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isCurrent ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(target.path),
              );
            },
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _titleForPath() {
    if (_currentPath == kComicFolderRootPath) return '收藏';
    final name = _currentPath.split('/').where((part) => part.isNotEmpty).last;
    return name.isEmpty ? '收藏' : name;
  }

  String _parentPath(String path) {
    if (path == kComicFolderRootPath) return kComicFolderRootPath;
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return kComicFolderRootPath;
    return trimmed.substring(0, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _currentPath == kComicFolderRootPath
            ? null
            : IconButton(
                tooltip: '返回上级',
                icon: const Icon(Icons.arrow_back),
                onPressed: _goParentFolder,
              ),
        title: Text(_titleForPath()),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createFolder,
          ),
        ],
      ),
      body: FutureBuilder<_FavoriteShelfData>(
        future: _shelfFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _FavoriteShelfData.empty();

          if (snapshot.connectionState == ConnectionState.waiting &&
              data.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && data.isEmpty) {
            return _FavoriteMessage(
              icon: Icons.error_outline,
              text: snapshot.error.toString(),
            );
          }

          if (data.isEmpty) {
            return const _FavoriteMessage(
              icon: Icons.favorite_outline,
              text: '暂无收藏',
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: _refreshShelf,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.itemCount,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index < data.folders.length) {
                  final folder = data.folders[index];
                  return _FavoriteFolderTile(
                    folder: folder,
                    onOpen: () => _openFolder(folder),
                    onRename: () => _renameFolder(folder),
                    onDelete: () => _deleteFolder(folder),
                  );
                }

                final favorite = data.favorites[index - data.folders.length];
                return _FavoriteComicTile(
                  favorite: favorite,
                  onOpen: () => _openFavorite(favorite),
                  onMove: () => _moveFavorite(favorite),
                  onRemove: () => _removeFavorite(favorite),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteShelfData {
  final List<ComicFolder> folders;
  final List<FavoriteComic> favorites;

  const _FavoriteShelfData({required this.folders, required this.favorites});

  const _FavoriteShelfData.empty()
    : folders = const <ComicFolder>[],
      favorites = const <FavoriteComic>[];

  int get itemCount => folders.length + favorites.length;

  bool get isEmpty => itemCount == 0;
}

class _FolderTarget {
  final String path;
  final String label;

  const _FolderTarget({required this.path, required this.label});
}

class _FavoriteFolderTile extends StatelessWidget {
  final ComicFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FavoriteFolderTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<_FolderAction>(
        onSelected: (action) {
          switch (action) {
            case _FolderAction.rename:
              onRename();
              return;
            case _FolderAction.delete:
              onDelete();
              return;
          }
        },
        itemBuilder: (context) {
          return const [
            PopupMenuItem(
              value: _FolderAction.rename,
              child: ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('重命名'),
              ),
            ),
            PopupMenuItem(
              value: _FolderAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('删除'),
              ),
            ),
          ];
        },
      ),
      onTap: onOpen,
    );
  }
}

class _FavoriteComicTile extends StatelessWidget {
  final FavoriteComic favorite;
  final VoidCallback onOpen;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  const _FavoriteComicTile({
    required this.favorite,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final providerName =
        ProviderRegistry().getProvider(favorite.providerId)?.name ??
        favorite.providerId;
    final subtitle = favorite.creator.isEmpty
        ? providerName
        : '$providerName · ${favorite.creator}';

    return ListTile(
      leading: _FavoriteCover(url: favorite.coverUrl),
      title: Text(favorite.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<_FavoriteAction>(
        onSelected: (action) {
          switch (action) {
            case _FavoriteAction.move:
              onMove();
              return;
            case _FavoriteAction.remove:
              onRemove();
              return;
          }
        },
        itemBuilder: (context) {
          return const [
            PopupMenuItem(
              value: _FavoriteAction.move,
              child: ListTile(
                leading: Icon(Icons.drive_file_move_outlined),
                title: Text('移动到'),
              ),
            ),
            PopupMenuItem(
              value: _FavoriteAction.remove,
              child: ListTile(
                leading: Icon(Icons.favorite),
                title: Text('取消收藏'),
              ),
            ),
          ];
        },
      ),
      onTap: onOpen,
    );
  }
}

enum _FolderAction { rename, delete }

enum _FavoriteAction { move, remove }

class _FavoriteCover extends StatelessWidget {
  final String url;

  const _FavoriteCover({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = url.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 60,
        child: resolvedUrl.isEmpty
            ? _buildPlaceholder(context)
            : Image.network(
                resolvedUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholder(context);
                },
              ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
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
