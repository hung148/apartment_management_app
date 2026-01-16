import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/screens/organizations/tenant_tab.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OrganizationScreen extends StatefulWidget {

  const OrganizationScreen({
    super.key,
  });

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  final OrganizationService _orgService = OrganizationService();
  final AuthService _authService = AuthService();
  final BuildingService _buildingService = BuildingService();
  final TenantService _tenantService = TenantService();
  final PaymentService _paymentService = PaymentService();
  final RoomService _roomService = RoomService();
  
  late Organization _organization;
  String? _selectedBuildingId; // For occupancy trend chart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _organization =
        ModalRoute.of(context)!.settings.arguments as Organization;
  }

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? inviteCode;
  bool loadingInvite = false;

  String? get _userId => _authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);

    return _orgService.getUserMembership(
      _userId!,
      _organization.id,
    );
  }

  Future<List<Membership>> _getMembers() {
    return _orgService.getOrganizationMembers(_organization.id);
  }

  Future<List<Building>> _getBuildings() {
    return _buildingService.getOrganizationBuildings(_organization.id);
  }

  Future<List<Tenant>> _getAllTenants() {
    return _tenantService.getOrganizationTenants(_organization.id);
  }

  Future<List<Payment>> _getAllPayments() {
    return _paymentService.getOrganizationPayments(_organization.id);
  }

  Future<List<Room>> _getAllRooms() {
    return _roomService.getOrganizationRooms(_organization.id);
  }

  Future<void> _loadInviteCode() async {
    if (_userId == null) return;

    setState(() => loadingInvite = true);

    final code = await _orgService.getInviteCode(
      _userId!,
      _organization.id,
    );

    setState(() {
      inviteCode = code;
      loadingInvite = false;
    });
  }

  // ========================================
  // BUILDING DIALOGS
  // ========================================
  Future<void> _showAddBuildingDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final floorsController = TextEditingController();
    final roomsPerFloorController = TextEditingController();
    final roomPrefixController = TextEditingController();
    
    bool autoGenerateRooms = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: AlertDialog(
                title: const Text('Thêm Toà Nhà'),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Building Name
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên toà nhà *',
                            hintText: 'vd: Toà A',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),  // Grey 400
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Address
                        TextField(
                          controller: addressController,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ *',
                            hintText: 'vd: 123 Đường ABC',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),  // Grey 400
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 24),
                        
                        // Auto-generate rooms toggle
                        CheckboxListTile(
                          title: const Text('Tự động tạo phòng'),
                          subtitle: const Text('Tạo phòng tự động khi thêm toà nhà'),
                          value: autoGenerateRooms,
                          onChanged: (value) {
                            setDialogState(() {
                              autoGenerateRooms = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        if (autoGenerateRooms) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          
                          // Room Configuration Section
                          const Text(
                            'Cấu hình phòng',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Number of floors
                          TextField(
                            controller: floorsController,
                            decoration: const InputDecoration(
                              labelText: 'Số tầng *',
                              hintText: '1',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),  // Grey 400
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'Số tầng trong toà nhà',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Rooms per floor
                          TextField(
                            controller: roomsPerFloorController,
                            decoration: const InputDecoration(
                              labelText: 'Số phòng mỗi tầng *',
                              hintText: '10',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),  // Grey 400
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'Số phòng trên mỗi tầng',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Room number prefix
                          TextField(
                            controller: roomPrefixController,
                            decoration: const InputDecoration(
                              labelText: 'Tiền tố số phòng (tùy chọn)',
                              hintText: 'A',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),  // Grey 400
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'VD: "A" sẽ tạo phòng A101, A102, ...',
                            ),
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Preview
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Ví dụ số phòng:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _generateRoomPreview(
                                    roomPrefixController.text,
                                    floorsController.text,
                                    roomsPerFloorController.text,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tổng số phòng: ${_calculateTotalRooms(floorsController.text, roomsPerFloorController.text)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Validate required fields
                      if (nameController.text.trim().isEmpty ||
                          addressController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vui lòng điền đầy đủ thông tin bắt buộc'),
                          ),
                        );
                        return;
                      }

                      // Validate room configuration if auto-generate is enabled
                      if (autoGenerateRooms) {
                        final floors = int.tryParse(floorsController.text.trim());
                        final roomsPerFloor = int.tryParse(roomsPerFloorController.text.trim());
                        
                        if (floors == null || floors <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Số tầng không hợp lệ'),
                            ),
                          );
                          return;
                        }
                        
                        if (roomsPerFloor == null || roomsPerFloor <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Số phòng mỗi tầng không hợp lệ'),
                            ),
                          );
                          return;
                        }
                      }

                      Navigator.of(context).pop({
                        'name': nameController.text.trim(),
                        'address': addressController.text.trim(),
                        'autoGenerateRooms': autoGenerateRooms,
                        'floors': autoGenerateRooms ? int.parse(floorsController.text.trim()) : 0,
                        'roomsPerFloor': autoGenerateRooms ? int.parse(roomsPerFloorController.text.trim()) : 0,
                        'roomPrefix': autoGenerateRooms ? roomPrefixController.text.trim() : '',
                      });
                    },
                    child: const Text('Thêm'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != null && mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Create building
        final building = Building(
          id: '',
          organizationId: _organization.id,
          name: result['name']!,
          address: result['address']!,
          createdAt: DateTime.now(),
        );

        final buildingId = await _buildingService.addBuilding(building);

        if (buildingId != null) {
          // Generate and add rooms if enabled
          if (result['autoGenerateRooms'] == true) {
            final rooms = await _roomService.generateRoomsForBuilding(
              organizationId: _organization.id,
              buildingId: buildingId,
              numberOfFloors: result['floors']!,
              roomsPerFloor: result['roomsPerFloor']!,
              prefix: result['roomPrefix']!,
            );

            await _roomService.addMultipleRooms(rooms);
          }

          // Close loading dialog
          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['autoGenerateRooms'] == true
                      ? 'Thêm toà nhà và ${result['floors']! * result['roomsPerFloor']!} phòng thành công'
                      : 'Thêm toà nhà thành công',
                ),
              ),
            );
            setState(() {}); // Refresh the list
          }
        } else {
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể thêm toà nhà')),
            );
          }
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e')),
          );
        }
      }
    }
  }

  // Add these helper methods after _showAddBuildingDialog:

  // Helper method to generate room number preview
  String _generateRoomPreview(String prefix, String floorsText, String roomsPerFloorText) {
    final floors = int.tryParse(floorsText);
    final roomsPerFloor = int.tryParse(roomsPerFloorText);
    
    if (floors == null || floors <= 0 || roomsPerFloor == null || roomsPerFloor <= 0) {
      return 'Nhập số tầng và số phòng hợp lệ';
    }
    
    final examples = <String>[];
    
    // Show first 3 rooms on first floor
    for (int i = 1; i <= 3 && i <= roomsPerFloor; i++) {
      examples.add('$prefix${1}${i.toString().padLeft(2, '0')}');
    }
    
    if (roomsPerFloor > 3) {
      examples.add('...');
    }
    
    // Show last room on first floor
    if (roomsPerFloor > 1) {
      examples.add('$prefix${1}${roomsPerFloor.toString().padLeft(2, '0')}');
    }
    
    // Show first room on last floor if multiple floors
    if (floors > 1) {
      examples.add('...');
      examples.add('$prefix$floors${1.toString().padLeft(2, '0')}');
    }
    
    return examples.join(', ');
  }

  // Helper method to calculate total rooms
  String _calculateTotalRooms(String floorsText, String roomsPerFloorText) {
    final floors = int.tryParse(floorsText);
    final roomsPerFloor = int.tryParse(roomsPerFloorText);
    
    if (floors == null || floors <= 0 || roomsPerFloor == null || roomsPerFloor <= 0) {
      return '0';
    }
    
    return '${floors * roomsPerFloor}';
  }

  Future<void> _showEditBuildingDialog(Building building) async {
    final nameController = TextEditingController(text: building.name);
    final addressController = TextEditingController(text: building.address);
    final floorsController = TextEditingController();
    final roomsPerFloorController = TextEditingController();
    final roomPrefixController = TextEditingController();
    
    bool autoGenerateRooms = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: AlertDialog(
                title: const Text('Chỉnh Sửa Toà Nhà'),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Building Name
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên toà nhà *',
                            hintText: 'vd: Toà A',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Address
                        TextField(
                          controller: addressController,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ *',
                            hintText: 'vd: 123 Đường ABC',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 24),
                        
                        // Auto-generate rooms toggle
                        CheckboxListTile(
                          title: const Text('Thêm phòng mới'),
                          subtitle: const Text('Tạo thêm phòng cho toà nhà này'),
                          value: autoGenerateRooms,
                          onChanged: (value) {
                            setDialogState(() {
                              autoGenerateRooms = value ?? false;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        if (autoGenerateRooms) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          
                          // Room Configuration Section
                          const Text(
                            'Cấu hình phòng',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Number of floors
                          TextField(
                            controller: floorsController,
                            decoration: const InputDecoration(
                              labelText: 'Số tầng *',
                              hintText: '1',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'Số tầng trong toà nhà',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Rooms per floor
                          TextField(
                            controller: roomsPerFloorController,
                            decoration: const InputDecoration(
                              labelText: 'Số phòng mỗi tầng *',
                              hintText: '10',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'Số phòng trên mỗi tầng',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Room number prefix
                          TextField(
                            controller: roomPrefixController,
                            decoration: const InputDecoration(
                              labelText: 'Tiền tố số phòng (tùy chọn)',
                              hintText: 'A',
                              hintStyle: TextStyle(
                                color: Color(0xFFBDBDBD),
                                fontStyle: FontStyle.italic,
                              ),
                              helperText: 'VD: "A" sẽ tạo phòng A101, A102, ...',
                            ),
                            onChanged: (value) {
                              setDialogState(() {}); // Update preview
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Preview
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Ví dụ số phòng:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _generateRoomPreview(
                                    roomPrefixController.text,
                                    floorsController.text,
                                    roomsPerFloorController.text,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tổng số phòng: ${_calculateTotalRooms(floorsController.text, roomsPerFloorController.text)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Validate required fields
                      if (nameController.text.trim().isEmpty ||
                          addressController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vui lòng điền đầy đủ thông tin bắt buộc'),
                          ),
                        );
                        return;
                      }

                      // Validate room configuration if auto-generate is enabled
                      if (autoGenerateRooms) {
                        final floors = int.tryParse(floorsController.text.trim());
                        final roomsPerFloor = int.tryParse(roomsPerFloorController.text.trim());
                        
                        if (floors == null || floors <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Số tầng không hợp lệ'),
                            ),
                          );
                          return;
                        }
                        
                        if (roomsPerFloor == null || roomsPerFloor <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Số phòng mỗi tầng không hợp lệ'),
                            ),
                          );
                          return;
                        }
                      }

                      Navigator.of(context).pop({
                        'name': nameController.text.trim(),
                        'address': addressController.text.trim(),
                        'autoGenerateRooms': autoGenerateRooms,
                        'floors': autoGenerateRooms ? int.parse(floorsController.text.trim()) : 0,
                        'roomsPerFloor': autoGenerateRooms ? int.parse(roomsPerFloorController.text.trim()) : 0,
                        'roomPrefix': autoGenerateRooms ? roomPrefixController.text.trim() : '',
                      });
                    },
                    child: const Text('Cập nhật'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != null && mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Update building basic info
        final success = await _buildingService.updateBuilding(
          building.id,
          {
            'name': result['name'],
            'address': result['address'],
          },
        );

        if (success) {
          // Generate and add rooms if enabled
          if (result['autoGenerateRooms'] == true) {
            final rooms = await _roomService.generateRoomsForBuilding(
              organizationId: _organization.id,
              buildingId: building.id,
              numberOfFloors: result['floors']!,
              roomsPerFloor: result['roomsPerFloor']!,
              prefix: result['roomPrefix']!,
            );

            await _roomService.addMultipleRooms(rooms);
          }

          // Close loading dialog
          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['autoGenerateRooms'] == true
                      ? 'Cập nhật toà nhà và thêm ${result['floors']! * result['roomsPerFloor']!} phòng thành công'
                      : 'Cập nhật toà nhà thành công',
                ),
              ),
            );
            setState(() {}); // Refresh the list
          }
        } else {
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể cập nhật toà nhà')),
            );
          }
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteBuilding(Building building) async {
    // First, check how many tenants will be affected
    final tenants = await _tenantService.getBuildingTenants(building.id);
    final activeTenants = tenants.where((t) => 
      t.status == TenantStatus.active || 
      t.status == TenantStatus.inactive || 
      t.status == TenantStatus.suspended
    ).toList();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
          ),
          child: AlertDialog(
            title: const Text('Xóa Toà Nhà'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bạn có chắc muốn xóa "${building.name}"?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Thao tác này sẽ:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Xóa tất cả phòng trong toà nhà'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (activeTenants.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.person_off_outlined, size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đánh dấu ${activeTenants.length} người thuê là "Đã chuyển đi"',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Thông tin người thuê sẽ được lưu giữ để tham khảo',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Xóa'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final result = await _buildingService.deleteBuildingWithRoomsAndTenants(building.id);
        
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();

        if (result['rooms']! > 0 || result['tenants']! > 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Đã xóa toà nhà\n'
                  '• ${result['rooms']} phòng đã bị xóa\n'
                  '• ${result['tenants']} người thuê đã được đánh dấu "Đã chuyển đi"',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
            setState(() {}); // Refresh the list
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể xóa toà nhà')),
            );
          }
        }
      } catch (e) {
        // Close loading dialog if still open
        if (mounted) Navigator.of(context).pop();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e')),
          );
        }
      }
    }
  }

  // ========================================
  // FORMAT HELPERS
  // ========================================
  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} ₫';
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:
        return Colors.green;
      case TenantStatus.inactive:
        return Colors.orange;
      case TenantStatus.moveOut:
        return Colors.red;
      case TenantStatus.suspended:
        return Colors.grey;
    }
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.purple;
      case PaymentStatus.partial:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_organization.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate if tabs will fit
                // Rough estimate: each tab needs about 120 pixels
                const estimatedTabWidth = 120.0;
                const numberOfTabs = 5;
                final totalEstimatedWidth = estimatedTabWidth * numberOfTabs;
                final shouldScroll = constraints.maxWidth < totalEstimatedWidth;

                return TabBar(
                  isScrollable: shouldScroll,
                  labelStyle: const TextStyle(fontSize: 12),
                  tabs: const [
                    Tab(icon: Icon(Icons.apartment), text: 'Toà nhà'),
                    Tab(icon: Icon(Icons.people), text: 'Người thuê'),
                    Tab(icon: Icon(Icons.receipt_long), text: 'Hóa đơn'),
                    Tab(icon: Icon(Icons.bar_chart), text: 'Thống kê'),
                    Tab(icon: Icon(Icons.group), text: 'Thành viên'),
                  ],
                );
              },
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildBuildingsTab(),
              TenantsTab(
              organization: _organization,
              tenantService: _tenantService,
              buildingService: _buildingService,
              roomService: _roomService,
              organizationService: _orgService,
              authService: _authService, // use your field name
            ),
            _buildPaymentsTab(),
            _buildStatisticsTab(),
            _buildMembersTab(),
          ],
        ),
      ),
    );
  }

  // ========================================
  // BUILDINGS TAB
  // ========================================
  Widget _buildBuildingsTab() {
    return FutureBuilder<Membership?>(
      future: _getMyMembership(),
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';

        return Column(
          children: [
            // Add Building Button (Admin Only)
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddBuildingDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm toà nhà'),
                  ),
                ),
              ),

            // Buildings List
            Expanded(
              child: FutureBuilder<List<Building>>(
                future: _getBuildings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.apartment, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Không tìm thấy toà nhà nào',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  final buildings = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: buildings.length,
                    itemBuilder: (context, index) {
                      final building = buildings[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(Icons.apartment, color: Colors.white),
                          ),
                          title: Text(
                            building.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(building.address),
                              const SizedBox(height: 4),
                              Text(
                                'Tạo lúc ${_formatDate(building.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: isAdmin
                              ? Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          items: [
                                            const PopupMenuItem(
                                              value: 'rooms',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.meeting_room, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Quản lý phòng'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Chỉnh sửa'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
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
                                        ).then((value) {
                                          if (value == 'edit') {
                                            _showEditBuildingDialog(building);
                                          } else if (value == 'delete') {
                                            _deleteBuilding(building);
                                          } else if (value == 'rooms') {
                                            Navigator.pushNamed(
                                              context,
                                              '/building-rooms',
                                              arguments: building,
                                            );
                                          }
                                        });
                                      },
                                    );
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/building-rooms',
                                      arguments: building,
                                    );
                                  },
                                ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/building-rooms',
                              arguments: building,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // PAYMENTS TAB
  // ========================================
  Widget _buildPaymentsTab() {
    return FutureBuilder<List<Payment>>(
      future: _getAllPayments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Chưa có hóa đơn nào',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

        final payments = snapshot.data!;
        
        // Sort by date (newest first)
        payments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: payments.length,
          itemBuilder: (context, index) {
            final payment = payments[index];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getPaymentStatusColor(payment.status).withOpacity(0.2),
                  child: Icon(
                    payment.status == PaymentStatus.paid 
                        ? Icons.check_circle
                        : payment.isOverdue
                            ? Icons.warning
                            : Icons.pending,
                    color: _getPaymentStatusColor(payment.status),
                  ),
                ),
                title: Text(
                  payment.getTypeDisplayName(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Người thuê: ${payment.tenantName}'),
                    const SizedBox(height: 2),
                    Text('Số tiền: ${_formatCurrency(payment.totalAmount)}'),
                    const SizedBox(height: 2),
                    Text('Hạn: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getPaymentStatusColor(payment.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        payment.getStatusDisplayName(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _getPaymentStatusColor(payment.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ========================================
  // STATISTICS TAB
  // ========================================
  Widget _buildStatisticsTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _getAllTenants(),
        _getAllPayments(),
        _getBuildings(),
        _getAllRooms(), // Fetch real room data
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('Không có dữ liệu'));
        }

        final tenants = snapshot.data![0] as List<Tenant>;
        final payments = snapshot.data![1] as List<Payment>;
        final buildings = snapshot.data![2] as List<Building>;
        final rooms = snapshot.data![3] as List<Room>;

        // Calculate statistics
        final totalTenants = tenants.length;
        final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
        
        final totalPayments = payments.length;
        final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).length;
        final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).length;
        final overduePayments = payments.where((p) => p.isOverdue).length;
        
        final totalRevenue = payments
            .where((p) => p.status == PaymentStatus.paid)
            .fold<double>(0, (sum, p) => sum + p.paidAmount);
        
        final pendingRevenue = payments
            .where((p) => p.status == PaymentStatus.pending)
            .fold<double>(0, (sum, p) => sum + p.remainingAmount);

        // Calculate monthly revenue for chart
        final monthlyRevenue = _calculateMonthlyRevenue(payments);
        
        // Calculate building occupancy with real room data
        final buildingOccupancy = _calculateBuildingOccupancy(buildings, rooms, tenants);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tổng quan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Buildings & Tenants
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Toà nhà',
                      buildings.length.toString(),
                      Icons.apartment,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Người thuê',
                      '$activeTenants',
                      Icons.people,
                      Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Payments Overview
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Đã thanh toán',
                      paidPayments.toString(),
                      Icons.check_circle,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Chưa thanh toán',
                      pendingPayments.toString(),
                      Icons.pending,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Quá hạn',
                      overduePayments.toString(),
                      Icons.warning,
                      Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Tổng hóa đơn',
                      totalPayments.toString(),
                      Icons.receipt_long,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              const Text(
                'Doanh thu',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Revenue Cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.attach_money, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Đã thu',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatCurrency(totalRevenue),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Chưa thu',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatCurrency(pendingRevenue),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Monthly Revenue Chart
              const SizedBox(height: 24),
              const Text(
                'Doanh thu theo tháng',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildMonthlyRevenueChart(monthlyRevenue),
              
              // Building Occupancy Chart
              const SizedBox(height: 24),
              const Text(
                'Tỷ lệ lấp đầy theo toà nhà hiện tại',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildBuildingOccupancyChart(buildingOccupancy),
              
              // Monthly Occupancy Trend Chart
              const SizedBox(height: 24),
              const Text(
                'Xu hướng lấp đầy theo tháng',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildMonthlyOccupancyTrendChart(buildings, rooms, tenants),
            ],
          ),
        );
      },
    );
  }

  Map<String, double> _calculateMonthlyRevenue(List<Payment> payments) {
    final Map<String, double> monthlyRevenue = {};
    final now = DateTime.now();
    
    // Get last 6 months
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MM/yyyy').format(month);
      monthlyRevenue[monthKey] = 0;
    }
    
    // Calculate revenue for each month
    for (var payment in payments.where((p) => p.status == PaymentStatus.paid)) {
      if (payment.paidAt != null) {
        final monthKey = DateFormat('MM/yyyy').format(payment.paidAt!);
        if (monthlyRevenue.containsKey(monthKey)) {
          monthlyRevenue[monthKey] = (monthlyRevenue[monthKey] ?? 0) + payment.paidAmount;
        }
      }
    }
    
    return monthlyRevenue;
  }

  Map<String, Map<String, dynamic>> _calculateBuildingOccupancy(
    List<Building> buildings,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    final Map<String, Map<String, dynamic>> occupancy = {};
    
    for (var building in buildings) {
      // Count actual rooms in this building
      final totalRooms = rooms.where((r) => r.buildingId == building.id).length;
      
      // Count rooms with active tenants (occupied rooms)
      final occupiedRooms = rooms
          .where((r) => r.buildingId == building.id)
          .where((room) {
            // Check if this room has any active tenants
            return tenants.any((t) => 
              t.roomId == room.id && 
              t.status == TenantStatus.active
            );
          })
          .length;
      
      // Force double calculation by converting to double first
      final percentage = totalRooms > 0 
          ? (occupiedRooms.toDouble() / totalRooms.toDouble() * 100) 
          : 0.0;
      
      occupancy[building.name] = {
        'occupied': occupiedRooms,
        'total': totalRooms,
        'percentage': percentage,
      };
    }
    
    return occupancy;
  }

  Map<String, double> _calculateMonthlyOccupancyTrend(
    String buildingId,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    final Map<String, double> monthlyOccupancy = {};
    final now = DateTime.now();
    
    // Get rooms for this building
    final buildingRooms = rooms.where((r) => r.buildingId == buildingId).toList();
    final totalRooms = buildingRooms.length;
    
    if (totalRooms == 0) return monthlyOccupancy;
    
    // Calculate for last 12 months
    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MM/yyyy').format(month);
      
      // Count tenants who were active during this month
      final activeTenants = tenants.where((tenant) {
        // Check if tenant belongs to this building
        if (tenant.buildingId != buildingId) return false;
        
        // Tenant moved in before or during this month
        final movedInBeforeOrDuringMonth = tenant.moveInDate.isBefore(
          DateTime(month.year, month.month + 1, 1)
        );
        
        // Check if tenant was still active
        // (either no move out date, or moved out after this month started)
        final stillActiveInMonth = tenant.status == TenantStatus.active ||
            (tenant.moveInDate.year < month.year ||
             (tenant.moveInDate.year == month.year && tenant.moveInDate.month <= month.month));
        
        return movedInBeforeOrDuringMonth && stillActiveInMonth;
      }).length;
      
      final occupancyRate = (activeTenants.toDouble() / totalRooms.toDouble() * 100);
      monthlyOccupancy[monthKey] = occupancyRate;
    }
    
    return monthlyOccupancy;
  }

  Widget _buildMonthlyRevenueChart(Map<String, double> monthlyRevenue) {
    if (monthlyRevenue.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Chưa có dữ liệu doanh thu',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    final maxRevenue = monthlyRevenue.values.reduce((a, b) => a > b ? a : b);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chart
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: monthlyRevenue.entries.map((entry) {
                  final barHeight = maxRevenue > 0 
                      ? (entry.value / maxRevenue * 150).clamp(5.0, 150.0)
                      : 5.0;
                  
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrencyShort(entry.value),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.green.shade700,
                                  Colors.green.shade300,
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingOccupancyChart(Map<String, Map<String, dynamic>> occupancy) {
    if (occupancy.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Chưa có dữ liệu toà nhà',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: occupancy.entries.map((entry) {
            final buildingName = entry.key;
            final data = entry.value;
            final percentage = data['percentage'] as double;
            final occupied = data['occupied'] as int;
            final total = data['total'] as int;
            
            Color barColor;
            if (percentage >= 80) {
              barColor = Colors.green;
            } else if (percentage >= 50) {
              barColor = Colors.orange;
            } else {
              barColor = Colors.red;
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          buildingName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        '$occupied/$total (${percentage.toStringAsFixed(0)}%)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      color: barColor,
                      minHeight: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthlyOccupancyTrendChart(
    List<Building> buildings,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    if (buildings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Chưa có dữ liệu toà nhà',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    // Set default selected building if not set
    if (_selectedBuildingId == null && buildings.isNotEmpty) {
      _selectedBuildingId = buildings.first.id;
    }

    final selectedBuilding = buildings.firstWhere(
      (b) => b.id == _selectedBuildingId,
      orElse: () => buildings.first,
    );

    final monthlyOccupancy = _calculateMonthlyOccupancyTrend(
      selectedBuilding.id,
      rooms,
      tenants,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Building Selector
            Row(
              children: [
                const Text(
                  'Chọn toà nhà:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Chọn tòa nhà'),

                    // ✅ Value must exist in items or be null
                    value: buildings.any((b) => b.id == _selectedBuildingId)
                        ? _selectedBuildingId
                        : null,

                    items: buildings.map((building) {
                      return DropdownMenuItem<String>(
                        value: building.id,
                        child: Text(building.name),
                      );
                    }).toList(),

                    onChanged: (value) {
                      setState(() {
                        _selectedBuildingId = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Chart
            if (monthlyOccupancy.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    'Chưa có dữ liệu cho toà nhà này',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: Column(
                  children: [
                    // Y-axis label
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tỷ lệ lấp đầy (%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: monthlyOccupancy.entries.map((entry) {
                          final occupancyRate = entry.value;
                          final barHeight = (occupancyRate / 100 * 150).clamp(5.0, 150.0);
                          
                          Color barColor;
                          if (occupancyRate >= 80) {
                            barColor = Colors.green;
                          } else if (occupancyRate >= 50) {
                            barColor = Colors.orange;
                          } else {
                            barColor = Colors.red;
                          }
                          
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${occupancyRate.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.key.split('/')[0], // Show only month
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(1)}B';
    } else if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toStringAsFixed(0);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // MEMBERS TAB
  // ========================================
  Widget _buildMembersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ===== ADMIN ACTIONS =====
          FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();

              final membership = snapshot.data!;
              if (membership.role != 'admin') return const SizedBox();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton(
                    onPressed: loadingInvite ? null : _loadInviteCode,
                    child: const Text("Lấy mã mời"),
                  ),
                  if (inviteCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      "Mã mời: $inviteCode",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                ],
              );
            },
          ),

          /// ===== MEMBERS LIST =====
          const Text(
            "Thành viên",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: FutureBuilder<List<Membership>>(
              future: _getMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Không tìm thấy thành viên."));
                }

                final members = snapshot.data!;

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    
                    return FutureBuilder(
                      future: _authService.getOwnerData(member.ownerId),
                      builder: (context, ownerSnapshot) {
                        if (ownerSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: const Text('Đang tải...'),
                              subtitle: Text(member.role.toUpperCase()),
                            ),
                          );
                        }

                        final ownerName = ownerSnapshot.data?.name ??
                            ownerSnapshot.data?.email ??
                            member.ownerId;

                        final ownerEmail = ownerSnapshot.data?.email;
                        final roleText = member.role == 'admin' ? 'Quản trị viên' : 'Thành viên';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: member.role == 'admin'
                                  ? Colors.orange
                                  : Colors.blue,
                              child: Icon(
                                member.role == 'admin'
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              ownerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roleText,
                                  style: TextStyle(
                                    color: member.role == 'admin'
                                        ? Colors.orange
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (ownerEmail != null)
                                  Text(
                                    ownerEmail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: FutureBuilder<Membership?>(
                              future: _getMyMembership(),
                              builder: (context, myMembershipSnapshot) {
                                if (!myMembershipSnapshot.hasData) {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                final myMembership = myMembershipSnapshot.data!;
                                
                                if (myMembership.role != 'admin') {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                if (member.ownerId == myMembership.ownerId) {
                                  return const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  );
                                }
                                
                                return Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          items: [
                                            if (member.role == 'member')
                                              const PopupMenuItem(
                                                value: 'promote',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_upward, size: 20),
                                                    SizedBox(width: 8),
                                                    Text('Thăng cấp Admin'),
                                                  ],
                                                ),
                                              ),
                                            if (member.role == 'admin')
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.remove_circle, size: 20, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xóa khỏi tổ chức', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ).then((value) async {
                                          if (value == 'promote') {
                                            final success = await _orgService.promoteMemberToAdmin(
                                              currentAdminId: myMembership.ownerId,
                                              memberIdToPromote: member.ownerId,
                                              orgId: _organization.id,
                                            );
                                            if (success && mounted) {
                                              scaffoldMessenger.showSnackBar(
                                                const SnackBar(content: Text('Đã thăng cấp thành admin')),
                                              );
                                              setState(() {});
                                            }
                                          } else if (value == 'remove') {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Xác nhận xóa'),
                                                content: Text('Bạn có chắc muốn xóa $ownerName khỏi tổ chức?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, false),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, true),
                                                    child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            
                                            if (confirm == true) {
                                              final success = await _orgService.leaveOrganization(
                                                member.ownerId,
                                                _organization.id,
                                              );
                                              if (success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã xóa thành viên')),
                                                );
                                                setState(() {});
                                              }
                                            }
                                          }
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'hôm nay';
    } else if (difference.inDays == 1) {
      return 'hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks tuần trước';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months tháng trước';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years năm trước';
    }
  }
}