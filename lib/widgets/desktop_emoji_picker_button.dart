import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import 'emoji_picker.dart';

/// Inserts [emoji] at the current selection without exceeding [maxBytes].
///
/// A selected range is replaced. If the controller has no valid selection,
/// the emoji is appended to the existing text.
bool insertEmojiIntoController(
  TextEditingController controller,
  String emoji, {
  required int maxBytes,
  String Function(String)? encoder,
}) {
  final oldValue = controller.value;
  final textLength = oldValue.text.length;
  final selection = oldValue.selection;
  final start = selection.isValid
      ? selection.start.clamp(0, textLength).toInt()
      : textLength;
  final end = selection.isValid
      ? selection.end.clamp(start, textLength).toInt()
      : textLength;
  final nextText = oldValue.text.replaceRange(start, end, emoji);
  final effectiveText = encoder?.call(nextText) ?? nextText;

  if (maxBytes <= 0 || utf8.encode(effectiveText).length > maxBytes) {
    return false;
  }

  controller.value = oldValue.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: start + emoji.length),
    composing: TextRange.empty,
  );
  return true;
}

/// An anchored Material emoji menu for desktop message composers.
class DesktopEmojiPickerButton extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxBytes;
  final String Function(String)? encoder;

  const DesktopEmojiPickerButton({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.maxBytes,
    this.encoder,
  });

  @override
  State<DesktopEmojiPickerButton> createState() =>
      _DesktopEmojiPickerButtonState();
}

class _DesktopEmojiPickerButtonState extends State<DesktopEmojiPickerButton> {
  final MenuController _menuController = MenuController();

  void _selectEmoji(String emoji) {
    insertEmojiIntoController(
      widget.controller,
      emoji,
      maxBytes: widget.maxBytes,
      encoder: widget.encoder,
    );
    _menuController.close();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _menuController,
      consumeOutsideTap: true,
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.lg),
          ),
        ),
      ),
      menuChildren: [_DesktopEmojiMenu(onEmojiSelected: _selectEmoji)],
      builder: (context, controller, child) => IconButton(
        key: const ValueKey('desktopEmojiPickerButton'),
        icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
        tooltip: context.l10n.emojiCategorySmileys,
        visualDensity: VisualDensity.compact,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }
}

class _DesktopEmojiMenu extends StatelessWidget {
  final ValueChanged<String> onEmojiSelected;

  const _DesktopEmojiMenu({required this.onEmojiSelected});

  @override
  Widget build(BuildContext context) {
    final categories = EmojiPicker.categories(context.l10n);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 360,
      height: 330,
      child: DefaultTabController(
        length: categories.length,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: EmojiPicker.quickEmojis
                    .map(
                      (emoji) => SizedBox(
                        width: 44,
                        height: 40,
                        child: _EmojiButton(
                          emoji: emoji,
                          backgroundColor: scheme.secondaryContainer,
                          onPressed: onEmojiSelected,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerHeight: 1,
              tabs: categories.keys
                  .map((category) => Tab(text: category, height: 40))
                  .toList(),
            ),
            Expanded(
              child: TabBarView(
                children: categories.values
                    .map(
                      (emojis) => GridView.builder(
                        primary: false,
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                        itemCount: emojis.length,
                        itemBuilder: (context, index) => _EmojiButton(
                          emoji: emojis[index],
                          onPressed: onEmojiSelected,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final Color? backgroundColor;
  final ValueChanged<String> onPressed;

  const _EmojiButton({
    required this.emoji,
    required this.onPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: emoji,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onPressed(emoji),
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              emoji,
              style: MeshTheme.emoji(fontSize: 26),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
