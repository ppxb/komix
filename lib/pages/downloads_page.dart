import 'dart:async';

import 'package:flutter/material.dart';

import '../services/download_service.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late Future<List<DownloadTaskView>> _tasksFuture;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _loadTasks();
    DownloadService.instance.revision.addListener(_handleDownloadsChanged);
  }

  @override
  void dispose() {
    DownloadService.instance.revision.removeListener(_handleDownloadsChanged);
    super.dispose();
  }

  Future<List<DownloadTaskView>> _loadTasks() {
    return DownloadService.instance.getTasks();
  }

  Future<void> _refreshTasks() {
    final future = _loadTasks();
    setState(() {
      _tasksFuture = future;
    });
    return future.then<void>((_) {}, onError: (_) {});
  }

  void _handleDownloadsChanged() {
    if (!mounted) return;
    unawaited(_refreshTasks());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: FutureBuilder<List<DownloadTaskView>>(
        future: _tasksFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <DownloadTaskView>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && items.isEmpty) {
            return _DownloadMessage(
              icon: Icons.error_outline,
              text: snapshot.error.toString(),
            );
          }

          if (items.isEmpty) {
            return const _DownloadMessage(
              icon: Icons.download_outlined,
              text: '暂无下载任务',
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: _refreshTasks,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: _DownloadStatusIcon(item: item),
                  title: Text(
                    item.comicName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.status.isEmpty ? '等待下载' : item.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DownloadStatusIcon extends StatelessWidget {
  final DownloadTaskView item;

  const _DownloadStatusIcon({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isDownloading) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (item.isCompleted && item.status.startsWith('下载失败')) {
      return Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      );
    }

    if (item.isCompleted) {
      return Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return const Icon(Icons.schedule);
  }
}

class _DownloadMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DownloadMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
