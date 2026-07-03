part of 'reader_page.dart';

typedef _ScheduleChapterDataApply = void Function(
  ReaderChapterData data,
  ReadSettingState readSetting,
);

class _ReaderChapterContent extends StatelessWidget {
  final int chapterIndex;
  final Future<ReaderChapterData> chapterFuture;
  final ReadSettingState readSetting;
  final Color backgroundColor;
  final bool enableDoublePage;
  final int pageIndex;
  final ReaderCubit readerCubit;
  final ReaderLayoutMetrics layoutMetrics;
  final ImageSizeCubit? imageSizeCubit;
  final List<GlobalKey> pageKeys;
  final List<GlobalKey> slotKeys;
  final ScrollController scrollController;
  final ListObserverController observerController;
  final PageController pageController;
  final VoidCallback onRetry;
  final bool Function(ReaderChapterData data) isChapterDataApplied;
  final _ScheduleChapterDataApply scheduleChapterDataApply;
  final ValueChanged<ReadSettingState> scheduleReaderMetricsSync;
  final ValueChanged<int> onPageObserved;
  final ValueChanged<int> onPageChanged;
  final void Function(int index, Size size) onSizeResolved;

  const _ReaderChapterContent({
    required this.chapterIndex,
    required this.chapterFuture,
    required this.readSetting,
    required this.backgroundColor,
    required this.enableDoublePage,
    required this.pageIndex,
    required this.readerCubit,
    required this.layoutMetrics,
    required this.imageSizeCubit,
    required this.pageKeys,
    required this.slotKeys,
    required this.scrollController,
    required this.observerController,
    required this.pageController,
    required this.onRetry,
    required this.isChapterDataApplied,
    required this.scheduleChapterDataApply,
    required this.scheduleReaderMetricsSync,
    required this.onPageObserved,
    required this.onPageChanged,
    required this.onSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReaderChapterData>(
      key: ValueKey(chapterIndex),
      future: chapterFuture,
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
            onRetry: onRetry,
          );
        }

        final data = snapshot.requireData;
        final chapterSnapshot = data.snapshot;
        if (chapterSnapshot.pages.isEmpty) {
          return _ReaderEmptyView(onRetry: onRetry);
        }

        if (!isChapterDataApplied(data)) {
          scheduleChapterDataApply(data, readSetting);
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final currentImageSizeCubit = imageSizeCubit;
        if (currentImageSizeCubit == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final slotCount = layoutMetrics.slotCountFor(
          readSetting,
          buildContext: context,
        );
        final maxSlot = slotCount > 0 ? slotCount - 1 : 0;
        final safePageIndex = pageIndex.clamp(0, maxSlot).toInt();
        if (readerCubit.state.totalSlots != slotCount ||
            pageIndex != safePageIndex) {
          scheduleReaderMetricsSync(readSetting);
        }

        return BlocProvider.value(
          value: currentImageSizeCubit,
          child: isColumnReadMode(readSetting.readMode)
              ? _ReaderColumnImageList(
                  pageKeys: pageKeys,
                  slotKeys: slotKeys,
                  providerId: chapterSnapshot.providerId,
                  comicId: chapterSnapshot.comic.id,
                  chapterId: chapterSnapshot.chapter.id,
                  pages: chapterSnapshot.pages,
                  controller: scrollController,
                  observerController: observerController,
                  enableDoublePage: enableDoublePage,
                  isRtl: isReverseRowReadMode(readSetting.readMode),
                  backgroundColor: backgroundColor,
                  onPageObserved: onPageObserved,
                  onSizeResolved: onSizeResolved,
                )
              : _ReaderRowImagePager(
                  pageKeys: pageKeys,
                  providerId: chapterSnapshot.providerId,
                  comicId: chapterSnapshot.comic.id,
                  chapterId: chapterSnapshot.chapter.id,
                  pages: chapterSnapshot.pages,
                  controller: pageController,
                  enableDoublePage: enableDoublePage,
                  isRtl: isReverseRowReadMode(readSetting.readMode),
                  backgroundColor: backgroundColor,
                  onPageChanged: onPageChanged,
                  onSizeResolved: onSizeResolved,
                ),
        );
      },
    );
  }
}

