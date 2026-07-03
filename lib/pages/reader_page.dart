import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../models/comic.dart';
import '../models/reader_snapshot.dart';
import '../providers/provider_registry.dart';
import '../reader/reader_cubit.dart';
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
  final int initialPageIndex;

  const ReaderPage({
    super.key,
    required this.providerId,
    required this.comic,
    required this.chapters,
    required this.initialChapterIndex,
    this.initialPageIndex = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _estimatedPageAspectRatio = 1.42;

  late int _chapterIndex;
  late Future<ReaderChapterSnapshot> _chapterFuture;
  late final ReaderCubit _readerCubit;
  late final ListObserverController _observerController;
  final ScrollController _scrollController = ScrollController();
  final Map<String, Size> _imageSizes = {};
  List<GlobalKey> _pageKeys = const [];
  ReaderChapterSnapshot? _chapterSnapshot;
  List<ReaderPageImage> _chapterPages = const [];
  Timer? _progressSaveTimer;
  Timer? _pageCorrectionTimer;
  bool _isSeeking = false;
  bool _isMenuVisible = false;
  int _pageIndex = 0;
  int _initialPageIndex = 0;
  bool _shouldRestoreInitialPage = false;
  bool _isRestoringInitialPage = false;
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
    _readerCubit = ReaderCubit();
    _observerController = ListObserverController(controller: _scrollController);
    _initialPageIndex = widget.initialPageIndex < 0
        ? 0
        : widget.initialPageIndex;
    _pageIndex = _initialPageIndex;
    _readerCubit.updatePageIndex(_pageIndex);
    _shouldRestoreInitialPage = _initialPageIndex > 0;
    _isRestoringInitialPage = _shouldRestoreInitialPage;
    _scrollController.addListener(_handleScrollChanged);
    _applySystemUiVisibility(false);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _pageCorrectionTimer?.cancel();
    unawaited(_saveProgressNow());
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    unawaited(_readerCubit.close());
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
    _readerCubit.updateMenuVisible(visible: visible);

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
    _scheduleProgressSave();
  }

  void _handleObservedPageIndex(int pageIndex) {
    if (_isSeeking || _chapterPages.isEmpty) return;

    final safePageIndex = pageIndex.clamp(0, _lastPageIndex).toInt();
    if (safePageIndex != _pageIndex && mounted) {
      setState(() {
        _pageIndex = safePageIndex;
      });
    }
    _readerCubit.updatePageIndex(safePageIndex);
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

  int get _lastPageIndex {
    if (_chapterPages.isEmpty) return 0;
    return _chapterPages.length - 1;
  }

  double _readerPageWidth() {
    if (!mounted) return 0;
    final size = MediaQuery.maybeSizeOf(context);
    if (size != null) return size.width;
    if (_scrollController.hasClients) {
      return _scrollController.position.viewportDimension;
    }
    return 0;
  }

  double _estimatedPageHeight(int index, double width) {
    if (width <= 0 || index < 0 || index >= _chapterPages.length) return 0;
    final size = _imageSizes[_chapterPages[index].cacheKey];
    if (size != null && size.width > 0 && size.height > 0) {
      return width * size.height / size.width;
    }
    return width * _estimatedPageAspectRatio;
  }

  double _estimatedPageOffset(int pageIndex) {
    final width = _readerPageWidth();
    final target = pageIndex.clamp(0, _lastPageIndex).toInt();
    var offset = 0.0;
    for (var i = 0; i < target; i++) {
      offset += _estimatedPageHeight(i, width);
    }
    return offset;
  }

  bool _syncChapterSnapshot(ReaderChapterSnapshot snapshot) {
    final oldKeys = _chapterPages
        .map((page) => page.cacheKey)
        .toList(growable: false);
    final newKeys = snapshot.pages
        .map((page) => page.cacheKey)
        .toList(growable: false);
    if (_chapterSnapshot?.chapter.id == snapshot.chapter.id &&
        listEquals(oldKeys, newKeys)) {
      return false;
    }

    _chapterSnapshot = snapshot;
    _chapterPages = snapshot.pages;
    _pageKeys = List<GlobalKey>.generate(
      snapshot.pages.length,
      (_) => GlobalKey(),
      growable: false,
    );
    _pageIndex = _pageIndex.clamp(0, _lastPageIndex).toInt();
    _initialPageIndex = _initialPageIndex.clamp(0, _lastPageIndex).toInt();
    return true;
  }

  void _handleImageSizeResolved(String url, Size size, int index) {
    final oldSize = _imageSizes[url];
    if (oldSize == size) return;

    _imageSizes[url] = size;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});

      if (_isSeeking || _isRestoringInitialPage || index <= _pageIndex) {
        _schedulePageCorrection(_pageIndex);
      }
    });
  }

  void _jumpToPage(int pageIndex, {bool correctAfterLayout = false}) {
    if (!_scrollController.hasClients || _chapterPages.isEmpty) return;

    final position = _scrollController.position;
    final target = _estimatedPageOffset(pageIndex).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target.toDouble());

    if (correctAfterLayout) {
      _schedulePageCorrection(pageIndex);
    }
  }

  void _schedulePageCorrection(int pageIndex) {
    _pageCorrectionTimer?.cancel();
    _pageCorrectionTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || !_scrollController.hasClients) return;
      _correctToPage(pageIndex);
      _pageCorrectionTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted || !_scrollController.hasClients) return;
        _correctToPage(pageIndex);
      });
    });
  }

  void _correctToPage(int pageIndex) {
    final target = pageIndex.clamp(0, _lastPageIndex).toInt();
    if (target < 0 || target >= _pageKeys.length) return;

    final pageContext = _pageKeys[target].currentContext;
    if (pageContext == null) {
      _jumpToPage(target);
      return;
    }

    Scrollable.ensureVisible(
      pageContext,
      alignment: 0,
      duration: Duration.zero,
      curve: Curves.linear,
    );
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      unawaited(_saveProgressNow());
    });
  }

  Future<void> _saveProgressNow() {
    if (widget.chapters.isEmpty || _chapterPages.isEmpty) {
      return Future<void>.value();
    }

    final chapter = _chapterSnapshot?.chapter ?? widget.chapters[_chapterIndex];
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
        pageIndex: _pageIndex.clamp(0, _lastPageIndex).toInt(),
        pageCount: _chapterPages.length,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _scheduleInitialPageRestore() {
    if (!_shouldRestoreInitialPage || _isRestoreScheduled) return;

    _isRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isRestoreScheduled = false;
      _restoreInitialPage();
    });
  }

  void _restoreInitialPage() {
    if (!mounted || !_shouldRestoreInitialPage) return;
    if (!_scrollController.hasClients) {
      _retryInitialPageRestore();
      return;
    }

    if (_scrollController.position.maxScrollExtent <= 0 && _lastPageIndex > 0) {
      _retryInitialPageRestore();
      return;
    }

    _shouldRestoreInitialPage = false;
    _jumpToPage(_initialPageIndex, correctAfterLayout: true);
    _readerCubit.updatePageIndex(_initialPageIndex);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _isRestoringInitialPage = false;
      });
    });
    _scheduleProgressSave();
  }

  void _retryInitialPageRestore() {
    if (_restoreAttempts >= 8) {
      _shouldRestoreInitialPage = false;
      if (mounted) {
        setState(() {
          _isRestoringInitialPage = false;
        });
      }
      return;
    }

    _restoreAttempts += 1;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _scheduleInitialPageRestore();
    });
  }

  void _handleProgressChangeStart(double value) {
    _progressSaveTimer?.cancel();
    _isSeeking = true;
    _readerCubit.updateSliderRolling(true);
    _readerCubit.updateIsComicRolling(true);
    HapticFeedback.selectionClick();
  }

  void _handleProgressChanged(double value) {
    final pageIndex = value.round().clamp(0, _lastPageIndex).toInt();
    if (pageIndex == _pageIndex) return;
    setState(() {
      _pageIndex = pageIndex;
    });
    _readerCubit.updateSliderChanged(pageIndex.toDouble());
    HapticFeedback.selectionClick();
  }

  void _handleProgressChangeEnd(double value) {
    final pageIndex = value.round().clamp(0, _lastPageIndex).toInt();
    _isSeeking = false;
    _readerCubit.updateSliderRolling(false);
    _readerCubit.updateIsComicRolling(false);
    setState(() {
      _pageIndex = pageIndex;
    });
    _readerCubit.updatePageIndex(pageIndex);
    _jumpToPage(pageIndex, correctAfterLayout: true);
    unawaited(_saveProgressNow());
  }

  String _chapterTitle(int index) {
    if (widget.chapters.isEmpty) return '暂无章节';
    final chapter = widget.chapters[index];
    return widget.chapters.length == 1 ? '单章节' : chapter.name;
  }

  Future<ReaderChapterSnapshot> _loadChapter(int index) async {
    if (widget.chapters.isEmpty) {
      throw StateError('暂无章节');
    }

    final provider = ProviderRegistry().getProvider(widget.providerId);
    if (provider == null) {
      throw StateError('未找到数据源: ${widget.providerId}');
    }

    final chapter = widget.chapters[index];
    return provider.getReaderChapterSnapshot(
      comic: widget.comic,
      chapter: chapter,
      chapters: widget.chapters,
    );
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
    unawaited(_saveProgressNow());
    _pageCorrectionTimer?.cancel();
    setState(() {
      _chapterIndex = index;
      _chapterFuture = _loadChapter(index);
      _pageIndex = 0;
      _initialPageIndex = 0;
      _chapterSnapshot = null;
      _chapterPages = const [];
      _pageKeys = const [];
      _shouldRestoreInitialPage = false;
      _isRestoringInitialPage = false;
      _restoreAttempts = 0;
    });
    _readerCubit.updateTotalSlots(0);
    _readerCubit.updatePageIndex(0);

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

    return BlocProvider.value(
      value: _readerCubit,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                    child: FutureBuilder<ReaderChapterSnapshot>(
                      key: ValueKey(_chapterIndex),
                      future: _chapterFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        }

                        if (snapshot.hasError && !snapshot.hasData) {
                          return _ReaderErrorView(
                            message: snapshot.error.toString(),
                            onRetry: _reloadChapter,
                          );
                        }

                        final data = snapshot.requireData;
                        if (data.pages.isEmpty) {
                          return _ReaderEmptyView(onRetry: _reloadChapter);
                        }

                        final snapshotChanged = _syncChapterSnapshot(data);
                        if (snapshotChanged) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _readerCubit.updateTotalSlots(data.pages.length);
                            _readerCubit.updatePageIndex(_pageIndex);
                            setState(() {});
                            unawaited(_saveProgressNow());
                          });
                        }
                        _scheduleInitialPageRestore();
                        return _ReaderImageList(
                          pageKeys: _pageKeys,
                          pages: data.pages,
                          imageSizes: _imageSizes,
                          controller: _scrollController,
                          observerController: _observerController,
                          onPageObserved: _handleObservedPageIndex,
                          onRetry: _reloadChapter,
                          onSizeResolved: _handleImageSizeResolved,
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
                  chapterCount: widget.chapters.length,
                  pageIndex: _pageIndex,
                  pageCount: _chapterPages.length,
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
              if (_isRestoringInitialPage)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
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
  final List<GlobalKey> pageKeys;
  final List<ReaderPageImage> pages;
  final Map<String, Size> imageSizes;
  final ScrollController controller;
  final ListObserverController observerController;
  final ValueChanged<int> onPageObserved;
  final VoidCallback onRetry;
  final void Function(String url, Size size, int index) onSizeResolved;

  const _ReaderImageList({
    required this.pageKeys,
    required this.pages,
    required this.imageSizes,
    required this.controller,
    required this.observerController,
    required this.onPageObserved,
    required this.onRetry,
    required this.onSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    final listView = ListView.builder(
      controller: controller,
      cacheExtent: MediaQuery.sizeOf(context).height * 2,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return _ReaderImage(
          key: pageKeys[index],
          url: page.url,
          pageNumber: index + 1,
          pageCount: pages.length,
          knownSize: imageSizes[page.cacheKey],
          onRetry: onRetry,
          onSizeResolved: (size) => onSizeResolved(page.cacheKey, size, index),
        );
      },
    );

    return ListViewObserver(
      controller: observerController,
      onObserve: (resultMap) {
        final visibleIndexes = resultMap.displayingChildIndexList;
        if (visibleIndexes.isEmpty) return;
        onPageObserved(visibleIndexes[visibleIndexes.length ~/ 2]);
      },
      child: listView,
    );
  }
}

