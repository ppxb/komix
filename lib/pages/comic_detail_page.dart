import 'package:flutter/material.dart';

import '../models/comic.dart';
import '../providers/provider_registry.dart';

class ComicDetailPage extends StatefulWidget {
  final String providerId;
  final Comic initialComic;

  const ComicDetailPage({
    super.key,
    required this.providerId,
    required this.initialComic,
  });

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Future<_ComicDetailData> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<_ComicDetailData> _loadDetail() async {
    final provider = ProviderRegistry().getProvider(widget.providerId);
    if (provider == null) {
      throw StateError('未找到数据源: ${widget.providerId}');
    }

    final results = await Future.wait<Object>([
      provider.getComicDetail(widget.initialComic.id),
      provider.getChapters(widget.initialComic.id),
    ]);

    return _ComicDetailData(
      comic: results[0] as Comic,
      chapters: results[1] as List<Chapter>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialComic.title)),
      body: FutureBuilder<_ComicDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _DetailBody(
              comic: widget.initialComic,
              chapters: const [],
              isLoading: true,
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _detailFuture = _loadDetail();
                });
              },
            );
          }

          final data = snapshot.requireData;
          return _DetailBody(comic: data.comic, chapters: data.chapters);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Comic comic;
  final List<Chapter> chapters;
  final bool isLoading;

  const _DetailBody({
    required this.comic,
    required this.chapters,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 168,
                child: Image.network(
                  comic.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(
                      color: Color(0xFFE0E0E0),
                      child: Center(child: Icon(Icons.broken_image)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (comic.author.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      comic.author.join(' / '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(icon: Icons.favorite_border, label: '${comic.likes}'),
                      _MetaChip(icon: Icons.visibility_outlined, label: '${comic.views}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
        ],
        if (comic.tags.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: comic.tags.map((tag) => Chip(label: Text(tag))).toList(),
          ),
        ],
        if (comic.description.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('简介', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(comic.description),
        ],
        const SizedBox(height: 24),
        Text('章节', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (chapters.isEmpty && !isLoading)
          const Text('暂无章节')
        else
          ...chapters.map(
            (chapter) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(chapter.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('阅读器还没接上，章节数据已加载')),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicDetailData {
  final Comic comic;
  final List<Chapter> chapters;

  const _ComicDetailData({required this.comic, required this.chapters});
}
