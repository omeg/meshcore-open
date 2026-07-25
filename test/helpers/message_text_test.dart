import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/message_text.dart';

void main() {
  test('removes trailing message whitespace while preserving leading text', () {
    expect(
      normalizeOutgoingMessageText('  hello mesh \t\r\n'),
      equals('  hello mesh'),
    );
  });

  test('normalizes whitespace-only messages to empty', () {
    expect(normalizeOutgoingMessageText(' \t\r\n'), isEmpty);
  });

  test('leaves messages without trailing whitespace unchanged', () {
    expect(normalizeOutgoingMessageText('hello mesh'), equals('hello mesh'));
  });
}
