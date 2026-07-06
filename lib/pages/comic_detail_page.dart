import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comic.dart';
import '../providers/provider_registry.dart';
import '../services/comic_detail_cache_service.dart';
import '../services/favorite_service.dart';
import '../services/reading_progress_service.dart';
import 'download_chapter_selection_page.dart';
import 'reader_page.dart';

class ComicDetailPage extends StatefulWidget {
  final String providerId;
  final Comic initialComic;

  const ComicDetailPage({
    super.key,
    required this.providerId,
    required this.initialComic,
  });

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Future<_ComicDetailData> _detailFuture;
  late Future<ReadingProgress?> _progressFuture;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  bool _isAppBarOpaque = false;
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;
  bool _isDownloadLoading = false;

  String get _providerName =>
      ProviderRegistry().getProvider(widget.providerId)?.name ??
      widget.providerId;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
    _progressFuture = _loadProgress();
    unawaited(_loadFavoriteStatus());
  }

  Future<_ComicDetailData> _loadDetail({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await ComicDetailCacheService.instance.read(
        widget.providerId,
        widget.initialComic.id,
      );
      if (cached != null) {
        return _ComicDetailData(
          comic: cached.comic,
          chapters: cached.chapters,
        );
      }
    }

    final provider = ProviderRegistry().getProvider(widget.providerId);
    if (provider == null) {
      throw StateError('未找到数据源: ${widget.providerId}');
    }

    final results = await Future.wait<Object>([
      provider.getComicDetail(widget.initialComic.id),
      provider.getChapters(widget.initialComic.id),
    ]);

    final data = _ComicDetailData(
      comic: results[0] as Comic,
      chapters: results[1] as List<Chapter>,
    );
    unawaited(
      ComicDetailCacheService.instance.write(
        providerId: widget.providerId,
        comicId: widget.initialComic.id,
        comic: data.comic,
        chapters: data.chapters,
      ).catchError((_) {}),
    );
    return data;
  }

  Future<void> _refreshDetail() {
    final future = _loadDetail(forceRefresh: true);
    setState(() {
      _detailFuture = future;
      _progressFuture = _loadProgress();
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  Future<ReadingProgress?> _loadProgress() {
    return ReadingProgressService.instance.getProgress(
      widget.providerId,
      widget.initialComic.id,
    );
  }

  Future<void> _loadFavoriteStatus() async {
    final favorite = await FavoriteService.instance.isFavorite(
      widget.providerId,
      widget.initialComic.id,
    );
    if (!mounted) return;
    setState(() {
      _isFavorite = favorite;
    });
  }

  void _showRefreshIndicator() {
    final refreshIndicator = _refreshIndicatorKey.currentState;
    if (refreshIndicator == null) {
      _refreshDetail();
      return;
    }
    refreshIndicator.show();
  }

  void _showPendingMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;

    setState(() {
      _isFavoriteLoading = true;
    });

    try {
      final data = await _detailFuture;
      final favorite = await FavoriteService.instance.toggleFavorite(
        providerId: widget.providerId,
        comic: data.comic,
      );
      if (!mounted) return;
      setState(() {
        _isFavorite = favorite;
      });
      _showPendingMessage(favorite ? '已添加收藏' : '已取消收藏');
    } catch (error) {
      if (!mounted) return;
      _showPendingMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isFavoriteLoading = false;
        });
      }
    }
  }

  Future<void> _enqueueDownload() async {
    if (_isDownloadLoading) return;

    setState(() {
      _isDownloadLoading = true;
    });

    try {
      final data = await _detailFuture;
      if (data.chapters.isEmpty) {
        throw StateError('暂无可下载章节');
      }
      if (!mounted) return;

      final enqueued = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => DownloadChapterSelectionPage(
            providerId: widget.providerId,
            comic: data.comic,
            chapters: data.chapters,
          ),
        ),
      );
      if (!mounted) return;
      if (enqueued == true) {
        _showPendingMessage('已加入下载队列');
      }
    } catch (error) {
      if (!mounted) return;
      _showPendingMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadLoading = false;
        });
      }
    }
  }

  void _openReader(
    Comic comic,
    List<Chapter> chapters,
    int chapterIndex, {
    int initialPageIndex = 0,
  }) {
    if (chapters.isEmpty) return;

    final returnSystemUiStyle = _detailSystemUiOverlayStyle(
      Theme.of(context),
      _isAppBarOpaque,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    Navigator.of(context)
        .push(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) {
              return ColoredBox(
                color: Colors.black,
                child: ReaderPage(
                  providerId: widget.providerId,
                  comic: comic,
                  chapters: chapters,
                  initialChapterIndex: chapterIndex,
                  initialPageIndex: initialPageIndex,
                ),
              );
            },
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _progressFuture = _loadProgress();
          });
          SystemChrome.setSystemUIOverlayStyle(returnSystemUiStyle);
        });
  }

  SystemUiOverlayStyle _detailSystemUiOverlayStyle(
    ThemeData theme,
    bool isAppBarOpaque,
  ) {
    final appBarBackground = isAppBarOpaque
        ? theme.colorScheme.surface
        : Colors.transparent;
    return SystemUiOverlayStyle(
      statusBarColor: appBarBackground,
      statusBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: theme.colorScheme.surface,
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  void _openReaderFromProgress(
    _ComicDetailData data,
    ReadingProgress? progress,
  ) {
    var chapterIndex = 0;
    var pageIndex = 0;

    if (progress != null && progress.canContinue) {
      final matchedIndex = data.chapters.indexWhere(
        (chapter) => chapter.id == progress.chapterId,
      );
      chapterIndex = matchedIndex >= 0
          ? matchedIndex
          : progress.chapterIndex.clamp(0, data.chapters.length - 1).toInt();
      pageIndex = progress.pageIndex.clamp(0, progress.pageCount - 1).toInt();
    }

    _openReader(
      data.comic,
      data.chapters,
      chapterIndex,
      initialPageIndex: pageIndex,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final shouldBeOpaque = notification.metrics.pixels > 0;
    if (shouldBeOpaque != _isAppBarOpaque) {
      setState(() {
        _isAppBarOpaque = shouldBeOpaque;
      });
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pageBackground = theme.colorScheme.surface;
    final appBarBackground = _isAppBarOpaque
        ? pageBackground
        : Colors.transparent;

    return Scaffold(
      backgroundColor: pageBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: appBarBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: appBarBackground,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness,
        ),
        actions: [
          IconButton(
            tooltip: '下载',
            onPressed: _isDownloadLoading
                ? null
                : () => unawaited(_enqueueDownload()),
            icon: _isDownloadLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
          PopupMenuButton<_DetailMenuAction>(
            onSelected: (action) {
              switch (action) {
                case _DetailMenuAction.refresh:
                  _showRefreshIndicator();
                  return;
                case _DetailMenuAction.addFavorite:
                  unawaited(_toggleFavorite());
                  return;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _DetailMenuAction.refresh,
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('刷新'),
                ),
              ),
              PopupMenuItem(
                value: _DetailMenuAction.addFavorite,
                enabled: !_isFavoriteLoading,
                child: ListTile(
                  leading: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  title: Text(_isFavorite ? '取消收藏' : '添加收藏'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _StartReadingFab(
        detailFuture: _detailFuture,
        progressFuture: _progressFuture,
        isExtended: !_isAppBarOpaque,
        onStartReading: _openReaderFromProgress,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: FutureBuilder<_ComicDetailData>(
          future: _detailFuture,
          builder: (context, snapshot) {
            final currentData = snapshot.data;

            if (snapshot.connectionState == ConnectionState.waiting &&
                currentData == null) {
              return _DetailBody(
                comic: widget.initialComic,
                providerName: _providerName,
                chapters: const [],
                refreshIndicatorKey: _refreshIndicatorKey,
                onRefresh: _refreshDetail,
                onChapterSelected: (_, _) {},
                isLoading: true,
              );
            }

            if (snapshot.hasError && currentData == null) {
              return _ErrorView(
                message: snapshot.error.toString(),
                onRetry: _showRefreshIndicator,
              );
            }

            final data = currentData ?? snapshot.requireData;
            return _DetailBody(
              comic: data.comic,
              providerName: _providerName,
              chapters: data.chapters,
              refreshIndicatorKey: _refreshIndicatorKey,
              onRefresh: _refreshDetail,
              onChapterSelected: (_, index) =>
                  _openReader(data.comic, data.chapters, index),
            );
          },
        ),
      ),
    );
  }
}

enum _DetailMenuAction { refresh, addFavorite }

class _StartReadingFab extends StatelessWidget {
  final Future<_ComicDetailData> detailFuture;
  final Future<ReadingProgress?> progressFuture;
  final bool isExtended;
  final void Function(_ComicDetailData data, ReadingProgress? progress)
  onStartReading;

  const _StartReadingFab({
    required this.detailFuture,
    required this.progressFuture,
    required this.isExtended,
    required this.onStartReading,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ComicDetailData>(
      future: detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data;
        final hasChapters = data != null && data.chapters.isNotEmpty;
        if (snapshot.hasError || (data != null && data.chapters.isEmpty)) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<ReadingProgress?>(
          future: progressFuture,
          builder: (context, progressSnapshot) {
            final progress = progressSnapshot.data;
            final hasProgress = switch (progress) {
              ReadingProgress(canContinue: true) => true,
              _ => false,
            };
            final isProgressLoading =
                progressSnapshot.connectionState == ConnectionState.waiting &&
                !progressSnapshot.hasData;
            VoidCallback? onPressed;
            if (hasChapters && !isProgressLoading) {
              onPressed = () => onStartReading(data, progress);
            }

            return FloatingActionButton.extended(
              heroTag: null,
              isExtended: isExtended,
              tooltip: hasProgress ? '继续阅读' : '开始阅读',
              onPressed: onPressed,
              icon: Icon(
                hasProgress ? Icons.history_rounded : Icons.play_arrow,
              ),
              label: Text(hasProgress ? '继续' : '开始'),
            );
          },
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Comic comic;
  final String providerName;
  final List<Chapter> chapters;
  final GlobalKey<RefreshIndicatorState> refreshIndicatorKey;
  final RefreshCallback onRefresh;
  final void Function(Chapter chapter, int index) onChapterSelected;
  final bool isLoading;

  const _DetailBody({
    required this.comic,
    required this.providerName,
    required this.chapters,
    required this.refreshIndicatorKey,
    required this.onRefresh,
    required this.onChapterSelected,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final refreshTopOffset = MediaQuery.paddingOf(context).top;

    return RefreshIndicator.adaptive(
      key: refreshIndicatorKey,
      edgeOffset: refreshTopOffset,
      displacement: refreshTopOffset,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _InfoHeader(comic: comic, providerName: providerName),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (comic.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('标签', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: comic.tags.map((tag) {
                      return Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          if (comic.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _DescriptionSection(description: comic.description),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '共 ${chapters.length} 章',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (chapters.isEmpty && !isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text(
                '暂无章节',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            )
          else
            ...chapters.asMap().entries.map((entry) {
              final index = entry.key;
              final chapter = entry.value;
              return _ChapterTile(
                title: chapters.length == 1 ? '单章节' : chapter.name,
                onTap: () => onChapterSelected(chapter, index),
              );
            }),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  final Comic comic;
  final String providerName;

  const _InfoHeader({required this.comic, required this.providerName});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topInset, 16, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverImage(url: comic.coverUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoLine(icon: Icons.source_outlined, text: providerName),
                  if (comic.author.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoLine(
                      icon: Icons.person_outline,
                      text: comic.author.join(' / '),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String url;

  const _CoverImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 112,
        height: 160,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image)),
            );
          },
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _DescriptionSection extends StatelessWidget {
  final String description;

  const _DescriptionSection({required this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('简介', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ChapterTile({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicDetailData {
  final Comic comic;
  final List<Chapter> chapters;

  const _ComicDetailData({required this.comic, required this.chapters});
}