class _ReaderColumnImageList extends StatelessWidget {
  final List<GlobalKey> pageKeys;
  final List<GlobalKey> slotKeys;
  final String providerId;
  final String comicId;
  final String chapterId;
  final List<ReaderPageImage> pages;
  final ScrollController controller;
  final ListObserverController observerController;
  final bool enableDoublePage;
  final bool isRtl;
  final Color backgroundColor;
  final ValueChanged<int> onPageObserved;
  final void Function(int index, Size size) onSizeResolved;

  const _ReaderColumnImageList({
    required this.pageKeys,
    required this.slotKeys,
    required this.providerId,
    required this.comicId,
    required this.chapterId,
    required this.pages,
    required this.controller,
    required this.observerController,
    required this.enableDoublePage,
    required this.isRtl,
    required this.backgroundColor,
    required this.onPageObserved,
    required this.onSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit cubit) => cubit.state.readSetting,
    );
    final slotCount = getReadModeSlotCount(
      imageCount: pages.length,
      enableDoublePage: enableDoublePage,
    );
    final listView = ListView.builder(
      controller: controller,
      scrollCacheExtent: const ScrollCacheExtent.viewport(2),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: slotCount,
      itemBuilder: (context, index) {
        if (enableDoublePage) {
          return _buildDoublePageSlot(context, index, readSetting);
        }
        return _buildSinglePageSlot(context, index, readSetting);
      },
    );

