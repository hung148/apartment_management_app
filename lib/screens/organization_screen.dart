import 'dart:io';

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
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;


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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Chưa có hóa đơn nào',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _showAddPaymentDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm Hóa Đơn'),
                ),
              ],
            ),
          );
        }

        final allPayments = snapshot.data!;
        allPayments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search with ValueListenableBuilder (no reload on type)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, child) {
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Tìm kiếm hóa đơn...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: value.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _showAddPaymentDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Payments List
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, child) {
                    return _buildPaymentsList(allPayments, value.text);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentsList(List<Payment> allPayments, String searchText) {
    final searchTerm = searchText.toLowerCase();
    
    // Filter payments based on search term
    final filteredPayments = allPayments.where((payment) {
      if (searchTerm.isEmpty) return true;
      
      return (payment.tenantName?.toLowerCase() ?? '').contains(searchTerm) ||
             payment.totalAmount.toString().contains(searchTerm) ||
             payment.getTypeDisplayName().toLowerCase().contains(searchTerm);
    }).toList();

    if (filteredPayments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              searchTerm.isEmpty ? Icons.receipt_long_outlined : Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              searchTerm.isEmpty ? 'Chưa có hóa đơn nào' : 'Không tìm thấy hóa đơn',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (searchTerm.isNotEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Tìm thấy ${filteredPayments.length} hóa đơn',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildPaymentsListView(filteredPayments),
          ),
        ],
      );
    }

    return _buildPaymentsListView(filteredPayments);
  }

  Widget _buildPaymentsListView(List<Payment> payments) {
    return ListView.builder(
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
            trailing: Builder(
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
                          value: 'view',
                          child: Row(
                            children: [
                              Icon(Icons.visibility, size: 20),
                              SizedBox(width: 8),
                              Text('Xem Chi Tiết'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 20),
                              SizedBox(width: 8),
                              Text('Chỉnh Sửa'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 20, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Xóa', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ).then((value) {
                      if (value == 'view') {
                        _showPaymentDetailsDialog(payment);
                      } else if (value == 'edit') {
                        _showEditPaymentDialog(payment);
                      } else if (value == 'delete') {
                        _confirmDeletePayment(payment);
                      }
                    });
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showAddPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) => _PaymentFormDialog(
        organization: _organization,
        buildingService: _buildingService,
        roomService: _roomService,
        tenantService: _tenantService,
        paymentService: _paymentService,
      ),
    );
  }

  void _showPaymentDetailsDialog(Payment payment) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getPaymentStatusColor(payment.status).withOpacity(0.2),
                      child: Icon(
                        payment.status == PaymentStatus.paid
                            ? Icons.check_circle
                            : Icons.pending,
                        color: _getPaymentStatusColor(payment.status),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(payment.getTypeDisplayName()),
                          Text(
                            payment.getStatusDisplayName(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getPaymentStatusColor(payment.status),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPaymentDetailRow('Người Thuê', payment.tenantName ?? 'Chưa xác định'),
                        _buildPaymentDetailRow('Số Tiền', _formatCurrency(payment.amount)),
                        _buildPaymentDetailRow('Hạn Thanh Toán', DateFormat('dd/MM/yyyy').format(payment.dueDate)),
                        _buildPaymentDetailRow('Trạng Thái', payment.getStatusDisplayName()),
                        if (payment.paidAt != null)
                          _buildPaymentDetailRow('Ngày Thanh Toán', DateFormat('dd/MM/yyyy').format(payment.paidAt!)),
                        if (payment.notes != null && payment.notes!.isNotEmpty)
                          _buildPaymentDetailRow('Ghi Chú', payment.notes!),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditPaymentDialog(payment);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Chỉnh Sửa'),
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
  }

  void _showEditPaymentDialog(Payment payment) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final tenantNameController = TextEditingController(text: payment.tenantName ?? '');
    final amountController = TextEditingController(text: payment.amount.toString());
    final notesController = TextEditingController(text: payment.notes ?? '');
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.edit),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Chỉnh Sửa Hóa Đơn',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        tenantNameController.dispose();
                        amountController.dispose();
                        notesController.dispose();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: tenantNameController,
                          decoration: InputDecoration(
                            labelText: 'Tên Người Thuê',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: amountController,
                          decoration: InputDecoration(
                            labelText: 'Số Tiền',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixText: '₫ ',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: TextEditingController(
                            text: DateFormat('dd/MM/yyyy').format(payment.dueDate),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Hạn Thanh Toán',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<PaymentStatus>(
                          value: payment.status,
                          decoration: InputDecoration(
                            labelText: 'Trạng Thái',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: PaymentStatus.values.map((status) {
                            String label = '';
                            switch (status) {
                              case PaymentStatus.pending:
                                label = 'Chờ thanh toán';
                                break;
                              case PaymentStatus.paid:
                                label = 'Đã thanh toán';
                                break;
                              case PaymentStatus.overdue:
                                label = 'Quá hạn';
                                break;
                              case PaymentStatus.cancelled:
                                label = 'Đã hủy';
                                break;
                              case PaymentStatus.refunded:
                                label = 'Đã hoàn tiền';
                                break;
                              case PaymentStatus.partial:
                                label = 'Thanh toán một phần';
                                break;
                            }
                            return DropdownMenuItem(
                              value: status,
                              child: Text(label),
                            );
                          }).toList(),
                          onChanged: (value) {},
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: notesController,
                          decoration: InputDecoration(
                            labelText: 'Ghi Chú',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          tenantNameController.dispose();
                          amountController.dispose();
                          notesController.dispose();
                          Navigator.pop(context);
                        },
                        child: const Text('Hủy'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          tenantNameController.dispose();
                          amountController.dispose();
                          notesController.dispose();
                          Navigator.pop(context);
                        },
                        child: const Text('Lưu'),
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
  }

  void _confirmDeletePayment(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa Hóa Đơn'),
        content: Text('Bạn có chắc muốn xóa hóa đơn của ${payment.tenantName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
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
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_chart_outlined, size: 20),
                      label: const Text('Xuất Excel'),
                      onPressed: () => _exportStatisticsToExcel(
                        buildings: buildings, 
                        tenants: tenants, 
                        rooms: rooms, 
                        payments: payments,
                        organizationName: _organization.name,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      label: const Text('Xuất PDF'),
                      onPressed: () => _exportStatisticsToPdf(
                        buildings: buildings, 
                        tenants: tenants, 
                        rooms: rooms, 
                        payments: payments,
                        organizationName: _organization.name,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
// COMPLETE ENHANCED PDF EXPORT FUNCTION
// ===========================================================================
// Replace your existing _exportStatisticsToPdf function with this one
// (Should be around line 1126 in your organization_screen.dart)
// ===========================================================================

Future<void> _exportStatisticsToPdf({
  required List<Building> buildings,
  required List<Tenant> tenants,
  required List<Room> rooms,
  required List<Payment> payments,
  String? organizationName,
  bool showTotalsRow = true,
}) async {
  final ttf = await PdfFontService.getFont();
  
  // Show progress indicator
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  try {
    // ============================================
    // FORMATTERS
    // ============================================
    final currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final dateFormatter = DateFormat('dd/MM/yyyy – HH:mm');

    // ============================================
    // CALCULATE COMPREHENSIVE STATISTICS
    // ============================================
    
    // Overall stats
    final totalBuildings = buildings.length;
    final totalRooms = rooms.length;
    final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
    final inactiveTenants = tenants.where((t) => t.status == TenantStatus.inactive).length;
    final movedOutTenants = tenants.where((t) => t.status == TenantStatus.moveOut).length;
    final suspendedTenants = tenants.where((t) => t.status == TenantStatus.suspended).length;
    
    // Payment stats
    final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).toList();
    final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).toList();
    final overduePayments = payments.where((p) => p.isOverdue).toList();
    final cancelledPayments = payments.where((p) => p.status == PaymentStatus.cancelled).toList();
    
    final totalRevenue = paidPayments.fold<double>(0, (sum, p) => sum + p.paidAmount);
    final pendingRevenue = pendingPayments.fold<double>(0, (sum, p) => sum + p.remainingAmount);
    final overdueRevenue = overduePayments.fold<double>(0, (sum, p) => sum + p.remainingAmount);
    
    // Monthly revenue calculation
    final monthlyRevenue = _calculateMonthlyRevenue(payments);
    
    // Building-specific stats
    final Map<String, _BuildingStats> statsByBuilding = {};
    for (final b in buildings) {
      statsByBuilding[b.id] = _BuildingStats(
        buildingId: b.id,
        buildingName: b.name,
        totalRooms: 0,
        occupiedRooms: 0,
        revenue: 0.0,
      );
    }

    for (final r in rooms) {
      final s = statsByBuilding[r.buildingId];
      if (s != null) s.totalRooms += 1;
    }

    for (final t in tenants) {
      if (t.buildingId.isEmpty) continue;
      if (t.status == TenantStatus.active) {
        final s = statsByBuilding[t.buildingId];
        if (s != null) s.occupiedRooms += 1;
      }
    }

    for (final pmt in paidPayments) {
      if (pmt.buildingId != null && pmt.buildingId!.isNotEmpty) {
        final s = statsByBuilding[pmt.buildingId!];
        if (s != null) s.revenue += pmt.paidAmount;
      } else if (pmt.roomId != null && pmt.roomId!.isNotEmpty) {
        final room = rooms.firstWhere(
          (r) => r.id == pmt.roomId, 
          orElse: () => Room(id: '', organizationId: '', buildingId: '', roomNumber: '', createdAt: DateTime.now())
        );
        if (room.id.isNotEmpty) {
          final s = statsByBuilding[room.buildingId];
          if (s != null) s.revenue += pmt.paidAmount;
        }
      }
    }

    // Build building table rows
    final List<List<String>> buildingTableRows = [];
    int grandTotalRooms = 0;
    int grandOccupied = 0;
    double grandRevenue = 0.0;

    for (final s in statsByBuilding.values) {
      final emptyRooms = (s.totalRooms - s.occupiedRooms).clamp(0, s.totalRooms);
      final occupancyRate = s.totalRooms > 0 
          ? ((s.occupiedRooms / s.totalRooms) * 100).toStringAsFixed(1) 
          : '0.0';
      
      buildingTableRows.add([
        s.buildingName,
        s.totalRooms.toString(),
        s.occupiedRooms.toString(),
        emptyRooms.toString(),
        '$occupancyRate%',
        currencyFormatter.format(s.revenue),
      ]);

      grandTotalRooms += s.totalRooms;
      grandOccupied += s.occupiedRooms;
      grandRevenue += s.revenue;
    }

    buildingTableRows.sort((a, b) => a[0].compareTo(b[0]));

    // ============================================
    // PDF SETUP
    // ============================================
    final pdf = pw.Document();
    
    // Text styles
    final titleStyle = pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final heading1Style = pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold);
    final heading2Style = pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold);
    final baseTextStyle = pw.TextStyle(font: ttf, fontSize: 10);
    final smallTextStyle = pw.TextStyle(font: ttf, fontSize: 9);
    final smallGrey = pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.grey600);
    final boldTextStyle = pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold);

    // Helper function to create stat boxes
    pw.Widget buildStatBox(String label, String value, {PdfColor color = PdfColors.blue}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: color.shade(0.1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: color, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      );
    }

    // ============================================
    // PAGE 1: EXECUTIVE SUMMARY
    // ============================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(organizationName ?? 'Tổ chức', style: titleStyle),
                      pw.SizedBox(height: 4),
                      pw.Text('BÁO CÁO THỐNG KÊ TỔNG QUAN', style: heading1Style),
                      pw.SizedBox(height: 4),
                      pw.Text('Ngày tạo: ${dateFormatter.format(DateTime.now())}', style: smallGrey),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 24),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 24),

              // Overview Section
              pw.Text('1. TỔNG QUAN', style: heading1Style),
              pw.SizedBox(height: 16),
              
              // Stats Grid Row 1
              pw.Row(
                children: [
                  pw.Expanded(child: buildStatBox('Toà nhà', totalBuildings.toString(), color: PdfColors.blue)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Tổng phòng', totalRooms.toString(), color: PdfColors.teal)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Đang thuê', activeTenants.toString(), color: PdfColors.green)),
                ],
              ),
              
              pw.SizedBox(height: 12),
              
              // Stats Grid Row 2
              pw.Row(
                children: [
                  pw.Expanded(child: buildStatBox('Tỷ lệ lấp đầy', totalRooms > 0 ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%' : '0%', color: PdfColors.purple)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Phòng trống', '${totalRooms - activeTenants}', color: PdfColors.orange)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Đã chuyển đi', movedOutTenants.toString(), color: PdfColors.grey)),
                ],
              ),

              pw.SizedBox(height: 24),

              // Tenant Status Breakdown
              pw.Text('2. TÌNH TRẠNG NGƯỜI THUÊ', style: heading1Style),
              pw.SizedBox(height: 12),
              
              pw.TableHelper.fromTextArray(
                headers: ['Trạng thái', 'Số lượng', 'Tỷ lệ'],
                data: [
                  ['Đang hoạt động', activeTenants.toString(), tenants.isNotEmpty ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Không hoạt động', inactiveTenants.toString(), tenants.isNotEmpty ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Đã chuyển đi', movedOutTenants.toString(), tenants.isNotEmpty ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Bị đình chỉ', suspendedTenants.toString(), tenants.isNotEmpty ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['TỔNG', tenants.length.toString(), '100%'],
                ],
                headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: PdfColors.blue50),
                cellStyle: baseTextStyle,
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                },
                border: pw.TableBorder.all(color: PdfColors.grey300),
              ),

              pw.SizedBox(height: 24),

              // Payment Summary
              pw.Text('3. TỔNG KẾT THANH TOÁN', style: heading1Style),
              pw.SizedBox(height: 12),
              
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.green, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Đã thu', style: heading2Style.copyWith(color: PdfColors.green)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(totalRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                          pw.SizedBox(height: 4),
                          pw.Text('${paidPayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.orange50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.orange, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Chưa thu', style: heading2Style.copyWith(color: PdfColors.orange)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(pendingRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                          pw.SizedBox(height: 4),
                          pw.Text('${pendingPayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 12),
              
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.red, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Quá hạn', style: heading2Style.copyWith(color: PdfColors.red)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(overdueRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                          pw.SizedBox(height: 4),
                          pw.Text('${overduePayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.grey, width: 1),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Đã hủy', style: heading2Style.copyWith(color: PdfColors.grey)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text('${cancelledPayments.length}', 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.grey)),
                          pw.SizedBox(height: 4),
                          pw.Text('hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                  pw.Text('Trang 1', style: smallGrey),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ============================================
    // PAGE 2: BUILDING DETAILS
    // ============================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CHI TIẾT THEO TÒA NHÀ', style: heading1Style),
                  pw.Text('Trang 2', style: smallGrey),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),

              // Building Table
              if (buildingTableRows.isEmpty)
                pw.Center(
                  child: pw.Text('Không có dữ liệu toà nhà', 
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                )
              else ...[
                pw.Table.fromTextArray(
                  headers: ['Toà nhà', 'Tổng phòng', 'Đang thuê', 'Trống', 'Tỷ lệ', 'Doanh thu'],
                  data: buildingTableRows,
                  headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                  headerDecoration: pw.BoxDecoration(color: PdfColors.blue50),
                  cellStyle: baseTextStyle,
                  cellAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.5),
                    5: const pw.FlexColumnWidth(2.5),
                  },
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  cellPadding: const pw.EdgeInsets.all(8),
                ),
                
                pw.SizedBox(height: 16),
                
                // Totals
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Tổng số toà nhà: ${statsByBuilding.length}', style: boldTextStyle),
                          pw.Text('Tổng phòng: $grandTotalRooms', style: boldTextStyle),
                          pw.Text('Tổng đang thuê: $grandOccupied', style: boldTextStyle),
                          pw.Text('Tổng doanh thu: ${currencyFormatter.format(grandRevenue)}', 
                            style: pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                  pw.Text('Trang 2', style: smallGrey),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ============================================
    // PAGE 3: REVENUE ANALYSIS
    // ============================================
    if (monthlyRevenue.isNotEmpty) {
      // Validate that we have valid revenue data
      final validRevenues = monthlyRevenue.values.where((v) => v.isFinite && !v.isNaN).toList();
      
      if (validRevenues.isNotEmpty) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(40),
            build: (context) {
              final maxRevenue = validRevenues.reduce((a, b) => a > b ? a : b);
              final safeMaxRevenue = maxRevenue > 0 ? maxRevenue : 1.0; // Ensure non-zero
              
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PHÂN TÍCH DOANH THU', style: heading1Style),
                      pw.Text('Trang 3', style: smallGrey),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 2),
                  pw.SizedBox(height: 20),

                  // Monthly Revenue Chart
                  pw.Text('Doanh thu 6 tháng gần nhất', style: heading2Style),
                  pw.SizedBox(height: 16),
                  
                  pw.Container(
                    height: 250,
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Chart(
                      grid: pw.CartesianGrid(
                        xAxis: pw.FixedAxis.fromStrings(
                          monthlyRevenue.keys.toList(),
                          marginStart: 30,
                          marginEnd: 30,
                          ticks: true,
                          textStyle: smallTextStyle,
                        ),
                        yAxis: pw.FixedAxis(
                          [0, safeMaxRevenue / 2, safeMaxRevenue],
                          format: (v) {
                            final doubleValue = v.toDouble();
                            return doubleValue.isFinite && !doubleValue.isNaN 
                                ? _formatCurrencyShort(doubleValue) 
                                : '0';
                          },
                          divisions: true,
                          textStyle: smallTextStyle,
                        ),
                      ),
                      datasets: [
                        pw.BarDataSet(
                          color: PdfColors.green,
                          legend: 'Doanh thu',
                          width: 20,
                          data: monthlyRevenue.entries.map((e) {
                            final value = e.value.isFinite && !e.value.isNaN ? e.value : 0.0;
                            return pw.PointChartValue(0, value);
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 24),

                  // Revenue Table
                  pw.Text('Chi tiết doanh thu theo tháng', style: heading2Style),
                  pw.SizedBox(height: 12),
                  
                  pw.TableHelper.fromTextArray(
                    headers: ['Tháng', 'Doanh thu', 'Tỷ lệ'],
                    data: monthlyRevenue.entries.map((e) {
                      final revenueValue = e.value.isFinite && !e.value.isNaN ? e.value : 0.0;
                      final percentage = totalRevenue > 0 
                          ? ((revenueValue / totalRevenue) * 100).toStringAsFixed(1) 
                          : '0.0';
                      return [
                        e.key,
                        currencyFormatter.format(revenueValue),
                        '$percentage%',
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                    headerDecoration: pw.BoxDecoration(color: PdfColors.green50),
                    cellStyle: baseTextStyle,
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(2),
                    },
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                  ),

                  pw.Spacer(),

                  // Footer
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                      pw.Text('Trang 3', style: smallGrey),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      }
    }

    // ============================================
    // SAVE AND PRESENT PDF
    // ============================================
    final pdfBytes = await pdf.save();

    // Close progress dialog
    if (mounted) Navigator.of(context).pop();

    // Platform-specific behavior
    if (Platform.isWindows) {
      final file = await getSaveLocation(
        suggestedName: 'statistics_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );

      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hủy xuất PDF'))
          );
        }
        return;
      }

      final path = file.path;
      await File(path).writeAsBytes(pdfBytes);
      await Process.run('explorer', [path]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu PDF: ${p.basename(path)}'))
        );
      }
    } else {
      // Non-Windows: use printing package
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdfBytes);
    }
  } catch (e) {
    // Close progress dialog if still open
    if (mounted) Navigator.of(context).pop();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xuất PDF: $e'))
      );
    }
  }
}

  // ===========================================================================
  // EXCEL EXPORT FUNCTION
  // ===========================================================================
  Future<void> _exportStatisticsToExcel({
    required List<Building> buildings,
    required List<Tenant> tenants,
    required List<Room> rooms,
    required List<Payment> payments,
    String? organizationName,
    bool showTotalsRow = true,
  }) async {
    // Show progress indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // ============================================
      // FORMATTERS
      // ============================================
      final currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
      final dateFormatter = DateFormat('dd/MM/yyyy – HH:mm');

      // ============================================
      // CALCULATE COMPREHENSIVE STATISTICS
      // ============================================
      
      // Overall stats
      final totalBuildings = buildings.length;
      final totalRooms = rooms.length;
      final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
      final inactiveTenants = tenants.where((t) => t.status == TenantStatus.inactive).length;
      final movedOutTenants = tenants.where((t) => t.status == TenantStatus.moveOut).length;
      final suspendedTenants = tenants.where((t) => t.status == TenantStatus.suspended).length;
      
      // Payment stats
      final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).toList();
      final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).toList();
      final overduePayments = payments.where((p) => p.isOverdue).toList();
      final cancelledPayments = payments.where((p) => p.status == PaymentStatus.cancelled).toList();
      
      final totalRevenue = paidPayments.fold<double>(0, (sum, p) => sum + p.paidAmount);
      final pendingRevenue = pendingPayments.fold<double>(0, (sum, p) => sum + p.remainingAmount);
      final overdueRevenue = overduePayments.fold<double>(0, (sum, p) => sum + p.remainingAmount);
      
      // Building-specific stats
      final Map<String, _BuildingStats> statsByBuilding = {};
      for (final b in buildings) {
        statsByBuilding[b.id] = _BuildingStats(
          buildingId: b.id,
          buildingName: b.name,
          totalRooms: 0,
          occupiedRooms: 0,
          revenue: 0.0,
        );
      }

      for (final r in rooms) {
        final s = statsByBuilding[r.buildingId];
        if (s != null) s.totalRooms += 1;
      }

      for (final t in tenants) {
        if (t.buildingId.isEmpty) continue;
        if (t.status == TenantStatus.active) {
          final s = statsByBuilding[t.buildingId];
          if (s != null) s.occupiedRooms += 1;
        }
      }

      for (final pmt in paidPayments) {
        if (pmt.buildingId != null && pmt.buildingId!.isNotEmpty) {
          final s = statsByBuilding[pmt.buildingId!];
          if (s != null) s.revenue += pmt.paidAmount;
        } else if (pmt.roomId != null && pmt.roomId!.isNotEmpty) {
          final room = rooms.firstWhere(
            (r) => r.id == pmt.roomId, 
            orElse: () => Room(id: '', organizationId: '', buildingId: '', roomNumber: '', createdAt: DateTime.now())
          );
          if (room.id.isNotEmpty) {
            final s = statsByBuilding[room.buildingId];
            if (s != null) s.revenue += pmt.paidAmount;
          }
        }
      }

      // Build building table rows
      final List<List<dynamic>> buildingTableRows = [];
      int grandTotalRooms = 0;
      int grandOccupied = 0;
      double grandRevenue = 0.0;

      for (final s in statsByBuilding.values) {
        final emptyRooms = (s.totalRooms - s.occupiedRooms).clamp(0, s.totalRooms);
        final occupancyRate = s.totalRooms > 0 
            ? ((s.occupiedRooms / s.totalRooms) * 100).toStringAsFixed(1) 
            : '0.0';
        
        buildingTableRows.add([
          s.buildingName,
          s.totalRooms,
          s.occupiedRooms,
          emptyRooms,
          '$occupancyRate%',
          s.revenue,
        ]);

        grandTotalRooms += s.totalRooms;
        grandOccupied += s.occupiedRooms;
        grandRevenue += s.revenue;
      }

      buildingTableRows.sort((a, b) => a[0].toString().compareTo(b[0].toString()));

      // ============================================
      // CREATE EXCEL WORKBOOK
      // ============================================
      var excel = Excel.createExcel();
      
      // Remove default sheet
      excel.delete('Sheet1');

      // ============================================
      // SHEET 1: EXECUTIVE SUMMARY
      // ============================================
      var summarySheet = excel['Tổng Quan'];
      
      int row = -1;
      
      // Title and Header
      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var titleCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      titleCell.value = TextCellValue(organizationName ?? 'Tổ chức');
      titleCell.cellStyle = CellStyle(bold: true, fontSize: 16);

      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var headerCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      headerCell.value = TextCellValue('BÁO CÁO THỐNG KÊ TỔNG QUAN');
      headerCell.cellStyle = CellStyle(bold: true, fontSize: 14);

      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var dateCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      dateCell.value = TextCellValue('Ngày tạo: ${dateFormatter.format(DateTime.now())}');
      dateCell.cellStyle = CellStyle(italic: true);
      row += 2;

      // Section 1: Overall Statistics
      var sectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      sectionCell.value = TextCellValue('1. TỔNG QUAN');
      sectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      // Create stat cards data
      final statsData = [
        ['Toà nhà', totalBuildings, 'Tổng phòng', totalRooms],
        ['Đang thuê', activeTenants, 'Tỷ lệ lấp đầy', totalRooms > 0 ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Phòng trống', totalRooms - activeTenants, 'Đã chuyển đi', movedOutTenants],
      ];

      for (var statRow in statsData) {
        var cell1 = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
        cell1.value = TextCellValue(statRow[0].toString());
        cell1.cellStyle = CellStyle(bold: true);
        
        var cell2 = summarySheet.cell(CellIndex.indexByString('B${row + 1}'));
        cell2.value = TextCellValue(statRow[1].toString());
        
        var cell3 = summarySheet.cell(CellIndex.indexByString('C${row + 1}'));
        cell3.value = TextCellValue(statRow[2].toString());
        cell3.cellStyle = CellStyle(bold: true);
        
        var cell4 = summarySheet.cell(CellIndex.indexByString('D${row + 1}'));
        cell4.value = TextCellValue(statRow[3].toString());
        
        row++;
      }

      row += 2;

      // Section 2: Tenant Status
      var tenantSectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      tenantSectionCell.value = TextCellValue('2. TÌNH TRẠNG NGƯỜI THUÊ');
      tenantSectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      // Tenant status headers
      final tenantHeaders = ['Trạng thái', 'Số lượng', 'Tỷ lệ'];
      for (int i = 0; i < tenantHeaders.length; i++) {
        var cell = summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(tenantHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FF0099FF'));
      }
      row++;

      // Tenant status data
      final tenantStatusData = [
        ['Đang hoạt động', activeTenants, tenants.isNotEmpty ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Không hoạt động', inactiveTenants, tenants.isNotEmpty ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Đã chuyển đi', movedOutTenants, tenants.isNotEmpty ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Bị đình chỉ', suspendedTenants, tenants.isNotEmpty ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['TỔNG', tenants.length, '100%'],
      ];

      for (var statusRow in tenantStatusData) {
        for (int i = 0; i < statusRow.length; i++) {
          var cell = summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
          cell.value = TextCellValue(statusRow[i].toString());
          if (statusRow[0] == 'TỔNG') {
            cell.cellStyle = CellStyle(bold: true);
          }
        }
        row++;
      }

      row += 2;

      // Section 3: Payment Summary
      var paymentSectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      paymentSectionCell.value = TextCellValue('3. TỔNG KẾT THANH TOÁN');
      paymentSectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      final paymentSummaryData = [
        ['Đã thu', currencyFormatter.format(totalRevenue), 'Số hóa đơn', paidPayments.length],
        ['Chưa thu', currencyFormatter.format(pendingRevenue), 'Số hóa đơn', pendingPayments.length],
        ['Quá hạn', currencyFormatter.format(overdueRevenue), 'Số hóa đơn', overduePayments.length],
        ['Đã hủy', cancelledPayments.length, 'Số hóa đơn', ''],
      ];

      for (var paymentRow in paymentSummaryData) {
        var cell1 = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
        cell1.value = TextCellValue(paymentRow[0].toString());
        cell1.cellStyle = CellStyle(bold: true);
        
        var cell2 = summarySheet.cell(CellIndex.indexByString('B${row + 1}'));
        cell2.value = TextCellValue(paymentRow[1].toString());
        
        var cell3 = summarySheet.cell(CellIndex.indexByString('C${row + 1}'));
        cell3.value = TextCellValue(paymentRow[2].toString());
        cell3.cellStyle = CellStyle(bold: true);
        
        var cell4 = summarySheet.cell(CellIndex.indexByString('D${row + 1}'));
        cell4.value = TextCellValue(paymentRow[3].toString());
        
        row++;
      }

      // ============================================
      // SHEET 2: BUILDING DETAILS
      // ============================================
      var buildingSheet = excel['Chi Tiết Tòa Nhà'];
      
      row = -1;
      
      // Header
      row++;
      var buildingTitleCell = buildingSheet.cell(CellIndex.indexByString('A${row + 1}'));
      buildingTitleCell.value = TextCellValue('CHI TIẾT THEO TÒA NHÀ');
      buildingTitleCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      row += 2;

      // Building table headers
      final buildingHeaders = ['Toà nhà', 'Tổng phòng', 'Đang thuê', 'Trống', 'Tỷ lệ', 'Doanh thu'];
      for (int i = 0; i < buildingHeaders.length; i++) {
        var cell = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(buildingHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FF0099FF'));
      }
      row++;

      // Building table data
      for (var buildingRow in buildingTableRows) {
        var cell0 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        cell0.value = TextCellValue(buildingRow[0].toString());
        
        var cell1 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        cell1.value = IntCellValue(buildingRow[1] as int);
        
        var cell2 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
        cell2.value = IntCellValue(buildingRow[2] as int);
        
        var cell3 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        cell3.value = IntCellValue(buildingRow[3] as int);
        
        var cell4 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
        cell4.value = TextCellValue(buildingRow[4].toString());
        
        var cell5 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
        cell5.value = DoubleCellValue(buildingRow[5] as double);
        
        row++;
      }

      // Totals row
      row++;
      var totalLabelCell = buildingSheet.cell(CellIndex.indexByString('A${row + 1}'));
      totalLabelCell.value = TextCellValue('TỔNG CỘNG');
      totalLabelCell.cellStyle = CellStyle(bold: true);

      var totalRoomsCell = buildingSheet.cell(CellIndex.indexByString('B${row + 1}'));
      totalRoomsCell.value = IntCellValue(grandTotalRooms);
      totalRoomsCell.cellStyle = CellStyle(bold: true);

      var totalOccupiedCell = buildingSheet.cell(CellIndex.indexByString('C${row + 1}'));
      totalOccupiedCell.value = IntCellValue(grandOccupied);
      totalOccupiedCell.cellStyle = CellStyle(bold: true);

      var totalEmptyCell = buildingSheet.cell(CellIndex.indexByString('D${row + 1}'));
      totalEmptyCell.value = IntCellValue(grandTotalRooms - grandOccupied);
      totalEmptyCell.cellStyle = CellStyle(bold: true);

      var totalRevenueCell = buildingSheet.cell(CellIndex.indexByString('F${row + 1}'));
      totalRevenueCell.value = DoubleCellValue(grandRevenue);
      totalRevenueCell.cellStyle = CellStyle(bold: true);

      // ============================================
      // SHEET 3: DETAILED PAYMENTS
      // ============================================
      var paymentsSheet = excel['Thanh Toán Chi Tiết'];
      
      row = -1;
      
      row++;
      var paymentsTitleCell = paymentsSheet.cell(CellIndex.indexByString('A${row + 1}'));
      paymentsTitleCell.value = TextCellValue('DANH SÁCH THANH TOÁN CHI TIẾT');
      paymentsTitleCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      row += 2;

      // Payment table headers
      final paymentHeaders = ['Mã thanh toán', 'Số tiền', 'Trạng thái', 'Ngày thanh toán', 'Ngày quá hạn', 'Ghi chú'];
      for (int i = 0; i < paymentHeaders.length; i++) {
        var cell = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(paymentHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FFFF9900'));
      }
      row++;

      // Payment data - sorted by date (newest first)
      final sortedPayments = List<Payment>.from(payments);
      sortedPayments.sort((a, b) {
        final dateA = a.createdAt ?? DateTime.now();
        final dateB = b.createdAt ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      for (var payment in sortedPayments) {
        var cell0 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        cell0.value = TextCellValue(payment.id);
        
        var cell1 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        cell1.value = DoubleCellValue(payment.totalAmount);
        
        var cell2 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
        final statusText = payment.status == PaymentStatus.paid ? 'Đã thanh toán' :
                          payment.status == PaymentStatus.pending ? 'Chưa thanh toán' :
                          payment.status == PaymentStatus.cancelled ? 'Đã hủy' : 'Khác';
        cell2.value = TextCellValue(statusText);
        
        var cell3 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        final paidDateText = payment.paidAt != null ? DateFormat('dd/MM/yyyy').format(payment.paidAt!) : '';
        cell3.value = TextCellValue(paidDateText);
        
        var cell4 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
        final dueDateText = payment.dueDate != null ? DateFormat('dd/MM/yyyy').format(payment.dueDate!) : '';
        cell4.value = TextCellValue(dueDateText);
        
        var cell5 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
        cell5.value = TextCellValue(payment.notes ?? '');
        
        row++;
      }

      // ============================================
      // AUTO-FIT COLUMNS FOR ALL SHEETS
      // ============================================
      // Set auto-fit column widths for all sheets
      for (var sheet in excel.sheets.keys) {
        var sheetObject = excel[sheet];
        
        // Get the maximum column index used in this sheet
        int maxCol = 0;
        for (var row in sheetObject.rows) {
          if (row.isNotEmpty) {
            maxCol = maxCol < row.length ? row.length : maxCol;
          }
        }
        
        // Set auto-fit width for each column
        for (int col = 0; col < maxCol; col++) {
          sheetObject.setColumnAutoFit(col);
        }
      }

      // ============================================
      // SAVE EXCEL FILE
      // ============================================
      final excelBytes = excel.encode();
      
      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Platform-specific behavior
      if (Platform.isWindows) {
        final file = await getSaveLocation(
          suggestedName: 'statistics_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          acceptedTypeGroups: [const XTypeGroup(label: 'Excel', extensions: ['xlsx'])],
        );

        if (file == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hủy xuất Excel'))
            );
          }
          return;
        }

        final path = file.path;
        await File(path).writeAsBytes(excelBytes!);
        await Process.run('explorer', [path]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu Excel: ${p.basename(path)}'))
          );
        }
      } else {
        // For other platforms, show a snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tệp Excel đã được tạo'))
          );
        }
      }
    } catch (e) {
      // Close progress dialog if still open
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất Excel: $e'))
        );
      }
    }
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

// ========================================
// PAYMENT FORM DIALOG
// ========================================
class _PaymentFormDialog extends StatefulWidget {
  final Organization organization;
  final BuildingService buildingService;
  final RoomService roomService;
  final TenantService tenantService;
  final PaymentService paymentService;

  const _PaymentFormDialog({
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
  });

  @override
  State<_PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends State<_PaymentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _paidAmountController;
  late TextEditingController _currencyController;
  late TextEditingController _transactionIdController;
  late TextEditingController _receiptNumberController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  late TextEditingController _lateFeeController;
  late TextEditingController _recurringParentIdController;

  String? _selectedBuildingId;
  String? _selectedRoomId;
  String? _selectedTenantId;
  String? _selectedTenantName;
  PaymentType? _selectedPaymentType;
  PaymentStatus? _selectedPaymentStatus;
  PaymentMethod? _selectedPaymentMethod;
  
  DateTime? _billingStartDate;
  DateTime? _billingEndDate;
  DateTime? _dueDate;
  DateTime? _paidAt;
  
  bool _isRecurring = false;

  List<Building> _buildings = [];
  List<Room> _rooms = [];
  List<Tenant> _tenants = [];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _paidAmountController = TextEditingController(text: '0.0');
    _currencyController = TextEditingController(text: 'VND');
    _transactionIdController = TextEditingController();
    _receiptNumberController = TextEditingController();
    _descriptionController = TextEditingController();
    _notesController = TextEditingController();
    _lateFeeController = TextEditingController(text: '0.0');
    _recurringParentIdController = TextEditingController();
    
    _selectedPaymentStatus = PaymentStatus.pending;
    _dueDate = DateTime.now().add(const Duration(days: 30));
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final buildings = await widget.buildingService.getOrganizationBuildings(widget.organization.id);
      final tenants = await widget.tenantService.getOrganizationTenants(widget.organization.id);
      
      setState(() {
        _buildings = buildings;
        _tenants = tenants;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  Future<void> _loadRooms() async {
    if (_selectedBuildingId == null) return;
    try {
      final rooms = await widget.roomService.getBuildingRooms(_selectedBuildingId!);
      setState(() {
        _rooms = rooms;
        _selectedRoomId = null; // Reset room selection
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading rooms: $e')),
      );
    }
  }

  Future<void> _selectDate(String dateType) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _getDueDate(dateType),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (picked != null) {
      setState(() {
        switch (dateType) {
          case 'billingStart':
            _billingStartDate = picked;
            break;
          case 'billingEnd':
            _billingEndDate = picked;
            break;
          case 'due':
            _dueDate = picked;
            break;
          case 'paid':
            _paidAt = picked;
            break;
        }
      });
    }
  }

  DateTime _getDueDate(String dateType) {
    switch (dateType) {
      case 'billingStart':
        return _billingStartDate ?? DateTime.now();
      case 'billingEnd':
        return _billingEndDate ?? DateTime.now();
      case 'due':
        return _dueDate ?? DateTime.now().add(const Duration(days: 30));
      case 'paid':
        return _paidAt ?? DateTime.now();
      default:
        return DateTime.now();
    }
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a building')),
      );
      return;
    }
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room')),
      );
      return;
    }
    if (_selectedPaymentType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment type')),
      );
      return;
    }
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a due date')),
      );
      return;
    }

    try {
      final payment = Payment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        organizationId: widget.organization.id,
        buildingId: _selectedBuildingId!,
        roomId: _selectedRoomId!,
        tenantId: _selectedTenantId,
        tenantName: _selectedTenantName ?? 'Unknown',
        type: _selectedPaymentType!,
        status: _selectedPaymentStatus ?? PaymentStatus.pending,
        amount: double.parse(_amountController.text),
        paidAmount: double.parse(_paidAmountController.text),
        currency: _currencyController.text,
        paymentMethod: _selectedPaymentMethod,
        transactionId: _transactionIdController.text.isEmpty ? null : _transactionIdController.text,
        receiptNumber: _receiptNumberController.text.isEmpty ? null : _receiptNumberController.text,
        billingStartDate: _billingStartDate,
        billingEndDate: _billingEndDate,
        dueDate: _dueDate!,
        createdAt: DateTime.now(),
        paidAt: _paidAt,
        paidBy: null, // Can be set to current user ID if needed
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        metadata: null, // Can be extended later
        lateFee: _lateFeeController.text.isEmpty ? null : double.parse(_lateFeeController.text),
        isRecurring: _isRecurring,
        recurringParentId: _recurringParentIdController.text.isEmpty ? null : _recurringParentIdController.text,
      );

      await widget.paymentService.addPayment(payment);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment created successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving payment: $e')),
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight,
            ),
            child: Column(
              children: [
                // Header (like AppBar)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Thêm Hóa Đơn',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Body
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: bodyConstraints.maxHeight,
                          ),
                            child: Form(
                              key: _formKey,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Building Selection
                                  DropdownButtonFormField<String>(
                                    value: _selectedBuildingId,
                                    decoration: InputDecoration(
                                      labelText: 'Toà nhà *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: _buildings.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                                    onChanged: (v) {
                                      setState(() => _selectedBuildingId = v);
                                      _loadRooms();
                                    },
                                    validator: (v) => v == null ? 'Chọn toà nhà' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Room Selection
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedRoomId,
                                    decoration: InputDecoration(
                                      labelText: 'Phòng *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: _rooms.map((r) => DropdownMenuItem(value: r.id, child: Text(r.roomNumber ?? ''))).toList(),
                                    onChanged: (v) => setState(() => _selectedRoomId = v),
                                    validator: (v) => v == null ? 'Chọn phòng' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Tenant Selection
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedTenantId,
                                    decoration: InputDecoration(
                                      labelText: 'Người thuê',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: [
                                      const DropdownMenuItem(value: null, child: Text('Không chọn')),
                                      ..._tenants.map((t) => DropdownMenuItem(value: t.id, child: Text(t.fullName ?? ''))).toList(),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        final tenant = _tenants.firstWhere((t) => t.id == v, orElse: () => _tenants.first);
                                        setState(() {
                                          _selectedTenantId = v;
                                          _selectedTenantName = tenant.fullName;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Payment Type
                                  DropdownButtonFormField<PaymentType>(
                                    initialValue: _selectedPaymentType,
                                    decoration: InputDecoration(
                                      labelText: 'Loại thanh toán *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: PaymentType.values.map((t) {
                                      const labels = {
                                        'rent': 'Tiền thuê',
                                        'electricity': 'Tiền điện',
                                        'water': 'Tiền nước',
                                        'internet': 'Tiền internet',
                                        'parking': 'Tiền gửi xe',
                                        'maintenance': 'Phí bảo trì',
                                        'deposit': 'Tiền cọc',
                                        'penalty': 'Tiền phạt',
                                        'other': 'Khác',
                                      };
                                      return DropdownMenuItem(value: t, child: Text(labels[t.toString().split('.')[1]] ?? ''));
                                    }).toList(),
                                    onChanged: (v) => setState(() => _selectedPaymentType = v),
                                    validator: (v) => v == null ? 'Chọn loại' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Amount
                                  TextFormField(
                                    controller: _amountController,
                                    decoration: InputDecoration(
                                      labelText: 'Số tiền *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      suffixText: 'VND',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => (v?.isEmpty ?? true) || double.tryParse(v ?? '') == null ? 'Nhập số tiền' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Due Date
                                  TextFormField(
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Hạn thanh toán *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.calendar_today),
                                        onPressed: () => _selectDate('due'),
                                      ),
                                    ),
                                    controller: TextEditingController(text: _dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : ''),
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Status
                                  DropdownButtonFormField<PaymentStatus>(
                                    value: _selectedPaymentStatus,
                                    decoration: InputDecoration(
                                      labelText: 'Trạng thái *',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: PaymentStatus.values.map((s) {
                                      const labels = {
                                        'pending': 'Chờ thanh toán',
                                        'paid': 'Đã thanh toán',
                                        'overdue': 'Quá hạn',
                                        'cancelled': 'Đã hủy',
                                        'refunded': 'Đã hoàn tiền',
                                        'partial': 'Thanh toán 1 phần',
                                      };
                                      return DropdownMenuItem(value: s, child: Text(labels[s.toString().split('.')[1]] ?? ''));
                                    }).toList(),
                                    onChanged: (v) => setState(() => _selectedPaymentStatus = v),
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Notes
                                  TextFormField(
                                    controller: _notesController,
                                    decoration: InputDecoration(
                                      labelText: 'Ghi chú',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    maxLines: 2,
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  // Action Buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Hủy'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _savePayment,
                                          child: const Text('Lưu'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Small helper class to aggregate building stats
class _BuildingStats {
  final String buildingId;
  final String buildingName;
  int totalRooms;
  int occupiedRooms;
  double revenue;

  _BuildingStats({
    required this.buildingId,
    required this.buildingName,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.revenue,
  });
}