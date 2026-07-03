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
import '../reader/reader_initial_page_restorer.dart';
import '../reader/reader_image_loader.dart';
import '../reader/reader_image_view.dart';
import '../reader/reader_layout.dart';
import '../reader/reader_page_info_overlay.dart';
import '../reader/reader_keyboard_shortcuts.dart';
import '../reader/reader_position_controller.dart';
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
  late final ReaderPositionController _positionController;
  late final ReaderInitialPageRestorer _initialPageRestorer;
  final ReaderChapterViewState _chapterView = ReaderChapterViewState();
  final ScrollController _scrollController = ScrollController();
  Timer? _progressSaveTimer;
  bool _isSeeking = false;
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
    _positionController = ReaderPositionController(
      context: context,
      scrollController: _scrollController,
      observerController: _observerController,
      pageController: _pageController,
      sideEffects: _sideEffects,
      isMounted: () => mounted,
      isSeeking: () => _isSeeking,
      hasPages: () => _chapterPages.isNotEmpty,
      lastPageIndex: () => _lastPageIndex,
      slotKeys: () => _slotKeys,
      estimatedPageOffset: _estimatedPageOffset,
      resetViewerTransform: _resetViewerTransformIfNeeded,
    );
    _initialPageRestorer = ReaderInitialPageRestorer(
      isMounted: () => mounted,
      requestRebuild: () {
        if (mounted) setState(() {});
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
    unawaited(_historyManager.init());
    _chapterFuture = _sessionController.loadChapter(_chapterIndex);
    _initialPageRestorer.configure(widget.initialPageIndex);
    _pageIndex = _initialPageRestorer.initialPageIndex;
    _readerCubit.updatePageIndex(_pageIndex);
    _scrollController.addListener(_handleScrollChanged);
    _sideEffects.applySystemUiVisibility(false, _readerSystemOverlayStyle);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _positionController.dispose();
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

  int _firstImageIndexForSlot(ReadSettingState readSetting, int slotIndex) {
    if (_chapterPages.isEmpty) return 0;
    final enableDoublePage = _effectiveDoublePageEnabled(readSetting);
    final imageIndex = enableDoublePage ? slotIndex * 2 : slotIndex;
    return imageIndex.clamp(0, _chapterPages.length - 1).toInt();
  }

  int _slotIndexForImage(ReadSettingState readSetting, int imageIndex) {
    final enableDoublePage = _effectiveDoublePageEnabled(readSetting);
    final slotIndex = enableDoublePage ? imageIndex ~/ 2 : imageIndex;
    final slotCount = _slotCountFor(readSetting);
    final maxSlot = slotCount > 0 ? slotCount - 1 : 0;
    return slotIndex.clamp(0, maxSlot).toInt();
  }

  int _pageIndexAfterLayoutChange(
    ReadSettingState previousReadSetting,
    ReadSettingState nextReadSetting,
  ) {
    final imageIndex = _firstImageIndexForSlot(
      previousReadSetting,
      _pageIndex,
    );
    return _slotIndexForImage(nextReadSetting, imageIndex);
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
      if (_initialPageRestorer.isRestoringInitialPage &&
          slotIndex <= _pageIndex) {
        _positionController.schedulePageCorrection(_pageIndex);
      }
    });
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
    _initialPageRestorer.schedule(_restoreInitialPage);
  }

  void _restoreInitialPage() {
    if (!mounted || !_initialPageRestorer.shouldRestoreInitialPage) return;
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

    _initialPageRestorer.markRestored();
    _positionController.jumpToPage(
      initialPageIndex,
      correctAfterLayout: true,
    );
    _readerCubit.updatePageIndex(initialPageIndex);
    _initialPageRestorer.finishRestoringDelayed();
    _scheduleProgressSave();
  }

  void _retryInitialPageRestore() {
    _initialPageRestorer.retry(_scheduleInitialPageRestore);
  }

  void _handleProgressChangeStart(double value) {
    _progressSaveTimer?.cancel();
    _positionController.cancelCorrection();
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
    _positionController.jumpToPage(pageIndex);
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
    if (_isSeeking ||
        _initialPageRestorer.isRestoringInitialPage ||
        widget.chapters.isEmpty) {
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
    _positionController.cancelCorrection();
    _historyManager.markLoading();
    final oldImageSizeCubit = _chapterView.reset();
    final targetInitialPageIndex = initialPageIndex < 0 ? 0 : initialPageIndex;
    setState(() {
      _chapterIndex = index;
      _chapterFuture = _sessionController.takeChapterFuture(index);
      _pageIndex = targetInitialPageIndex;
      _initialPageRestorer.configure(targetInitialPageIndex);
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

  void _handleReaderLayoutChanged(ReadSettingState previousReadSetting) {
    final nextReadSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final targetPageIndex = _pageIndexAfterLayoutChange(
      previousReadSetting,
      nextReadSetting,
    );
    _progressSaveTimer?.cancel();
    _positionController.cancelCorrection();
    _sideEffects.hideEinkMask();
    _resetViewerTransformIfNeeded();
    setState(() {
      _pageIndex = targetPageIndex;
      _initialPageRestorer.reset();
    });
    _readerCubit.updateTotalSlots(_slotCountFor(nextReadSetting));
    _readerCubit.updatePageIndex(targetPageIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _positionController.jumpToPage(
        targetPageIndex,
        correctAfterLayout: isColumnReadMode(nextReadSetting.readMode),
      );
      _scheduleProgressSave();
    });
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
