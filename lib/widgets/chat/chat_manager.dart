import 'package:phan_mem_quan_ly_can_ho/screens/ai_chat/ai_import_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/ai_chat/ai_subscription_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async' show TimeoutException;

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/services/ai_agent_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// =============================================================================
// OVERLAY MANAGER
// =============================================================================

class ChatOverlayManager {
  static OverlayEntry? _entry;
  static final ValueNotifier<bool> _visible = ValueNotifier(false);
  static final ValueNotifier<bool> _panelOpen = ValueNotifier(false);
  static final ValueNotifier<Offset?> _fabPosition = ValueNotifier(null);
  static final ValueNotifier<int> _modalDepth = ValueNotifier(0);
  static int _modalGeneration = 0;

  static void install() {
    _visible.value = true;
    // Route notifications from a chat-owned dialog must not move the chat
    // above that dialog or recreate the conversation while it is open.
    if (_modalDepth.value > 0) return;
    _reinsertOnTop();
  }

  static Future<T?> showModal<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    closePanel();
    final generation = _modalGeneration;
    _modalDepth.value++;
    try {
      return await showDialog<T>(
        context: context,
        useRootNavigator: true,
        builder: builder,
      );
    } finally {
      if (generation == _modalGeneration) _modalDepth.value--;
    }
  }

  static void uninstall() {
    dismissKeyboard();
    _visible.value = false;
    _panelOpen.value = false;
  }

  /// Closes the panel and makes sure the soft keyboard goes with it.
  static void closePanel() {
    dismissKeyboard();
    _panelOpen.value = false;
  }

  static void dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.hasFocus) focus.unfocus();
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
          return ValueListenableBuilder<int>(
            valueListenable: _modalDepth,
            builder: (_, depth, child) => Offstage(
              offstage: depth > 0,
              child: TickerMode(enabled: depth == 0, child: child!),
            ),
            child: _ChatOverlay(panelOpen: _panelOpen, fabPosition: _fabPosition),
          );
        },
      ),
    );
    overlay.insert(_entry!);
  }

  static void dispose() {
    dismissKeyboard();
    _modalGeneration++;
    _modalDepth.value = 0;
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
                child: _ChatPanel(onClose: ChatOverlayManager.closePanel),
              ),
            ),
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
              onPanStart: (d) {
                _dragStart = d.globalPosition;
                _posStart = pos;
              },
              onPanUpdate: (d) {
                final delta = d.globalPosition - _dragStart;
                if (delta.distance > 4) {
                  _didMove = true;
                  if (!_dragging) setState(() => _dragging = true);
                }
                if (!_didMove) return;
                widget.positionNotifier.value = _toFrac(
                  _posStart + delta,
                  screen,
                );
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
                  key: const ValueKey('ai-chat-launcher'),
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
  final _history = <Map<String, String>>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _streamingText = ValueNotifier<String>('');

  Map<String, dynamic>? _usage;
  Future<void> _refreshUsage() async {
    try {
      final value = await _ai.usage();
      if (mounted) setState(() => _usage = value);
    } catch (_) {}
  }

  Future<void> _upload() async {
    final count = await ChatOverlayManager.showModal<int>(
      context: context,
      builder: (_) => const AIImportDialog(),
    );
    if (count != null && mounted)
      setState(
        () => _messages.add(
          _ChatMessage(
            text: AppTranslations.of(
              context,
            ).textWithParams('ai_import_saved', {'count': count}),
            isUser: false,
          ),
        ),
      );
    await _refreshUsage();
  }

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  bool _loading = false;
  bool _isStreaming = false;
  bool _scrollPending = false;
  double _lastKeyboardInset = 0;

  AIAgentService get _ai => getIt<AIAgentService>();

  @override
  void dispose() {
    ChatOverlayManager.dismissKeyboard();
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
    _streamReply(text);
  }

  // ---------------------------------------------------------------------------
  // Tool executor
  // ---------------------------------------------------------------------------

  Future<void> _streamReply(String userText) async {
    final t = AppTranslations.of(context);
    final msgTimeout = t.text('chat_error_timeout'); // raw template

    final historyData = List<Map<String, String>>.from(_history);
    _streamingText.value = '';
    final buffer = StringBuffer();

    try {
      final result = await _ai.chat(
        message: userText,
        history: historyData,
        language: t.locale.languageCode,
      );
      buffer.write(result);
      if (mounted && result.isNotEmpty) {
        const chunkSize = 8;
        var i = 0;
        while (i < result.length) {
          if (!mounted) break;
          i = (i + chunkSize).clamp(0, result.length);
          _streamingText.value = result.substring(0, i);
          _scrollToBottom();
          await Future.delayed(const Duration(milliseconds: 16));
        }
      }

      if (buffer.isNotEmpty) {
        _history.add({'role': 'user', 'text': userText});
        _history.add({'role': 'model', 'text': buffer.toString()});
      }
    } on TimeoutException catch (e) {
      buffer.write(msgTimeout.replaceAll('{{message}}', e.message ?? ''));
      _streamingText.value = buffer.toString();
    } catch (e) {
      buffer.write(
        e is FirebaseFunctionsException
            ? t[e.message?.startsWith('ai_') == true
                  ? e.message!
                  : 'ai_unavailable']
            : t['ai_unavailable'],
      );
      _streamingText.value = buffer.toString();
    } finally {
      if (mounted) {
        setState(() {
          if (buffer.isNotEmpty) {
            _messages.add(_ChatMessage(text: buffer.toString(), isUser: false));
          }
          _loading = false;
          _isStreaming = false;
        });
        _streamingText.value = '';
        _refreshUsage();
        _scrollToBottom();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Scroll
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
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isSmall = screenWidth < 600;

    // Keep the newest message in view while the keyboard slides in or out.
    if (media.viewInsets.bottom != _lastKeyboardInset) {
      _lastKeyboardInset = media.viewInsets.bottom;
      _scrollToBottom();
    }

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _usage == null
                          ? AppTranslations.of(context)['ai_free_allowance']
                          : AppTranslations.of(
                              context,
                            ).textWithParams('ai_usage', {
                              'messages': _usage!['remainingMessages'],
                              'imports': _usage!['remainingImports'],
                            }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ChatOverlayManager.showModal<void>(
                        context: context,
                        builder: (_) => const AISubscriptionDialog(),
                      );
                      await _refreshUsage();
                    },
                    child: const Text('AI Pro'),
                  ),
                ],
              ),
            ),
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
          Expanded(
            child: Text(
              AppTranslations.of(context).text('chat_ai_assistant'),
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
                : () => setState(() {
                    _messages.clear();
                    _history.clear();
                  }),
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: Colors.white.withValues(
                alpha: (_messages.isEmpty && !_isStreaming) ? 0.4 : 1.0,
              ),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: AppTranslations.of(
              context,
            ).text('chat_clear_conversation'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty && !_isStreaming) return const _EmptyState();

    final itemCount =
        _messages.length +
        (_isStreaming ? 1 : 0) +
        (_loading && !_isStreaming ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_loading && !_isStreaming && index == _messages.length) {
          return const _TypingIndicator();
        }
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
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final media = MediaQuery.of(context);
    // Height the soft keyboard is covering right now (0 when it is closed).
    final keyboardInset = media.viewInsets.bottom;
    // When the keyboard is closed, keep clear of the home indicator instead.
    final bottomPad = keyboardInset > 0
        ? keyboardInset + 10
        : media.padding.bottom + 10;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(10, 10, 10, bottomPad),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _loading ? null : _upload,
            tooltip: AppTranslations.of(context)['ai_import_title'],
            icon: const Icon(Icons.attach_file),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              enabled: !_loading,
              decoration: InputDecoration(
                hintText: _loading
                    ? AppTranslations.of(context).text('chat_input_thinking')
                    : AppTranslations.of(context).text('chat_input_hint'),
                hintStyle: TextStyle(color: theme.colorScheme.outline),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
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
            AppTranslations.of(context).text('chat_empty_hint'),
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
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        if (!disabled) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) {
          if (!disabled) setState(() => _pressed = true);
        },
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

