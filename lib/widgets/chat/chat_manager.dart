import 'package:apartment_management_project_2/main.dart';
import 'package:flutter/material.dart';

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

// ---------------------------------------------------------------------------
// Root overlay widget
// ---------------------------------------------------------------------------
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
              top: isSmall ? 0 : 0,
              left: isSmall ? 0 : null, // full width on small
              child: AnimatedSlide(
                offset: isOpen
                    ? Offset.zero
                    : isSmall
                        ? const Offset(0, 1.0)  // slide up from bottom
                        : const Offset(1.0, 0), // slide in from right
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: _ChatPanel(onClose: () => panelOpen.value = false),
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

// ---------------------------------------------------------------------------
// Draggable FAB — position stored as fractional offset (0.0–1.0)
// so it stays proportional when the window resizes
// ---------------------------------------------------------------------------
class _DraggableFab extends StatefulWidget {
  final ValueNotifier<Offset?> positionNotifier;
  final VoidCallback onTap;
  const _DraggableFab({
    required this.positionNotifier,
    required this.onTap,
  });

  @override
  State<_DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<_DraggableFab> {
  bool _didMove = false;
  bool _dragging = false; // cursor style only
  bool _hovered = false;
  Offset _dragStart = Offset.zero;
  Offset _posStart = Offset.zero; // pixel position at drag start

  static const double _fabSize = 96.0;

  // Default: bottom-right corner
  Offset _defaultFrac() => const Offset(1.0, 1.0);

  static const double _marginRight = 16.0;
  static const double _marginBottom = 24.0;

  Offset _toPixel(Offset frac, Size screen) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final maxX = screen.width - _fabSize - _marginRight;
    final maxY = screen.height - _fabSize - bottomPad - _marginBottom;
    return Offset(
      frac.dx * maxX,
      frac.dy * maxY,
    );
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
        final frac = savedFrac ?? _defaultFrac();
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
                  setState(() => _dragging = true);
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

// ---------------------------------------------------------------------------
// Chat panel
// ---------------------------------------------------------------------------
class _ChatPanel extends StatefulWidget {
  final VoidCallback onClose;
  const _ChatPanel({required this.onClose});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    // TODO: replace with AIAgentService call
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          text: 'I received: "$text". Connect me to AIAgentService!',
          isUser: false,
        ));
        _loading = false;
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

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

    // On small screens, wrap in a full-screen sized box
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
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) return const _EmptyState();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return const _TypingIndicator();
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

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
              decoration: InputDecoration(
                hintText: 'Type a message...',
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
          _SendButton(onTap: _send),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 240),
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
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 13,
            color: isUser ? Colors.white : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 40, color: Theme.of(context).colorScheme.outline),
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
        child: const SizedBox(
          width: 32,
          height: 12,
          child: _DotsAnimation(),
        ),
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
  late AnimationController _ctrl;

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
                  color: Theme.of(context).colorScheme.outline,
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

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
      ),
    );
  }
}