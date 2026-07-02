import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/provider_registry.dart';

/// 更多 Tab - 设置和其他功能
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        children: [
          // 数据源管理
          _buildSection(
            context,
            title: '数据源',
            children: [
              _buildListTile(
                context,
                icon: Icons.source_outlined,
                title: '数据源管理',
                subtitle: '管理订阅的数据源',
                onTap: () {
                  _showProviderManagement(context);
                },
              ),
            ],
          ),

          const Divider(),

          // 阅读设置
          _buildSection(
            context,
            title: '阅读',
            children: [
              _buildListTile(
                context,
                icon: Icons.auto_stories_outlined,
                title: '阅读设置',
                subtitle: '阅读模式、翻页方向等',
                onTap: () {
                  // TODO: 导航到阅读设置
                },
              ),
              _buildListTile(
                context,
                icon: Icons.download_outlined,
                title: '下载管理',
                subtitle: '管理已下载的漫画',
                onTap: () {
                  // TODO: 导航到下载管理
                },
              ),
            ],
          ),

          const Divider(),

          // 应用设置
          _buildSection(
            context,
            title: '应用',
            children: [
              _buildListTile(
                context,
                icon: Icons.palette_outlined,
                title: '外观设置',
                subtitle: '主题、字体等',
                onTap: () {
                  // TODO: 导航到外观设置
                },
              ),
              _buildListTile(
                context,
                icon: Icons.info_outline,
                title: '关于',
                subtitle: '版本信息',
                onTap: () {
                  _showAboutDialog(context);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showProviderManagement(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _ProviderManagementSheet(),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Komix',
      applicationVersion: '0.1.0',
      applicationIcon: const FlutterLogo(size: 48),
      children: [
        const Text('一个跨平台的漫画阅读器'),
        const SizedBox(height: 16),
        const Text('采用 Flutter + Rust 构建'),
      ],
    );
  }
}

/// 数据源管理弹窗
class _ProviderManagementSheet extends StatelessWidget {
  const _ProviderManagementSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '数据源管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 数据源列表
            Expanded(
              child: Consumer<ProviderRegistry>(
                builder: (context, registry, child) {
                  final allProviders = registry.getAllProviders();

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: allProviders.length,
                    itemBuilder: (context, index) {
                      final provider = allProviders[index];
                      final isSubscribed = registry.isSubscribed(provider.id);

                      return SwitchListTile(
                        title: Text(provider.name),
                        subtitle: Text(provider.id),
                        value: isSubscribed,
                        onChanged: (value) {
                          if (value) {
                            registry.subscribe(provider.id);
                          } else {
                            registry.unsubscribe(provider.id);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