    return ListViewObserver(
      controller: observerController,
      onObserve: (resultMap) {
        final firstVisibleIndex = resultMap.firstChild?.index;
        if (firstVisibleIndex != null) {
          onPageObserved(firstVisibleIndex);
          return;
        }

        final visibleIndexes = resultMap.displayingChildIndexList;
        if (visibleIndexes.isEmpty) return;
        onPageObserved(visibleIndexes.first);
      },
      child: listView,
    );
  }

  Widget _buildSinglePageSlot(
    BuildContext context,
    int index,
    ReadSettingState readSetting,
  ) {
    final page = pages[index];
    return BlocSelector<
      ImageSizeCubit,
      ImageSizeState,
      ({Size size, bool isCached})
    >(
      selector: (state) => (
        size: state.getSizeValue(index),
        isCached: state.resolvedIndices.contains(index),
      ),
      builder: (context, cached) {
        final containerWidth = MediaQuery.sizeOf(context).width;
        final width = getConstrainedImageWidth(
          containerWidth: containerWidth,
          enableSidePadding: readSetting.sidePaddingEnabled,
          sidePaddingPercent: readSetting.sidePaddingPercent,
        );
        final displayHeight = cached.size.width > 0 && cached.size.height > 0
            ? width * cached.size.height / cached.size.width
            : width * _ReaderPageState._estimatedPageAspectRatio;
        return SizedBox(
          key: index < slotKeys.length ? slotKeys[index] : null,
          width: containerWidth,
          child: ColoredBox(
            color: backgroundColor,
            child: Center(
              child: ReaderImageView(
                key: index < pageKeys.length ? pageKeys[index] : null,
                request: _requestFor(page),
                pageNumber: index + 1,
                pageCount: pages.length,
                displaySize: Size(width, displayHeight),
                isSizeResolved: cached.isCached,
                onSizeResolved: (size) => onSizeResolved(index, size),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoublePageSlot(
    BuildContext context,
    int slotIndex,
    ReadSettingState readSetting,
  ) {
    const panelGap = 6.0;
    final leftIndex = slotIndex * 2;
    final rightIndex = leftIndex + 1;
    final containerWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = getConstrainedImageWidth(
      containerWidth: containerWidth,
      enableSidePadding: readSetting.sidePaddingEnabled,
      sidePaddingPercent: readSetting.sidePaddingPercent,
    );
    final panelWidth = ((contentWidth - panelGap) / 2)
        .clamp(1.0, contentWidth)
        .toDouble();

    return BlocSelector<
      ImageSizeCubit,
      ImageSizeState,
      (Size, Size, bool, bool)
    >(
      selector: (state) => (
        state.getSizeValue(leftIndex),
        rightIndex < pages.length
            ? state.getSizeValue(rightIndex)
            : const Size(0, 0),
        state.resolvedIndices.contains(leftIndex),
        state.resolvedIndices.contains(rightIndex),
      ),
      builder: (context, cached) {
        final leftHeight = _displayHeightFor(cached.$1, panelWidth);
        final rightHeight = rightIndex < pages.length
            ? _displayHeightFor(cached.$2, panelWidth)
            : 0.0;
        final slotHeight = (leftHeight > rightHeight ? leftHeight : rightHeight)
            .clamp(1.0, double.infinity)
            .toDouble();

        final leftChild = _buildPanelImage(
          index: leftIndex,
          width: panelWidth,
          height: slotHeight,
          isSizeResolved: cached.$3,
        );
        final rightChild = rightIndex < pages.length
            ? _buildPanelImage(
                index: rightIndex,
                width: panelWidth,
                height: slotHeight,
                isSizeResolved: cached.$4,
              )
            : SizedBox(width: panelWidth, height: slotHeight);
        final children = isRtl
            ? [rightChild, const SizedBox(width: panelGap), leftChild]
            : [leftChild, const SizedBox(width: panelGap), rightChild];

        return SizedBox(
          key: slotIndex < slotKeys.length ? slotKeys[slotIndex] : null,
          width: containerWidth,
          height: slotHeight,
          child: ColoredBox(
            color: backgroundColor,
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanelImage({
    required int index,
    required double width,
    required double height,
    required bool isSizeResolved,
  }) {
    final page = pages[index];
    return SizedBox(
      width: width,
      height: height,
      child: ReaderImageView(
        key: index < pageKeys.length ? pageKeys[index] : null,
        request: _requestFor(page),
        pageNumber: index + 1,
        pageCount: pages.length,
        displaySize: Size(width, height),
        isSizeResolved: isSizeResolved,
        onSizeResolved: (size) => onSizeResolved(index, size),
      ),
    );
  }

  double _displayHeightFor(Size cachedSize, double width) {
    if (cachedSize.width > 0 && cachedSize.height > 0) {
      return width * cachedSize.height / cachedSize.width;
    }
    return width * _ReaderPageState._estimatedPageAspectRatio;
  }

  ReaderImageRequest _requestFor(ReaderPageImage page) {
    return ReaderImageRequest(
      providerId: providerId,
      comicId: comicId,
      chapterId: chapterId,
      pageId: page.id,
      url: page.url,
      path: page.path,
      extern: page.extern,
    );
  }
}

class _ReaderRowImagePager extends StatelessWidget {
  final List<GlobalKey> pageKeys;
  final String providerId;
  final String comicId;
  final String chapterId;
  final List<ReaderPageImage> pages;
  final PageController controller;
  final bool enableDoublePage;
  final bool isRtl;
  final Color backgroundColor;
  final ValueChanged<int> onPageChanged;
  final void Function(int index, Size size) onSizeResolved;

  const _ReaderRowImagePager({
    required this.pageKeys,
    required this.providerId,
    required this.comicId,
    required this.chapterId,
    required this.pages,
    required this.controller,
    required this.enableDoublePage,
    required this.isRtl,
    required this.backgroundColor,
    required this.onPageChanged,
    required this.onSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit cubit) => cubit.state.readSetting,
    );
    final slotCount = getReadModeSlotCount(
      imageCount: pages.length,
      enableDoublePage: enableDoublePage,
    );

    return PageView.builder(
      controller: controller,
      reverse: isRtl,
      itemCount: slotCount,
      onPageChanged: onPageChanged,
      itemBuilder: (context, slotIndex) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final pageWidth = constraints.maxWidth;
            final pageHeight = constraints.maxHeight;
            final contentWidth = getConstrainedImageWidth(
              containerWidth: pageWidth,
              enableSidePadding: readSetting.sidePaddingEnabled,
              sidePaddingPercent: readSetting.sidePaddingPercent,
            );
            if (enableDoublePage) {
              return _buildDoublePage(
                slotIndex: slotIndex,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                contentWidth: contentWidth,
              );
            }
            return _buildSinglePage(
              imageIndex: slotIndex,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
              contentWidth: contentWidth,
            );
          },
        );
      },
    );
  }

  Widget _buildSinglePage({
    required int imageIndex,
    required double pageWidth,
    required double pageHeight,
    required double contentWidth,
  }) {
    return SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: ColoredBox(
        color: backgroundColor,
        child: Center(
          child: _buildImage(
            imageIndex: imageIndex,
            maxWidth: contentWidth,
            maxHeight: pageHeight,
          ),
        ),
      ),
    );
  }

  Widget _buildDoublePage({
    required int slotIndex,
    required double pageWidth,
    required double pageHeight,
    required double contentWidth,
  }) {
    const panelGap = 6.0;
    final leftIndex = slotIndex * 2;
    final rightIndex = leftIndex + 1;
    final panelWidth = ((contentWidth - panelGap) / 2)
        .clamp(1.0, contentWidth)
        .toDouble();
    final leftChild = _buildPanel(
      imageIndex: leftIndex,
      width: panelWidth,
      height: pageHeight,
    );
    final rightChild = rightIndex < pages.length
        ? _buildPanel(
            imageIndex: rightIndex,
            width: panelWidth,
            height: pageHeight,
          )
        : SizedBox(width: panelWidth, height: pageHeight);
    final children = isRtl
        ? [rightChild, const SizedBox(width: panelGap), leftChild]
        : [leftChild, const SizedBox(width: panelGap), rightChild];

    return SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: ColoredBox(
        color: backgroundColor,
        child: Center(
          child: SizedBox(
            width: contentWidth,
            child: Row(children: children),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel({
    required int imageIndex,
    required double width,
    required double height,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: _buildImage(
          imageIndex: imageIndex,
          maxWidth: width,
          maxHeight: height,
        ),
      ),
    );
  }

  Widget _buildImage({
    required int imageIndex,
    required double maxWidth,
    required double maxHeight,
  }) {
    final page = pages[imageIndex];
    return BlocSelector<
      ImageSizeCubit,
      ImageSizeState,
      ({Size size, bool isCached})
    >(
      selector: (state) => (
        size: state.getSizeValue(imageIndex),
        isCached: state.resolvedIndices.contains(imageIndex),
      ),
      builder: (context, cached) {
        final displaySize = _containedImageSize(
          sourceSize: cached.size,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
        return SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: ReaderImageView(
            key: imageIndex < pageKeys.length ? pageKeys[imageIndex] : null,
            request: ReaderImageRequest(
              providerId: providerId,
              comicId: comicId,
              chapterId: chapterId,
              pageId: page.id,
              url: page.url,
              path: page.path,
              extern: page.extern,
            ),
            pageNumber: imageIndex + 1,
            pageCount: pages.length,
            displaySize: displaySize,
            isSizeResolved: cached.isCached,
            onSizeResolved: (size) => onSizeResolved(imageIndex, size),
          ),
        );
      },
    );
  }

  Size _containedImageSize({
    required Size sourceSize,
    required double maxWidth,
    required double maxHeight,
  }) {
    final safeMaxWidth = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 1.0;
    final safeMaxHeight = maxHeight.isFinite && maxHeight > 0
        ? maxHeight
        : safeMaxWidth * _ReaderPageState._estimatedPageAspectRatio;
    final sourceWidth = sourceSize.width > 0 ? sourceSize.width : safeMaxWidth;
    final sourceHeight = sourceSize.height > 0
        ? sourceSize.height
        : sourceWidth * _ReaderPageState._estimatedPageAspectRatio;
    final widthScale = safeMaxWidth / sourceWidth;
    final heightScale = safeMaxHeight / sourceHeight;
    final scale = widthScale < heightScale ? widthScale : heightScale;

    if (!scale.isFinite || scale <= 0) {
      return Size(safeMaxWidth, safeMaxHeight);
    }
    return Size(
      (sourceWidth * scale).clamp(1.0, safeMaxWidth).toDouble(),
      (sourceHeight * scale).clamp(1.0, safeMaxHeight).toDouble(),
    );
  }
}
