class ChatMessage {
  ChatMessage({required this.role, this.content = ''}) : id = _nextId++;

  static int _nextId = 0;

  final int id;
  final String role;
  String content;
  String thinking = '';
  bool isStreaming = false;
  bool _insideThinking = false;
  String _pendingText = '';

  Map<String, String> toApiJson() => {'role': role, 'content': content};

  void appendThinking(String value) {
    thinking += value;
  }

  void appendContent(String value) {
    var remaining = _pendingText + value;
    _pendingText = '';

    while (remaining.isNotEmpty) {
      final marker = _insideThinking ? '</think>' : '<think>';
      final markerIndex = remaining.indexOf(marker);
      if (markerIndex >= 0) {
        _appendVisibleText(remaining.substring(0, markerIndex));
        remaining = remaining.substring(markerIndex + marker.length);
        _insideThinking = !_insideThinking;
        continue;
      }

      var pendingLength = 0;
      for (var length = 1; length < marker.length; length++) {
        if (remaining.endsWith(marker.substring(0, length))) {
          pendingLength = length;
        }
      }
      final visibleLength = remaining.length - pendingLength;
      _appendVisibleText(remaining.substring(0, visibleLength));
      _pendingText = remaining.substring(visibleLength);
      break;
    }
  }

  void finish() {
    _appendVisibleText(_pendingText);
    _pendingText = '';
    isStreaming = false;
  }

  void _appendVisibleText(String value) {
    if (_insideThinking) {
      thinking += value;
    } else {
      content += value;
    }
  }
}
