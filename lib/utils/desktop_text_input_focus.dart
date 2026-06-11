import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';

import 'platform_info.dart';

/// Keeps a primary text input focused on desktop screens where typing is the
/// main action. This covers first open and returning to the app via alt-tab.
class DesktopTextInputFocusHelper with WidgetsBindingObserver {
  final State<StatefulWidget> state;
  final FocusNode focusNode;
  final bool Function()? canRequestFocus;

  bool _attached = false;
  int? _viewId;

  DesktopTextInputFocusHelper({
    required this.state,
    required this.focusNode,
    this.canRequestFocus,
  });

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    requestFocus();
  }

  void dispose() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  void requestFocus({Duration delay = const Duration(milliseconds: 80)}) {
    if (!PlatformInfo.isDesktop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_requestAfterDelay(delay));
    });
  }

  Future<void> _requestAfterDelay(Duration delay) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!state.mounted) return;
    if (canRequestFocus?.call() == false) return;
    if (ModalRoute.of(state.context)?.isCurrent == false) return;
    if (!focusNode.canRequestFocus || focusNode.hasFocus) return;
    focusNode.requestFocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      requestFocus();
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state != ViewFocusState.focused) return;
    if (state.mounted) {
      _viewId ??= View.of(state.context).viewId;
      if (event.viewId != _viewId) return;
    }
    requestFocus(delay: const Duration(milliseconds: 30));
  }
}
