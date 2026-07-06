import 'package:flutter/material.dart';
import 'downloads_page.dart';
import 'tabs/bookshelf_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/more_tab.dart';

// 主页面 - 底部导航容器
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  int _historyRefreshVersion = 0;

  List<Widget> _buildTabs() {
    return [
      const BookshelfTab(),
      const DiscoverTab(),
      HistoryTab(refreshVersion: _historyRefreshVersion),
      const DownloadsPage(),
      const MoreTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _buildTabs()),
      bottomNavigationBar: _KomixBottomTabs(
        currentIndex: _currentIndex,
        onSelected: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 2) {
              _historyRefreshVersion += 1;
            }
          });
        },
        tabs: const [
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
        ],
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
        minimum: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          height: 70,
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
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      color: labelColor,
      fontSize: 14,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.1,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedDestinationIcon(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                selected: selected,
              ),
              const SizedBox(height: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style:
                    textStyle ??
                    TextStyle(
                      color: labelColor,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1.1,
                    ),
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 32,
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
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
          size: 24,
          color: selected
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
