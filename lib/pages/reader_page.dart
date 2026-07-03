import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comic.dart';
import '../providers/provider_registry.dart';
import '../services/reading_progress_service.dart';

const _readerSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.black,
  systemNavigationBarColor: Colors.black,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
);

class ReaderPage extends StatefulWidget {
  final String providerId;
  final Comic comic;
  final List<Chapter> chapters;
  final int initialChapterIndex;
  final double initialScrollProgress;

  const ReaderPage({
    super.key,
    required this.providerId,
    required this.comic,
    required this.chapters,
    required this.initialChapterIndex,
    this.initialScrollProgress = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int _chapterIndex;
  late Future<_ReaderChapterData> _chapterFuture;
  final ScrollController _scrollController = ScrollController();
  Timer? _progressSaveTimer;
  bool _isSeeking = false;
  bool _isMenuVisible = false;
  double _scrollProgress = 0;
  bool _shouldRestoreInitialProgress = false;
  bool _isRestoreScheduled = false;
  int _restoreAttempts = 0;

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.chapters.length - 1;
    _chapterIndex = lastIndex < 0
        ? 0
        : widget.initialChapterIndex.clamp(0, lastIndex).toInt();
    _chapterFuture = _loadChapter(_chapterIndex);
    _scrollProgress = widget.initialScrollProgress.clamp(0.0, 1.0).toDouble();
    _shouldRestoreInitialProgress = _scrollProgress > 0;
    _scrollController.addListener(_handleScrollChanged);
    _applySystemUiVisibility(false);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    unawaited(_saveProgressNow());
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _setMenuVisible(bool visible) {
    if (_isMenuVisible == visible) {
      _applySystemUiVisibility(visible);
      return;
    }

    setState(() {
      _isMenuVisible = visible;
    });

    _applySystemUiVisibility(visible);
  }

  void _applySystemUiVisibility(bool visible) {
    SystemChrome.setSystemUIOverlayStyle(_readerSystemOverlayStyle);
    if (visible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _toggleMenu() {
    _setMenuVisible(!_isMenuVisible);
  }

  void _handleScrollChanged() {
    if (_isSeeking) return;

    final progress = _currentScrollProgress();
    if ((progress - _scrollProgress).abs() > 0.002 && mounted) {
      setState(() {
        _scrollProgress = progress;
      });
    }

    _scheduleProgressSave();
  }

  bool _handleReaderScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || !_isMenuVisible) {
      return false;
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _setMenuVisible(false);
    }

    return false;
  }

  double _currentScrollProgress() {
    if (!_scrollController.hasClients) return _scrollProgress;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return 0;
    return (position.pixels / position.maxScrollExtent)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      unawaited(_saveProgressNow());
    });
  }

