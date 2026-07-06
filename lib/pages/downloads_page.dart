import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comic.dart';
import '../services/download_service.dart';
import 'reader_page.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late Future<List<DownloadTaskView>> _tasksFuture;
  late Future<List<DownloadedComic>> _downloadedFuture;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _loadTasks();
    _downloadedFuture = _loadDownloaded();
    DownloadService.instance.revision.addListener(_handleDownloadsChanged);
  }

  @override
  void dispose() {
    DownloadService.instance.revision.removeListener(_handleDownloadsChanged);
    super.dispose();
  }

  Future<List<DownloadTaskView>> _loadTasks() {
    return DownloadService.instance.getTasks();
  }

  Future<List<DownloadedComic>> _loadDownloaded() {
    return DownloadService.instance.getDownloadedComics();
  }

  Future<void> _refreshAll() {
    final tasksFuture = _loadTasks();
    final downloadedFuture = _loadDownloaded();
    setState(() {
      _tasksFuture = tasksFuture;
      _downloadedFuture = downloadedFuture;
    });
    return Future.wait<Object>([
      tasksFuture,
      downloadedFuture,
    ]).then<void>((_) {}, onError: (_) {});
  }

  void _handleDownloadsChanged() {
    if (!mounted) return;
    unawaited(_refreshAll());
  }

  Future<void> _handleTaskAction(
    _DownloadTaskAction action,
    DownloadTaskView task,
  ) async {
    switch (action) {
      case _DownloadTaskAction.cancel:
        await DownloadService.instance.cancelTask(task.id);
        _showMessage('已请求取消');
        return;
      case _DownloadTaskAction.retry:
        await DownloadService.instance.retryTask(task.id);
        _showMessage('已重新加入队列');
        return;
      case _DownloadTaskAction.remove:
        await DownloadService.instance.removeTask(task.id);
        _showMessage('已移除任务');
        return;
    }
  }

  Future<void> _openDownloaded(DownloadedComic downloaded) async {
    if (downloaded.chapters.isEmpty) {
      _showMessage('暂无本地章节');
      return;
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ColoredBox(
            color: Colors.black,
            child: ReaderPage(
              providerId: downloaded.providerId,
              comic: downloaded.toComic(),
              chapters: downloaded.chapters,
              initialChapterIndex: 0,
              snapshotLoader:
                  ({
                    required Comic comic,
                    required Chapter chapter,
                    required List<Chapter> chapters,
                  }) {
                    return DownloadService.instance
                        .getDownloadedChapterSnapshot(
                          download: downloaded,
                          chapter: chapter,
                        );
                  },
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    final theme = Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: theme.brightness,
        systemNavigationBarColor: theme.colorScheme.surface,
        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  Future<void> _deleteDownloaded(DownloadedComic downloaded) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除下载'),
          content: Text('确定要删除《${downloaded.title}》的下载记录和本地文件吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await DownloadService.instance.deleteDownloadedComic(downloaded);
      if (!mounted) return;
      _showMessage('已删除下载');
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('下载'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '任务'),
              Tab(text: '已下载'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DownloadTaskList(
              future: _tasksFuture,
              onRefresh: _refreshAll,
              onAction: _handleTaskAction,
            ),
            _DownloadedList(
              future: _downloadedFuture,
              onRefresh: _refreshAll,
              onOpen: _openDownloaded,
              onDelete: _deleteDownloaded,
            ),
          ],
        ),
      ),
    );
  }
}

enum _DownloadTaskAction { cancel, retry, remove }

enum _DownloadedAction { open, delete }

class _DownloadTaskList extends StatelessWidget {
  final Future<List<DownloadTaskView>> future;
  final RefreshCallback onRefresh;
  final Future<void> Function(_DownloadTaskAction action, DownloadTaskView task)
  onAction;

  const _DownloadTaskList({
    required this.future,
    required this.onRefresh,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DownloadTaskView>>(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <DownloadTaskView>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError && items.isEmpty) {
          return _DownloadMessage(
            icon: Icons.error_outline,
            text: snapshot.error.toString(),
          );
        }

        if (items.isEmpty) {
          return const _DownloadMessage(
            icon: Icons.download_outlined,
            text: '暂无下载任务',
          );
        }

        return RefreshIndicator.adaptive(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: _DownloadStatusIcon(item: item),
                title: Text(
                  item.comicName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.status.isEmpty ? '等待下载' : item.status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<_DownloadTaskAction>(
                  onSelected: (action) => unawaited(onAction(action, item)),
                  itemBuilder: (context) {
                    return [
                      if (!item.isCompleted)
                        const PopupMenuItem(
                          value: _DownloadTaskAction.cancel,
                          child: ListTile(
                            leading: Icon(Icons.close),
                            title: Text('取消'),
                          ),
                        ),
                      if (item.isFailed || item.isCancelled)
                        const PopupMenuItem(
                          value: _DownloadTaskAction.retry,
                          child: ListTile(
                            leading: Icon(Icons.refresh),
                            title: Text('重试'),
                          ),
                        ),
                      if (item.isCompleted)
                        const PopupMenuItem(
                          value: _DownloadTaskAction.remove,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('移除记录'),
                          ),
                        ),
                    ];
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DownloadedList extends StatelessWidget {
  final Future<List<DownloadedComic>> future;
  final RefreshCallback onRefresh;
  final Future<void> Function(DownloadedComic downloaded) onOpen;
  final Future<void> Function(DownloadedComic downloaded) onDelete;

  const _DownloadedList({
    required this.future,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DownloadedComic>>(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <DownloadedComic>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError && items.isEmpty) {
          return _DownloadMessage(
            icon: Icons.error_outline,
            text: snapshot.error.toString(),
          );
        }

        if (items.isEmpty) {
          return const _DownloadMessage(
            icon: Icons.inventory_2_outlined,
            text: '暂无已下载漫画',
          );
        }

        return RefreshIndicator.adaptive(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final subtitle = item.creator.isEmpty
                  ? '${item.chapters.length} 章'
                  : '${item.creator} · ${item.chapters.length} 章';
              return ListTile(
                leading: _DownloadedCover(url: item.coverUrl),
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
                trailing: PopupMenuButton<_DownloadedAction>(
                  onSelected: (action) {
                    switch (action) {
                      case _DownloadedAction.open:
                        unawaited(onOpen(item));
                        return;
                      case _DownloadedAction.delete:
                        unawaited(onDelete(item));
                        return;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _DownloadedAction.open,
                      child: ListTile(
                        leading: Icon(Icons.menu_book_outlined),
                        title: Text('阅读'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _DownloadedAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('删除下载'),
                      ),
                    ),
                  ],
                ),
                onTap: () => unawaited(onOpen(item)),
              );
            },
          ),
        );
      },
    );
  }
}

class _DownloadStatusIcon extends StatelessWidget {
  final DownloadTaskView item;

  const _DownloadStatusIcon({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isDownloading) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (item.isFailed) {
      return Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      );
    }

    if (item.isCancelled) {
      return Icon(
        Icons.cancel_outlined,
        color: Theme.of(context).colorScheme.outline,
      );
    }

    if (item.isCompleted) {
      return Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return const Icon(Icons.schedule);
  }
}

class _DownloadedCover extends StatelessWidget {
  final String url;

  const _DownloadedCover({required this.url});

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

class _DownloadMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DownloadMessage({required this.icon, required this.text});

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
