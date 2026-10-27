import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';

/// Flat layers with depth, ordered Completed | Late | Upcoming.
/// One controller drives direct selection, gestures and accessibility actions.
class AndroidBoardCarousel extends StatefulWidget {
  final List<Widget> columns;
  final VoidCallback onAdd;
  const AndroidBoardCarousel({
    super.key,
    required this.columns,
    required this.onAdd,
  });
  @override
  State<AndroidBoardCarousel> createState() => _AndroidBoardCarouselState();
}

class _AndroidBoardCarouselState extends State<AndroidBoardCarousel>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 2,
    value: 2,
  )..addListener(_changed);
  final _selected = ValueNotifier(2);
  int _dragAnchor = 2;
  double _dragOrigin = 2;
  double _dragExtent = 1;

  void _changed() => _selected.value = _rotation.value.round();

  void _select(int index) {
    final destination = index.clamp(0, 2).toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.value = destination;
      return;
    }
    final distance = (destination - _rotation.value).abs();
    _rotation.animateTo(
      destination,
      duration: Duration(milliseconds: 260 + (distance * 100).round()),
      curve: AppMotion.curve,
    );
  }

  void _start(DragStartDetails details) {
    _rotation.stop();
    _dragOrigin = _rotation.value;
    _dragAnchor = _dragOrigin.round();
  }

  void _drag(DragUpdateDetails details) {
    // One neighboring destination per gesture makes the landing predictable.
    _rotation.value = (_rotation.value - details.delta.dx / _dragExtent).clamp(
      math.max(0, _dragAnchor - 1).toDouble(),
      math.min(2, _dragAnchor + 1).toDouble(),
    );
  }

  void _end(DragEndDetails details) {
    final delta = _rotation.value - _dragOrigin;
    final velocity = -(details.primaryVelocity ?? 0);
    final direction = velocity.abs() > 500 && delta.abs() > .04
        ? velocity.sign
        : delta.abs() >= .28
        ? delta.sign
        : 0.0;
    _select(_dragAnchor + direction.toInt());
  }

  @override
  void dispose() {
    _rotation.removeListener(_changed);
    _rotation.dispose();
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Stable surfaces: layer movement changes transforms, not the cards.
    final surfaces = [
      for (final column in widget.columns) RepaintBoundary(child: column),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final leading = (bounds.maxWidth * .08).clamp(28.0, 48.0);
        final peek = (leading - 8) / 2;
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    _dragExtent = width * .8;
                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: _start,
                      onHorizontalDragUpdate: _drag,
                      onHorizontalDragEnd: _end,
                      onHorizontalDragCancel: () =>
                          _select(_rotation.value.round()),
                      child: ClipRect(
                        child: AnimatedBuilder(
                          animation: _rotation,
                          builder: (context, _) {
                            final position = _rotation.value;
                            final active = position.round();
                            final settled = (position - active).abs() < .001;
                            final poses = [
                              for (var i = 0; i < 3; i++)
                                _pose(position - i, width, peek, reduced),
                            ];
                            final order = [0, 1, 2]
                              ..sort(
                                (a, b) =>
                                    poses[b].depth.compareTo(poses[a].depth),
                              );
                            return Semantics(
                              label: 'Task columns',
                              onScrollLeft: active < 2
                                  ? () => _select(active + 1)
                                  : null,
                              onScrollRight: active > 0
                                  ? () => _select(active - 1)
                                  : null,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final i in order)
                                    Positioned(
                                      key: ValueKey(i),
                                      left: leading,
                                      right: 0,
                                      top: 8,
                                      bottom: 12,
                                      child: Offstage(
                                        offstage: position - i <= -1,
                                        child: Transform(
                                          key: ValueKey('carousel-layer-$i'),
                                          alignment: Alignment.topLeft,
                                          transform: poses[i].transform,
                                          child: IgnorePointer(
                                            ignoring: !settled || i != active,
                                            child: ExcludeFocus(
                                              excluding:
                                                  !settled || i != active,
                                              child: ExcludeSemantics(
                                                excluding:
                                                    !settled || i != active,
                                                child: surfaces[i],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(leading, 0, 16, 16),
              child: ValueListenableBuilder<int>(
                valueListenable: _selected,
                builder: (context, selected, _) => _CarouselActions(
                  selected: selected,
                  onSelect: _select,
                  onAdd: widget.onAdd,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  ({double depth, Matrix4 transform}) _pose(
    double offset,
    double width,
    double peek,
    bool reduced,
  ) {
    final depth = offset;
    double x;
    if (offset >= 0) {
      x = -peek * depth;
    } else {
      // Passed columns leave on the right. They never wrap behind the remaining
      // stack, so its visible layers accurately show the finite destinations.
      x = -offset * width * 1.08;
    }
    final scale = reduced || offset < 0 ? 1.0 : 1 - .035 * depth;
    return (
      depth: depth,
      transform: Matrix4.identity()
        ..translateByDouble(x, reduced || offset < 0 ? 0 : 6 * depth, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1),
    );
  }
}

class _CarouselActions extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  const _CarouselActions({
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });
  static const _labels = ['Completed', 'Late', 'Upcoming'];
  static const _icons = [
    Icons.check_circle_rounded,
    Icons.warning_rounded,
    Icons.schedule_rounded,
  ];
  static const _colors = [
    AppColors.completeHeader,
    AppColors.lateHeader,
    AppColors.upcomingHeader,
  ];
  static const _backgrounds = [
    AppColors.completeHeaderLight,
    AppColors.lateHeaderLight,
    AppColors.upcomingHeaderLight,
  ];

  @override
  Widget build(BuildContext context) {
    final canWrite = context.select<WorkspaceController, bool>(
      (workspace) => workspace.canWrite,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = TextPainter(
          text: TextSpan(
            text: 'New Task',
            style:
                Theme.of(context).floatingActionButtonTheme.extendedTextStyle ??
                Theme.of(context).textTheme.labelLarge,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final extended = constraints.maxWidth >= 144 + 12 + text.width + 68;
        text.dispose();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Semantics(
                      selected: i == selected,
                      child: IconButton(
                        tooltip: _labels[i],
                        onPressed: () => onSelect(i),
                        icon: Icon(_icons[i]),
                        style: IconButton.styleFrom(
                          foregroundColor: _colors[i],
                          backgroundColor: i == selected
                              ? _backgrounds[i]
                              : Colors.transparent,
                          minimumSize: const Size(48, 48),
                          maximumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PressFeedback(
              child: extended
                  ? FloatingActionButton.extended(
                      tooltip: 'New Task',
                      onPressed: canWrite ? onAdd : null,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New Task'),
                    )
                  : FloatingActionButton(
                      tooltip: 'New Task',
                      onPressed: canWrite ? onAdd : null,
                      child: const Icon(Icons.add_rounded),
                    ),
            ),
          ],
        );
      },
    );
  }
}
