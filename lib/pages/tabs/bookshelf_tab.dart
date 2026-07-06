import 'dart:async';

import 'package:flutter/material.dart';

import '../../object_box/model.dart';
import '../../providers/provider_registry.dart';
import '../../services/comic_folder_service.dart';
import '../../services/comic_link_service.dart';
import '../../services/favorite_service.dart';
import '../comic_detail_page.dart';

class BookshelfTab extends StatefulWidget {
  const BookshelfTab({super.key});

  @override
  State<BookshelfTab> createState() => _BookshelfTabState();
}

class _BookshelfStyle {
  static const double searchHeight = 40;
  static const double clearIconSize = 20;
  static const double coverWidth = 44;
  static const double coverHeight = 60;
  static const double coverRadius = 4;
  static const double messageIconSize = 64;
  static const double messageEmojiSize = 42;
  static const double messageGap = 16;

  static const EdgeInsets filterTitlePadding = EdgeInsets.fromLTRB(
    24,
    8,
    24,
    4,
  );
  static const EdgeInsets filterButtonPadding = EdgeInsets.fromLTRB(
    24,
    8,
    24,
    0,
  );
  static const EdgeInsets filterSheetPadding = EdgeInsets.only(bottom: 16);
}

class _BookshelfTabState extends State<BookshelfTab> {
  late Future<_BookshelfData> _bookshelfFuture;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _currentPath = kComicFolderRootPath;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _showFolders = true;
  bool _showBooks = true;
  _BookshelfSort _sort = _BookshelfSort.updatedDesc;

  @override
  void initState() {
    super.initState();
    _bookshelfFuture = _loadBookshelf();
    FavoriteService.instance.revision.addListener(_handleBookshelfChanged);
  }

