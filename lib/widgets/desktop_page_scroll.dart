import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

class _DesktopPageScrollIntent extends Intent {
  const _DesktopPageScrollIntent(this.direction);

  final AxisDirection direction;
}

class _DesktopScrollBoundaryIntent extends Intent {
  const _DesktopScrollBoundaryIntent({required this.toTop});

  final bool toTop;
}

/// Routes paging and boundary keys to a screen's main scrollable on desktop.
///
/// Keeping the shortcut above both the list and nearby text fields means a
/// user can page through results or messages without first moving focus out of
/// a search box or message composer.
class DesktopPageScroll extends StatelessWidget {
  const DesktopPageScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  void _scroll(AxisDirection direction) {
    if (!controller.hasClients || controller.positions.length != 1) return;

    final position = controller.position;
    if (axisDirectionToAxis(position.axisDirection) != Axis.vertical) return;

    final increment = position.viewportDimension * 0.8;
    final delta = direction == position.axisDirection ? increment : -increment;
    position.moveTo(
      position.pixels + delta,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToBoundary({required bool toTop}) {
    if (!controller.hasClients || controller.positions.length != 1) return;

    final position = controller.position;
    if (axisDirectionToAxis(position.axisDirection) != Axis.vertical) return;

    final isReversed = position.axisDirection == AxisDirection.up;
    final target = toTop == isReversed
        ? position.maxScrollExtent
        : position.minScrollExtent;
    position.moveTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfo.isDesktop) return child;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.pageUp): _DesktopPageScrollIntent(
          AxisDirection.up,
        ),
        SingleActivator(LogicalKeyboardKey.pageDown): _DesktopPageScrollIntent(
          AxisDirection.down,
        ),
        SingleActivator(LogicalKeyboardKey.home): _DesktopScrollBoundaryIntent(
          toTop: true,
        ),
        SingleActivator(LogicalKeyboardKey.end): _DesktopScrollBoundaryIntent(
          toTop: false,
        ),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DesktopPageScrollIntent: CallbackAction<_DesktopPageScrollIntent>(
            onInvoke: (intent) {
              _scroll(intent.direction);
              return null;
            },
          ),
          _DesktopScrollBoundaryIntent:
              CallbackAction<_DesktopScrollBoundaryIntent>(
                onInvoke: (intent) {
                  _scrollToBoundary(toTop: intent.toTop);
                  return null;
                },
              ),
        },
        child: Focus(autofocus: true, skipTraversal: true, child: child),
      ),
    );
  }
}
