import 'package:flutter/material.dart';
import 'tabs/browse/browse_tab.dart';
import 'tabs/favorite_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/more_tab.dart';

/// 主页面 - 底部导航容器
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
      const BrowseTab(),
      const FavoriteTab(),
      HistoryTab(refreshVersion: _historyRefreshVersion),
      const MoreTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _buildTabs()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 2) {
              _historyRefreshVersion += 1;
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '浏览',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: '更多',
          ),
        ],
      ),
    );
  }
}
