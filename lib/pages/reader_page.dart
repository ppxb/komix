import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../config/global/global_setting.dart';
import '../models/comic.dart';
import '../models/reader_snapshot.dart';
import '../reader/image_size_cubit.dart';
import '../reader/reader_chapter_navigation_controller.dart';
import '../reader/reader_chapter_view_state.dart';
import '../reader/reader_action_controller.dart';
import '../reader/reader_cubit.dart';
import '../reader/reader_gesture_logic.dart';
import '../reader/reader_history_manager.dart';
import '../reader/reader_initial_page_restorer.dart';
import '../reader/reader_image_loader.dart';
import '../reader/reader_image_view.dart';
import '../reader/reader_layout.dart';
import '../reader/reader_layout_metrics.dart';
import '../reader/reader_page_info_overlay.dart';
import '../reader/reader_keyboard_shortcuts.dart';
import '../reader/reader_position_controller.dart';
import '../reader/reader_progress_controller.dart';
import '../reader/reader_session_controller.dart';
import '../reader/reader_settings_sheet.dart';
import '../reader/reader_side_effect_controller.dart';

part 'reader_page_content.dart';
part 'reader_page_overlays.dart';
part 'reader_page_status_views.dart';

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
  final ReaderChapterSnapshotLoader? snapshotLoader;

  const ReaderPage({
    super.key,
    required this.providerId,
    required this.comic,
    required this.chapters,
    required this.initialChapterIndex,
    this.initialPageIndex = 0,
    this.snapshotLoader,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _estimatedPageAspectRatio = 1.42;
  static const _scaleLockThreshold = 1.01;
  static const _chapterEndPageIndex = 0x3fffffff;

  late int _chapterIndex;
  late Future<ReaderChapterData> _chapterFuture;
  late final ReaderCubit _readerCubit;
  late final ListObserverController _observerController;
  late final PageController _pageController;
  late final TransformationController _transformationController;
  late final FocusNode _readerFocusNode;
  late final ReaderActionController _actionController;
  late final ReaderHistoryManager _historyManager;
  late final ReaderSessionController _sessionController;
  late final ReaderSideEffectController _sideEffects;
  late final ReaderLayoutMetrics _layoutMetrics;
  late final ReaderPositionController _positionController;
  late final ReaderProgressController _progressController;
  late final ReaderChapterNavigationController _chapterNavigation;
  late final ReaderInitialPageRestorer _initialPageRestorer;
  final ReaderChapterViewState _chapterView = ReaderChapterViewState();
  final ScrollController _scrollController = ScrollController();
  bool _isMenuVisible = false;
  double _currentViewerScale = 1.0;
  int _pageIndex = 0;
  bool _isChapterDataApplyScheduled = false;
  bool _isReaderMetricsSyncScheduled = false;
  ReaderChapterData? _pendingChapterData;
  ReadSettingState? _pendingChapterReadSetting;
  ReadSettingState? _pendingMetricsReadSetting;
  TapDownDetails? _tapDownDetails;
  TapDownDetails? _doubleTapDownDetails;
  bool _isElementActive = true;
  bool _isDisposing = false;
  int _lastKnownSlotCount = 0;

  ImageSizeCubit? get _imageSizeCubit => _chapterView.imageSizeCubit;
  List<GlobalKey> get _pageKeys => _chapterView.pageKeys;
  List<GlobalKey> get _slotKeys => _chapterView.slotKeys;
  ReaderChapterSnapshot? get _chapterSnapshot => _chapterView.snapshot;
  List<ReaderPageImage> get _chapterPages => _chapterView.pages;
  bool get _canUseContext => mounted && _isElementActive && !_isDisposing;

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.chapters.length - 1;
    _chapterIndex = lastIndex < 0
        ? 0
        : widget.initialChapterIndex.clamp(0, lastIndex).toInt();
    _readerCubit = ReaderCubit();
    _observerController = ListObserverController(controller: _scrollController);
    _pageController = PageController(initialPage: 0);
    _transformationController = TransformationController();
    _readerFocusNode = FocusNode();
    _layoutMetrics = ReaderLayoutMetrics(
      context: context,
      scrollController: _scrollController,
      isMounted: () => _canUseContext,
      pages: () => _chapterPages,
      imageSizeCubit: () => _imageSizeCubit,
      defaultAspectRatio: _estimatedPageAspectRatio,
    );
    _actionController = ReaderActionController(
      context: context,
      isActive: () => _canUseContext,
      scrollController: _scrollController,
      observerController: _observerController,
      pageController: _pageController,
      onBeforeTurnPage: _restoreScaleBeforeTurnPage,
      onChapterBoundary: (isNext) => _chapterNavigation.handleBoundary(
        isNext,
        chapterEndPageIndex: _chapterEndPageIndex,
      ),
    );
    _sideEffects = ReaderSideEffectController(
      actionController: _actionController,
      isMounted: () => _canUseContext,
      isMenuVisible: () => _isMenuVisible,
      isSeeking: () => _progressController.isSeeking,
      slotCount: () => _slotCount,
      requestRebuild: () {
        if (_canUseContext) setState(() {});
      },
    );
    _positionController = ReaderPositionController(
      context: context,
      scrollController: _scrollController,
      observerController: _observerController,
      pageController: _pageController,
      sideEffects: _sideEffects,
      isMounted: () => _canUseContext,
      isSeeking: () => _progressController.isSeeking,
      hasPages: () => _chapterPages.isNotEmpty,
      lastPageIndex: () => _lastPageIndex,
      slotKeys: () => _slotKeys,
      estimatedPageOffset: _layoutMetrics.estimatedPageOffset,
      resetViewerTransform: _resetViewerTransformIfNeeded,
    );
    _initialPageRestorer = ReaderInitialPageRestorer(
      isMounted: () => _canUseContext,
      requestRebuild: () {
        if (_canUseContext) setState(() {});
      },
    );
    _historyManager = ReaderHistoryManager(
      providerId: widget.providerId,
      comic: widget.comic,
      chapterCount: widget.chapters.length,
      getChapterId: () {
        if (widget.chapters.isEmpty) return '';
        return _chapterSnapshot?.chapter.id ??
            widget.chapters[_chapterIndex].id;
      },
      getChapterTitle: () => _chapterTitle(_chapterIndex),
      getChapterIndex: () => _chapterIndex,
      getPageIndex: () => _pageIndex,
      getPageCount: () => _slotCount,
    );
    _sessionController = ReaderSessionController(
      providerId: widget.providerId,
      comic: widget.comic,
      chapters: widget.chapters,
      snapshotLoader: widget.snapshotLoader,
      onLoadStarted: _historyManager.markLoading,
    );
    _progressController = ReaderProgressController(
      readerCubit: _readerCubit,
      historyManager: _historyManager,
      positionController: _positionController,
      sideEffects: _sideEffects,
      isMounted: () => _canUseContext,
      hasChapters: () => widget.chapters.isNotEmpty,
      hasPages: () => _chapterPages.isNotEmpty,
      isMenuVisible: () => _isMenuVisible,
      currentPageIndex: () => _pageIndex,
      lastPageIndex: () => _lastPageIndex,
      slotCount: () => _slotCount,
      readSetting: () => context.read<GlobalSettingCubit>().state.readSetting,
      setPageIndex: _setPageIndex,
      setMenuVisible: _setMenuVisible,
      resetViewerTransform: _resetViewerTransformIfNeeded,
    );
    _chapterNavigation = ReaderChapterNavigationController(
      chapters: widget.chapters,
      readerCubit: _readerCubit,
      chapterView: _chapterView,
      historyManager: _historyManager,
      sessionController: _sessionController,
      sideEffects: _sideEffects,
      positionController: _positionController,
      progressController: _progressController,
      scrollController: _scrollController,
      pageController: _pageController,
      chapterIndex: () => _chapterIndex,
      isRestoringInitialPage: () =>
          _initialPageRestorer.isRestoringInitialPage,
      resetViewerTransform: _resetViewerTransformIfNeeded,
      setChapterFuture: _setChapterFuture,
      setChapterState: _setChapterState,
    );
    _sideEffects.listenVolume();
    unawaited(_historyManager.init());
    _chapterFuture = _sessionController.loadChapter(_chapterIndex);
    _initialPageRestorer.configure(widget.initialPageIndex);
    _pageIndex = _initialPageRestorer.initialPageIndex;
    _readerCubit.updatePageIndex(_pageIndex);
    _scrollController.addListener(_progressController.handleScrollChanged);
    _sideEffects.applySystemUiVisibility(false, _readerSystemOverlayStyle);
  }

  @override
  void activate() {
    super.activate();
    _isElementActive = true;
  }

  @override
  void deactivate() {
    _isElementActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _isElementActive = false;
    _progressController.dispose();
    _positionController.dispose();
    _sessionController.clearPrefetch();
    unawaited(_progressController.saveNow());
    _sideEffects.restoreSystemUi();
    _scrollController.removeListener(_progressController.handleScrollChanged);
    _scrollController.dispose();
    _pageController.dispose();
    _transformationController.dispose();
    _readerFocusNode.dispose();
    _sideEffects.dispose();
    _historyManager.stop();
    unawaited(_chapterView.close());
    unawaited(_readerCubit.close());
    super.dispose();
  }

  void _setPageIndex(int pageIndex) {
    if (pageIndex == _pageIndex) return;
    if (mounted) {
      setState(() {
        _pageIndex = pageIndex;
      });
      return;
    }
    _pageIndex = pageIndex;
  }

  void _setChapterFuture(Future<ReaderChapterData> chapterFuture) {
    if (!mounted) return;
    setState(() {
      _chapterFuture = chapterFuture;
    });
  }

  void _setChapterState({
    required int chapterIndex,
    required Future<ReaderChapterData> chapterFuture,
    required int pageIndex,
  }) {
    if (!mounted) return;
    setState(() {
      _chapterIndex = chapterIndex;
      _chapterFuture = chapterFuture;
      _pageIndex = pageIndex;
      _initialPageRestorer.configure(pageIndex);
    });
  }

  void _setMenuVisible(bool visible) {
    if (!_canUseContext) return;
    if (_isMenuVisible == visible) {
      _sideEffects.applySystemUiVisibility(visible, _readerSystemOverlayStyle);
      return;
    }

    setState(() {
      _isMenuVisible = visible;
    });
    _readerCubit.updateMenuVisible(visible: visible);

    _sideEffects.applySystemUiVisibility(visible, _readerSystemOverlayStyle);
    _sideEffects.syncReadSetting(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
  }

  void _toggleMenu() {
    _setMenuVisible(!_isMenuVisible);
  }

  void _toggleAutoReadPaused() {
    if (!_canUseContext) return;
    _sideEffects.toggleAutoReadPaused(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
  }

  void _updateViewerScale() {
    final nextScale = _transformationController.value.getMaxScaleOnAxis();
    final wasLocked = _currentViewerScale > _scaleLockThreshold;
    final shouldLock = nextScale > _scaleLockThreshold;
    _currentViewerScale = nextScale;
    if (_canUseContext && wasLocked != shouldLock) {
      setState(() {});
    }
  }

  bool _restoreScaleBeforeTurnPage(bool _) {
    _resetViewerTransformIfNeeded();
    return false;
  }

  bool _resetViewerTransformIfNeeded() {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final tx = matrix.storage[12].abs();
    final ty = matrix.storage[13].abs();
    final shouldReset = scale > _scaleLockThreshold || tx > 0.5 || ty > 0.5;
    if (!shouldReset) return false;

    _transformationController.value = Matrix4.identity();
    _currentViewerScale = 1.0;
    if (_canUseContext) {
      setState(() {});
    }
    return true;
  }

  Future<void> _handleTap() async {
    await Future<void>.delayed(Duration.zero);
    final details = _tapDownDetails;
    if (details == null || !_canUseContext) return;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;

    ReaderGestureLogic.handleTap(
      actionController: _actionController,
      controller: _pageController,
      context: context,
      details: details,
      onToggleMenu: readSetting.doubleTapOpenMenu
          ? () {
              if (_isMenuVisible) {
                _toggleMenu();
              }
            }
          : _toggleMenu,
      onBeforePageTurn: _resetViewerTransformIfNeeded,
    );
    _tapDownDetails = null;
  }

  void _handleDoubleTap() {
    if (!_canUseContext) return;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    _tapDownDetails = null;

    if (readSetting.doubleTapZoom) {
      _handleDoubleTapZoom();
      return;
    }

    if (readSetting.doubleTapOpenMenu) {
      _toggleMenu();
    }
  }

  void _handleDoubleTapZoom() {
    if (!_canUseContext) return;
    final details = _doubleTapDownDetails;
    if (details == null) return;

    if (_resetViewerTransformIfNeeded()) {
      _doubleTapDownDetails = null;
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      _doubleTapDownDetails = null;
      return;
    }

    final localPosition = renderObject.globalToLocal(details.globalPosition);
    const targetScale = 2.5;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        renderObject.size.width / 2 - localPosition.dx * targetScale,
        renderObject.size.height / 2 - localPosition.dy * targetScale,
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, targetScale, 1);

    _transformationController.value = matrix;
    _doubleTapDownDetails = null;
    _updateViewerScale();
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

  int get _slotCount {
    if (!_canUseContext) return _lastKnownSlotCount;
    final count = _layoutMetrics.slotCount;
    _lastKnownSlotCount = count;
    return count;
  }

  int get _lastPageIndex => _layoutMetrics.lastPageIndex;

  bool _syncChapterSnapshot(
    ReaderChapterSnapshot snapshot,
    Map<int, Size> persistedSizes,
  ) {
    final snapshotChanged = _chapterView.applySnapshot(
      nextSnapshot: snapshot,
      persistedSizes: persistedSizes,
      sourceTag: widget.providerId,
      defaultWidth: _layoutMetrics.readerContentWidth(),
      defaultAspectRatio: _estimatedPageAspectRatio,
    );
    if (!snapshotChanged) return false;

    _pageIndex = _pageIndex.clamp(0, _lastPageIndex).toInt();
    _initialPageRestorer.clampInitialPage(_lastPageIndex);
    return true;
  }

  bool _isCurrentChapterSnapshot(ReaderChapterSnapshot snapshot) {
    if (widget.chapters.isEmpty) return false;
    return snapshot.chapter.id == widget.chapters[_chapterIndex].id;
  }

  bool _isChapterDataApplied(ReaderChapterData data) {
    return _chapterView.isApplied(data.snapshot);
  }

  void _scheduleChapterDataApply(
    ReaderChapterData data,
    ReadSettingState readSetting,
  ) {
    _pendingChapterData = data;
    _pendingChapterReadSetting = readSetting;
    if (_isChapterDataApplyScheduled) return;

    _isChapterDataApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isChapterDataApplyScheduled = false;
      final pendingData = _pendingChapterData;
      final pendingReadSetting = _pendingChapterReadSetting;
      _pendingChapterData = null;
      _pendingChapterReadSetting = null;
      if (!_canUseContext ||
          pendingData == null ||
          pendingReadSetting == null) {
        return;
      }
      _applyChapterData(pendingData, pendingReadSetting);
    });
  }

  void _applyChapterData(ReaderChapterData data, ReadSettingState readSetting) {
    if (!_canUseContext) return;
    final chapterSnapshot = data.snapshot;
    if (!_isCurrentChapterSnapshot(chapterSnapshot)) return;

    final snapshotChanged = _syncChapterSnapshot(
      chapterSnapshot,
      data.persistedSizes,
    );
    _historyManager.markLoaded();
    _sessionController.prefetchAdjacentChapters(_chapterIndex);
    final pageIndexChanged = _syncReaderMetrics(readSetting);
    if (snapshotChanged && !pageIndexChanged && _canUseContext) {
      setState(() {});
    }
    if (snapshotChanged) {
      unawaited(_progressController.saveNow());
    }
    _sideEffects.syncReadSetting(readSetting);
    _scheduleInitialPageRestore();
  }

  void _scheduleReaderMetricsSync(ReadSettingState readSetting) {
    _pendingMetricsReadSetting = readSetting;
    if (_isReaderMetricsSyncScheduled) return;

    _isReaderMetricsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isReaderMetricsSyncScheduled = false;
      final pendingReadSetting = _pendingMetricsReadSetting;
      _pendingMetricsReadSetting = null;
      if (!_canUseContext || pendingReadSetting == null) return;
      _syncReaderMetrics(pendingReadSetting);
    });
  }

  bool _syncReaderMetrics(ReadSettingState readSetting) {
    final slotCount = _layoutMetrics.slotCountFor(readSetting);
    _lastKnownSlotCount = slotCount;
    final maxSlot = slotCount > 0 ? slotCount - 1 : 0;
    final safePageIndex = _pageIndex.clamp(0, maxSlot).toInt();
    final pageIndexChanged = safePageIndex != _pageIndex;
    if (pageIndexChanged) {
      if (_canUseContext) {
        setState(() {
          _pageIndex = safePageIndex;
        });
      } else {
        _pageIndex = safePageIndex;
      }
    }
    _readerCubit.updateTotalSlots(slotCount);
    _readerCubit.updatePageIndex(safePageIndex);
    return pageIndexChanged;
  }

  void _handleReadSettingChanged(ReadSettingState readSetting) {
    if (!_canUseContext) return;
    if (!readSetting.doubleTapZoom &&
        _currentViewerScale > _scaleLockThreshold) {
      _resetViewerTransformIfNeeded();
    }
    _syncReaderMetrics(readSetting);
    _sideEffects.syncReadSetting(readSetting);
  }

  void _handleImageSizeResolved(int index, Size size) {
    if (!_canUseContext) return;
    _imageSizeCubit?.updateSize(index, size);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canUseContext || _progressController.isSeeking) return;
      final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
      if (!isColumnReadMode(readSetting.readMode)) return;
      final slotIndex = _layoutMetrics.effectiveDoublePageEnabled(readSetting)
          ? index ~/ 2
          : index;
      if (_initialPageRestorer.isRestoringInitialPage &&
          slotIndex <= _pageIndex) {
        _positionController.schedulePageCorrection(_pageIndex);
      }
    });
  }

  void _scheduleInitialPageRestore() {
    _initialPageRestorer.schedule(_restoreInitialPage);
  }

  void _restoreInitialPage() {
    if (!_canUseContext || !_initialPageRestorer.shouldRestoreInitialPage) {
      return;
    }
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final initialPageIndex = _initialPageRestorer.initialPageIndex;
    if (!isColumnReadMode(readSetting.readMode)) {
      if (!_pageController.hasClients) {
        _retryInitialPageRestore();
        return;
      }

      _initialPageRestorer.markRestored();
      _pageController.jumpToPage(
        initialPageIndex.clamp(0, _lastPageIndex).toInt(),
      );
      _readerCubit.updatePageIndex(initialPageIndex);
      _initialPageRestorer.finishRestoringDelayed();
      _progressController.scheduleSave();
      return;
    }

    if (!_scrollController.hasClients) {
      _retryInitialPageRestore();
      return;
    }

    if (_scrollController.position.maxScrollExtent <= 0 && _lastPageIndex > 0) {
      _retryInitialPageRestore();
      return;
    }

    _initialPageRestorer.markRestored();
    _positionController.jumpToPage(
      initialPageIndex,
      correctAfterLayout: true,
    );
    _readerCubit.updatePageIndex(initialPageIndex);
    _initialPageRestorer.finishRestoringDelayed();
    _progressController.scheduleSave();
  }

  void _retryInitialPageRestore() {
    _initialPageRestorer.retry(_scheduleInitialPageRestore);
  }

  String _chapterTitle(int index) {
    return _sessionController.chapterTitle(index);
  }

  Future<void> _showChapterPicker() async {
    if (widget.chapters.isEmpty || !_canUseContext) return;

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

    if (!_canUseContext || selectedIndex == null) return;
    _chapterNavigation.goToChapter(selectedIndex);
  }

  void _handleReaderLayoutChanged(ReadSettingState previousReadSetting) {
    if (!_canUseContext) return;
    final nextReadSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final targetPageIndex = _layoutMetrics.pageIndexAfterLayoutChange(
      previousReadSetting: previousReadSetting,
      nextReadSetting: nextReadSetting,
      currentPageIndex: _pageIndex,
    );
    _progressController.cancelPendingSave();
    _positionController.cancelCorrection();
    _sideEffects.hideEinkMask();
    _resetViewerTransformIfNeeded();
    setState(() {
      _pageIndex = targetPageIndex;
      _initialPageRestorer.reset();
    });
    final nextSlotCount = _layoutMetrics.slotCountFor(nextReadSetting);
    _lastKnownSlotCount = nextSlotCount;
    _readerCubit.updateTotalSlots(nextSlotCount);
    _readerCubit.updatePageIndex(targetPageIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canUseContext) return;
      _positionController.jumpToPage(
        targetPageIndex,
        correctAfterLayout: isColumnReadMode(nextReadSetting.readMode),
      );
      _progressController.scheduleSave();
    });
  }

  Future<void> _showReaderSettings() {
    if (!_canUseContext) return Future<void>.value();
    return showReaderSettingsSheet(
      context,
      onLayoutChanged: _handleReaderLayoutChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPrevious = _chapterIndex > 0;
    final hasNext = _chapterIndex < widget.chapters.length - 1;
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final backgroundColor = readSetting.resolveReaderBackgroundColor(
      Theme.of(context).brightness,
    );
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final filterOpacityPercent = readSetting.readFilterOpacityPercent
        .clamp(0, 100)
        .toDouble();
    final enableReaderFilter =
        isDarkMode && readSetting.readFilterEnabled && filterOpacityPercent > 0;
    final effectiveDoublePageEnabled = _layoutMetrics.effectiveDoublePageEnabled(
      readSetting,
      buildContext: context,
    );
    final isDoubleTapActionEnabled =
        readSetting.doubleTapOpenMenu || readSetting.doubleTapZoom;

    return BlocProvider.value(
      value: _readerCubit,
      child: BlocListener<GlobalSettingCubit, GlobalSettingState>(
        listenWhen: (previous, current) =>
            previous.readSetting != current.readSetting,
        listener: (context, state) =>
            _handleReadSettingChanged(state.readSetting),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: _readerSystemOverlayStyle,
          child: Scaffold(
            backgroundColor: backgroundColor,
            body: Stack(
              children: [
                Positioned.fill(
                  child: Focus(
                    focusNode: _readerFocusNode,
                    autofocus: true,
                    onKeyEvent: (node, event) {
                      final handled = handleGlobalKeyEvent(
                        event,
                        _actionController,
                      );
                      return handled
                          ? KeyEventResult.handled
                          : KeyEventResult.ignored;
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) => _tapDownDetails = details,
                      onTap: _handleTap,
                      onDoubleTapDown: isDoubleTapActionEnabled
                          ? (details) => _doubleTapDownDetails = details
                          : null,
                      onDoubleTap: isDoubleTapActionEnabled
                          ? _handleDoubleTap
                          : null,
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: EdgeInsets.zero,
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: _currentViewerScale > _scaleLockThreshold,
                        scaleEnabled: readSetting.doubleTapZoom,
                        interactionEndFrictionCoefficient: 0.00001,
                        onInteractionUpdate: (_) => _updateViewerScale(),
                        onInteractionEnd: (_) => _updateViewerScale(),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleReaderScrollNotification,
                          child: _ReaderChapterContent(
                            chapterIndex: _chapterIndex,
                            chapterFuture: _chapterFuture,
                            readSetting: readSetting,
                            backgroundColor: backgroundColor,
                            enableDoublePage: effectiveDoublePageEnabled,
                            pageIndex: _pageIndex,
                            readerCubit: _readerCubit,
                            layoutMetrics: _layoutMetrics,
                            imageSizeCubit: _imageSizeCubit,
                            pageKeys: _pageKeys,
                            slotKeys: _slotKeys,
                            scrollController: _scrollController,
                            observerController: _observerController,
                            pageController: _pageController,
                            onRetry: _chapterNavigation.reloadChapter,
                            isChapterDataApplied: _isChapterDataApplied,
                            scheduleChapterDataApply:
                                _scheduleChapterDataApply,
                            scheduleReaderMetricsSync:
                                _scheduleReaderMetricsSync,
                            onPageObserved:
                                _progressController.handleObservedPageIndex,
                            onPageChanged:
                                _progressController.handlePagedPageChanged,
                            onSizeResolved: _handleImageSizeResolved,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (enableReaderFilter)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: filterOpacityPercent / 100,
                        ),
                      ),
                    ),
                  ),
                if (_sideEffects.showEinkMask)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
                if (_chapterPages.isNotEmpty)
                  ReaderPageInfoOverlay(
                    totalPageCount: _chapterPages.length,
                    enableDoublePage: effectiveDoublePageEnabled,
                  ),
                if (_chapterPages.isNotEmpty && readSetting.autoScroll)
                  _ReaderAutoReadButton(
                    isMenuVisible: _isMenuVisible,
                    isPaused: _sideEffects.isAutoReadPaused,
                    onPressed: _toggleAutoReadPaused,
                  ),
                _ReaderTopBar(
                  title: widget.comic.title,
                  chapterTitle: _chapterTitle(_chapterIndex),
                  isVisible: _isMenuVisible,
                  onRefresh: _chapterNavigation.reloadChapter,
                ),
                _ReaderBottomOverlay(
                  isVisible: _isMenuVisible,
                  child: _ReaderBottomBar(
                    chapterCount: widget.chapters.length,
                    pageIndex: _pageIndex,
                    pageCount: _slotCount,
                    hasPrevious: hasPrevious,
                    hasNext: hasNext,
                    onProgressChangeStart:
                        _progressController.handleProgressChangeStart,
                    onProgressChanged:
                        _progressController.handleProgressChanged,
                    onProgressChangeEnd:
                        _progressController.handleProgressChangeEnd,
                    onPrevious: () =>
                        _chapterNavigation.goToChapter(_chapterIndex - 1),
                    onChapterPicker: _showChapterPicker,
                    onSettings: () => unawaited(_showReaderSettings()),
                    onNext: () =>
                        _chapterNavigation.goToChapter(_chapterIndex + 1),
                  ),
                ),
                if (_initialPageRestorer.isRestoringInitialPage)
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
      ),
    );
  }
}
