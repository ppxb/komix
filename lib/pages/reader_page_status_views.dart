part of 'reader_page.dart';

class _ReaderEmptyView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReaderEmptyView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const foregroundColor = Colors.white;
    const secondaryColor = Colors.white70;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: secondaryColor,
            ),
            const SizedBox(height: 16),
            const Text('暂无图片', style: TextStyle(color: foregroundColor)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              style: OutlinedButton.styleFrom(foregroundColor: secondaryColor),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderChapterData {
  final ReaderChapterSnapshot snapshot;
  final Map<int, Size> persistedSizes;

  const _ReaderChapterData({
    required this.snapshot,
    required this.persistedSizes,
  });
}

class _ReaderErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReaderErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const foregroundColor = Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: foregroundColor),
            ),
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
