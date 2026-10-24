import 'package:deneme/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage', () {
    test('separates thinking tags split across streamed chunks', () {
      final message = ChatMessage(role: 'assistant')..isStreaming = true;

      message
        ..appendContent('Ön bilgi <thi')
        ..appendContent('nk>akıl yürütme<')
        ..appendContent('/think>nihai yanıt');
      message.finish();

      expect(message.thinking, 'akıl yürütme');
      expect(message.content, 'Ön bilgi nihai yanıt');
      expect(message.isStreaming, isFalse);
    });

    test('keeps API thinking separate from response content', () {
      final message = ChatMessage(role: 'assistant');

      message
        ..appendThinking('model reasoning')
        ..appendContent('Final answer');

      expect(message.thinking, 'model reasoning');
      expect(message.content, 'Final answer');
    });
  });
}
