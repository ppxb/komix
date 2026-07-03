import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config/global/global_setting.dart';
import '../models/reader_snapshot.dart';
import 'image_size_cubit.dart';
import 'reader_layout.dart';

class ReaderLayoutMetrics {
  final BuildContext context;
  final ScrollController scrollController;
  final bool Function() isMounted;
  final List<ReaderPageImage> Function() pages;
  final ImageSizeCubit? Function() imageSizeCubit;
  final double defaultAspectRatio;

  ReaderLayoutMetrics({
    required this.context,
    required this.scrollController,
    required this.isMounted,
    required this.pages,
    required this.imageSizeCubit,
    required this.defaultAspectRatio,
  });

  int get slotCount {
    if (pages().isEmpty || !isMounted()) return 0;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    return slotCountFor(readSetting);
  }

  int get lastPageIndex {
    final count = slotCount;
    if (count <= 0) return 0;
    return count - 1;
  }

  bool effectiveDoublePageEnabled(
    ReadSettingState readSetting, {
    BuildContext? buildContext,
  }) {
    final contextForSize = buildContext ?? context;
    final size = MediaQuery.maybeSizeOf(contextForSize);
    final isCompact = size != null && size.shortestSide < 600;
    return readSetting.doublePageMode && !isCompact;
  }

  int slotCountFor(
    ReadSettingState readSetting, {
    BuildContext? buildContext,
  }) {
    return getReadModeSlotCount(
      imageCount: pages().length,
      enableDoublePage: effectiveDoublePageEnabled(
        readSetting,
        buildContext: buildContext,
      ),
    );
  }

  int pageIndexAfterLayoutChange({
    required ReadSettingState previousReadSetting,
    required ReadSettingState nextReadSetting,
    required int currentPageIndex,
  }) {
    final imageIndex = firstImageIndexForSlot(
      previousReadSetting,
      currentPageIndex,
    );
    return slotIndexForImage(nextReadSetting, imageIndex);
  }

  int firstImageIndexForSlot(ReadSettingState readSetting, int slotIndex) {
    final currentPages = pages();
    if (currentPages.isEmpty) return 0;
    final enableDoublePage = effectiveDoublePageEnabled(readSetting);
    final imageIndex = enableDoublePage ? slotIndex * 2 : slotIndex;
    return imageIndex.clamp(0, currentPages.length - 1).toInt();
  }

  int slotIndexForImage(ReadSettingState readSetting, int imageIndex) {
    final enableDoublePage = effectiveDoublePageEnabled(readSetting);
    final slotIndex = enableDoublePage ? imageIndex ~/ 2 : imageIndex;
    final count = slotCountFor(readSetting);
    final maxSlot = count > 0 ? count - 1 : 0;
    return slotIndex.clamp(0, maxSlot).toInt();
  }

  double readerContentWidth() {
    final containerWidth = _readerPageWidth();
    if (containerWidth <= 0) return 0;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    return getConstrainedImageWidth(
      containerWidth: containerWidth,
      enableSidePadding: readSetting.sidePaddingEnabled,
      sidePaddingPercent: readSetting.sidePaddingPercent,
    );
  }

  double estimatedPageOffset(int pageIndex) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final enableDoublePage = effectiveDoublePageEnabled(readSetting);
    final width = readerContentWidth();
    final target = pageIndex.clamp(0, lastPageIndex).toInt();
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

  double _readerPageWidth() {
    if (!isMounted()) return 0;
    final size = MediaQuery.maybeSizeOf(context);
    if (size != null) return size.width;
    if (scrollController.hasClients) {
      return scrollController.position.viewportDimension;
    }
    return 0;
  }

  double _estimatedImageHeight(int index, double width) {
    final currentPages = pages();
    if (width <= 0 || index < 0 || index >= currentPages.length) return 0;
    final size = imageSizeCubit()?.state.getSizeValue(index);
    if (size != null && size.width > 0 && size.height > 0) {
      if ((size.width - width).abs() < 0.1) return size.height;
      return width * size.height / size.width;
    }
    return width * defaultAspectRatio;
  }

  double _estimatedSlotHeight({
    required int slotIndex,
    required double width,
    required bool enableDoublePage,
  }) {
    if (width <= 0) return 0;
    if (!enableDoublePage) {
      return _estimatedImageHeight(slotIndex, width);
    }

    const panelGap = 6.0;
    final panelWidth = ((width - panelGap) / 2).clamp(1.0, width).toDouble();
    final firstIndex = slotIndex * 2;
    final secondIndex = firstIndex + 1;
    final firstHeight = _estimatedImageHeight(firstIndex, panelWidth);
    final secondHeight = secondIndex < pages().length
        ? _estimatedImageHeight(secondIndex, panelWidth)
        : 0.0;
    return firstHeight > secondHeight ? firstHeight : secondHeight;
  }
}
