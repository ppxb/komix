part of 'reader_page.dart';

class _ReaderAutoReadButton extends StatelessWidget {
  final bool isMenuVisible;
  final bool isPaused;
  final VoidCallback onPressed;

  const _ReaderAutoReadButton({
    required this.isMenuVisible,
    required this.isPaused,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      right: 16,
      bottom: (isMenuVisible ? 104.0 : 16.0) + bottomPadding,
      child: FloatingActionButton.small(
        heroTag: 'reader_auto_read_toggle',
        tooltip: isPaused ? '继续自动阅读' : '暂停自动阅读',
        onPressed: onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            key: ValueKey(isPaused),
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
  final VoidCallback onSettings;
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
    required this.onSettings,
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
                        tooltip: '阅读设置',
                        onPressed: onSettings,
                        icon: Icons.tune,
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
