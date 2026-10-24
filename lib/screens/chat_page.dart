import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/ollama_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _baseUrlController = TextEditingController(
    text: 'http://10.0.2.2:11434',
  );
  final _modelController = TextEditingController(text: 'llama3.2');
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _ollamaService = OllamaService();
  final List<ChatMessage> _messages = [];
  List<OllamaModel> _models = [];
  String? _selectedModel;
  String? _notice;
  bool _loadingModels = false;
  bool _sending = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _ollamaService.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _notice = null;
    });
    try {
      final models = await _ollamaService.fetchModels(_baseUrlController.text);
      if (!mounted) return;
      setState(() {
        _models = models;
        _connected = true;
        if (models.isNotEmpty) {
          _selectedModel = models.any((model) => model.name == _selectedModel)
              ? _selectedModel
              : models.first.name;
          _modelController.text = _selectedModel!;
          if (!_selectedModelSupportsThinking) {
            _notice = 'Seçilen model düşünme çıktısı sağlamıyor.';
          }
        } else {
          _selectedModel = null;
          _notice = 'Ollama bağlantısı kuruldu; yüklü model bulunamadı.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _models = [];
        _selectedModel = null;
        _connected = false;
        _notice = 'Ollama bağlantısı kurulamadı. $error';
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final model = (_selectedModel ?? _modelController.text).trim();
    if (text.isEmpty || _sending) return;
    if (model.isEmpty) {
      setState(() => _notice = 'Önce bir model adı girin.');
      return;
    }

    final userMessage = ChatMessage(role: 'user', content: text);
    final requestMessages = [
      ..._messages,
      userMessage,
    ].map((message) => message.toApiJson()).toList();
    final assistantMessage = ChatMessage(role: 'assistant')..isStreaming = true;

    setState(() {
      _messages
        ..add(userMessage)
        ..add(assistantMessage);
      _messageController.clear();
      _sending = true;
      _notice = null;
    });
    _scrollToBottom();

    try {
      await for (final delta in _ollamaService.chat(
        baseUrl: _baseUrlController.text,
        model: model,
        messages: requestMessages,
        enableThinking: _selectedModelSupportsThinking,
      )) {
        if (!mounted) return;
        setState(() {
          assistantMessage
            ..appendThinking(delta.thinking)
            ..appendContent(delta.content);
          _connected = true;
        });
        _scrollToBottom();
      }
      assistantMessage.finish();
    } catch (error) {
      assistantMessage.finish();
      if (!mounted) return;
      setState(() {
        if (assistantMessage.content.isEmpty &&
            assistantMessage.thinking.isEmpty) {
          _messages.remove(assistantMessage);
        }
        _connected = false;
        _notice =
            'Yanıt alınamadı. Ollama sunucusunu ve bağlantıyı kontrol edin. $error';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _sending
        ? 'Düşünüyor'
        : _loadingModels
        ? 'Bağlanıyor'
        : _connected
        ? 'Bağlı'
        : 'Bağlantı yok';
    final statusColor = _connected ? const Color(0xFF256B57) : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.forum_outlined, color: Color(0xFF256B57)),
            SizedBox(width: 10),
            Text('Ollama Sohbet'),
          ],
        ),
        backgroundColor: const Color(0xFFF5F6F2),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                Icon(Icons.circle, size: 9, color: statusColor),
                const SizedBox(width: 7),
                Text(status, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _baseUrlController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Ollama adresi',
                            prefixIcon: Icon(Icons.link),
                          ),
                          onSubmitted: (_) => _loadModels(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Bağlantıyı ve modelleri yenile',
                        onPressed: _loadingModels ? null : _loadModels,
                        icon: _loadingModels
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_models.isEmpty)
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'Model adı',
                        hintText: 'Örnek: llama3.2',
                        prefixIcon: Icon(Icons.memory),
                      ),
                      textInputAction: TextInputAction.done,
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedModel,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        prefixIcon: Icon(Icons.memory),
                      ),
                      items: _models
                          .map(
                            (model) => DropdownMenuItem<String>(
                              value: model.name,
                              child: Text(model.name),
                            ),
                          )
                          .toList(),
                      onChanged: (model) {
                        setState(() {
                          _selectedModel = model;
                          _modelController.text = model ?? '';
                          _notice = !_selectedModelSupportsThinking
                              ? 'Seçilen model düşünme çıktısı sağlamıyor.'
                              : null;
                        });
                      },
                    ),
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _connected
                            ? const Color(0xFFE1EFE9)
                            : const Color(0xFFF8E9E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _connected
                                ? Icons.info_outline
                                : Icons.wifi_off_outlined,
                            size: 18,
                            color: _connected
                                ? const Color(0xFF256B57)
                                : const Color(0xFF9B3E32),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _notice!,
                              style: TextStyle(
                                color: _connected
                                    ? const Color(0xFF256B57)
                                    : const Color(0xFF85372D),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFD9DED8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'Bir mesaj yazarak sohbeti başlatın.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) =>
                                  _buildMessage(_messages[index]),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: const InputDecoration(
                            hintText: 'Mesajınızı yazın',
                            prefixIcon: Icon(Icons.chat_bubble_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Gönder',
                        onPressed: _sending ? null : _sendMessage,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(50, 50),
                          backgroundColor: const Color(0xFF256B57),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _selectedModelSupportsThinking => _models.any(
    (model) => model.name == _selectedModel && model.supportsThinking,
  );

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFE1EFE9) : const Color(0xFFF1F3EF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: isUser
            ? SelectableText(message.content)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.thinking.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD9DED8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ExpansionTile(
                        key: ValueKey('thinking-${message.id}'),
                        initiallyExpanded: message.isStreaming,
                        dense: true,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        leading: const Icon(
                          Icons.psychology_outlined,
                          size: 20,
                        ),
                        title: const Text('Düşünme'),
                        subtitle: message.isStreaming
                            ? const Text('Akış sürüyor')
                            : null,
                        children: [SelectableText(message.thinking)],
                      ),
                    ),
                    if (message.content.isNotEmpty) const SizedBox(height: 10),
                  ],
                  if (message.content.isNotEmpty)
                    SelectableText(message.content),
                  if (message.isStreaming)
                    Padding(
                      padding: EdgeInsets.only(
                        top: message.content.isEmpty && message.thinking.isEmpty
                            ? 2
                            : 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            message.thinking.isEmpty
                                ? 'Düşünüyor...'
                                : 'Yanıt yazılıyor...',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
