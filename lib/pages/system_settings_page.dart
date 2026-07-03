import 'package:flutter/material.dart';

import '../services/cache_maintenance_service.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  late Future<CacheStats> _cacheStatsFuture;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _cacheStatsFuture = CacheMaintenanceService.instance.getStats();
  }

  Future<void> _refreshCacheStats() async {
    setState(() {
      _cacheStatsFuture = CacheMaintenanceService.instance.getStats();
    });
    await _cacheStatsFuture;
  }

  Future<void> _confirmClearCache() async {
    if (_isClearingCache) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除缓存'),
          content: const Text('将删除已缓存的图片、详情数据和阅读章节快照。已下载内容不会被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearingCache = true;
    });
    try {
      await CacheMaintenanceService.instance.clearCache();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
      await _refreshCacheStats();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除缓存失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: RefreshIndicator(
        onRefresh: _refreshCacheStats,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '缓存',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            FutureBuilder<CacheStats>(
              future: _cacheStatsFuture,
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storage_outlined),
                      title: const Text('缓存大小'),
                      subtitle: Text(stats?.displaySize ?? '计算中'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('缓存目录'),
                      subtitle: Text(
                        stats?.path ?? '计算中',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ListTile(
                      leading: _isClearingCache
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cleaning_services_outlined),
                      title: const Text('清除缓存'),
                      subtitle: const Text('清除图片、详情、阅读快照和图片尺寸缓存'),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_isClearingCache,
                      onTap: _confirmClearCache,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
