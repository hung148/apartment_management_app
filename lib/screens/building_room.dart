import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:flutter/material.dart';
import 'dart:async';

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
  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;

  Set<String> _selectedRoomIds = {}; // Stores IDs of selected rooms
  bool _isSelectionMode = false;     // Toggles selection UI

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
  bool _isInitialized = false;  // Track if we've gotten the building from route

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {  
      // Initialize stream subscription once on widget creation
      _initializeStream();
    } catch (e, stackTrace) {
      print('❌ ERROR in initState: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _initializeStream() {
    if (!mounted) return; // Add this
    print('Initializing room stream for building: ${widget.building.id}');
    
    // Cancel existing subscription if any
    _roomSubscription?.cancel();
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      _roomSubscription = _roomService
          .streamBuildingRooms(widget.building.id)
          .listen(
            (rooms) {
              print('✓ Stream received ${rooms.length} rooms');
              if (mounted) {
                setState(() {
                  _cachedRooms = rooms;
                  _isLoading = false;
                  _errorMessage = null;
                });
              }
            },
            onError: (error, stackTrace) {
              print('❌ Stream ERROR: $error');
              print('Stack trace: $stackTrace');
              if (mounted) {
                setState(() {
                  _errorMessage = 'Stream error: $error';
                  _isLoading = false;
                });
              }
            },
            cancelOnError: false,
          );
    } catch (e, stackTrace) {
      print('❌ ERROR setting up stream: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to setup stream: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    print('BuildingRoomScreen: disposing');
    WidgetsBinding.instance.removeObserver(this);
    _roomSubscription?.cancel();
    super.dispose();
  }

   // Debounce timer for resize handling
  Timer? _resizeDebounceTimer;

  // Guard to prevent overlapping dismiss calls
  bool _isDismissing = false;

  // ─── Called whenever screen size / metrics change ───
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Cancel any pending debounce before setting a new one
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      if (screenWidth < 360 || screenHeight < 600) {
        _dismissAllOverlays();
      }
    });
  }

  // Pops all open dialogs/bottom sheets by popping until only the base route remains.
  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;

    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        // Yield to the framework between each pop so it can finish
        // destroying the previous overlay before we pop the next one.
        // This prevents back-to-back surface destruction that triggers EGL errors.
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

  // ─── Overlay helpers ───

  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    _overlayCount++;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  // =========================
  // ADD / EDIT ROOM DIALOG
  // =========================
  void _showRoomDialog({Room? room}) {
    final numberController = TextEditingController(text: room?.roomNumber ?? '');
    final typeController = TextEditingController(text: room?.roomType ?? 'Tiêu chuẩn');

    // Use a local variable to prevent double-submissions
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder( // Add StatefulBuilder here
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(room == null ? 'Thêm phòng mới' : 'Chỉnh sửa phòng'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(labelText: 'Số phòng *', hintText: 'VD: A101'),
                  autofocus: true,
                  enabled: !isSaving, // Disable input while saving
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(labelText: 'Loại phòng', hintText: 'VD: Studio, 1PN, 2PN...'),
                  enabled: !isSaving, // Disable input while saving
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            actions: [
              TextButton(
                // Disable cancel button while saving
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                // If isSaving is true, onPressed is null, which disables the button
                onPressed: isSaving 
                  ? null 
                  : () async {
                      final roomNumber = numberController.text.trim();
                      final roomType = typeController.text.trim();
                      
                      if (roomNumber.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vui lòng nhập số phòng')),
                        );
                        return;
                      }

                      // Start saving state
                      setDialogState(() => isSaving = true);

                      try {
                        if (room == null) {
                          await _roomService.addRoom(
                            Room(
                              id: '',
                              area: 0.0,
                              organizationId: widget.building.organizationId,
                              buildingId: widget.building.id,
                              roomNumber: roomNumber,
                              roomType: roomType.isEmpty ? 'Standard' : roomType,
                              createdAt: DateTime.now(),
                            ),
                          );
                        } else {
                          await _roomService.updateRoom(room.id, {
                            'roomNumber': roomNumber,
                            'roomType': roomType.isEmpty ? 'Standard' : roomType,
                          });
                        }

                        // Important: Check if the dialog is still open before popping
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(room == null ? 'Đã thêm thành công' : 'Đã cập nhật thành công')),
                            );
                          }
                        }
                      } catch (e) {
                        print('❌ ERROR saving room: $e');
                        // Reset saving state so user can try again
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                child: isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================
  // DELETE ROOM
  // =========================
  void _deleteRoom(Room room) {
    bool isDeleting = false; // Add state guard

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Xoá phòng'),
            content: isDeleting 
                ? const Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Đang xoá...'),
                    ],
                  )
                : Text('Bạn có chắc muốn xoá phòng ${room.roomNumber}?'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: isDeleting 
                  ? null 
                  : () async {
                      setDialogState(() => isDeleting = true); // Disable button
                      try {
                        final success = await _roomService.deleteRoom(room.id);
                        
                        // Safety check before popping
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          if (mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã xoá phòng thành công')),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isDeleting = false); // Re-enable on error
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                child: const Text('Xoá'),
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================
  // MULTI-SELECTION LOGIC
  // =========================
  void _toggleRoomSelection(String roomId) {
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
    setState(() {
      _selectedRoomIds.clear();
      _isSelectionMode = false;
    });
  }

  void _selectAll() {
    if (_cachedRooms == null) return;
    setState(() {
      _selectedRoomIds = _cachedRooms!.map((r) => r.id).toSet();
      _isSelectionMode = true;
    });
  }

  // =========================
  // DELETE MULTIPLE ROOMS
  // =========================
  void _deleteSelectedRooms() {
    final count = _selectedRoomIds.length;
    bool isDeleting = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Xoá nhiều phòng'),
            content: Text(isDeleting 
                ? 'Đang xoá $count phòng...' 
                : 'Bạn có chắc muốn xoá $count phòng đã chọn? Thao tác này không thể hoàn tác.'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: isDeleting 
                  ? null 
                  : () async {
                      setDialogState(() => isDeleting = true);
                      try {
                        final success = await _roomService.deleteMultipleRooms(_selectedRoomIds.toList());
                        
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          if (mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã xoá $count phòng thành công')),
                            );
                            _clearSelection();
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isDeleting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                child: isDeleting 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Xoá tất cả'),
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================
  // SHOW ROOM INFO DIALOG
  // =========================
  void _showRoomInfoDialog(Room room) {
    _showTrackedDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.meeting_room, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text('Phòng ${room.roomNumber}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRoomInfoRow('Số phòng:', room.roomNumber),
              const SizedBox(height: 12),
              _buildRoomInfoRow('ID phòng:', room.id),
              const SizedBox(height: 12),
              _buildRoomInfoRow('ID tòa nhà:', room.buildingId),
              const SizedBox(height: 12),
              _buildRoomInfoRow('ID tổ chức:', room.organizationId),
              const SizedBox(height: 12),
              _buildRoomInfoRow('Tên tòa nhà:', widget.building.name),
              const SizedBox(height: 12),
              _buildRoomInfoRow('Địa chỉ tòa nhà:', widget.building.address),
              const SizedBox(height: 12),
              _buildRoomInfoRow('Ngày tạo:', _formatDate(room.createdAt)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

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
  Widget _buildRoomList() {
    print('Building room list widget - Loading: $_isLoading, Error: $_errorMessage, Rooms: ${_cachedRooms?.length}');
    
    // Show error state
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Lỗi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  print('Retry button pressed');
                  _initializeStream();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang tải danh sách phòng...'),
          ],
        ),
      );
    }

    // Show empty state
    if (_cachedRooms == null || _cachedRooms!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Chưa có phòng nào',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhấn nút + để thêm phòng mới',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Show room list
    print('Rendering ${_cachedRooms!.length} rooms');
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _cachedRooms!.length,
      itemBuilder: (context, index) {
        final room = _cachedRooms![index];
        final isSelected = _selectedRoomIds.contains(room.id);
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // Highlight the card with a light blue background when selected
          color: isSelected ? Colors.blue.shade50 : null,
          // Add a blue border when selected
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isSelected 
                ? BorderSide(color: Colors.blue.shade300, width: 2) 
                : BorderSide.none,
          ),
          child: ListTile(
            leading: _isSelectionMode 
              ? Checkbox(
                  value: isSelected, 
                  activeColor: Colors.blue.shade700,
                  onChanged: (_) => _toggleRoomSelection(room.id),
                )
              : CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.meeting_room, color: Colors.blue.shade700),
                ),
            title: Text(
              'Phòng ${room.roomNumber}',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.blue.shade900 : null,
              ),
            ),
            subtitle: room.roomType != null ? Text(room.roomType!) : null,
            onTap: () {
              if (_isSelectionMode) {
                _toggleRoomSelection(room.id);
              } else {
                if (_isNavigating) return; // Prevent double push
                _isNavigating = true;
                // Normal navigation
                Navigator.pushNamed(
                  context,
                  '/room-detail',
                  arguments: {'room': room, 'organization': widget.organization},
                );
                _isNavigating = false; // Reset when they come back
              }
            },
            onLongPress: () => _toggleRoomSelection(room.id),
            // Hide the menu button when in selection mode
            trailing: _isSelectionMode ? null : PopupMenuButton<String>(
              onSelected: (value) {
                print('Menu selected: $value for room ${room.roomNumber}');
                
                if (value == 'view') {
                  _showRoomInfoDialog(room);
                } else if (value == 'edit') {
                  _showRoomDialog(room: room);
                } else if (value == 'delete') {
                  _deleteRoom(room);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Chi tiết'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Xoá', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    print('BuildingRoomScreen: build called');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check minimum size
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          return Scaffold(
            body: _buildMinimumSizeWarning(context, constraints),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: _isSelectionMode 
              ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection)
              : null,
            title: _isSelectionMode 
              ? Text(_selectedRoomIds.isEmpty ? 'Chọn phòng' : '${_selectedRoomIds.length} đã chọn')
              : Text(widget.building.name),
            actions: [
              if (_isSelectionMode) ...[
                // Actions when selecting
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'Chọn tất cả',
                ),
                // Only show the delete button if at least one room is selected
                if (_selectedRoomIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: _deleteSelectedRooms,
                    tooltip: 'Xoá đã chọn',
                  ),
              ] else ...[
                // NEW: Action when NOT selecting (to enter mode)
                IconButton(
                  icon: const Icon(Icons.checklist_rtl),
                  onPressed: () => setState(() => _isSelectionMode = true),
                  tooltip: 'Chọn nhiều phòng',
                ),
              ]
            ],
          ),
          // Hide FAB when selecting to avoid confusion
          floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
            onPressed: () => _showRoomDialog(),
            child: const Icon(Icons.add),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =========================
              // BUILDING INFO
              // =========================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.apartment, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.building.name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.building.address,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tổng số phòng: ${_cachedRooms?.length ?? 0}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // =========================
              // ROOM LIST
              // =========================
              Expanded(
                child: _buildRoomList(),
              ),
            ],
          ),
        );
      }
    );
  }
}