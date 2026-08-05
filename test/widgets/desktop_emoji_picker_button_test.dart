import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/desktop_emoji_picker_button.dart';

void main() {
  group('insertEmojiIntoController', () {
    test('replaces the selection and places the caret after the emoji', () {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
        ),
      );
      addTearDown(controller.dispose);

      final inserted = insertEmojiIntoController(
        controller,
        '🙂',
        maxBytes: 100,
      );

      expect(inserted, isTrue);
      expect(controller.text, 'h🙂o');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
    });

    test('rejects an emoji that would exceed the encoded byte limit', () {
      final controller = TextEditingController(text: 'ab');
      addTearDown(controller.dispose);

      final inserted = insertEmojiIntoController(
        controller,
        '🙂',
        maxBytes: 6,
        encoder: (text) => '$text!',
      );

      expect(inserted, isFalse);
      expect(controller.text, 'ab');
    });
  });

  testWidgets('opens an anchored menu and inserts the selected emoji', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Hi ');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  suffixIcon: DesktopEmojiPickerButton(
                    controller: controller,
                    focusNode: focusNode,
                    maxBytes: 100,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('desktopEmojiPickerButton')));
    await tester.pumpAndSettle();

    expect(find.text('Smileys'), findsOneWidget);
    await tester.tap(find.text('👍').first);
    await tester.pumpAndSettle();

    expect(controller.text, 'Hi 👍');
    expect(focusNode.hasFocus, isTrue);
    expect(find.text('Smileys'), findsNothing);
  });
}
