import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Balances complete groups and matches each row to its tallest natural card.
/// Uses real layout (not intrinsic sizing), so nested LayoutBuilders are safe.
class BalancedCardGrid extends StatelessWidget {
  const BalancedCardGrid({
    super.key,
    required this.children,
    this.maxColumns = 3,
    this.minimumCardWidth = 250,
    this.spacing = 14,
  });
  final List<Widget> children;
  final int maxColumns;
  final double minimumCardWidth, spacing;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      if (children.isEmpty) return const SizedBox.shrink();
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      var columns = math
          .min(
            maxColumns,
            ((box.maxWidth + spacing) /
                    (minimumCardWidth * math.max(1, scale) + spacing))
                .floor(),
          )
          .clamp(1, children.length);
      while (columns > 1 && children.length % columns != 0) {
        columns--;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i += columns) ...[
            if (i != 0) SizedBox(height: spacing),
            _EqualCardRow(
              spacing: spacing,
              children: children.sublist(
                i,
                math.min(i + columns, children.length),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _EqualCardRow extends MultiChildRenderObjectWidget {
  const _EqualCardRow({required super.children, required this.spacing});
  final double spacing;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualCardRow(spacing);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualCardRow renderObject,
  ) {
    if (renderObject.spacing != spacing) {
      renderObject.spacing = spacing;
      renderObject.markNeedsLayout();
    }
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualCardRow extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderEqualCardRow(this.spacing);
  double spacing;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  @override
  void performLayout() {
    final width = math.max(
      0.0,
      (constraints.maxWidth - spacing * (childCount - 1)) / childCount,
    );
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height = math.max(height, child.size.height);
      child =
          (child.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tight(Size(width, height)),
        parentUsesSize: true,
      );
      final data = child.parentData! as ContainerBoxParentData<RenderBox>;
      data.offset = Offset(x, 0);
      x += width + spacing;
      child = data.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
