import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../images/product_image_store.dart';

/// يعرض صورة المنتج مكبَّرة في صندوق عائم عند بقاء مؤشر الفأرة فوقها.
///
/// ينتظر [delay] قبل الظهور كي لا تقفز الصورة عند مجرد مرور المؤشر، ويُغلق
/// فورًا عند خروجه أو النقر أو التمرير. الصندوق يبقى داخل حدود النافذة
/// وينقلب إلى الجهة الأخرى إذا لم يجد مساحة بجانب المؤشر.
class ProductHoverPreview extends StatefulWidget {
  final String? imagePath;
  final Widget child;
  final Duration delay;
  final double size;

  const ProductHoverPreview({
    super.key,
    required this.imagePath,
    required this.child,
    this.delay = const Duration(milliseconds: 400),
    this.size = 320,
  });

  @override
  State<ProductHoverPreview> createState() => _ProductHoverPreviewState();
}

class _ProductHoverPreviewState extends State<ProductHoverPreview> {
  Timer? _timer;
  OverlayEntry? _entry;
  Offset _pointer = Offset.zero;

  @override
  void didUpdateWidget(covariant ProductHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) _dismiss();
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent event) {
    _pointer = event.position;
    if (ProductImageStore.fileFor(widget.imagePath) == null) return;
    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      if (mounted && _entry == null) _show();
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    final file = ProductImageStore.fileFor(widget.imagePath);
    if (file == null) return;

    final media = MediaQuery.of(context);
    final screen = media.size;
    const margin = 12.0;
    // لا تتجاوز المعاينة حدود النافذة حتى لو كانت صغيرة.
    final box = math.min(
      widget.size,
      math.max(120.0, math.min(screen.width, screen.height) - margin * 2),
    );

    var left = _pointer.dx + 20;
    var top = _pointer.dy + 20;
    if (left + box > screen.width - margin) left = _pointer.dx - box - 20;
    if (top + box > screen.height - margin) top = _pointer.dy - box - 20;
    left = left.clamp(margin, math.max(margin, screen.width - box - margin));
    top = top.clamp(margin, math.max(margin, screen.height - box - margin));

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: _PreviewBox(
            file: file,
            size: box,
            cacheWidth: (box * media.devicePixelRatio).round(),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onHover: (event) => _pointer = event.position,
      onExit: (_) => _dismiss(),
      child: Listener(
        onPointerDown: (_) => _dismiss(),
        onPointerSignal: (_) => _dismiss(),
        child: widget.child,
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final File file;
  final double size;
  final int cacheWidth;

  const _PreviewBox({
    required this.file,
    required this.size,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 130),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: Material(
        key: const ValueKey('hover-preview'),
        elevation: 14,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(10),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_outlined,
              size: size * 0.3,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
