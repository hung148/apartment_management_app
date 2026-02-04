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
    print('Opening room dialog - Edit mode: ${room != null}');
    
    final numberController = TextEditingController(
      text: room?.roomNumber ?? '',
    );
    
    // 1. Thêm controller cho loại phòng
    final typeController = TextEditingController(
      text: room?.roomType ?? 'Tiêu chuẩn', // Mặc định là Standard nếu là phòng mới
    );

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(room == null ? 'Thêm phòng mới' : 'Chỉnh sửa phòng'),
        content: Column(
          mainAxisSize: MainAxisSize.min, // Quan trọng để dialog không chiếm hết màn hình
          children: [
            TextField(
              controller: numberController,
              decoration: const InputDecoration(
                labelText: 'Số phòng *',
                hintText: 'VD: A101',
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            // 2. Thêm trường nhập Loại phòng
            TextField(
              controller: typeController,
              decoration: const InputDecoration(
                labelText: 'Loại phòng',
                hintText: 'VD: Studio, 1PN, 2PN...',
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () async {
              final roomNumber = numberController.text.trim();
              final roomType = typeController.text.trim();
              
              if (roomNumber.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập số phòng')),
                );
                return;
              }

              try {
                if (room == null) {
                  // ADD NEW
                  await _roomService.addRoom(
                    Room(
                      id: '',
                      area: 0.0,
                      organizationId: widget.building.organizationId,
                      buildingId: widget.building.id,
                      roomNumber: roomNumber,
                      roomType: roomType.isEmpty ? 'Standard' : roomType, // 3. Gửi roomType
                      createdAt: DateTime.now(),
                    ),
                  );
                } else {
                  // EDIT EXISTING
                  // 4. Sử dụng hàm updateRoom chung để cập nhật cả 2 trường
                  await _roomService.updateRoom(room.id, {
                    'roomNumber': roomNumber,
                    'roomType': roomType.isEmpty ? 'Standard' : roomType,
                  });
                }

                if (mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(room == null 
                          ? 'Đã thêm phòng thành công' 
                          : 'Đã cập nhật phòng thành công'),
                    ),
                  );
                }
              } catch (e) {
                print('❌ ERROR saving room: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // =========================
  // DELETE ROOM
  // =========================
  void _deleteRoom(Room room) {
    print('Opening delete confirmation for room: ${room.roomNumber}');
    
    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá phòng'),
        content: Text('Bạn có chắc muốn xoá phòng ${room.roomNumber}?'),
        actions: [
          TextButton(
            onPressed: () {
              print('Delete cancelled');
              Navigator.pop(dialogContext);
            },
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              print('Deleting room ${room.id}...');
              
              try {
                final success = await _roomService.deleteRoom(room.id);
                print('✓ Room deleted: $success');
                
                if (mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xoá phòng thành công')),
                  );
                }
              } catch (e, stackTrace) {
                print('❌ ERROR deleting room: $e');
                print('Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi xoá phòng: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Xoá'),
          ),
        ],
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
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.meeting_room, color: Colors.blue.shade700),
            ),
            title: Text(
              'Phòng ${room.roomNumber}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            // Add onTap to navigate to room detail
            onTap: () {
              print('Navigating to room detail: ${room.roomNumber}');
              Navigator.pushNamed(
                context,
                '/room-detail',
                arguments: {
                  'room': room,
                  'organization': widget.organization,
                },
              );
            },
            trailing: PopupMenuButton<String>(
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
            title: Text(widget.building.name),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              print('FAB pressed - opening add room dialog');
              _showRoomDialog();
            },
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