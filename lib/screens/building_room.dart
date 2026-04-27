import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/shared.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';

class BuildingRoomScreen extends StatefulWidget {
  final Organization organization; 
  final Building building;

  const BuildingRoomScreen({
    required this.organization,
    required this.building,
    super.key
  });

  @override
  State<BuildingRoomScreen> createState() => _BuildingRoomScreenState();
}

class _BuildingRoomScreenState extends State<BuildingRoomScreen> with WidgetsBindingObserver {
  int _overlayCount = 0;

  Set<String> _selectedRoomIds = {};
  bool _isSelectionMode = false;

  bool _isSmallScreen(BuildContext context) => MediaQuery.of(context).size.width < 600;
  bool _isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }

  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.95;
    if (screenWidth < 1200) return 600;
    return 800;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    return EdgeInsets.all(_isSmallScreen(context) ? 12.0 : 16.0);
  }

  Widget _buildMinimumSizeWarning(BuildContext context, BoxConstraints constraints) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              'Kích thước cửa sổ quá nhỏ',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Kích thước tối thiểu: 360x600',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Hiện tại: ${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  final RoomService _roomService = RoomService();
  
  StreamSubscription<List<Room>>? _roomSubscription;
  List<Room>? _cachedRooms;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isNavigating = false; // prevent stale state from hot reload
    print('🟢 [initState] START — building.id=${widget.building.id}, org.id=${widget.organization.id}');
    WidgetsBinding.instance.addObserver(this);
    try {  
      _initializeStream();
    } catch (e, stackTrace) {
      print('❌ [initState] CAUGHT ERROR: $e');
      print('Stack trace: $stackTrace');
    }
    print('🟢 [initState] END');
  }

  void _initializeStream() {
    print('🔵 [_initializeStream] START — mounted=$mounted');
    if (!mounted) {
      print('⚠️ [_initializeStream] Not mounted, returning early');
      return;
    }

    print('🔵 [_initializeStream] Cancelling existing subscription...');
    _roomSubscription?.cancel();
    print('🔵 [_initializeStream] Subscription cancelled');
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    print('🔵 [_initializeStream] setState(loading=true) done');
    
    try {
      print('🔵 [_initializeStream] Calling _roomService.streamBuildingRooms...');
      final stream = _roomService.streamBuildingRooms(
        widget.building.id,
        widget.organization.id,
      );
      print('🔵 [_initializeStream] Stream object created: $stream');

      _roomSubscription = stream.listen(
        (rooms) {
          print('✅ [stream.onData] Received ${rooms.length} rooms — mounted=$mounted');
          if (mounted) {
            setState(() {
              _cachedRooms = rooms;
              _isLoading = false;
              _errorMessage = null;
            });
            print('✅ [stream.onData] setState done, _cachedRooms.length=${_cachedRooms?.length}');
          } else {
            print('⚠️ [stream.onData] Widget unmounted, skipping setState');
          }
        },
        onError: (error, stackTrace) {
          print('❌ [stream.onError] $error');
          print('Stack trace: $stackTrace');
          if (mounted) {
            setState(() {
              _errorMessage = 'Stream error: $error';
              _isLoading = false;
            });
          }
        },
        onDone: () {
          // This fires when the stream closes — should NOT happen for a real-time stream
          print('⚠️ [stream.onDone] Stream closed unexpectedly! mounted=$mounted');
        },
        cancelOnError: false,
      );
      print('🔵 [_initializeStream] listen() called, subscription=$_roomSubscription');
    } catch (e, stackTrace) {
      print('❌ [_initializeStream] Exception setting up stream: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to setup stream: $e';
        _isLoading = false;
      });
    }
    print('🔵 [_initializeStream] END');
  }

  @override
  void dispose() {
    print('🔴 [dispose] START — cancelling subscription');
    WidgetsBinding.instance.removeObserver(this);
    _roomSubscription?.cancel();
    _resizeDebounceTimer?.cancel();
    print('🔴 [dispose] END');
    super.dispose();
  }

  Timer? _resizeDebounceTimer;
  bool _isDismissing = false;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      // Use WidgetsBinding instead of MediaQuery to avoid frame scheduling issues
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      print('📐 [didChangeMetrics] size=${size.width}x${size.height}');
      if (size.width < 360 || size.height < 600) {
        print('📐 [didChangeMetrics] Below minimum, dismissing overlays');
        _dismissAllOverlays();
      }
    });
  }

  Future<void> _dismissAllOverlays() async {
    print('🔔 [_dismissAllOverlays] START — _isDismissing=$_isDismissing, mounted=$mounted');
    if (!mounted || _isDismissing) return;
    _isDismissing = true;

    try {
      final nav = Navigator.of(context);
      int popCount = 0;
      while (nav.canPop()) {
        nav.pop();
        popCount++;
        print('🔔 [_dismissAllOverlays] Popped overlay #$popCount');
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) {
          print('🔔 [_dismissAllOverlays] Unmounted during pop loop, breaking');
          break;
        }
      }
      print('🔔 [_dismissAllOverlays] Done — total pops=$popCount');
    } finally {
      _isDismissing = false;
      print('🔔 [_dismissAllOverlays] END');
    }
  }

  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    _overlayCount++;
    print('🪟 [_showTrackedDialog] Showing dialog — overlayCount=$_overlayCount');
    try {
      final result = await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
      print('🪟 [_showTrackedDialog] Dialog closed — result=$result');
      return result;
    } finally {
      if (mounted) {
        _overlayCount--;
        print('🪟 [_showTrackedDialog] overlayCount now=$_overlayCount');
      }
    }
  }

  // =========================
  // ADD / EDIT ROOM DIALOG
  // =========================
  void _showRoomDialog({Room? room}) {
    print('📝 [_showRoomDialog] Opening — editing=${room != null}, room=${room?.id}');
    final t = AppTranslations.of(context);
    final isEditing = room != null;

    final numberController = TextEditingController(text: room?.roomNumber ?? '');
    final typeController = TextEditingController(text: room?.roomType ?? 'Tiêu chuẩn');
    final areaController = TextEditingController(
      text: (room?.area ?? 0) > 0 ? room!.area.toString() : '',
    );
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: _isSmallScreen(context) ? 12 : 24,
              vertical: 24,
            ),
            child: Container(
              width: _getDialogWidth(context),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Gradient header ──────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isEditing
                              ? [Colors.orange.shade700, Colors.orange.shade400]
                              : [Colors.blue.shade700, Colors.blue.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isEditing ? Icons.edit_rounded : Icons.add_home_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing ? t['room_dialog_title_edit'] : t['room_dialog_title_add'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isEditing ? t['room_dialog_subtitle_edit'] : t['room_dialog_subtitle_add'],
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            tooltip: t['cancel'],
                          ),
                        ],
                      ),
                    ),

                    // ── Body ─────────────────────────────────────────────────
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section label
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16,
                                    color: isEditing ? Colors.orange.shade700 : Colors.blue.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  t['room_dialog_section_basic'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: isEditing ? Colors.orange.shade700 : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // ── Room number ──────────────────────────────────
                            _buildDialogField(
                              controller: numberController,
                              label: t['room_field_number_label'],
                              hint: t['room_field_number_hint'],
                              icon: Icons.tag_rounded,
                              enabled: !isSaving,
                              maxLength: 20,
                              autofocus: true,
                              textCapitalization: TextCapitalization.characters,
                              accentColor: isEditing ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                            const SizedBox(height: 14),

                            // ── Room type ────────────────────────────────────
                            _buildDialogField(
                              controller: typeController,
                              label: t['room_field_type_label'],
                              hint: t['room_field_type_hint'],
                              icon: Icons.category_rounded,
                              enabled: !isSaving,
                              maxLength: 50,
                              textCapitalization: TextCapitalization.words,
                              accentColor: isEditing ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                            const SizedBox(height: 14),

                            // ── Area ─────────────────────────────────────────
                            _buildDialogField(
                              controller: areaController,
                              label: t['room_field_area_label'],
                              hint: t['room_field_area_hint'],
                              icon: Icons.square_foot_rounded,
                              suffixText: 'm²',
                              enabled: !isSaving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              accentColor: isEditing ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Divider + Actions ─────────────────────────────────────
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(t['cancel'],
                                  style: TextStyle(color: Colors.grey.shade700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final roomNumber = numberController.text.trim();
                                      final roomType = typeController.text.trim();
                                      final area = double.tryParse(areaController.text.trim()) ?? 0.0;
                                      print('📝 [_showRoomDialog] Save — number="$roomNumber", type="$roomType", area=$area');

                                      if (roomNumber.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(t['room_field_number_required'])),
                                        );
                                        return;
                                      }

                                      setDialogState(() => isSaving = true);

                                      try {
                                        if (!isEditing) {
                                          await _roomService.addRoom(Room(
                                            id: '',
                                            area: area,
                                            organizationId: widget.building.organizationId,
                                            buildingId: widget.building.id,
                                            roomNumber: roomNumber,
                                            roomType: roomType.isEmpty ? 'Standard' : roomType,
                                            createdAt: DateTime.now(),
                                          ));
                                        } else {
                                          await _roomService.updateRoom(room.id, {
                                            'roomNumber': roomNumber,
                                            'roomType': roomType.isEmpty ? 'Standard' : roomType,
                                            'area': area,
                                          });
                                        }

                                        if (Navigator.of(dialogContext).canPop()) {
                                          Navigator.pop(dialogContext);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(isEditing
                                                    ? t['room_update_success']
                                                    : t['room_add_success']),
                                              ),
                                            );
                                          }
                                        }
                                      } catch (e, st) {
                                        print('❌ [_showRoomDialog] Error: $e\n$st');
                                        setDialogState(() => isSaving = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Lỗi: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                backgroundColor:
                                    isEditing ? Colors.orange.shade700 : Colors.blue.shade700,
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isEditing ? Icons.save_rounded : Icons.add_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isEditing ? t['room_action_save'] : t['room_action_add'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Reusable field builder ───────────────────────────────────────────────────
  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color accentColor,
    bool enabled = true,
    bool autofocus = false,
    int? maxLength,
    String? suffixText,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        suffixText: suffixText,
        prefixIcon: Icon(icon, size: 20, color: accentColor),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        floatingLabelStyle: TextStyle(color: accentColor, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  // =========================
  // DELETE ROOM
  // =========================
  void _deleteRoom(Room room) {
    print('🗑️ [_deleteRoom] Opening confirm dialog for room=${room.id}');
    final t = AppTranslations.of(context);
    bool isDeleting = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade700, Colors.red.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              t['room_delete_title'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: isDeleting
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 14),
                                Text(t['room_delete_deleting'],
                                    style: const TextStyle(fontSize: 15)),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Room badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.meeting_room_rounded,
                                          size: 18, color: Colors.red.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Phòng ${room.roomNumber}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  t.textWithParams('room_delete_confirm',
                                      {'number': room.roomNumber}),
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 15, color: Colors.orange.shade700),
                                    const SizedBox(width: 6),
                                    Text(
                                      t['room_delete_warning'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    // Actions
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isDeleting
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(t['cancel'],
                                  style: TextStyle(color: Colors.grey.shade700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isDeleting
                                  ? null
                                  : () async {
                                      print('🗑️ [_deleteRoom] Delete confirmed');
                                      setDialogState(() => isDeleting = true);
                                      try {
                                        final success =
                                            await _roomService.deleteRoom(room.id);
                                        if (Navigator.of(dialogContext).canPop()) {
                                          Navigator.pop(dialogContext);
                                          if (mounted && success) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content:
                                                  Text(t['room_delete_success']),
                                            ));
                                          }
                                        }
                                      } catch (e, st) {
                                        print('❌ [_deleteRoom] $e\n$st');
                                        setDialogState(() => isDeleting = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                            content: Text('Lỗi: $e'),
                                            backgroundColor: Colors.red,
                                          ));
                                        }
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                backgroundColor: Colors.red.shade700,
                              ),
                              icon: const Icon(Icons.delete_rounded,
                                  size: 18, color: Colors.white),
                              label: Text(t['room_delete_action'],
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // DELETE MULTIPLE ROOMS
  // =========================
  void _deleteSelectedRooms() {
    final count = _selectedRoomIds.length;
    final t = AppTranslations.of(context);
    print('🗑️ [_deleteSelectedRooms] Opening confirm for $count rooms');
    bool isDeleting = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade800, Colors.red.shade500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_sweep_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t['room_delete_multi_title'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.textWithParams(
                                      'room_selected_count', {'count': count}),
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: isDeleting
                          ? Row(
                              children: [
                                const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                                const SizedBox(width: 14),
                                Text(
                                  t.textWithParams('room_delete_multi_deleting',
                                      {'count': count}),
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Count chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.meeting_room_rounded,
                                          size: 18, color: Colors.red.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        t.textWithParams(
                                            'room_selected_count', {'count': count}),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  t.textWithParams('room_delete_multi_confirm',
                                      {'count': count}),
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 15, color: Colors.orange.shade700),
                                    const SizedBox(width: 6),
                                    Text(
                                      t['room_delete_warning'],
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    // Actions
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isDeleting
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Text(t['cancel'],
                                  style: TextStyle(color: Colors.grey.shade700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isDeleting
                                  ? null
                                  : () async {
                                      print(
                                          '🗑️ [_deleteSelectedRooms] Delete confirmed');
                                      setDialogState(() => isDeleting = true);
                                      try {
                                        final success = await _roomService
                                            .deleteMultipleRooms(
                                                _selectedRoomIds.toList());
                                        if (Navigator.of(dialogContext).canPop()) {
                                          Navigator.pop(dialogContext);
                                          if (mounted && success) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content: Text(t.textWithParams(
                                                  'room_delete_multi_success',
                                                  {'count': count})),
                                            ));
                                            _clearSelection();
                                          }
                                        }
                                      } catch (e, st) {
                                        print(
                                            '❌ [_deleteSelectedRooms] $e\n$st');
                                        setDialogState(() => isDeleting = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                            content: Text('Lỗi: $e'),
                                            backgroundColor: Colors.red,
                                          ));
                                        }
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                backgroundColor: Colors.red.shade700,
                              ),
                              icon: const Icon(Icons.delete_sweep_rounded,
                                  size: 18, color: Colors.white),
                              label: Text(t['room_delete_multi_action'],
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // SHOW ROOM INFO DIALOG
  // =========================
  void _showRoomInfoDialog(Room room) {
    print('ℹ️ [_showRoomInfoDialog] room=${room.id}');
    final t = AppTranslations.of(context);

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: _isSmallScreen(context) ? 12 : 32,
          vertical: 24,
        ),
        child: Container(
          width: _getDialogWidth(context),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.blue.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.meeting_room_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t['room_info_title'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Phòng ${room.roomNumber}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Info rows
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildInfoCard(children: [
                          _buildInfoRow(
                            icon: Icons.tag_rounded,
                            label: t['room_info_number'],
                            value: room.roomNumber,
                            color: Colors.blue.shade700,
                          ),
                          _buildInfoDivider(),
                          _buildInfoRow(
                            icon: Icons.category_rounded,
                            label: t['room_info_type'],
                            value: room.roomType,
                            color: Colors.blue.shade700,
                          ),
                          if (room.area > 0) ...[
                            _buildInfoDivider(),
                            _buildInfoRow(
                              icon: Icons.square_foot_rounded,
                              label: t['room_info_area'],
                              value: t.textWithParams(
                                  'room_area_value', {'area': room.area}),
                              color: Colors.blue.shade700,
                            ),
                          ],
                          _buildInfoDivider(),
                          _buildInfoRow(
                            icon: Icons.calendar_today_rounded,
                            label: t['room_info_created_at'],
                            value: _formatDate(room.createdAt),
                            color: Colors.blue.shade700,
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _buildInfoCard(children: [
                          _buildInfoRow(
                            icon: Icons.apartment_rounded,
                            label: t['room_info_building_name'],
                            value: widget.building.name,
                            color: Colors.indigo.shade600,
                          ),
                          _buildInfoDivider(),
                          _buildInfoRow(
                            icon: Icons.location_on_rounded,
                            label: t['room_info_building_address'],
                            value: widget.building.address,
                            color: Colors.indigo.shade600,
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _buildInfoCard(children: [
                          _buildInfoRow(
                            icon: Icons.fingerprint_rounded,
                            label: t['room_info_id'],
                            value: room.id,
                            color: Colors.grey.shade600,
                            selectable: true,
                            mono: true,
                          ),
                          _buildInfoDivider(),
                          _buildInfoRow(
                            icon: Icons.domain_rounded,
                            label: t['room_info_building_id'],
                            value: room.buildingId,
                            color: Colors.grey.shade600,
                            selectable: true,
                            mono: true,
                          ),
                          _buildInfoDivider(),
                          _buildInfoRow(
                            icon: Icons.corporate_fare_rounded,
                            label: t['room_info_org_id'],
                            value: room.organizationId,
                            color: Colors.grey.shade600,
                            selectable: true,
                            mono: true,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                // Close button
                Divider(height: 1, color: Colors.grey.shade200),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.blue.shade700,
                      ),
                      child: Text(t['close'],
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Info dialog helpers ──────────────────────────────────────────────────────
  Widget _buildInfoCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoDivider() =>
      Divider(height: 1, indent: 44, color: Colors.grey.shade200);

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool selectable = false,
    bool mono = false,
  }) {
    final valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFamily: mono ? 'monospace' : null,
      color: Colors.grey.shade800,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.4)),
                const SizedBox(height: 3),
                selectable
                    ? SelectableText(value, style: valueStyle)
                    : Text(value, style: valueStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Remove old _buildRoomInfoRow — replaced by _buildInfoRow above

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // =========================
  // BUILD ROOM LIST
  // =========================
  bool _isNavigating = false;

  Widget _buildRoomSliver(AppTranslations t) {
    if (_errorMessage != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              Text(t['room_error_title'],
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700)),
              const SizedBox(height: 8),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _initializeStream,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: Text(t['room_retry'],
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue.shade700),
              const SizedBox(height: 16),
              Text(t['room_loading'],
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    if (_cachedRooms == null || _cachedRooms!.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50, shape: BoxShape.circle),
                child: Icon(Icons.meeting_room_outlined,
                    size: 48, color: Colors.blue.shade300),
              ),
              const SizedBox(height: 20),
              Text(t['room_empty_title'],
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(t['room_empty_hint'],
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final room = _cachedRooms![index];
          final isSelected = _selectedRoomIds.contains(room.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleRoomSelection(room.id);
                  } else {
                    if (_isNavigating) return;
                    _isNavigating = true;
                    final sw = Stopwatch()..start();
                    Navigator.pushNamed(
                      context,
                      '/room-detail',
                      arguments: {
                        'room': room,
                        'organization': widget.organization
                      },
                    ).then((_) {
                      print('👆 POST-PUSH ${sw.elapsedMilliseconds}ms');
                      _isNavigating = false;
                    }).catchError((e, st) {
                      print('❌ pushNamed: $e');
                      _isNavigating = false;
                    });
                  }
                },
                onLongPress: () => _toggleRoomSelection(room.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade50
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade400
                          : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isSelectionMode
                              ? Checkbox(
                                  key: const ValueKey('checkbox'),
                                  value: isSelected,
                                  activeColor: Colors.blue.shade700,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(4)),
                                  onChanged: (_) =>
                                      _toggleRoomSelection(room.id),
                                )
                              : Container(
                                  key: const ValueKey('avatar'),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.shade100
                                        : Colors.blue.shade50,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.meeting_room_rounded,
                                      color: Colors.blue.shade700,
                                      size: 22),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Phòng ${room.roomNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: isSelected
                                      ? Colors.blue.shade900
                                      : Colors.grey.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (room.roomType.isNotEmpty) ...[
                                    Icon(Icons.category_rounded,
                                        size: 12,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(room.roomType,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600)),
                                  ],
                                  if (room.roomType.isNotEmpty &&
                                      room.area > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      child: Text('·',
                                          style: TextStyle(
                                              color:
                                                  Colors.grey.shade400)),
                                    ),
                                  if (room.area > 0) ...[
                                    Icon(Icons.square_foot_rounded,
                                        size: 12,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text('${room.area} m²',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!_isSelectionMode)
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded,
                                color: Colors.grey.shade500),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            onSelected: (value) {
                              if (value == 'view')
                                _showRoomInfoDialog(room);
                              else if (value == 'edit')
                                _showRoomDialog(room: room);
                              else if (value == 'delete') _deleteRoom(room);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'view',
                                child: Row(children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 18,
                                      color: Colors.blue.shade700),
                                  const SizedBox(width: 10),
                                  Text(t['room_popup_view']),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded,
                                      size: 18,
                                      color: Colors.orange.shade700),
                                  const SizedBox(width: 10),
                                  Text(t['room_popup_edit']),
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_rounded,
                                      size: 18,
                                      color: Colors.red.shade700),
                                  const SizedBox(width: 10),
                                  Text(t['room_popup_delete'],
                                      style: TextStyle(
                                          color: Colors.red.shade700)),
                                ]),
                              ),
                            ],
                          )
                        else
                          const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        childCount: _cachedRooms!.length,
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
        return Scaffold(body: _buildMinimumSizeWarning(context, constraints));
      }

      return Scaffold(
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton(
                onPressed: _showRoomDialog,
                backgroundColor: Colors.blue.shade700,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
        body: CustomScrollView(
          slivers: [
            // ── Merged SliverAppBar + header ─────────────────────────────────
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              stretch: true,
              backgroundColor: Colors.blue.shade800,
              automaticallyImplyLeading: false,
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: _clearSelection,
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
              title: _isSelectionMode
                  ? Text(
                      _selectedRoomIds.isEmpty
                          ? t['room_select_mode_title']
                          : t.textWithParams('room_selected_count',
                              {'count': _selectedRoomIds.length}),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    )
                  : null,
              actions: [
                if (_isSelectionMode) ...[
                  IconButton(
                    icon: Icon(
                      _cachedRooms != null && _selectedRoomIds.length == _cachedRooms!.length
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _selectAll,
                    tooltip: _cachedRooms != null && _selectedRoomIds.length == _cachedRooms!.length
                        ? t['room_deselect_all_tooltip']
                        : t['room_select_all_tooltip'],
                  ),
                  if (_selectedRoomIds.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_rounded, color: Colors.white),
                      onPressed: _deleteSelectedRooms,
                      tooltip: t['room_delete_selected_tooltip'],
                    ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.checklist_rtl_rounded, color: Colors.white),
                    onPressed: () => setState(() => _isSelectionMode = true),
                    tooltip: t['room_multi_select_tooltip'],
                  ),
                ],
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                // ⚠️ No title here — avoids the bleed-through overlap
                background: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Gradient background ──────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade900, Colors.blue.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),

                    // ── Right-side circles ───────────────────────────────
                    Positioned(
                      right: -15,
                      top: -20,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 55,
                      top: -28,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.10),
                        ),
                      ),
                    ),

                    // ── Center circle ────────────────────────────────────
                    Positioned(
                      left: 280,
                      top: -18,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.09),
                        ),
                      ),
                    ),

                    // ── Left-side circles ────────────────────────────────
                    Positioned(
                      left: -18,
                      bottom: -12,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 42,
                      top: -12,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),

                    // ── Existing content column ──────────────────────────
                    Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Building name row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.apartment_rounded,
                                        color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.building.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.3,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Address + room count row
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on_rounded,
                                            size: 13,
                                            color: Colors.white.withValues(alpha: 0.75)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            widget.building.address,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.white.withValues(alpha: 0.85),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.3), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.meeting_room_rounded,
                                            size: 13, color: Colors.white),
                                        const SizedBox(width: 5),
                                        Text(
                                          t.textWithParams('room_total_count',
                                              {'count': _cachedRooms?.length ?? 0}),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Room list as sliver ───────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              sliver: _buildRoomSliver(t),
            ),
          ],
        ),
      );
    });
  }

  // =========================
  // MULTI-SELECTION LOGIC
  // =========================
  void _toggleRoomSelection(String roomId) {
    print('☑️ [_toggleRoomSelection] roomId=$roomId, currently selected=${_selectedRoomIds.contains(roomId)}');
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
      } else {
        _selectedRoomIds.add(roomId);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    print('☑️ [_clearSelection] Clearing ${_selectedRoomIds.length} selections');
    setState(() {
      _selectedRoomIds.clear();
      _isSelectionMode = false;
    });
  }

  void _selectAll() {
    if (_cachedRooms == null) return;
    final allSelected = _selectedRoomIds.length == _cachedRooms!.length;
    print('☑️ [_selectAll] ${allSelected ? "Deselecting" : "Selecting"} all ${_cachedRooms!.length} rooms');
    setState(() {
      if (allSelected) {
        _selectedRoomIds.clear();
      } else {
        _selectedRoomIds = _cachedRooms!.map((r) => r.id).toSet();
      }
      _isSelectionMode = true;
    });
  }
}