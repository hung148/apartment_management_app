import 'dart:convert';
import 'dart:async' show TimeoutException;

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/services/ai_agent_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> _callWithRetry({
  required String apiKey,
  required String modelName,
  required String systemPrompt,
  required String userMsg,
  required List<Map<String, String>> history,
  int maxRetries = 3,
}) async {
  int attempt = 0;
  while (true) {
    try {
      return await _callGeminiHttp(
        apiKey: apiKey,
        modelName: modelName,
        systemPrompt: systemPrompt,
        userMsg: userMsg,
        history: history,
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      attempt++;
      final msg = e.toString();
      final is503 = msg.contains('503') || msg.contains('UNAVAILABLE');
      final is429 = msg.contains('429') || msg.contains('RESOURCE_EXHAUSTED');

      if ((!is503 && !is429) || attempt >= maxRetries) rethrow;

      final waitSeconds = is429 ? 60 : (2 << (attempt - 1));
      await Future.delayed(Duration(seconds: waitSeconds));
    }
  }
}

Future<Map<String, dynamic>> _sendToolResultWithRetry({
  required String apiKey,
  required String modelName,
  required String systemPrompt,
  required List<Map<String, dynamic>> contents,
  int maxRetries = 3,
}) async {
  int attempt = 0;
  while (true) {
    try {
      return await _sendToolResult(
        apiKey: apiKey,
        modelName: modelName,
        systemPrompt: systemPrompt,
        contents: contents,
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      attempt++;
      final is503 = e.toString().contains('503') || e.toString().contains('UNAVAILABLE');
      if (!is503 || attempt >= maxRetries) rethrow;
      await Future.delayed(Duration(seconds: 2 << (attempt - 1)));
    }
  }
}

// =============================================================================
// FUNCTION DECLARATIONS
// =============================================================================

const List<Map<String, dynamic>> _functionDeclarations = [
  {
    'name': 'get_organizations',
    'description':
        'Get all organizations the current user belongs to. '
        'Call this first when the user mentions an organization by name, '
        'to resolve the correct organizationId before calling other tools.',
    'parameters': {
      'type': 'object',
      'properties': {},
    },
  },
  {
    'name': 'get_buildings',
    'description':
        'List all buildings in an organization. '
        'Ask the user which organization if not already known.',
    'parameters': {
      'type': 'object',
      'properties': {
        'organizationId': {'type': 'string', 'description': 'The organization ID'},
      },
      'required': ['organizationId'],
    },
  },
  {
    'name': 'get_tenants',
    'description':
        'List tenants in an organization. '
        'Optionally filter by buildingId.',
    'parameters': {
      'type': 'object',
      'properties': {
        'organizationId': {'type': 'string', 'description': 'The organization ID'},
        'buildingId': {'type': 'string', 'description': 'Optional: filter by building ID'},
      },
      'required': ['organizationId'],
    },
  },
  {
    'name': 'get_payments',
    'description':
        'List payments in an organization. '
        'Optionally filter by buildingId, tenantId, or overdue status.',
    'parameters': {
      'type': 'object',
      'properties': {
        'organizationId': {'type': 'string', 'description': 'The organization ID'},
        'buildingId': {'type': 'string', 'description': 'Optional: filter by building ID'},
        'tenantId': {'type': 'string', 'description': 'Optional: filter by tenant ID'},
        'overdueOnly': {
          'type': 'boolean',
          'description': 'If true, return only overdue payments',
        },
      },
      'required': ['organizationId'],
    },
  },
  {
    'name': 'create_building',
    'description':
        'Create a new building. '
        'ALWAYS ask the user for the organization, building name, and address '
        'before calling this. Never invent a name or address.',
    'parameters': {
      'type': 'object',
      'properties': {
        'organizationId': {'type': 'string', 'description': 'The organization ID'},
        'name': {'type': 'string', 'description': 'Building name provided by the user'},
        'address': {'type': 'string', 'description': 'Building address provided by the user'},
      },
      'required': ['organizationId', 'name', 'address'],
    },
  },
  {
    'name': 'get_rooms',
    'description': 'List all rooms in a building.',
    'parameters': {
      'type': 'object',
      'properties': {
        'organizationId': {'type': 'string', 'description': 'The organization ID'},
        'buildingId': {'type': 'string', 'description': 'The building ID'},
      },
      'required': ['organizationId', 'buildingId'],
    },
  },
];

// =============================================================================
// GEMINI HTTP
// =============================================================================

Future<Map<String, dynamic>> _callGeminiHttp({
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
      'parts': [
        {'text': h['text']}
      ],
    });
  }
  contents.add({
    'role': 'user',
    'parts': [
      {'text': userMsg}
    ],
  });

  final body = jsonEncode({
    'system_instruction': {
      'parts': [
        {'text': systemPrompt}
      ],
    },
    'contents': contents,
    'tools': [
      {'function_declarations': _functionDeclarations}
    ],
  });

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );

  if (response.statusCode != 200) {
    throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
  }

  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _sendToolResult({
  required String apiKey,
  required String modelName,
  required String systemPrompt,
  required List<Map<String, dynamic>> contents, // already fully built
}) async {
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
  );

  final body = jsonEncode({
    'system_instruction': {
      'parts': [{'text': systemPrompt}],
    },
    'contents': contents,
    'tools': [
      {'function_declarations': _functionDeclarations}
    ],
  });

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );

  if (response.statusCode != 200) {
    throw Exception('Gemini follow-up error ${response.statusCode}: ${response.body}');
  }

  return jsonDecode(response.body) as Map<String, dynamic>;
}