class _ReaderImage extends StatefulWidget {
  final String url;
  final int pageNumber;
  final int pageCount;
  final Size? knownSize;
  final VoidCallback onRetry;
  final ValueChanged<Size> onSizeResolved;

  const _ReaderImage({
    super.key,
    required this.url,
    required this.pageNumber,
    required this.pageCount,
    required this.knownSize,
    required this.onRetry,
    required this.onSizeResolved,
  });

  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant _ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.knownSize != widget.knownSize) {
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _resolveImageSize() {
    if (widget.knownSize != null) {
      _removeImageListener();
      return;
    }

    _removeImageListener();
    final provider = CachedNetworkImageProvider(widget.url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      widget.onSizeResolved(size);
    });

    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final imageSize = widget.knownSize;
        final height = imageSize != null && imageSize.width > 0
            ? width * imageSize.height / imageSize.width
            : width * _ReaderPageState._estimatedPageAspectRatio;

        return Semantics(
          label: '第 ${widget.pageNumber} 页，共 ${widget.pageCount} 页',
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: CachedNetworkImage(
              imageUrl: widget.url,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              progressIndicatorBuilder: (context, url, progress) {
                return Center(
                  child: CircularProgressIndicator(value: progress.progress),
                );
              },
              errorWidget: (context, url, error) {
                return _ImageErrorView(onRetry: widget.onRetry);
              },
            ),
          ),
        );
      },
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  final int chapterCount;
  final int pageIndex;
  final int pageCount;
  final bool hasPrevious;
  final bool hasNext;
  final ValueChanged<double> onProgressChangeStart;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onProgressChangeEnd;
  final VoidCallback onPrevious;
  final VoidCallback onChapterPicker;
  final VoidCallback onNext;

  const _ReaderBottomBar({
    required this.chapterCount,
    required this.pageIndex,
    required this.pageCount,
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
    final maxPage = pageCount > 0 ? pageCount - 1 : 0;
    final sliderValue = pageIndex.clamp(0, maxPage).toDouble();
    final pageLabel = pageCount == 0
        ? '暂无页数'
        : '第 ${pageIndex.clamp(0, maxPage) + 1} / $pageCount 页';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0.78),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
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
                      value: sliderValue,
                      min: 0,
                      max: maxPage.toDouble(),
                      divisions: maxPage > 0 ? maxPage : null,
                      onChangeStart: pageCount > 1
                          ? onProgressChangeStart
                          : null,
                      onChanged: pageCount > 1 ? onProgressChanged : null,
                      onChangeEnd: pageCount > 1 ? onProgressChangeEnd : null,
                    ),
                  ),
                ),
                Text(
                  pageLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ReaderBottomIconButton(
                        tooltip: '上一章',
                        onPressed: hasPrevious ? onPrevious : null,
                        icon: Icons.skip_previous,
                      ),
                      const SizedBox(width: 18),
                      _ReaderBottomIconButton(
                        tooltip: '章节列表',
                        onPressed: chapterCount > 0 ? onChapterPicker : null,
                        icon: Icons.format_list_bulleted,
                      ),
                      const SizedBox(width: 18),
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
