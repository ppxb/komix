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
import '../reader/reader_chapter_view_state.dart';
import '../reader/reader_action_controller.dart';
import '../reader/reader_cubit.dart';
import '../reader/reader_gesture_logic.dart';
import '../reader/reader_history_manager.dart';
import '../reader/reader_image_loader.dart';
import '../reader/reader_image_view.dart';
import '../reader/reader_layout.dart';
import '../reader/reader_page_info_overlay.dart';
import '../reader/reader_keyboard_shortcuts.dart';
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
  final ReaderChapterViewState _chapterView = ReaderChapterViewState();
  final ScrollController _scrollController = ScrollController();
  Timer? _progressSaveTimer;
  Timer? _pageCorrectionTimer;
  bool _isSeeking = false;
  bool _isMenuVisible = false;
  double _currentViewerScale = 1.0;
  int _pageIndex = 0;
  int _initialPageIndex = 0;
  bool _shouldRestoreInitialPage = false;
  bool _isRestoringInitialPage = false;
  bool _isRestoreScheduled = false;
  bool _isChapterDataApplyScheduled = false;
  bool _isReaderMetricsSyncScheduled = false;
  ReaderChapterData? _pendingChapterData;
  ReadSettingState? _pendingChapterReadSetting;
  ReadSettingState? _pendingMetricsReadSetting;
  int _restoreAttempts = 0;
  TapDownDetails? _tapDownDetails;
  TapDownDetails? _doubleTapDownDetails;

  ImageSizeCubit? get _imageSizeCubit => _chapterView.imageSizeCubit;
  List<GlobalKey> get _pageKeys => _chapterView.pageKeys;
  List<GlobalKey> get _slotKeys => _chapterView.slotKeys;
  ReaderChapterSnapshot? get _chapterSnapshot => _chapterView.snapshot;
  List<ReaderPageImage> get _chapterPages => _chapterView.pages;

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
    _actionController = ReaderActionController(
      context: context,
      scrollController: _scrollController,
      observerController: _observerController,
      pageController: _pageController,
      onBeforeTurnPage: _restoreScaleBeforeTurnPage,
      onChapterBoundary: _handleChapterBoundary,
    );
    _sideEffects = ReaderSideEffectController(
      actionController: _actionController,
      isMounted: () => mounted,
      isMenuVisible: () => _isMenuVisible,
      isSeeking: () => _isSeeking,
      slotCount: () => _slotCount,
      requestRebuild: () {
        if (mounted) setState(() {});
      },
    );
    _sideEffects.listenVolume();
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
    unawaited(_historyManager.init());
    _chapterFuture = _sessionController.loadChapter(_chapterIndex);
    _initialPageIndex = widget.initialPageIndex < 0
        ? 0
        : widget.initialPageIndex;
    _pageIndex = _initialPageIndex;
    _readerCubit.updatePageIndex(_pageIndex);
    _shouldRestoreInitialPage = _initialPageIndex > 0;
    _isRestoringInitialPage = _shouldRestoreInitialPage;
    _scrollController.addListener(_handleScrollChanged);
    _sideEffects.applySystemUiVisibility(false, _readerSystemOverlayStyle);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _pageCorrectionTimer?.cancel();
    _sessionController.clearPrefetch();
    unawaited(_saveProgressNow());
    _sideEffects.restoreSystemUi();
    _scrollController.removeListener(_handleScrollChanged);
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

  void _setMenuVisible(bool visible) {
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
    _sideEffects.toggleAutoReadPaused(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
  }

  void _updateViewerScale() {
    final nextScale = _transformationController.value.getMaxScaleOnAxis();
    final wasLocked = _currentViewerScale > _scaleLockThreshold;
    final shouldLock = nextScale > _scaleLockThreshold;
    _currentViewerScale = nextScale;
    if (mounted && wasLocked != shouldLock) {
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
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  Future<void> _handleTap() async {
    await Future<void>.delayed(Duration.zero);
    final details = _tapDownDetails;
    if (details == null || !mounted) return;
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
    if (!mounted) return;
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

  bool _effectiveDoublePageEnabled(
    ReadSettingState readSetting, {
    BuildContext? buildContext,
  }) {
    final contextForSize = buildContext ?? context;
    final size = MediaQuery.maybeSizeOf(contextForSize);
    final isCompact = size != null && size.shortestSide < 600;
    return readSetting.doublePageMode && !isCompact;
  }

  int _slotCountFor(
    ReadSettingState readSetting, {
    BuildContext? buildContext,
  }) {
    return getReadModeSlotCount(
      imageCount: _chapterPages.length,
      enableDoublePage: _effectiveDoublePageEnabled(
        readSetting,
        buildContext: buildContext,
      ),
    );
  }

  int get _slotCount {
    if (_chapterPages.isEmpty || !mounted) return 0;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    return _slotCountFor(readSetting);
  }

  int get _lastPageIndex {
    final slotCount = _slotCount;
    if (slotCount <= 0) return 0;
    return slotCount - 1;
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

  double _readerContentWidth() {
    final containerWidth = _readerPageWidth();
    if (containerWidth <= 0) return 0;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    return getConstrainedImageWidth(
      containerWidth: containerWidth,
      enableSidePadding: readSetting.sidePaddingEnabled,
      sidePaddingPercent: readSetting.sidePaddingPercent,
    );
  }

  double _estimatedImageHeight(int index, double width) {
    if (width <= 0 || index < 0 || index >= _chapterPages.length) return 0;
    final size = _imageSizeCubit?.state.getSizeValue(index);
    if (size != null && size.width > 0 && size.height > 0) {
      if ((size.width - width).abs() < 0.1) return size.height;
      return width * size.height / size.width;
    }
    return width * _estimatedPageAspectRatio;
  }

  double _estimatedSlotHeight({
    required int slotIndex,
    required double width,
    required bool enableDoublePage,
  }) {
    if (!enableDoublePage) {
      return _estimatedImageHeight(slotIndex, width);
    }

    const panelGap = 6.0;
    final panelWidth = ((width - panelGap) / 2).clamp(1.0, width).toDouble();
    final firstIndex = slotIndex * 2;
    final secondIndex = firstIndex + 1;
    final firstHeight = _estimatedImageHeight(firstIndex, panelWidth);
    final secondHeight = secondIndex < _chapterPages.length
        ? _estimatedImageHeight(secondIndex, panelWidth)
        : 0.0;
    return firstHeight > secondHeight ? firstHeight : secondHeight;
  }

  double _estimatedPageOffset(int pageIndex) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final enableDoublePage = _effectiveDoublePageEnabled(readSetting);
    final width = _readerContentWidth();
    final target = pageIndex.clamp(0, _lastPageIndex).toInt();
    var offset = 0.0;
    for (var i = 0; i < target; i++) {
      offset += _estimatedSlotHeight(
        slotIndex: i,
        width: width,
        enableDoublePage: enableDoublePage,
      );
    }
    return offset;
  }

  bool _syncChapterSnapshot(
    ReaderChapterSnapshot snapshot,
    Map<int, Size> persistedSizes,
  ) {
    final snapshotChanged = _chapterView.applySnapshot(
      nextSnapshot: snapshot,
      persistedSizes: persistedSizes,
      sourceTag: widget.providerId,
      defaultWidth: _readerContentWidth(),
      defaultAspectRatio: _estimatedPageAspectRatio,
    );
    if (!snapshotChanged) return false;

    _pageIndex = _pageIndex.clamp(0, _lastPageIndex).toInt();
    _initialPageIndex = _initialPageIndex.clamp(0, _lastPageIndex).toInt();
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
      if (!mounted || pendingData == null || pendingReadSetting == null) {
        return;
      }
      _applyChapterData(pendingData, pendingReadSetting);
    });
  }

  void _applyChapterData(ReaderChapterData data, ReadSettingState readSetting) {
    final chapterSnapshot = data.snapshot;
    if (!_isCurrentChapterSnapshot(chapterSnapshot)) return;

    final snapshotChanged = _syncChapterSnapshot(
      chapterSnapshot,
      data.persistedSizes,
    );
    _historyManager.markLoaded();
    _sessionController.prefetchAdjacentChapters(_chapterIndex);
    final pageIndexChanged = _syncReaderMetrics(readSetting);
    if (snapshotChanged && !pageIndexChanged && mounted) {
      setState(() {});
    }
    if (snapshotChanged) {
      unawaited(_saveProgressNow());
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
      if (!mounted || pendingReadSetting == null) return;
      _syncReaderMetrics(pendingReadSetting);
    });
  }

  bool _syncReaderMetrics(ReadSettingState readSetting) {
    final slotCount = _slotCountFor(readSetting);
    final maxSlot = slotCount > 0 ? slotCount - 1 : 0;
    final safePageIndex = _pageIndex.clamp(0, maxSlot).toInt();
    final pageIndexChanged = safePageIndex != _pageIndex;
    if (pageIndexChanged) {
      if (mounted) {
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
    if (!readSetting.doubleTapZoom &&
        _currentViewerScale > _scaleLockThreshold) {
      _resetViewerTransformIfNeeded();
    }
    _syncReaderMetrics(readSetting);
    _sideEffects.syncReadSetting(readSetting);
  }

  void _handleImageSizeResolved(int index, Size size) {
    _imageSizeCubit?.updateSize(index, size);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSeeking) return;
      final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
      if (!isColumnReadMode(readSetting.readMode)) return;
      final slotIndex = _effectiveDoublePageEnabled(readSetting)
          ? index ~/ 2
          : index;
      if (_isRestoringInitialPage && slotIndex <= _pageIndex) {
        _schedulePageCorrection(_pageIndex);
      }
    });
  }

  void _jumpToPage(int pageIndex, {bool correctAfterLayout = false}) {
    if (_chapterPages.isEmpty) return;

    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final targetPage = pageIndex.clamp(0, _lastPageIndex).toInt();
    _resetViewerTransformIfNeeded();
    if (!isColumnReadMode(readSetting.readMode)) {
      if (!_pageController.hasClients) return;
      _pageController.jumpToPage(targetPage);
      _sideEffects.triggerEinkDelay(readSetting);
      return;
    }

    _jumpToColumnPage(targetPage, correctAfterLayout: correctAfterLayout);
  }

  void _jumpToColumnPage(int targetPage, {required bool correctAfterLayout}) {
    if (!_scrollController.hasClients) return;
    if (_jumpToBuiltColumnSlot(targetPage)) {
      if (correctAfterLayout) {
        _schedulePageCorrection(targetPage);
      }
      return;
    }

    try {
      final future = _observerController.jumpTo(
        index: targetPage,
        alignment: 0,
      );
      unawaited(
        future.then<void>(
          (_) {
            if (!mounted) return;
            if (correctAfterLayout) {
              _schedulePageCorrection(targetPage);
            }
          },
          onError: (_) {
            if (!mounted) return;
            _jumpToEstimatedColumnOffset(
              targetPage,
              correctAfterLayout: correctAfterLayout,
            );
          },
        ),
      );
    } catch (_) {
      _jumpToEstimatedColumnOffset(
        targetPage,
        correctAfterLayout: correctAfterLayout,
      );
    }
  }

  bool _jumpToBuiltColumnSlot(int targetPage) {
    if (targetPage < 0 || targetPage >= _slotKeys.length) return false;

    final pageContext = _slotKeys[targetPage].currentContext;
    if (pageContext == null) return false;

    Scrollable.ensureVisible(
      pageContext,
      alignment: 0,
      duration: Duration.zero,
      curve: Curves.linear,
    );
    return true;
  }

  void _jumpToEstimatedColumnOffset(
    int targetPage, {
    required bool correctAfterLayout,
  }) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = _estimatedPageOffset(
      targetPage,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.jumpTo(target.toDouble());

    if (correctAfterLayout) {
      _schedulePageCorrection(targetPage);
    }
  }

  void _schedulePageCorrection(int pageIndex) {
    _pageCorrectionTimer?.cancel();
    _pageCorrectionTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || _isSeeking || !_scrollController.hasClients) return;
      _correctToPage(pageIndex);
      _pageCorrectionTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted || _isSeeking || !_scrollController.hasClients) return;
        _correctToPage(pageIndex);
      });
    });
  }

  void _correctToPage(int pageIndex) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    if (!isColumnReadMode(readSetting.readMode)) {
      _jumpToPage(pageIndex);
      return;
    }

    final target = pageIndex.clamp(0, _lastPageIndex).toInt();
    if (target < 0 || target >= _slotKeys.length) return;

    if (!_jumpToBuiltColumnSlot(target)) {
      _jumpToPage(target);
    }
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      unawaited(_saveProgressNow());
    });
  }

  Future<void> _saveProgressNow() {
    if (widget.chapters.isEmpty || _slotCount <= 0) {
      return Future<void>.value();
    }
    return _historyManager.flushNow();
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
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    if (!isColumnReadMode(readSetting.readMode)) {
      if (!_pageController.hasClients) {
        _retryInitialPageRestore();
        return;
      }

      _shouldRestoreInitialPage = false;
      _pageController.jumpToPage(
        _initialPageIndex.clamp(0, _lastPageIndex).toInt(),
      );
      _readerCubit.updatePageIndex(_initialPageIndex);
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() {
          _isRestoringInitialPage = false;
        });
      });
      _scheduleProgressSave();
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
    _pageCorrectionTimer?.cancel();
    _sideEffects.stopAutoRead();
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
    _jumpToPage(pageIndex);
    unawaited(_saveProgressNow());
    _sideEffects.syncReadSetting(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
  }

  String _chapterTitle(int index) {
    return _sessionController.chapterTitle(index);
  }

  Future<void> _reloadChapter() {
    _sideEffects.hideEinkMask();
    _resetViewerTransformIfNeeded();
    _sessionController.removePrefetch(_chapterIndex);
    final future = _sessionController.loadChapter(_chapterIndex);
    setState(() {
      _chapterFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  bool _handleChapterBoundary(bool isNext) {
    if (_isSeeking || _isRestoringInitialPage || widget.chapters.isEmpty) {
      return false;
    }

    final targetIndex = _chapterIndex + (isNext ? 1 : -1);
    if (targetIndex < 0 || targetIndex >= widget.chapters.length) {
      return false;
    }

    _goToChapter(
      targetIndex,
      initialPageIndex: isNext ? 0 : _chapterEndPageIndex,
    );
    return true;
  }

  void _goToChapter(int index, {int initialPageIndex = 0}) {
    if (index < 0 ||
        index >= widget.chapters.length ||
        index == _chapterIndex) {
      return;
    }

    _progressSaveTimer?.cancel();
    _sideEffects.stopAutoRead();
    _sideEffects.hideEinkMask();
    _resetViewerTransformIfNeeded();
    unawaited(_saveProgressNow());
    _pageCorrectionTimer?.cancel();
    _historyManager.markLoading();
    final oldImageSizeCubit = _chapterView.reset();
    final targetInitialPageIndex = initialPageIndex < 0 ? 0 : initialPageIndex;
    setState(() {
      _chapterIndex = index;
      _chapterFuture = _sessionController.takeChapterFuture(index);
      _pageIndex = targetInitialPageIndex;
      _initialPageIndex = targetInitialPageIndex;
      _shouldRestoreInitialPage = targetInitialPageIndex > 0;
      _isRestoringInitialPage = targetInitialPageIndex > 0;
      _isRestoreScheduled = false;
      _restoreAttempts = 0;
    });
    unawaited(oldImageSizeCubit?.close());
    _readerCubit.updateTotalSlots(0);
    _readerCubit.updatePageIndex(0);

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
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

  void _handlePagedPageChanged(int pageIndex) {
    if (_isSeeking || _chapterPages.isEmpty) return;

    final safePageIndex = pageIndex.clamp(0, _lastPageIndex).toInt();
    if (safePageIndex != _pageIndex && mounted) {
      setState(() {
        _pageIndex = safePageIndex;
      });
    }
    _readerCubit.updatePageIndex(safePageIndex);
    _scheduleProgressSave();
    _resetViewerTransformIfNeeded();
    _sideEffects.triggerEinkDelay(
      context.read<GlobalSettingCubit>().state.readSetting,
    );

    if (_isMenuVisible) {
      _setMenuVisible(false);
    }
  }

  void _handleReaderLayoutChanged() {
    _progressSaveTimer?.cancel();
    _pageCorrectionTimer?.cancel();
    _sideEffects.hideEinkMask();
    _resetViewerTransformIfNeeded();
    setState(() {
      _pageIndex = 0;
      _initialPageIndex = 0;
      _shouldRestoreInitialPage = false;
      _isRestoringInitialPage = false;
      _restoreAttempts = 0;
    });
    _readerCubit.updatePageIndex(0);

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    _scheduleProgressSave();
  }

  Future<void> _showReaderSettings() {
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
    final effectiveDoublePageEnabled = _effectiveDoublePageEnabled(
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
                          child: FutureBuilder<ReaderChapterData>(
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
                              final chapterSnapshot = data.snapshot;
                              if (chapterSnapshot.pages.isEmpty) {
                                return _ReaderEmptyView(
                                  onRetry: _reloadChapter,
                                );
                              }

                              if (!_isChapterDataApplied(data)) {
                                _scheduleChapterDataApply(data, readSetting);
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                );
                              }

                              final imageSizeCubit = _imageSizeCubit;
                              if (imageSizeCubit == null) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                );
                              }
                              final enableDoublePage =
                                  effectiveDoublePageEnabled;
                              final slotCount = _slotCountFor(
                                readSetting,
                                buildContext: context,
                              );
                              final maxSlot = slotCount > 0 ? slotCount - 1 : 0;
                              final safePageIndex = _pageIndex
                                  .clamp(0, maxSlot)
                                  .toInt();
                              if (_readerCubit.state.totalSlots != slotCount ||
                                  _pageIndex != safePageIndex) {
                                _scheduleReaderMetricsSync(readSetting);
                              }

                              return BlocProvider.value(
                                value: imageSizeCubit,
                                child: isColumnReadMode(readSetting.readMode)
                                    ? _ReaderColumnImageList(
                                        pageKeys: _pageKeys,
                                        slotKeys: _slotKeys,
                                        providerId: chapterSnapshot.providerId,
                                        comicId: chapterSnapshot.comic.id,
                                        chapterId: chapterSnapshot.chapter.id,
                                        pages: chapterSnapshot.pages,
                                        controller: _scrollController,
                                        observerController: _observerController,
                                        enableDoublePage: enableDoublePage,
                                        isRtl: isReverseRowReadMode(
                                          readSetting.readMode,
                                        ),
                                        backgroundColor: backgroundColor,
                                        onPageObserved:
                                            _handleObservedPageIndex,
                                        onSizeResolved:
                                            _handleImageSizeResolved,
                                      )
                                    : _ReaderRowImagePager(
                                        pageKeys: _pageKeys,
                                        providerId: chapterSnapshot.providerId,
                                        comicId: chapterSnapshot.comic.id,
                                        chapterId: chapterSnapshot.chapter.id,
                                        pages: chapterSnapshot.pages,
                                        controller: _pageController,
                                        enableDoublePage: enableDoublePage,
                                        isRtl: isReverseRowReadMode(
                                          readSetting.readMode,
                                        ),
                                        backgroundColor: backgroundColor,
                                        onPageChanged: _handlePagedPageChanged,
                                        onSizeResolved:
                                            _handleImageSizeResolved,
                                      ),
                              );
                            },
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
                  onRefresh: _reloadChapter,
                ),
                _ReaderBottomOverlay(
                  isVisible: _isMenuVisible,
                  child: _ReaderBottomBar(
                    chapterCount: widget.chapters.length,
                    pageIndex: _pageIndex,
                    pageCount: _slotCount,
                    hasPrevious: hasPrevious,
                    hasNext: hasNext,
                    onProgressChangeStart: _handleProgressChangeStart,
                    onProgressChanged: _handleProgressChanged,
                    onProgressChangeEnd: _handleProgressChangeEnd,
                    onPrevious: () => _goToChapter(_chapterIndex - 1),
                    onChapterPicker: _showChapterPicker,
                    onSettings: () => unawaited(_showReaderSettings()),
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
      ),
    );
  }
}
