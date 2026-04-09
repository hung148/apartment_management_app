import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/services/ai_agent_service.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'dart:async' show TimeoutException;
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

class _IsolateHelper {
  static Future<String?> fetchHttp(String url) async {
    try {
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      return response.body;
    } catch (e) {
      return null;
    }
  }

  static Future<String> callGemini(Map<String, dynamic> args) async {
    final apiKey = args['apiKey'] as String;
    final modelName = args['modelName'] as String;
    final systemPrompt = args['systemPrompt'] as String;
    final userMsg = args['userMsg'] as String;
    final history = List<Map<String, String>>.from(args['history'] as List);

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      contents.add({
        'role': h['role'] == 'user' ? 'user' : 'model',
        'parts': [{'text': h['text']}],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [{'text': userMsg}],
    });

    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': systemPrompt}],
      },
      'contents': contents,
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';
    return parts[0]['text'] as String? ?? '';
  }
}

Future<String> _callGeminiHttp({
  required String apiKey,
  required String modelName,
  required String systemPrompt,
  required String userMsg,
  required List<Map<String, String>> history,
}) async {
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
  );

  final contents = <Map<String, dynamic>>[];

  for (final h in history) {
    contents.add({
      'role': h['role'] == 'user' ? 'user' : 'model',
      'parts': [{'text': h['text']}],
    });
  }
  contents.add({
    'role': 'user',
    'parts': [{'text': userMsg}],
  });

  final body = jsonEncode({
    'system_instruction': {
      'parts': [{'text': systemPrompt}],
    },
    'contents': contents,
  });

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );

  if (response.statusCode != 200) {
    throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final candidates = json['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) return '';
  final content = candidates[0]['content'] as Map<String, dynamic>?;
  final parts = content?['parts'] as List?;
  if (parts == null || parts.isEmpty) return '';
  return parts[0]['text'] as String? ?? '';
}

// =============================================================================
// OVERLAY MANAGER
// =============================================================================

class ChatOverlayManager {
  static OverlayEntry? _entry;
  static final ValueNotifier<bool> _visible = ValueNotifier(false);
  static final ValueNotifier<bool> _panelOpen = ValueNotifier(false);
  static final ValueNotifier<Offset?> _fabPosition = ValueNotifier(null);

  static void install() {
    _visible.value = true;
    _reinsertOnTop();
  }

  static void uninstall() {
    _visible.value = false;
    _panelOpen.value = false;
  }

  static void _reinsertOnTop() {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: _visible,
        builder: (_, visible, __) {
          if (!visible) return const SizedBox.shrink();
          return _ChatOverlay(panelOpen: _panelOpen, fabPosition: _fabPosition);
        },
      ),
    );
    overlay.insert(_entry!);
  }

  static void dispose() {
    _entry?.remove();
    _entry = null;
    _visible.value = false;
    _panelOpen.value = false;
  }
}

// =============================================================================
// ROOT OVERLAY WIDGET
// =============================================================================

class _ChatOverlay extends StatelessWidget {
  final ValueNotifier<bool> panelOpen;
  final ValueNotifier<Offset?> fabPosition;

  const _ChatOverlay({required this.panelOpen, required this.fabPosition});

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 600;