  @override
  void dispose() {
    FavoriteService.instance.revision.removeListener(_handleBookshelfChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<_BookshelfData> _loadBookshelf() async {
    final folders = ComicFolderService.listChildFolders(
      _currentPath,
      ComicFolderType.favorite,
    );
    final books = await FavoriteService.instance.getFavoritesInFolder(
      _currentPath,
    );
    return _BookshelfData(folders: folders, books: books);
  }

  Future<void> _refreshBookshelf() {
    final future = _loadBookshelf();
    setState(() {
      _bookshelfFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  void _handleBookshelfChanged() {
    if (!mounted) return;
    unawaited(_refreshBookshelf());
  }

  void _openFolder(ComicFolder folder) {
    setState(() {
      _currentPath = ComicFolderService.folderPath(folder);
      _bookshelfFuture = _loadBookshelf();
    });
  }

  void _goParentFolder() {
    if (_currentPath == kComicFolderRootPath) return;
    setState(() {
      _currentPath = _parentPath(_currentPath);
      _bookshelfFuture = _loadBookshelf();
    });
  }

  void _openBook(FavoriteComic book) {
    final provider = ProviderRegistry().getProvider(book.providerId);
    if (provider == null) {
      _showMessage('未找到数据源: ${book.providerId}');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComicDetailPage(
          providerId: book.providerId,
          initialComic: book.toComic(),
        ),
      ),
    );
  }

  void _enterSearch() {
    setState(() {
      _isSearching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _exitSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value.trim();
    });
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
    _searchFocusNode.requestFocus();
  }

  Future<void> _performAndRefresh(FutureOr<void> Function() action) async {
    try {
      await action();
      await _refreshBookshelf();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  Future<void> _showShelfFilters() async {
    final result = await showModalBottomSheet<_BookshelfFilterState>(
      context: context,
      showDragHandle: true,
      builder: (context) => _BookshelfFilterSheet(
        initialState: _BookshelfFilterState(
          showFolders: _showFolders,
          showBooks: _showBooks,
          sort: _sort,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _showFolders = result.showFolders;
      _showBooks = result.showBooks;
      _sort = result.sort;
    });
  }

  Future<void> _createFolder() async {
    final name = await _promptFolderName(title: '新建文件夹', actionText: '创建');
    if (name == null) return;

    await _performAndRefresh(
      () => ComicFolderService.createFolder(
        _currentPath,
        name,
        ComicFolderType.favorite,
      ),
    );
  }

  Future<void> _renameFolder(ComicFolder folder) async {
    final path = ComicFolderService.folderPath(folder);
    final name = await _promptFolderName(
      title: '重命名文件夹',
      actionText: '保存',
      initialValue: folder.name,
    );
    if (name == null || name == folder.name) return;

    await _performAndRefresh(
      () => ComicFolderService.renameFolder(
        path,
        name,
        ComicFolderType.favorite,
      ),
    );
  }

  Future<void> _deleteFolder(ComicFolder folder) async {
    final confirmed = await _confirmDeleteFolder(folder.name);
    if (!confirmed) return;

    final path = ComicFolderService.folderPath(folder);
    await _performAndRefresh(() {
      ComicLinkService.removeLinksInFolderTree(path, ComicFolderType.favorite);
      ComicFolderService.deleteFolder(path, ComicFolderType.favorite);
    });
  }

  Future<void> _moveBook(FavoriteComic book) async {
    final targetPath = await _chooseTargetFolder();
    if (targetPath == null || targetPath == _currentPath) return;

    await _performAndRefresh(() {
      ComicLinkService.moveComic(
        book.uniqueKey,
        _currentPath,
        targetPath,
        ComicFolderType.favorite,
      );
    });
  }

  Future<void> _removeBook(FavoriteComic book) async {
    await FavoriteService.instance.removeFavorite(
      providerId: book.providerId,
      comicId: book.comicId,
    );
    if (!mounted) return;
    _showMessage('已移出书架');
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
          content: Text('删除 "$name" 后，其中仅存在于该文件夹的书架条目也会被移除。'),
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
      const _FolderTarget(path: kComicFolderRootPath, label: '书架根目录'),
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

  String _parentPath(String path) {
    if (path == kComicFolderRootPath) return kComicFolderRootPath;
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return kComicFolderRootPath;
    return trimmed.substring(0, index);
  }

  _BookshelfData _prepareData(_BookshelfData data) {
    final query = _searchQuery.toLowerCase();
    final folders = _showFolders
        ? data.folders.where((folder) {
            if (query.isEmpty) return true;
            return folder.name.toLowerCase().contains(query);
          }).toList()
        : <ComicFolder>[];
    final books = _showBooks
        ? data.books.where((book) {
            if (query.isEmpty) return true;
            final providerName =
                ProviderRegistry().getProvider(book.providerId)?.name ??
                book.providerId;
            return book.title.toLowerCase().contains(query) ||
                book.creator.toLowerCase().contains(query) ||
                providerName.toLowerCase().contains(query) ||
                book.tags.any((tag) => tag.toLowerCase().contains(query));
          }).toList()
        : <FavoriteComic>[];

    switch (_sort) {
      case _BookshelfSort.updatedDesc:
        books.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _BookshelfSort.titleAsc:
        folders.sort((a, b) => a.name.compareTo(b.name));
        books.sort((a, b) => a.title.compareTo(b.title));
    }

    return _BookshelfData(folders: folders, books: books);
  }

  Widget _buildAppBarTitle() {
    final theme = Theme.of(context);
    if (!_isSearching) return const Text('书架');

    return SizedBox(
      height: _BookshelfStyle.searchHeight,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration.collapsed(
                hintText: '搜索...',
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _handleSearchChanged,
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close),
              iconSize: _BookshelfStyle.clearIconSize,
              visualDensity: VisualDensity.compact,
              onPressed: _clearSearch,
            ),
        ],
      ),
    );
  }

  Widget? _buildAppBarLeading() {
    if (_isSearching) {
      return IconButton(
        tooltip: '返回书架',
        icon: const Icon(Icons.arrow_back),
        onPressed: _exitSearch,
      );
    }

    if (_currentPath == kComicFolderRootPath) return null;
    return IconButton(
      tooltip: '返回上级',
      icon: const Icon(Icons.arrow_back),
      onPressed: _goParentFolder,
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      if (!_isSearching)
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: _enterSearch,
        ),
      IconButton(
        tooltip: '筛选',
        icon: const Icon(Icons.filter_list),
        onPressed: _showShelfFilters,
      ),
      PopupMenuButton<_BookshelfMenuAction>(
        tooltip: '更多',
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _BookshelfMenuAction.createFolder:
              unawaited(_createFolder());
          }
        },
        itemBuilder: (context) {
          return const [
            PopupMenuItem(
              value: _BookshelfMenuAction.createFolder,
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('新建文件夹'),
              ),
            ),
          ];
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _buildAppBarLeading(),
        title: _buildAppBarTitle(),
        actions: _buildAppBarActions(),
      ),
      body: FutureBuilder<_BookshelfData>(
        future: _bookshelfFuture,
        builder: (context, snapshot) {
          final rawData = snapshot.data ?? const _BookshelfData.empty();
          final data = _prepareData(rawData);

          if (snapshot.connectionState == ConnectionState.waiting &&
              rawData.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && rawData.isEmpty) {
            return _BookshelfMessage(
              icon: Icons.error_outline,
              text: snapshot.error.toString(),
            );
          }

          if (data.isEmpty) {
            if (rawData.isNotEmpty) {
              return const _BookshelfMessage.textIcon(
                iconText: '(･o･;)',
                text: '没有匹配结果',
              );
            }
            return _BookshelfMessage.textIcon(iconText: '(･o･;)', text: '书架为空');
          }

          return RefreshIndicator.adaptive(
            onRefresh: _refreshBookshelf,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.itemCount,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index < data.folders.length) {
                  final folder = data.folders[index];
                  return _BookshelfFolderTile(
                    folder: folder,
                    onOpen: () => _openFolder(folder),
                    onRename: () => _renameFolder(folder),
                    onDelete: () => _deleteFolder(folder),
                  );
                }

                final book = data.books[index - data.folders.length];
                return _BookshelfBookTile(
                  book: book,
                  onOpen: () => _openBook(book),
                  onMove: () => _moveBook(book),
                  onRemove: () => _removeBook(book),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _BookshelfData {
  final List<ComicFolder> folders;
  final List<FavoriteComic> books;

  const _BookshelfData({required this.folders, required this.books});

  const _BookshelfData.empty()
    : folders = const <ComicFolder>[],
      books = const <FavoriteComic>[];

  int get itemCount => folders.length + books.length;

  bool get isEmpty => itemCount == 0;

  bool get isNotEmpty => !isEmpty;
}

class _FolderTarget {
  final String path;
  final String label;

  const _FolderTarget({required this.path, required this.label});
}

class _BookshelfFolderTile extends StatelessWidget {
  final ComicFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _BookshelfFolderTile({
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

class _BookshelfBookTile extends StatelessWidget {
  final FavoriteComic book;
  final VoidCallback onOpen;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  const _BookshelfBookTile({
    required this.book,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final providerName =
        ProviderRegistry().getProvider(book.providerId)?.name ??
        book.providerId;
    final subtitle = book.creator.isEmpty
        ? providerName
        : '$providerName · ${book.creator}';

    return ListTile(
      leading: _BookshelfCover(url: book.coverUrl),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<_BookshelfAction>(
        onSelected: (action) {
          switch (action) {
            case _BookshelfAction.move:
              onMove();
              return;
            case _BookshelfAction.remove:
              onRemove();
              return;
          }
        },
        itemBuilder: (context) {
          return const [
            PopupMenuItem(
              value: _BookshelfAction.move,
              child: ListTile(
                leading: Icon(Icons.drive_file_move_outlined),
                title: Text('移动到'),
              ),
            ),
            PopupMenuItem(
              value: _BookshelfAction.remove,
              child: ListTile(
                leading: Icon(Icons.remove_circle_outline),
                title: Text('移出书架'),
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

enum _BookshelfAction { move, remove }

enum _BookshelfMenuAction { createFolder }

enum _BookshelfSort { updatedDesc, titleAsc }

class _BookshelfFilterState {
  final bool showFolders;
  final bool showBooks;
  final _BookshelfSort sort;

  const _BookshelfFilterState({
    required this.showFolders,
    required this.showBooks,
    required this.sort,
  });
}

class _BookshelfFilterSheet extends StatefulWidget {
  final _BookshelfFilterState initialState;

  const _BookshelfFilterSheet({required this.initialState});

  @override
  State<_BookshelfFilterSheet> createState() => _BookshelfFilterSheetState();
}

class _BookshelfFilterSheetState extends State<_BookshelfFilterSheet> {
  late bool _showFolders;
  late bool _showBooks;
  late _BookshelfSort _sort;

  @override
  void initState() {
    super.initState();
    _showFolders = widget.initialState.showFolders;
    _showBooks = widget.initialState.showBooks;
    _sort = widget.initialState.sort;
  }

  void _submit() {
    Navigator.of(context).pop(
      _BookshelfFilterState(
        showFolders: _showFolders,
        showBooks: _showBooks,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: _BookshelfStyle.filterSheetPadding,
        children: [
          Padding(
            padding: _BookshelfStyle.filterTitlePadding,
            child: Text(
              '筛选',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('显示文件夹'),
            value: _showFolders,
            onChanged: (value) {
              setState(() {
                _showFolders = value;
              });
            },
          ),
          SwitchListTile(
            title: const Text('显示漫画'),
            value: _showBooks,
            onChanged: (value) {
              setState(() {
                _showBooks = value;
              });
            },
          ),
          const Divider(height: 1),
          RadioGroup<_BookshelfSort>(
            groupValue: _sort,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _sort = value;
              });
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<_BookshelfSort>(
                  title: Text('最近更新'),
                  value: _BookshelfSort.updatedDesc,
                ),
                RadioListTile<_BookshelfSort>(
                  title: Text('标题排序'),
                  value: _BookshelfSort.titleAsc,
                ),
              ],
            ),
          ),
          Padding(
            padding: _BookshelfStyle.filterButtonPadding,
            child: FilledButton(onPressed: _submit, child: const Text('完成')),
          ),
        ],
      ),
    );
  }
}

class _BookshelfCover extends StatelessWidget {
  final String url;

  const _BookshelfCover({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = url.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(_BookshelfStyle.coverRadius),
      child: SizedBox(
        width: _BookshelfStyle.coverWidth,
        height: _BookshelfStyle.coverHeight,
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

class _BookshelfMessage extends StatelessWidget {
  final IconData? icon;
  final String? iconText;
  final String text;

  const _BookshelfMessage({required IconData this.icon, required this.text})
    : iconText = null;

  const _BookshelfMessage.textIcon({
    required String this.iconText,
    required this.text,
  }) : icon = null;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (iconText == null)
            Icon(icon, size: _BookshelfStyle.messageIconSize, color: color)
          else
            Text(
              iconText!,
              style: TextStyle(
                color: color,
                fontSize: _BookshelfStyle.messageEmojiSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: _BookshelfStyle.messageGap),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
