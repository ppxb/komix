import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comic.dart';
import '../services/download_service.dart';
import '../util/foreground_task/data/download_task_json.dart';

class DownloadChapterSelectionPage extends StatefulWidget {
  final String providerId;
  final Comic comic;
  final List<Chapter> chapters;

  const DownloadChapterSelectionPage({
    super.key,
    required this.providerId,
    required this.comic,
    required this.chapters,
  });

  @override
  State<DownloadChapterSelectionPage> createState() =>
      _DownloadChapterSelectionPageState();
}

class _DownloadChapterSelectionPageState
    extends State<DownloadChapterSelectionPage> {
  final Map<String, bool> _selectedByKey = <String, bool>{};
  Set<String> _downloadedKeys = const <String>{};
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDownloadedState());
  }

  Future<void> _loadDownloadedState() async {
    final downloadedKeys = await DownloadService.instance
        .getDownloadedChapterKeys(
          providerId: widget.providerId,
          comicId: widget.comic.id,
        );
    if (!mounted) return;

    setState(() {
      _downloadedKeys = downloadedKeys;
      _selectedByKey
        ..clear()
        ..addEntries(
          widget.chapters.map((chapter) {
            final key = _selectionKey(chapter);
            return MapEntry(key, !_isChapterDownloaded(chapter));
          }),
        );
      _isLoading = false;
    });
  }

  int get _selectableCount =>
      widget.chapters.where((chapter) => !_isChapterDownloaded(chapter)).length;

  int get _selectedCount => widget.chapters
      .where((chapter) => _selectedByKey[_selectionKey(chapter)] == true)
      .length;

  bool get _allSelectableSelected =>
      _selectableCount > 0 && _selectedCount >= _selectableCount;

  void _toggleChapter(Chapter chapter) {
    if (_isSubmitting || _isChapterDownloaded(chapter)) return;
    final key = _selectionKey(chapter);
    setState(() {
      _selectedByKey[key] = !(_selectedByKey[key] ?? false);
    });
  }

  void _toggleSelectAll() {
    if (_isSubmitting || _selectableCount == 0) return;
    final nextSelected = !_allSelectableSelected;
    setState(() {
      for (final chapter in widget.chapters) {
        if (_isChapterDownloaded(chapter)) continue;
        _selectedByKey[_selectionKey(chapter)] = nextSelected;
      }
    });
  }

  Future<void> _startDownload() async {
    if (_isSubmitting) return;
    final selectedChapters = widget.chapters
        .where((chapter) => _selectedByKey[_selectionKey(chapter)] == true)
        .toList(growable: false);
    if (selectedChapters.isEmpty) {
      _showMessage('请选择要下载的章节');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final enqueued = await DownloadService.instance.enqueueComic(
        providerId: widget.providerId,
        comic: widget.comic,
        chapters: selectedChapters,
        chapterRefs: selectedChapters.map(_taskRefFromChapter).toList(),
      );
      if (!mounted) return;
      if (!enqueued) {
        _showMessage('下载任务已存在');
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  DownloadChapterTaskRef _taskRefFromChapter(Chapter chapter) {
    final key = _selectionKey(chapter);
    return DownloadChapterTaskRef(
      chapterId: chapter.id,
      requestId: chapter.id,
      storageChapterId: chapter.id,
      logicalKey: key,
      title: _chapterTitle(chapter),
      order: chapter.order,
    );
  }

  bool _isChapterDownloaded(Chapter chapter) {
    final probes = <String>{_selectionKey(chapter)};
    final id = chapter.id.trim();
    if (id.isNotEmpty) probes.add(id);
    if (chapter.order > 0) probes.add(chapter.order.toString());
    return probes.any(_downloadedKeys.contains);
  }

  String _selectionKey(Chapter chapter) {
    return DownloadService.chapterSelectionKey(chapter);
  }

  String _chapterTitle(Chapter chapter) {
    if (widget.chapters.length == 1) return '单章节';
    final name = chapter.name.trim();
    return name.isEmpty ? '第 ${chapter.order} 章' : name;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedCount;
    final selectableCount = _selectableCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择下载章节'),
        actions: [
          IconButton(
            tooltip: _allSelectableSelected ? '取消全选' : '全选',
            onPressed: _isLoading || _isSubmitting || selectableCount == 0
                ? null
                : _toggleSelectAll,
            icon: Icon(
              _allSelectableSelected
                  ? Icons.deselect_outlined
                  : Icons.select_all_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: !_isLoading && !_isSubmitting && selectedCount > 0
            ? () => unawaited(_startDownload())
            : null,
        icon: _isSubmitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined),
        label: Text(
          selectedCount > 0
              ? '下载 $selectedCount 章'
              : selectableCount == 0
              ? '已全部下载'
              : '开始下载',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _DownloadChapterSelectionBody(
              chapters: widget.chapters,
              selectedByKey: _selectedByKey,
              selectedCount: selectedCount,
              selectableCount: selectableCount,
              isSubmitting: _isSubmitting,
              isDownloaded: _isChapterDownloaded,
              selectionKey: _selectionKey,
              chapterTitle: _chapterTitle,
              onToggle: _toggleChapter,
            ),
    );
  }
}

class _DownloadChapterSelectionBody extends StatelessWidget {
  final List<Chapter> chapters;
  final Map<String, bool> selectedByKey;
  final int selectedCount;
  final int selectableCount;
  final bool isSubmitting;
  final bool Function(Chapter chapter) isDownloaded;
  final String Function(Chapter chapter) selectionKey;
  final String Function(Chapter chapter) chapterTitle;
  final void Function(Chapter chapter) onToggle;

  const _DownloadChapterSelectionBody({
    required this.chapters,
    required this.selectedByKey,
    required this.selectedCount,
    required this.selectableCount,
    required this.isSubmitting,
    required this.isDownloaded,
    required this.selectionKey,
    required this.chapterTitle,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return const _DownloadSelectionMessage(
        icon: Icons.menu_book_outlined,
        text: '暂无可下载章节',
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: chapters.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          final downloadedCount = chapters.length - selectableCount;
          return Text(
            '已选择 $selectedCount / $selectableCount 章'
            '${downloadedCount > 0 ? '，已下载 $downloadedCount 章' : ''}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          );
        }

        final chapter = chapters[index - 1];
        final downloaded = isDownloaded(chapter);
        final selected = selectedByKey[selectionKey(chapter)] == true;
        return _DownloadChapterTile(
          title: chapterTitle(chapter),
          order: chapter.order,
          selected: selected,
          downloaded: downloaded,
          enabled: !isSubmitting && !downloaded,
          onTap: () => onToggle(chapter),
        );
      },
    );
  }
}

class _DownloadChapterTile extends StatelessWidget {
  final String title;
  final int order;
  final bool selected;
  final bool downloaded;
  final bool enabled;
  final VoidCallback onTap;

  const _DownloadChapterTile({
    required this.title,
    required this.order,
    required this.selected,
    required this.downloaded,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primaryContainer.withValues(alpha: 0.32);
    final normalColor = colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.42,
    );

    return Material(
      color: downloaded || selected ? selectedColor : normalColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                downloaded || selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: downloaded
                    ? colorScheme.outline
                    : selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: selected || downloaded
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (order > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '第 $order 章',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (downloaded) ...[
                const SizedBox(width: 8),
                Chip(
                  label: const Text('已下载'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadSelectionMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DownloadSelectionMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
