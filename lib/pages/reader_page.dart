import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic.dart';
import '../providers/provider_registry.dart';

class ReaderPage extends StatefulWidget {
  final String providerId;
  final Comic comic;
  final List<Chapter> chapters;
  final int initialChapterIndex;

  const ReaderPage({
    super.key,
    required this.providerId,
    required this.comic,
    required this.chapters,
    required this.initialChapterIndex,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int _chapterIndex;
  late Future<_ReaderChapterData> _chapterFuture;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.chapters.length - 1;
    _chapterIndex = lastIndex < 0
        ? 0
        : widget.initialChapterIndex.clamp(0, lastIndex).toInt();
    _chapterFuture = _loadChapter(_chapterIndex);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _chapterTitle(int index) {
    if (widget.chapters.isEmpty) return '暂无章节';
    final chapter = widget.chapters[index];
    return widget.chapters.length == 1 ? '单章节' : chapter.name;
  }

  Future<_ReaderChapterData> _loadChapter(int index) async {
    if (widget.chapters.isEmpty) {
      throw StateError('暂无章节');
    }

    final provider = ProviderRegistry().getProvider(widget.providerId);
    if (provider == null) {
      throw StateError('未找到数据源: ${widget.providerId}');
    }

    final chapter = widget.chapters[index];
    final images = (await provider.getChapterImages(chapter.id))
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return _ReaderChapterData(images: images);
  }

  Future<void> _reloadChapter() {
    final future = _loadChapter(_chapterIndex);
    setState(() {
      _chapterFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= widget.chapters.length || index == _chapterIndex) {
      return;
    }

    setState(() {
      _chapterIndex = index;
      _chapterFuture = _loadChapter(index);
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _showChapterPicker() async {
    if (widget.chapters.isEmpty) return;

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, sheetController) {
            return SafeArea(
              child: ListView.separated(
                controller: sheetController,
                itemCount: widget.chapters.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final isCurrent = index == _chapterIndex;
                  return ListTile(
                    selected: isCurrent,
                    leading: isCurrent
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.menu_book_outlined),
                    title: Text(
                      _chapterTitle(index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '第 ${index + 1} / ${widget.chapters.length} 章',
                    ),
                    onTap: () => Navigator.of(context).pop(index),
                  );
                },
              ),
            );
          },
        );
      },
    );

    if (!mounted || selectedIndex == null) return;
    _goToChapter(selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    final hasPrevious = _chapterIndex > 0;
    final hasNext = _chapterIndex < widget.chapters.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.comic.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _reloadChapter,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_ReaderChapterData>(
        key: ValueKey(_chapterIndex),
        future: _chapterFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && !snapshot.hasData) {
            return _ReaderErrorView(
              message: snapshot.error.toString(),
              onRetry: _reloadChapter,
            );
          }

          final data = snapshot.requireData;
          if (data.images.isEmpty) {
            return _ReaderEmptyView(onRetry: _reloadChapter);
          }

          return _ReaderImageList(
            images: data.images,
            controller: _scrollController,
            onRetry: _reloadChapter,
          );
        },
      ),
      bottomNavigationBar: _ReaderBottomBar(
        chapterTitle: _chapterTitle(_chapterIndex),
        chapterIndex: _chapterIndex,
        chapterCount: widget.chapters.length,
        hasPrevious: hasPrevious,
        hasNext: hasNext,
        onPrevious: () => _goToChapter(_chapterIndex - 1),
        onChapterPicker: _showChapterPicker,
        onNext: () => _goToChapter(_chapterIndex + 1),
      ),
    );
  }
}

class _ReaderImageList extends StatelessWidget {
  final List<String> images;
  final ScrollController controller;
  final VoidCallback onRetry;

  const _ReaderImageList({
    required this.images,
    required this.controller,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      cacheExtent: MediaQuery.sizeOf(context).height * 2,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return _ReaderImage(
          url: images[index],
          pageNumber: index + 1,
          pageCount: images.length,
          onRetry: onRetry,
        );
      },
    );
  }
}

class _ReaderImage extends StatelessWidget {
  final String url;
  final int pageNumber;
  final int pageCount;
  final VoidCallback onRetry;

  const _ReaderImage({
    required this.url,
    required this.pageNumber,
    required this.pageCount,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: '第 $pageNumber 页，共 $pageCount 页',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '$pageNumber / $pageCount',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            progressIndicatorBuilder: (context, url, progress) {
              return SizedBox(
                height: 240,
                child: Center(
                  child: CircularProgressIndicator(value: progress.progress),
                ),
              );
            },
            errorWidget: (context, url, error) {
              return _ImageErrorView(onRetry: onRetry);
            },
          ),
        ],
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onChapterPicker;
  final VoidCallback onNext;

  const _ReaderBottomBar({
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onChapterPicker,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              tooltip: '上一章',
              onPressed: hasPrevious ? onPrevious : null,
              icon: const Icon(Icons.skip_previous),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: chapterCount > 0 ? onChapterPicker : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chapterCount == 0
                            ? '暂无章节'
                            : '${chapterIndex + 1} / $chapterCount',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '章节列表',
              onPressed: chapterCount > 0 ? onChapterPicker : null,
              icon: const Icon(Icons.format_list_bulleted),
            ),
            IconButton(
              tooltip: '下一章',
              onPressed: hasNext ? onNext : null,
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderEmptyView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReaderEmptyView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('暂无图片'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
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

class _ReaderErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReaderErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
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

class _ImageErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ImageErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 240,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('图片加载失败'),
      ),
    );
  }
}

class _ReaderChapterData {
  final List<String> images;

  const _ReaderChapterData({required this.images});
}
