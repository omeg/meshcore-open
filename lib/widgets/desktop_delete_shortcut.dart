import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

/// Gives a desktop list item a focused/selected state and handles the Delete
/// key while that item has focus.
class DesktopDeleteShortcut extends StatefulWidget {
  const DesktopDeleteShortcut({
    super.key,
    required this.onDelete,
    required this.builder,
  });

  final VoidCallback onDelete;
  final Widget Function(BuildContext context, bool selected) builder;

  @override
  State<DesktopDeleteShortcut> createState() => _DesktopDeleteShortcutState();
}

class _DesktopDeleteShortcutState extends State<DesktopDeleteShortcut> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.delete) {
      widget.onDelete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfo.isDesktop) {
      return widget.builder(context, false);
    }

    return Focus(
      focusNode: _focusNode,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _focusNode.requestFocus(),
          child: widget.builder(context, _focusNode.hasFocus),
        ),
      ),
    );
  }
}
