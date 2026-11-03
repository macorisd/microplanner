import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Keep a dragged row inside its visible list, including inside scrolling forms.
class BoundedReorderableList extends StatefulWidget {
  const BoundedReorderableList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.proxyColor = AppColors.surfaceVariant,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ReorderCallback onReorder;
  final Color proxyColor;

  @override
  State<BoundedReorderableList> createState() => _BoundedReorderableListState();
}

class _BoundedReorderableListState extends State<BoundedReorderableList> {
  final _region = GlobalKey();
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant BoundedReorderableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) _dragging = false;
  }

  Rect _visibleBounds() {
    final box = _region.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return Rect.zero;
    var bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    // The shrink-wrapped list can extend beyond its form's scroll viewport.
    for (
      RenderObject? ancestor = box.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is RenderBox && ancestor is RenderAbstractViewport) {
        bounds = bounds.intersect(
          MatrixUtils.transformRect(
            ancestor.getTransformTo(null),
            Offset.zero & ancestor.size,
          ),
        );
      }
    }
    return bounds;
  }

  @override
  Widget build(BuildContext context) => TooltipVisibility(
    visible: !_dragging,
    child: Listener(
      onPointerCancel: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      child: ClipRect(
        key: _region,
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
          onReorder: widget.onReorder,
          onReorderStart: (_) {
            Tooltip.dismissAllToolTips();
            setState(() => _dragging = true);
          },
          onReorderEnd: (_) => setState(() => _dragging = false),
          proxyDecorator: (child, index, animation) => _BoundedDragProxy(
            bounds: _visibleBounds,
            child: TooltipVisibility(
              visible: false,
              child: Material(
                key: const ValueKey('reorder-drag-surface'),
                color: widget.proxyColor,
                elevation: 3,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BoundedDragProxy extends SingleChildRenderObjectWidget {
  const _BoundedDragProxy({required this.bounds, required super.child});
  final Rect Function() bounds;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBoundedDragProxy(bounds);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBoundedDragProxy render,
  ) {
    render.bounds = bounds;
    render.markNeedsPaint();
  }
}

class _RenderBoundedDragProxy extends RenderProxyBox {
  _RenderBoundedDragProxy(this.bounds);
  Rect Function() bounds;

  Rect get _localBounds =>
      MatrixUtils.transformRect(getTransformTo(null)..invert(), bounds());

  Offset get _translation {
    final area = _localBounds;
    return Offset(
      0.0.clamp(area.left, math.max(area.left, area.right - size.width)),
      0.0.clamp(area.top, math.max(area.top, area.bottom - size.height)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (bounds().isEmpty) return;
    final translation = _translation;
    // Preserve logical drop coordinates so the first/last slots stay reachable;
    // only the visual proxy is clamped and clipped to the designated region.
    context.pushClipRect(
      needsCompositing,
      offset,
      _localBounds,
      (context, offset) => super.paint(context, offset + translation),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final translation = _translation;
    transform.translateByDouble(translation.dx, translation.dy, 0, 1);
  }
}
