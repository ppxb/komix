import 'dart:io';

import 'package:flutter/material.dart';

import 'reader_image_loader.dart';

class ReaderImageView extends StatefulWidget {
  final ReaderImageRequest request;
  final int pageNumber;
  final int pageCount;
  final Size displaySize;
  final bool isSizeResolved;
  final ValueChanged<Size> onSizeResolved;

  const ReaderImageView({
    super.key,
    required this.request,
    required this.pageNumber,
    required this.pageCount,
    required this.displaySize,
    required this.isSizeResolved,
    required this.onSizeResolved,
  });

  @override
  State<ReaderImageView> createState() => _ReaderImageViewState();
}

class _ReaderImageViewState extends State<ReaderImageView> {
  late Future<File> _imageFuture;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  String? _listeningFilePath;

  @override
  void initState() {
    super.initState();
    _imageFuture = ReaderImageLoader.cacheFileFor(widget.request);
  }

  @override
  void didUpdateWidget(covariant ReaderImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.url != widget.request.url ||
        oldWidget.request.path != widget.request.path ||
        oldWidget.request.cacheKey != widget.request.cacheKey) {
      _resetImageFuture();
    } else if (!widget.isSizeResolved && _listeningFilePath != null) {
      _resolveImageSize(File(_listeningFilePath!));
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _resetImageFuture() {
    _removeImageListener();
    setState(() {
      _imageFuture = ReaderImageLoader.cacheFileFor(widget.request);
    });
  }

  void _resolveImageSize(File file) {
    if (widget.isSizeResolved) {
      _removeImageListener();
      return;
    }
    if (_listeningFilePath == file.path && _imageListener != null) {
      return;
    }

    _removeImageListener();
    _listeningFilePath = file.path;
    final provider = FileImage(file);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      widget.onSizeResolved(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
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
    _listeningFilePath = null;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 ${widget.pageNumber} 页，共 ${widget.pageCount} 页',
      child: SizedBox(
        width: widget.displaySize.width,
        height: widget.displaySize.height,
        child: FutureBuilder<File>(
          future: _imageFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && !snapshot.hasData) {
              return _ReaderImageErrorView(
                message: snapshot.error.toString(),
                onRetry: _resetImageFuture,
              );
            }

            final file = snapshot.requireData;
            _resolveImageSize(file);
            return Image.file(
              file,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return _ReaderImageErrorView(
                  message: error.toString(),
                  onRetry: _resetImageFuture,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReaderImageErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReaderImageErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 240,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(
            '图片加载失败\n$message',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