String _extractText(Map<String, dynamic> json) {
  final candidates = json['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) return '';
  final content = candidates[0]['content'] as Map<String, dynamic>?;
  final parts = content?['parts'] as List?;
  if (parts == null || parts.isEmpty) return '';
  return parts[0]['text'] as String? ?? '';
}

Map<String, dynamic>? _extractFunctionCall(Map<String, dynamic> json) {
  final candidates = json['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) return null;
  final content = candidates[0]['content'] as Map<String, dynamic>?;
  final parts = content?['parts'] as List?;
  if (parts == null || parts.isEmpty) return null;
  for (final part in parts) {
    if ((part as Map)['functionCall'] != null) {
      return part['functionCall'] as Map<String, dynamic>;
    }
  }
  return null;
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
            cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
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
                widget.positionNotifier.value = _toFrac(_posStart + delta, screen);
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
  final _history = <Map<String, String>>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _streamingText = ValueNotifier<String>('');

  bool _loading = false;
  bool _isStreaming = false;
  bool _scrollPending = false;

  String get _systemPrompt {
    final isVi = getIt<LocaleNotifier>().locale.languageCode == 'vi';
    
    if (isVi) {
      return 'Bạn là trợ lý AI cho ứng dụng quản lý căn hộ. '
          'Hãy trả lời ngắn gọn, rõ ràng. '
          'Khi cần thông tin về tổ chức, tòa nhà, người thuê hoặc thanh toán — hãy dùng công cụ. '
          'Khi người dùng yêu cầu tạo dữ liệu: LUÔN hỏi đầy đủ thông tin trước khi gọi công cụ. '
          'Không bao giờ tự đặt tên hoặc bịa thông tin.';
    }
    
    return 'You are an AI assistant for an apartment management app. '
        'Be concise and clear. '
        'When you need data about organizations, buildings, tenants, or payments — use the provided tools. '
        'When the user asks to create data: ALWAYS ask for all required info before calling any tool. '
        'Never invent names or details.';
  }

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
    _streamReply(text);
  }

  // ---------------------------------------------------------------------------
  // Tool executor
  // ---------------------------------------------------------------------------

  Future<String> _executeTool(String name, Map<String, dynamic> args) async {
    final userId = getIt<AuthService>().currentUser?.uid;
    if (userId == null) return 'Error: not authenticated.';

    // Permission check for org-scoped tools
    final orgId = args['organizationId'] as String?;
    if (orgId != null && orgId.isNotEmpty) {
      final membership = await getIt<OrganizationService>()
          .getUserMembership(userId, orgId);
      if (membership == null) {
        return 'Access denied: you are not a member of this organization.';
      }
      const writeTools = {'create_building'};
      if (writeTools.contains(name) && membership.role != 'admin') {
        return 'Access denied: admin role required for this action.';
      }
    }

    try {
      switch (name) {
        case 'get_organizations':
          final orgs = await getIt<OrganizationService>()
              .getUserOrganizations(userId);
          if (orgs.isEmpty) return 'No organizations found.';
          return orgs.map((o) => '- ${o.name} (ID: ${o.id})').join('\n');

        case 'get_buildings':
          final buildings = await getIt<BuildingService>()
              .getOrganizationBuildings(orgId!);
          if (buildings.isEmpty) return 'No buildings found.';
          return buildings
              .map((b) => '- ${b.name}, ${b.address} (ID: ${b.id})')
              .join('\n');

        case 'get_tenants':
          final bid = args['buildingId'] as String?;
          final tenants = bid != null && bid.isNotEmpty
              ? await getIt<TenantService>()
                  .getBuildingTenants(orgId!, bid)
              : await getIt<TenantService>()
                  .getOrganizationTenants(orgId!);
          if (tenants.isEmpty) return 'No tenants found.';
          return tenants
              .map((t) => '- ${t.fullName}, Phone: ${t.phoneNumber}, Room: ${t.roomId}')
              .join('\n');

        case 'get_payments':
          final bid = args['buildingId'] as String?;
          final tid = args['tenantId'] as String?;
          final overdueOnly = args['overdueOnly'] as bool? ?? false;

          final payments = overdueOnly
              ? await getIt<PaymentService>().getOverduePayments(orgId!)
              : bid != null && bid.isNotEmpty
                  ? await getIt<PaymentService>()
                      .getBuildingPayments(orgId!, bid)
                  : tid != null && tid.isNotEmpty
                      ? await getIt<PaymentService>()
                          .getTenantPayments(orgId!, tid)
                      : await getIt<PaymentService>()
                          .getOrganizationPayments(orgId!);

          if (payments.isEmpty) return 'No payments found.';
          return payments
              .map((p) =>
                  '- ${p.tenantName}: ${p.totalAmount.toStringAsFixed(0)}đ '
                  '(${p.status.name}, due: ${p.dueDate.day}/${p.dueDate.month}/${p.dueDate.year})')
              .join('\n');

        case 'create_building':
          final buildingName = args['name'] as String? ?? '';
          final address = args['address'] as String? ?? '';
          if (buildingName.isEmpty) return 'Missing building name.';

          final newId = await getIt<BuildingService>()
              .addBuildingFromDialogResult(
            organizationId: orgId!,
            dialogResult: {
              'name': buildingName,
              'address': address,
              'autoGenerateRooms': false,
            },
          );
          if (newId == null) return 'Failed to create building. Please try again.';
          return 'Building "$buildingName" created successfully. '
              'You can now add rooms from the Buildings screen.';
        
        case 'get_rooms':
          final bid = args['buildingId'] as String? ?? '';
          if (bid.isEmpty) return 'Missing buildingId.';
          final rooms = await getIt<RoomService>()
              .getBuildingRooms(orgId!, bid);
          if (rooms.isEmpty) return 'No rooms found in this building.';
          return rooms
              .map((r) => '- ${r.roomNumber}, Type: ${r.roomType}, Area: ${r.area}m² (ID: ${r.id})')
              .join('\n');
        
        default:
          return 'Unknown tool: $name';
      }
    } catch (e) {
      return 'Tool error: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // Reply with function calling support
  // ---------------------------------------------------------------------------

  Future<void> _streamReply(String userText) async {
    final t = AppTranslations.of(context);
    final msgNotConfigured = t.text('chat_not_configured');
    final msgTimeout       = t.text('chat_error_timeout');   // raw template
    final msgError         = t.text('chat_error_generic');   // raw template

    if (_ai.apiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: msgNotConfigured,
            isUser: false,
          ));
          _loading = false;
          _isStreaming = false;
        });
      }
      return;
    }

    final historyData = List<Map<String, String>>.from(_history);
    _streamingText.value = '';
    final buffer = StringBuffer();

    try {
      // Build contents list once — we'll append to it each tool round
      final contents = <Map<String, dynamic>>[];
      for (final h in historyData) {
        contents.add({
          'role': h['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': h['text']}],
        });
      }
      contents.add({
        'role': 'user',
        'parts': [{'text': userText}],
      });

      // First call
      var responseJson = await _callWithRetry(
        apiKey: _ai.apiKey,
        modelName: _ai.modelName,
        systemPrompt: _systemPrompt,
        userMsg: userText,
        history: historyData,
      );

      // Loop to handle chained tool calls (e.g. get_organizations → get_buildings)
      while (true) {
        final functionCall = _extractFunctionCall(responseJson);
        if (functionCall == null) break; // No more tools → proceed to final text

        final fnName = functionCall['name'] as String;
        final fnArgs = (functionCall['args'] as Map<String, dynamic>?) ?? {};

        _streamingText.value = ''; // keep typing indicator visible

        final toolResult = await _executeTool(fnName, fnArgs);

        // Append this tool round to contents
        contents.add({
          'role': 'model',
          'parts': [{'functionCall': functionCall}],
        });
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': fnName,
                'response': {'result': toolResult},
              }
            }
          ],
        });

        // ✅ Add delay before next API call to avoid hitting rate limit
        await Future.delayed(const Duration(seconds: 3));

        // Send updated contents and get next response
        responseJson = await _sendToolResultWithRetry(
          apiKey: _ai.apiKey,
          modelName: _ai.modelName,
          systemPrompt: _systemPrompt,
          contents: contents,
        );
      }

      // Now extract the final text response
      final result = _extractText(responseJson);

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
       buffer.write(msgError.replaceAll('{{error}}', e.toString()));
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
              color: Colors.white
                  .withValues(alpha: (_messages.isEmpty && !_isStreaming) ? 0.4 : 1.0),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: AppTranslations.of(context).text('chat_clear_conversation'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty && !_isStreaming) return const _EmptyState();

    final itemCount = _messages.length +
        (_isStreaming ? 1 : 0) +
        (_loading && !_isStreaming ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
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
                hintText: _loading
                    ? AppTranslations.of(context).text('chat_input_thinking')
                    : AppTranslations.of(context).text('chat_input_hint'),
                hintStyle: TextStyle(color: theme.colorScheme.outline),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  p: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  code: TextStyle(
                      fontSize: 12, backgroundColor: theme.colorScheme.surface),
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
          Icon(Icons.chat_bubble_outline,
              size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            AppTranslations.of(context).text('chat_empty_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Theme.of(context).colorScheme.outline),
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
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
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
                          strokeWidth: 2, color: Colors.white),
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}