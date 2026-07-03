import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'reader_image_loader.dart';

class ReaderImageView extends StatefulWidget {
  final ReaderImageRequest request;
  final int pageNumber;
  final int pageCount;
  final Size displaySize;
  final bool isSizeResolved;
  final VoidCallback onRetry;
  final ValueChanged<Size> onSizeResolved;

  const ReaderImageView({
    super.key,
    required this.request,
    required this.pageNumber,
    required this.pageCount,
    required this.displaySize,
    required this.isSizeResolved,
    required this.onRetry,
    required this.onSizeResolved,
  });

  @override
  State<ReaderImageView> createState() => _ReaderImageViewState();
}

class _ReaderImageViewState extends State<ReaderImageView> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant ReaderImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.url != widget.request.url ||
        oldWidget.isSizeResolved != widget.isSizeResolved) {
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _resolveImageSize() {
    if (widget.isSizeResolved) {
      _removeImageListener();
      return;
    }

    _removeImageListener();
    final provider = ReaderImageLoader.providerFor(widget.request);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      widget.onSizeResolved(
        Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ),
      );
    });

    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 ${widget.pageNumber} 页，共 ${widget.pageCount} 页',
      child: SizedBox(
        width: widget.displaySize.width,
        height: widget.displaySize.height,
        child: CachedNetworkImage(
          imageUrl: widget.request.url,
          cacheKey: widget.request.cacheKey,
          httpHeaders: widget.request.headers,
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          progressIndicatorBuilder: (context, url, progress) {
            return Center(
              child: CircularProgressIndicator(value: progress.progress),
            );
          },
          errorWidget: (context, url, error) {
            return _ReaderImageErrorView(onRetry: widget.onRetry);
          },
        ),
      ),
    );
  }
}

class _ReaderImageErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReaderImageErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 240,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('图片加载失败'),
      ),
    );
  }
}