  Future<void> _saveProgressNow() {
    if (widget.chapters.isEmpty) return Future<void>.value();

    final chapter = widget.chapters[_chapterIndex];
    return ReadingProgressService.instance.saveProgress(
      ReadingProgress(
        providerId: widget.providerId,
        comicId: widget.comic.id,
        comicTitle: widget.comic.title,
        coverUrl: widget.comic.coverUrl,
        chapterId: chapter.id,
        chapterTitle: _chapterTitle(_chapterIndex),
        chapterIndex: _chapterIndex,
        chapterCount: widget.chapters.length,
        scrollProgress: _currentScrollProgress(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _scheduleInitialProgressRestore() {
    if (!_shouldRestoreInitialProgress || _isRestoreScheduled) return;

    _isRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isRestoreScheduled = false;
      _restoreInitialProgress();
    });
  }

  void _restoreInitialProgress() {
    if (!mounted || !_shouldRestoreInitialProgress) return;
    if (!_scrollController.hasClients) {
      _retryInitialProgressRestore();
      return;
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      _retryInitialProgressRestore();
      return;
    }

    _shouldRestoreInitialProgress = false;
    final offset =
        position.maxScrollExtent * _scrollProgress.clamp(0.0, 1.0).toDouble();
    _scrollController.jumpTo(
      offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    _scheduleProgressSave();
  }

  void _retryInitialProgressRestore() {
    if (_restoreAttempts >= 8) {
      _shouldRestoreInitialProgress = false;
      return;
    }

    _restoreAttempts += 1;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _scheduleInitialProgressRestore();
    });
  }

  void _handleProgressChangeStart(double value) {
    _progressSaveTimer?.cancel();
    _isSeeking = true;
  }

  void _handleProgressChanged(double value) {
    setState(() {
      _scrollProgress = value.clamp(0.0, 1.0).toDouble();
    });
  }

  void _handleProgressChangeEnd(double value) {
    final progress = value.clamp(0.0, 1.0).toDouble();
    _isSeeking = false;

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final target = position.maxScrollExtent * progress;
      _scrollController.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }

    setState(() {
      _scrollProgress = progress;
    });
    unawaited(_saveProgressNow());
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

    _progressSaveTimer?.cancel();
    setState(() {
      _chapterIndex = index;
      _chapterFuture = _loadChapter(index);
      _scrollProgress = 0;
      _shouldRestoreInitialProgress = false;
      _restoreAttempts = 0;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    unawaited(_saveProgressNow());
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _readerSystemOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleMenu,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleReaderScrollNotification,
                  child: FutureBuilder<_ReaderChapterData>(
                    key: ValueKey(_chapterIndex),
                    future: _chapterFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
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

                      _scheduleInitialProgressRestore();
                      return _ReaderImageList(
                        images: data.images,
                        controller: _scrollController,
                        onRetry: _reloadChapter,
                      );
                    },
                  ),
                ),
              ),
            ),
            _ReaderTopBar(
              title: widget.comic.title,
              chapterTitle: _chapterTitle(_chapterIndex),
              isVisible: _isMenuVisible,
              onRefresh: _reloadChapter,
            ),
            _ReaderBottomOverlay(
              isVisible: _isMenuVisible,
              child: _ReaderBottomBar(
                chapterIndex: _chapterIndex,
                chapterCount: widget.chapters.length,
                progress: _scrollProgress,
                hasPrevious: hasPrevious,
                hasNext: hasNext,
                onProgressChangeStart: _handleProgressChangeStart,
                onProgressChanged: _handleProgressChanged,
                onProgressChangeEnd: _handleProgressChangeEnd,
                onPrevious: () => _goToChapter(_chapterIndex - 1),
                onChapterPicker: _showChapterPicker,
                onNext: () => _goToChapter(_chapterIndex + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  final String title;
  final String chapterTitle;
  final bool isVisible;
  final VoidCallback onRefresh;

  const _ReaderTopBar({
    required this.title,
    required this.chapterTitle,
    required this.isVisible,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          offset: isVisible ? Offset.zero : const Offset(0, -1),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: colorScheme.surface.withValues(alpha: 0.78),
                elevation: isVisible ? 2 : 0,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        const BackButton(),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                chapterTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomOverlay extends StatelessWidget {
  final bool isVisible;
  final Widget child;

  const _ReaderBottomOverlay({required this.isVisible, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          offset: isVisible ? Offset.zero : const Offset(0, 1),
          child: SafeArea(top: false, child: child),
        ),
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
    return Semantics(
      label: '第 $pageNumber 页，共 $pageCount 页',
      child: CachedNetworkImage(
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
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  final int chapterIndex;
  final int chapterCount;
  final double progress;
  final bool hasPrevious;
  final bool hasNext;
  final ValueChanged<double> onProgressChangeStart;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onProgressChangeEnd;
  final VoidCallback onPrevious;
  final VoidCallback onChapterPicker;
  final VoidCallback onNext;

  const _ReaderBottomBar({
    required this.chapterIndex,
    required this.chapterCount,
    required this.progress,
    required this.hasPrevious,
    required this.hasNext,
    required this.onProgressChangeStart,
    required this.onProgressChanged,
    required this.onProgressChangeEnd,
    required this.onPrevious,
    required this.onChapterPicker,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0.78),
          elevation: 3,
          child: SizedBox(
            height: 78,
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0).toDouble(),
                            onChangeStart: onProgressChangeStart,
                            onChanged: onProgressChanged,
                            onChangeEnd: onProgressChangeEnd,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(progress * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      _ReaderBottomIconButton(
                        tooltip: '上一章',
                        onPressed: hasPrevious ? onPrevious : null,
                        icon: Icons.skip_previous,
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: chapterCount > 0 ? onChapterPicker : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Center(
                              child: Text(
                                chapterCount == 0
                                    ? '暂无章节'
                                    : '${chapterIndex + 1} / $chapterCount',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _ReaderBottomIconButton(
                        tooltip: '章节列表',
                        onPressed: chapterCount > 0 ? onChapterPicker : null,
                        icon: Icons.format_list_bulleted,
                      ),
                      _ReaderBottomIconButton(
                        tooltip: '下一章',
                        onPressed: hasNext ? onNext : null,
                        icon: Icons.skip_next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  const _ReaderBottomIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class _ReaderEmptyView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReaderEmptyView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const foregroundColor = Colors.white;
    const secondaryColor = Colors.white70;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: secondaryColor,
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无图片',
              style: TextStyle(color: foregroundColor),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              style: OutlinedButton.styleFrom(foregroundColor: secondaryColor),
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
    const foregroundColor = Colors.white;

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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: foregroundColor),
            ),
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
