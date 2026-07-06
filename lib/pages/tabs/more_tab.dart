import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bika_provider.dart';
import '../../providers/provider_registry.dart';
import '../downloads_page.dart';
import '../system_settings_page.dart';

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
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const DownloadsPage(),
                    ),
                  );
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
                icon: Icons.settings_outlined,
                title: '系统设置',
                subtitle: '缓存、存储等',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const SystemSettingsPage(),
                    ),
                  );
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

                      return ListTile(
                        title: Text(provider.name),
                        subtitle: Text(provider.id),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (provider is BikaProvider)
                              IconButton(
                                tooltip: '登录设置',
                                icon: const Icon(Icons.manage_accounts),
                                onPressed: () =>
                                    _showBikaLoginSheet(context, provider),
                              ),
                            Switch(
                              value: isSubscribed,
                              onChanged: (value) {
                                if (value) {
                                  registry.subscribe(provider.id);
                                } else {
                                  registry.unsubscribe(provider.id);
                                }
                              },
                            ),
                          ],
                        ),
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

  void _showBikaLoginSheet(BuildContext context, BikaProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BikaLoginSheet(provider: provider),
    );
  }
}

class _BikaLoginSheet extends StatefulWidget {
  final BikaProvider provider;

  const _BikaLoginSheet({required this.provider});

  @override
  State<_BikaLoginSheet> createState() => _BikaLoginSheetState();
}

class _BikaLoginSheetState extends State<_BikaLoginSheet> {
  late final TextEditingController _accountController;
  late final TextEditingController _passwordController;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final setting = widget.provider.setting;
    _accountController = TextEditingController(text: setting.account);
    _passwordController = TextEditingController(text: setting.password);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.provider.loginWithPassword(
        account: _accountController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      _showMessage('哔咔登录成功');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearSession() async {
    await widget.provider.clearSession();
    if (!mounted) return;
    _showMessage('已清理登录状态');
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasToken = widget.provider.hasAuthorization;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('哔咔账号', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '账号',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isLoading ? null : _login,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('登录'),
            ),
            if (hasToken) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _isLoading ? null : () => _clearSession(),
                icon: const Icon(Icons.logout),
                label: const Text('清理登录状态'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
