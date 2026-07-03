import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/comic.dart';
import '../../providers/provider_registry.dart';
import '../../services/reading_progress_service.dart';
import '../reader_page.dart';

class HistoryTab extends StatefulWidget {
  final int refreshVersion;

  const HistoryTab({super.key, this.refreshVersion = 0});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  late Future<List<ReadingProgress>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  @override
  void didUpdateWidget(covariant HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _refreshHistory();
    }
  }

  Future<List<ReadingProgress>> _loadHistory() {
    return ReadingProgressService.instance.getAllProgress();
  }

  Future<void> _refreshHistory() {
    final future = _loadHistory();
    setState(() {
      _historyFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  Future<void> _openHistory(ReadingProgress progress) async {
    if (ProviderRegistry().getProvider(progress.providerId) == null) {
      _showMessage('未找到数据源: ${progress.providerId}');
      return;
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ColoredBox(
            color: Colors.black,
            child: _HistoryReaderEntry(progress: progress),
          );
        },
      ),
    );

    if (!mounted) return;
    final theme = Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: theme.colorScheme.surface,
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ));
    await _refreshHistory();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: FutureBuilder<List<ReadingProgress>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ReadingProgress>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && items.isEmpty) {
            return _HistoryMessage(
              icon: Icons.error_outline,
              text: snapshot.error.toString(),
            );
          }

          if (items.isEmpty) {
            return const _HistoryMessage(
              icon: Icons.history_outlined,
              text: '暂无浏览历史',
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: _refreshHistory,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: _HistoryCover(url: item.coverUrl),
                  title: Text(
                    item.comicTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.chapterTitle} · 第 ${item.pageIndex + 1} / ${item.pageCount} 页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openHistory(item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryReaderEntry extends StatefulWidget {
  final ReadingProgress progress;

  const _HistoryReaderEntry({required this.progress});

  @override
  State<_HistoryReaderEntry> createState() => _HistoryReaderEntryState();
}

class _HistoryReaderEntryState extends State<_HistoryReaderEntry> {
  late Future<_HistoryReaderData> _readerFuture;

  @override
  void initState() {
    super.initState();
    _readerFuture = _loadReaderData();
  }

  Future<_HistoryReaderData> _loadReaderData() async {
    final progress = widget.progress;
    final provider = ProviderRegistry().getProvider(progress.providerId);
    if (provider == null) {
      throw StateError('未找到数据源: ${progress.providerId}');
    }

    final results = await Future.wait<Object>([
      provider.getComicDetail(progress.comicId),
      provider.getChapters(progress.comicId),
    ]);
    final comic = results[0] as Comic;
    final chapters = results[1] as List<Chapter>;
    if (chapters.isEmpty) {
      throw StateError('暂无章节');
    }

    final matchedIndex = chapters.indexWhere(
      (chapter) => chapter.id == progress.chapterId,
    );
    final chapterIndex = matchedIndex >= 0
        ? matchedIndex
        : progress.chapterIndex.clamp(0, chapters.length - 1).toInt();
    final maxPageIndex = progress.pageCount > 0 ? progress.pageCount - 1 : 0;
    final pageIndex = progress.pageIndex.clamp(0, maxPageIndex).toInt();

    return _HistoryReaderData(
      comic: comic,
      chapters: chapters,
      chapterIndex: chapterIndex,
      pageIndex: pageIndex,
    );
  }

  void _retry() {
    setState(() {
      _readerFuture = _loadReaderData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HistoryReaderData>(
      future: _readerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final data = snapshot.requireData;
          return ReaderPage(
            providerId: widget.progress.providerId,
            comic: data.comic,
            chapters: data.chapters,
            initialChapterIndex: data.chapterIndex,
            initialPageIndex: data.pageIndex,
          );
        }

        if (snapshot.hasError) {
          return _HistoryReaderErrorView(
            message: snapshot.error.toString(),
            onRetry: _retry,
          );
        }

        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
    );
  }
}

class _HistoryReaderData {
  final Comic comic;
  final List<Chapter> chapters;
  final int chapterIndex;
  final int pageIndex;

  const _HistoryReaderData({
    required this.comic,
    required this.chapters,
    required this.chapterIndex,
    required this.pageIndex,
  });
}

class _HistoryReaderErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _HistoryReaderErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('返回'),
                  ),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCover extends StatelessWidget {
  final String url;

  const _HistoryCover({required this.url});

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

class _HistoryMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HistoryMessage({required this.icon, required this.text});

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
