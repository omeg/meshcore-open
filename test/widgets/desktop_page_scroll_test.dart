import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/desktop_page_scroll.dart';

void main() {
  testWidgets('Page Down scrolls the main list while a text field has focus', (
    tester,
  ) async {
    final controller = ScrollController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPageScroll(
            controller: controller,
            child: Column(
              children: [
                TextField(autofocus: true, focusNode: focusNode),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: 100,
                    itemExtent: 40,
                    itemBuilder: (context, index) => Text('Item $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(controller.offset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.minScrollExtent);
  });

  testWidgets('page direction follows a reversed chat list', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPageScroll(
            controller: controller,
            child: ListView.builder(
              reverse: true,
              controller: controller,
              itemCount: 100,
              itemExtent: 40,
              itemBuilder: (context, index) => Text('Message $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    final pageUpOffset = controller.offset;
    expect(pageUpOffset, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(pageUpOffset));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.minScrollExtent);
  });
}
