import 'package:flutter/material.dart';
import 'downloads_page.dart';
import 'tabs/bookshelf_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/more_tab.dart';

class _BottomTabsStyle {
  static const double barHeight = 72;
  static const double iconContainerWidth = 54;
  static const double iconContainerHeight = 32;
  static const double iconSize = 24;
  static const double iconRadius = 18;
  static const double iconTextGap = 8;
  static const double labelFontSize = 14;

  static const EdgeInsets tabPadding = EdgeInsets.only(top: 7, bottom: 5);
  static const EdgeInsets safeAreaMinimum = EdgeInsets.only(bottom: 10);

  static const Duration iconSwitchDuration = Duration(milliseconds: 220);
  static const Duration labelSwitchDuration = Duration(milliseconds: 180);
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  // TODO: SHOULD REFACTOR
  int _historyRefreshVersion = 0;

  static const _tabs = [
    _BottomTabItem(
      icon: Icons.collections_bookmark_outlined,
      selectedIcon: Icons.collections_bookmark,
      label: '书架',
    ),
    _BottomTabItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: '发现',
    ),
    _BottomTabItem(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: '历史',
    ),
    _BottomTabItem(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
      label: '下载',
    ),
    _BottomTabItem(
      icon: Icons.more_horiz_outlined,
      selectedIcon: Icons.more_horiz,
      label: '更多',
    ),
  ];

  static const int _historyTabIndex = 2;

  List<Widget> _buildTabs() {
    return [
      const BookshelfTab(),
      const DiscoverTab(),
      HistoryTab(refreshVersion: _historyRefreshVersion),
      const DownloadsPage(),
      const MoreTab(),
    ];
  }

  void _handleTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      if (index == _historyTabIndex) {
        _historyRefreshVersion += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _buildTabs()),
      bottomNavigationBar: _KomixBottomTabs(
        currentIndex: _currentIndex,
        onSelected: _handleTabSelected,
        tabs: _tabs,
      ),
    );
  }
}

class _KomixBottomTabs extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<_BottomTabItem> tabs;

  const _KomixBottomTabs({
    required this.currentIndex,
    required this.onSelected,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.62 : 0.82,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: _BottomTabsStyle.safeAreaMinimum,
        child: SizedBox(
          height: _BottomTabsStyle.barHeight,
          child: Row(
            children: [
              for (var index = 0; index < tabs.length; index += 1)
                Expanded(
                  child: _BottomTab(
                    item: tabs[index],
                    selected: currentIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  final _BottomTabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _BottomTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final fontWeight = selected ? FontWeight.w600 : FontWeight.w500;

    final fallbackTextStyle = TextStyle(
      color: labelColor,
      fontSize: _BottomTabsStyle.labelFontSize,
      fontWeight: fontWeight,
      height: 1.1,
    );
    final textStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: labelColor,
          fontSize: _BottomTabsStyle.labelFontSize,
          fontWeight: fontWeight,
          height: 1.1,
        ) ??
        fallbackTextStyle;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: _BottomTabsStyle.tabPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedDestinationIcon(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                selected: selected,
              ),
              const SizedBox(height: _BottomTabsStyle.iconTextGap),
              AnimatedDefaultTextStyle(
                duration: _BottomTabsStyle.labelSwitchDuration,
                curve: Curves.easeOutCubic,
                style: textStyle,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _BottomTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _AnimatedDestinationIcon extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;

  const _AnimatedDestinationIcon({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeIcon = selected ? selectedIcon : icon;

    return AnimatedContainer(
      duration: _BottomTabsStyle.iconSwitchDuration,
      curve: Curves.easeOutCubic,
      width: _BottomTabsStyle.iconContainerWidth,
      height: _BottomTabsStyle.iconContainerHeight,
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(_BottomTabsStyle.iconRadius),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: _BottomTabsStyle.iconSwitchDuration,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final scale = Tween<double>(begin: 0.78, end: 1).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        child: Icon(
          activeIcon,
          key: ValueKey<IconData>(activeIcon),
          size: _BottomTabsStyle.iconSize,
          color: selected
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
