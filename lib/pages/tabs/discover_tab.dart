import 'package:flutter/material.dart';

import 'browse/search_page.dart';

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: const SearchPage(),
    );
  }
}