    return ValueListenableBuilder<bool>(
      valueListenable: panelOpen,
      builder: (context, isOpen, __) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Chat panel — always in tree, slides in/out
            Positioned(
              right: 0,
              bottom: 0,
              top: 0,
              left: isSmall ? 0 : null,
              child: AnimatedSlide(
                offset: isOpen
                    ? Offset.zero
                    : isSmall
                        ? const Offset(0, 1.0)
                        : const Offset(1.0, 0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: _ChatPanel(onClose: () => panelOpen.value = false),
              ),
            ),
            // FAB — only rendered when panel is closed
            if (!isOpen)
              _DraggableFab(
                positionNotifier: fabPosition,
                onTap: () => panelOpen.value = true,
              ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// DRAGGABLE FAB
// Stores position as fractional offset (0.0–1.0) so it stays proportional
// when the window resizes.
// =============================================================================

class _DraggableFab extends StatefulWidget {
  final ValueNotifier<Offset?> positionNotifier;
  final VoidCallback onTap;

  const _DraggableFab({required this.positionNotifier, required this.onTap});

  @override
  State<_DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<_DraggableFab> {
  static const double _fabSize = 96.0;
  static const double _marginRight = 16.0;
  static const double _marginBottom = 24.0;

  bool _didMove = false;
  bool _dragging = false;
  bool _hovered = false;
  Offset _dragStart = Offset.zero;
  Offset _posStart = Offset.zero;

  Offset _toPixel(Offset frac, Size screen) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final maxX = screen.width - _fabSize - _marginRight;
    final maxY = screen.height - _fabSize - bottomPad - _marginBottom;
    return Offset(frac.dx * maxX, frac.dy * maxY);
  }

  Offset _toFrac(Offset pixel, Size screen) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final maxX = screen.width - _fabSize - _marginRight;
    final maxY = screen.height - _fabSize - bottomPad - _marginBottom;
    return Offset(
      (pixel.dx / maxX).clamp(0.0, 1.0),
      (pixel.dy / maxY).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: widget.positionNotifier,
      builder: (context, savedFrac, __) {
        final screen = MediaQuery.of(context).size;
        final frac = savedFrac ?? const Offset(1.0, 1.0);
        final pos = _toPixel(frac, screen);

        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            cursor: _dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: GestureDetector(
              onTap: _didMove ? null : widget.onTap,
              onPanStart: (details) {
                _dragStart = details.globalPosition;
                _posStart = pos;
              },
              onPanUpdate: (details) {
                final delta = details.globalPosition - _dragStart;
                if (delta.distance > 4) {
                  _didMove = true;
                  if (!_dragging) setState(() => _dragging = true);
                }
                if (!_didMove) return;
                widget.positionNotifier.value =
                    _toFrac(_posStart + delta, screen);
              },
              onPanEnd: (_) {
                _didMove = false;
                setState(() => _dragging = false);
              },
              child: AnimatedScale(
                scale: _hovered && !_dragging ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Image.asset(
                  'assets/image/chat_button.png',
                  width: _fabSize,
                  height: _fabSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// CHAT MESSAGE MODEL
// =============================================================================

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}

// =============================================================================
// CHAT PANEL
// =============================================================================

class _ChatPanel extends StatefulWidget {
  final VoidCallback onClose;
  const _ChatPanel({required this.onClose});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _messages = <_ChatMessage>[];
  final _history = <Content>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // ValueNotifier for the actively streaming bubble — avoids setState per chunk
  final _streamingText = ValueNotifier<String>('');

  bool _loading = false;
  bool _isStreaming = false;
  bool _scrollPending = false; // throttle scroll callbacks

  AIAgentService get _ai => getIt<AIAgentService>();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _streamingText.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------------

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _loading = true;
      _isStreaming = true;
    });

    _scrollToBottom();
    _testConnectivity();
  }

  Future<void> _testConnectivity() async {
    debugPrint('🧪 Testing HTTP via static isolate...');
    try {
      final body = await compute(_IsolateHelper.fetchHttp, 'https://httpbin.org/get');
      debugPrint('🧪 httpbin result: ${body != null ? "OK (${body.length} bytes)" : "NULL"}');

      debugPrint('🧪 Testing Gemini endpoint...');
      final geminiBody = await compute(
        _IsolateHelper.fetchHttp,
        'https://generativelanguage.googleapis.com/v1beta/models?key=${_ai.apiKey}',
      );
      debugPrint('🧪 Gemini result: ${geminiBody != null ? "OK" : "NULL"} — ${geminiBody?.substring(0, geminiBody.length.clamp(0, 100))}');

      // If both passed, proceed to actual reply
      if (mounted) _streamReply(_messages.last.text);

    } catch (e) {
      debugPrint('🔴 Connectivity test FAILED: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _isStreaming = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Stream reply
  // ---------------------------------------------------------------------------
  Future<void> _streamReply(String userText) async {

    // Guard: fail immediately if API key is missing
    if (_ai.apiKey.isEmpty) {
      debugPrint('🔴 [CHAT] API key is empty — dotenv may not have loaded before AIAgentService constructed');
      if (mounted) {
        setState(() {
          _messages.add(const _ChatMessage(
            text: '⚠️ AI not configured. Please check your .env file.',
            isUser: false,
          ));
          _loading = false;
          _isStreaming = false;
        });
      }
      return;
    }

    _history.add(Content.text(userText));
    _streamingText.value = '';
    final buffer = StringBuffer();

    final sw = Stopwatch()..start();
    debugPrint('🔵 [CHAT] _streamReply START');

    try {
      // --- Step 1: Build history ---
      final List<Map<String, String>> historyData = [];
      if (_history.length > 1) {
        for (final c in _history.sublist(0, _history.length - 1)) {
          try {
            final part = c.parts.first;
            if (part is TextPart) {
              historyData.add({'role': c.role ?? 'user', 'text': part.text});
            }
          } catch (_) {}
        }
      }
      debugPrint('🟡 [CHAT] history built in ${sw.elapsedMilliseconds}ms');

      // debugPrint('🟡 [CHAT] apiKey length=${_ai.apiKey.length}, first4=${_ai.apiKey.isEmpty ? "EMPTY" : _ai.apiKey.substring(0, 4)}');

      // --- Step 2: HTTP call ---
      debugPrint('🟡 [CHAT] calling Gemini HTTP...');
      final String result;
      try {
        result = await _callGeminiHttp(
          apiKey: _ai.apiKey,
          modelName: _ai.modelName,
          systemPrompt: 'Bạn là trợ lý AI cho ứng dụng quản lý căn hộ. '
              'Hãy trả lời ngắn gọn, rõ ràng bằng ngôn ngữ mà người dùng đang dùng '
              '(tiếng Việt hoặc tiếng Anh).'
              'Khi người dùng yêu cầu tạo tòa nhà, phòng, hoặc người thuê: '
              'LUÔN hỏi đầy đủ thông tin cần thiết (tên, địa chỉ...) TRƯỚC KHI gọi bất kỳ công cụ nào. '
              'Không bao giờ tự đặt tên hoặc bịa thông tin.',
          userMsg: userText,
          history: historyData,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Gemini HTTP call timed out after 30s'),
        );
      } catch (e) {
        debugPrint('🔴 [CHAT] HTTP call FAILED at ${sw.elapsedMilliseconds}ms: $e');
        rethrow;
      }
      debugPrint('🟢 [CHAT] HTTP responded in ${sw.elapsedMilliseconds}ms, length=${result.length}');

      // --- Step 3: Text animation loop ---
      buffer.write(result);
      if (mounted && result.isNotEmpty) {
        const chunkSize = 8;
        var i = 0;
        var loopIterations = 0;
        final loopSw = Stopwatch()..start();

        while (i < result.length) {
          if (!mounted) {
            debugPrint('🔴 [CHAT] widget unmounted mid-animation, breaking');
            break;
          }
          i = (i + chunkSize).clamp(0, result.length);
          loopIterations++;

          // Warn if a single iteration is taking too long
          if (loopSw.elapsedMilliseconds > 500) {
            debugPrint('⚠️ [CHAT] animation loop stalled: iter=$loopIterations i=$i at ${sw.elapsedMilliseconds}ms');
            loopSw.reset();
          }

          _streamingText.value = result.substring(0, i);
          _scrollToBottom();
          await Future.delayed(const Duration(milliseconds: 16));
        }
        debugPrint('🟢 [CHAT] animation done: $loopIterations iters, ${sw.elapsedMilliseconds}ms total');
      }

      if (buffer.isNotEmpty) {
        _history.add(Content.model([TextPart(buffer.toString())]));
      }
    } on TimeoutException catch (e) {
      final errMsg = '⚠️ Timeout: ${e.message}';
      debugPrint('🔴 [CHAT] $errMsg at ${sw.elapsedMilliseconds}ms');
      _streamingText.value = errMsg;
      buffer.write(errMsg);
    } catch (e, stack) {
      final errMsg = '⚠️ Lỗi: ${e.toString()}';
      debugPrint('🔴 [CHAT] EXCEPTION at ${sw.elapsedMilliseconds}ms: $e');
      debugPrint('🔴 [CHAT] STACK: $stack');
      _streamingText.value = errMsg;
      buffer.write(errMsg);
    } finally {
      debugPrint('🔵 [CHAT] finally block at ${sw.elapsedMilliseconds}ms, mounted=$mounted');
      if (mounted) {
        setState(() {
          if (buffer.isNotEmpty) {
            _messages.add(_ChatMessage(text: buffer.toString(), isUser: false));
          }
          _loading = false;
          _isStreaming = false;
        });
        _streamingText.value = '';
        _scrollToBottom();
      }
      sw.stop();
      debugPrint('🔵 [CHAT] _streamReply DONE, total=${sw.elapsedMilliseconds}ms');
    }
  }

  // ---------------------------------------------------------------------------
  // Scroll — throttled so we don't schedule hundreds of callbacks
  // ---------------------------------------------------------------------------

  void _scrollToBottom() {
    if (_scrollPending) return;
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 600;

    final panel = Material(
      elevation: 8,
      borderRadius: isSmall
          ? BorderRadius.zero
          : const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: isSmall ? screenWidth : 320,
        child: Column(
          children: [
            _buildHeader(theme, isSmall: isSmall),
            Expanded(child: _buildMessages()),
            _buildInputBar(theme),
          ],
        ),
      ),
    );

    if (isSmall) {
      return SizedBox(
        width: screenWidth,
        height: MediaQuery.of(context).size.height,
        child: panel,
      );
    }
    return panel;
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ThemeData theme, {bool isSmall = false}) {
    return Container(
      padding: EdgeInsets.only(
        left: isSmall ? 4 : 16,
        right: 16,
        top: isSmall ? MediaQuery.of(context).padding.top + 8 : 12,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: isSmall
            ? BorderRadius.zero
            : const BorderRadius.only(topLeft: Radius.circular(16)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose,
            icon: Icon(
              isSmall ? Icons.arrow_back_rounded : Icons.close,
              color: Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'AI Assistant',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: (_messages.isEmpty && !_isStreaming)
                ? null
                : () {
                    setState(() {
                      _messages.clear();
                      _history.clear();
                    });
                  },
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.white.withValues(
                alpha: (_messages.isEmpty && !_isStreaming) ? 0.4 : 1.0,
              ),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Clear conversation',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Message list
  // The streaming bubble is driven by ValueNotifier — zero setState per chunk.
  // ---------------------------------------------------------------------------

  Widget _buildMessages() {
    final hasContent = _messages.isNotEmpty || _isStreaming;
    if (!hasContent) return const _EmptyState();

    // Total items:
    //   - committed messages
    //   - streaming bubble (if active)
    //   - typing indicator (while loading but stream hasn't started yet)
    final itemCount = _messages.length +
        (_isStreaming ? 1 : 0) +
        (_loading && !_isStreaming ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Typing indicator slot (before stream starts)
        if (_loading && !_isStreaming && index == _messages.length) {
          return const _TypingIndicator();
        }

        // Streaming bubble slot — rebuilt only by ValueNotifier
        if (_isStreaming && index == _messages.length) {
          return ValueListenableBuilder<String>(
            valueListenable: _streamingText,
            builder: (_, text, __) {
              if (text.isEmpty) return const _TypingIndicator();
              return _MessageBubble(
                message: _ChatMessage(text: text, isUser: false),
              );
            },
          );
        }

        // Committed messages
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Input bar
  // ---------------------------------------------------------------------------

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              enabled: !_loading,
              decoration: InputDecoration(
                hintText: _loading ? 'AI is thinking...' : 'Type a message...',
                hintStyle: TextStyle(color: theme.colorScheme.outline),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: _loading ? null : _send),
        ],
      ),
    );
  }
}

// =============================================================================
// MESSAGE BUBBLE
// =============================================================================

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    if (!isUser && message.text.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          width: 80,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              bottomLeft: Radius.circular(2),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: isUser ? 240 : 280),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 12),
          ),
        ),
        child: isUser
            ? Text(
                message.text,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              )
            : MarkdownBody(
                data: message.text,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  code: TextStyle(
                    fontSize: 12,
                    backgroundColor: theme.colorScheme.surface,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Ask me anything about\nyour properties',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TYPING INDICATOR
// =============================================================================

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
            bottomLeft: Radius.circular(2),
          ),
        ),
        child: const SizedBox(width: 32, height: 12, child: _DotsAnimation()),
      ),
    );
  }
}

class _DotsAnimation extends StatefulWidget {
  const _DotsAnimation();

  @override
  State<_DotsAnimation> createState() => _DotsAnimationState();
}

class _DotsAnimationState extends State<_DotsAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.15).clamp(0.0, 1.0);
            final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
            return Opacity(
              opacity: opacity,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// =============================================================================
// SEND BUTTON
// =============================================================================

class _SendButton extends StatefulWidget {
  /// Null means disabled (while AI is responding).
  final VoidCallback? onTap;
  const _SendButton({required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color _darken(Color c, double amount) => Color.fromARGB(
        (c.a * 255.0).round().clamp(0, 255),
        (c.r * 255.0 * (1 - amount)).round().clamp(0, 255),
        (c.g * 255.0 * (1 - amount)).round().clamp(0, 255),
        (c.b * 255.0 * (1 - amount)).round().clamp(0, 255),
      );

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final disabled = widget.onTap == null;

    final bgColor = disabled
        ? color.withValues(alpha: 0.4)
        : _pressed
            ? _darken(color, 0.18)
            : _hovered
                ? _darken(color, 0.08)
                : color;

    return MouseRegion(
      cursor:
          disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) { if (!disabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) { if (!disabled) setState(() => _pressed = true); },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: (_hovered && !_pressed && !disabled)
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: AnimatedScale(
            scale: _pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: disabled
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}