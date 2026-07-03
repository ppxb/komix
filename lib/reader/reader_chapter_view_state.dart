import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/reader_snapshot.dart';
import 'image_size_cubit.dart';
import 'reader_session_controller.dart';

class ReaderChapterViewState {
  ReaderChapterSnapshot? snapshot;
  List<ReaderPageImage> pages = const [];
  List<GlobalKey> pageKeys = const [];
  List<GlobalKey> slotKeys = const [];
  List<String> pageSizeKeys = const [];
  ImageSizeCubit? imageSizeCubit;

  bool get hasPages => pages.isNotEmpty;

  bool hasSamePages(ReaderChapterSnapshot nextSnapshot) {
    if (snapshot?.chapter.id != nextSnapshot.chapter.id ||
        pages.length != nextSnapshot.pages.length) {
      return false;
    }

    for (var i = 0; i < pages.length; i++) {
      if (pages[i].cacheKey != nextSnapshot.pages[i].cacheKey) {
        return false;
      }
    }
    return true;
  }

  bool isApplied(ReaderChapterSnapshot nextSnapshot) {
    return imageSizeCubit != null && hasSamePages(nextSnapshot);
  }

  bool applySnapshot({
    required ReaderChapterSnapshot nextSnapshot,
    required Map<int, Size> persistedSizes,
    required String sourceTag,
    required double defaultWidth,
    required double defaultAspectRatio,
  }) {
    if (hasSamePages(nextSnapshot)) {
      return false;
    }

    snapshot = nextSnapshot;
    pages = nextSnapshot.pages;
    pageSizeKeys = ReaderSessionController.buildPageSizeKeys(nextSnapshot);
    pageKeys = List<GlobalKey>.generate(
      nextSnapshot.pages.length,
      (_) => GlobalKey(),
      growable: false,
    );
    slotKeys = List<GlobalKey>.generate(
      nextSnapshot.pages.length,
      (_) => GlobalKey(),
      growable: false,
    );

    final oldCubit = imageSizeCubit;
    imageSizeCubit = ImageSizeCubit.create(
      defaultWidth: defaultWidth > 0 ? defaultWidth : 1,
      count: nextSnapshot.pages.length,
      sourceTag: sourceTag,
      pageKeys: pageSizeKeys,
      defaultAspectRatio: defaultAspectRatio,
      persistedCache: persistedSizes,
    );
    unawaited(oldCubit?.close());
    return true;
  }

  ImageSizeCubit? reset() {
    final oldCubit = imageSizeCubit;
    snapshot = null;
    pages = const [];
    pageSizeKeys = const [];
    pageKeys = const [];
    slotKeys = const [];
    imageSizeCubit = null;
    return oldCubit;
  }

  Future<void> close() async {
    await imageSizeCubit?.close();
  }
}
