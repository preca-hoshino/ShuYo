import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({
    super.key,
    required this.image,
  });

  final Uint8List image;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  CropController _controller = CropController();
  int _editorRevision = 0;
  bool _ready = false;
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('调整头像'),
        actions: [
          TextButton(
            onPressed: _ready && !_cropping ? _crop : null,
            child: const Text('确认'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Crop(
                key: ValueKey(_editorRevision),
                image: widget.image,
                controller: _controller,
                onCropped: _onCropped,
                onStatusChanged: (status) {
                  final ready = status == CropStatus.ready;
                  if (mounted && (_ready != ready || _cropping && ready)) {
                    setState(() {
                      _ready = ready;
                      if (ready) _cropping = false;
                    });
                  }
                },
                withCircleUi: true,
                interactive: true,
                fixCropRect: true,
                initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                  size: 0.82,
                  aspectRatio: 1,
                ),
                maskColor: Colors.black.withValues(alpha: 0.72),
                baseColor: Colors.black,
                progressIndicator: const Center(
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                cornerDotBuilder: (_, __) => const SizedBox.shrink(),
                willUpdateScale: (scale) => scale <= 8,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '双指缩放并拖动图片',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cropping ? null : _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重置'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _crop() {
    setState(() => _cropping = true);
    _controller.crop();
  }

  void _reset() {
    setState(() {
      _controller = CropController();
      _editorRevision++;
      _ready = false;
    });
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('头像裁剪失败：$cause')),
        );
    }
  }
}
