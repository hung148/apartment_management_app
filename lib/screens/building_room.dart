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
  bool _isInitialized = false;

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
    final numberController = TextEditingController(text: room?.roomNumber ?? '');
    final typeController = TextEditingController(text: room?.roomType ?? 'Tiêu chuẩn');
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(room == null ? 'Thêm phòng mới' : 'Chỉnh sửa phòng'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  maxLength: 20,
                  decoration: const InputDecoration(counterText: "", labelText: 'Số phòng *', hintText: 'VD: A101'),
                  autofocus: true,
                  enabled: !isSaving,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: typeController,
                  maxLength: 50,
                  decoration: const InputDecoration(counterText: "", labelText: 'Loại phòng', hintText: 'VD: Studio, 1PN, 2PN...'),
                  enabled: !isSaving,
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () {
                  print('📝 [_showRoomDialog] Cancel pressed');
                  Navigator.pop(dialogContext);
                },
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                onPressed: isSaving 
                  ? null 
                  : () async {
                      final roomNumber = numberController.text.trim();
                      final roomType = typeController.text.trim();
                      print('📝 [_showRoomDialog] Save pressed — roomNumber="$roomNumber", roomType="$roomType"');
                      
                      if (roomNumber.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vui lòng nhập số phòng')),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      print('📝 [_showRoomDialog] isSaving=true, calling service...');

                      try {
                        if (room == null) {
                          print('📝 [_showRoomDialog] Calling addRoom...');
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
                          print('📝 [_showRoomDialog] addRoom completed');
                        } else {
                          print('📝 [_showRoomDialog] Calling updateRoom for id=${room.id}...');
                          await _roomService.updateRoom(room.id, {
                            'roomNumber': roomNumber,
                            'roomType': roomType.isEmpty ? 'Standard' : roomType,
                          });
                          print('📝 [_showRoomDialog] updateRoom completed');
                        }

                        print('📝 [_showRoomDialog] Checking canPop...');
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(room == null ? 'Đã thêm thành công' : 'Đã cập nhật thành công')),
                            );
                          }
                        } else {
                          print('⚠️ [_showRoomDialog] canPop=false, dialog may already be closed');
                        }
                      } catch (e, stackTrace) {
                        print('❌ [_showRoomDialog] Save error: $e');
                        print('Stack trace: $stackTrace');
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
    print('🗑️ [_deleteRoom] Opening confirm dialog for room=${room.id}, number=${room.roomNumber}');
    bool isDeleting = false;

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
                onPressed: isDeleting ? null : () {
                  print('🗑️ [_deleteRoom] Cancel pressed');
                  Navigator.pop(dialogContext);
                },
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: isDeleting 
                  ? null 
                  : () async {
                      print('🗑️ [_deleteRoom] Delete confirmed for room=${room.id}');
                      setDialogState(() => isDeleting = true);
                      try {
                        print('🗑️ [_deleteRoom] Calling _roomService.deleteRoom...');
                        final success = await _roomService.deleteRoom(room.id);
                        print('🗑️ [_deleteRoom] deleteRoom returned success=$success');
                        
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          if (mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã xoá phòng thành công')),
                            );
                          }
                        } else {
                          print('⚠️ [_deleteRoom] canPop=false after delete');
                        }
                      } catch (e, stackTrace) {
                        print('❌ [_deleteRoom] Error: $e');
                        print('Stack trace: $stackTrace');
                        setDialogState(() => isDeleting = false);
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
    print('☑️ [_selectAll] Selecting all ${_cachedRooms!.length} rooms');
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
    print('🗑️ [_deleteSelectedRooms] Opening confirm for $count rooms: $_selectedRoomIds');
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
                onPressed: isDeleting ? null : () {
                  print('🗑️ [_deleteSelectedRooms] Cancel pressed');
                  Navigator.pop(dialogContext);
                },
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: isDeleting 
                  ? null 
                  : () async {
                      print('🗑️ [_deleteSelectedRooms] Delete confirmed — ids=$_selectedRoomIds');
                      setDialogState(() => isDeleting = true);
                      try {
                        print('🗑️ [_deleteSelectedRooms] Calling deleteMultipleRooms...');
                        final success = await _roomService.deleteMultipleRooms(_selectedRoomIds.toList());
                        print('🗑️ [_deleteSelectedRooms] deleteMultipleRooms returned success=$success');
                        
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.pop(dialogContext);
                          if (mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Đã xoá $count phòng thành công')),
                            );
                            _clearSelection();
                          }
                        } else {
                          print('⚠️ [_deleteSelectedRooms] canPop=false after delete');
                        }
                      } catch (e, stackTrace) {
                        print('❌ [_deleteSelectedRooms] Error: $e');
                        print('Stack trace: $stackTrace');
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
    print('ℹ️ [_showRoomInfoDialog] room=${room.id}, number=${room.roomNumber}');
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
            onPressed: () {
              print('ℹ️ [_showRoomInfoDialog] Close pressed');
              Navigator.pop(context);
            },
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
    print('🏗️ [_buildRoomList] _isLoading=$_isLoading, _errorMessage=$_errorMessage, rooms=${_cachedRooms?.length}');
    
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red[700]),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  print('🔄 [_buildRoomList] Retry pressed');
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

    if (_cachedRooms == null || _cachedRooms!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Chưa có phòng nào', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Nhấn nút + để thêm phòng mới', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }

    print('🏗️ [_buildRoomList] Rendering ListView with ${_cachedRooms!.length} items');
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _cachedRooms!.length,
      itemBuilder: (context, index) {
        final room = _cachedRooms![index];
        final isSelected = _selectedRoomIds.contains(room.id);
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isSelected ? Colors.blue.shade50 : null,
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
              print('🔥 RAW TAP FIRED');
              print('👆 [onTap] room=${room.id}, _isSelectionMode=$_isSelectionMode, _isNavigating=$_isNavigating');
              if (_isSelectionMode) {
                _toggleRoomSelection(room.id);
              } else {
                if (_isNavigating) {
                  print('👆 [onTap] Already navigating, ignoring tap');
                  return;
                }
                _isNavigating = true;
                print('👆 [onTap] PRE-PUSH — about to call Navigator.pushNamed');
                print('👆 [onTap] Route: /room-detail, args: room.id=${room.id}, room.number=${room.roomNumber}');
                
                final sw = Stopwatch()..start();
                // ------------------NAVIGATE TO ROOM DETAIL-----------------
                Navigator.pushNamed(
                  context,
                  '/room-detail',
                  arguments: {'room': room, 'organization': widget.organization},
                ).then((_) {
                  print('👆 [onTap] POST-PUSH resolved — total=${sw.elapsedMilliseconds}ms');
                  _isNavigating = false;
                }).catchError((e, st) {
                  print('❌ [onTap] pushNamed threw: $e');
                  print('Stack trace: $st');
                  _isNavigating = false;
                });
                
                // This prints immediately after push is REGISTERED (sync), before the route builds
                print('👆 [onTap] POST-PUSH sync done — elapsed=${sw.elapsedMilliseconds}ms');
                // ⚠️ If the line above never prints, Navigator.pushNamed itself is blocking
                // ⚠️ If it prints but [onTap] POST-PUSH resolved never appears, the route screen hangs on build/init
              }
            },
            onLongPress: () {
              print('👆 [onLongPress] room=${room.id}');
              _toggleRoomSelection(room.id);
            },
            trailing: _isSelectionMode ? null : PopupMenuButton<String>(
              onSelected: (value) {
                print('📋 [PopupMenu] Selected "$value" for room=${room.id}');
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
                  child: Row(children: [Icon(Icons.info_outline, size: 20), SizedBox(width: 8), Text('Chi tiết')]),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 8), Text('Chỉnh sửa')]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Xoá', style: TextStyle(color: Colors.red))]),
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
    print('🏗️ [build] called — _isLoading=$_isLoading, rooms=${_cachedRooms?.length}, _isSelectionMode=$_isSelectionMode');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        print('🏗️ [LayoutBuilder] constraints=${constraints.maxWidth}x${constraints.maxHeight}');
        
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          print('⚠️ [LayoutBuilder] Below minimum size, showing warning widget');
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
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'Chọn tất cả',
                ),
                if (_selectedRoomIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: _deleteSelectedRooms,
                    tooltip: 'Xoá đã chọn',
                  ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.checklist_rtl),
                  onPressed: () {
                    print('☑️ [AppBar] Entering selection mode');
                    setState(() => _isSelectionMode = true);
                  },
                  tooltip: 'Chọn nhiều phòng',
                ),
              ]
            ],
          ),
          floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
            onPressed: () {
              print('➕ [FAB] Add room pressed');
              _showRoomDialog();
            },
            child: const Icon(Icons.add),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
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
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
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
                          child: Text(widget.building.address, style: const TextStyle(color: Colors.grey)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tổng số phòng: ${_cachedRooms?.length ?? 0}',
                      style: TextStyle(fontSize: 14, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildRoomList()),
            ],
          ),
        );
      }
    );
  }
}