import 'package:flutter/material.dart';
import 'search_page.dart';
import 'subscribe_page.dart';

/// 浏览 Tab - 包含搜索和订阅两个子页面
class BrowseTab extends StatefulWidget {
  const BrowseTab({super.key});

  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '搜索'),
            Tab(text: '订阅'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [SearchPage(), SubscribePage()],
      ),
    );
  }
}
