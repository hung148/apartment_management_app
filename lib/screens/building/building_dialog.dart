import 'package:flutter/material.dart';

/// Enhanced dialog that allows different room counts per floor with bulk editing
class BuildingDialog extends StatefulWidget {
  final bool isEditMode;
  final String? initialName;
  final String? initialAddress;
  final int? initialFloors;
  final String? initialRoomPrefix;
  final bool? initialUniformRooms;
  final int? initialRoomsPerFloor;
  final List<int>? initialFloorRoomCounts;

  const BuildingDialog({
    super.key,
    this.isEditMode = false,
    this.initialName,
    this.initialAddress,
    this.initialFloors,
    this.initialRoomPrefix,
    this.initialUniformRooms,
    this.initialRoomsPerFloor,
    this.initialFloorRoomCounts,
  });

  @override
  State<BuildingDialog> createState() => _BuildingDialogState();
}

class _BuildingDialogState extends State<BuildingDialog> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController floorsController = TextEditingController();
  final TextEditingController roomPrefixController = TextEditingController();
  
  bool autoGenerateRooms = true;
  bool uniformRoomsPerFloor = true;
  
  // For uniform mode
  final TextEditingController uniformRoomsController = TextEditingController();
  
  // For custom mode
  List<FloorConfig> floorConfigs = [];
  
  // For bulk editing
  bool showBulkEdit = false;
  final TextEditingController bulkStartFloorController = TextEditingController();
  final TextEditingController bulkEndFloorController = TextEditingController();
  final TextEditingController bulkRoomsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Initialize basic fields
    if (widget.initialName != null) nameController.text = widget.initialName!;
    if (widget.initialAddress != null) addressController.text = widget.initialAddress!;
    
    // Initialize room configuration in edit mode
    if (widget.isEditMode) {
      // If building has saved room configuration, load it
      if (widget.initialFloors != null) {
        floorsController.text = widget.initialFloors.toString();
        
        if (widget.initialRoomPrefix != null && widget.initialRoomPrefix!.isNotEmpty) {
          roomPrefixController.text = widget.initialRoomPrefix!;
        }
        
        if (widget.initialUniformRooms != null) {
          uniformRoomsPerFloor = widget.initialUniformRooms!;
          
          if (uniformRoomsPerFloor && widget.initialRoomsPerFloor != null) {
            uniformRoomsController.text = widget.initialRoomsPerFloor.toString();
          } else if (!uniformRoomsPerFloor && widget.initialFloorRoomCounts != null) {
            // Initialize custom floor configs with existing data
            _initializeFloorConfigsWithData(widget.initialFloorRoomCounts!);
          }
        }
      }
      // For old buildings without saved config, autoGenerateRooms defaults to true
      // but fields remain empty for user to fill in if they want to add rooms
    }
  }

  void _initializeFloorConfigsWithData(List<int> roomCounts) {
    floorConfigs.clear();
    for (int i = 0; i < roomCounts.length; i++) {
      floorConfigs.add(FloorConfig(
        floorNumber: i + 1,
        controller: TextEditingController(text: roomCounts[i].toString()),
      ));
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    floorsController.dispose();
    roomPrefixController.dispose();
    uniformRoomsController.dispose();
    bulkStartFloorController.dispose();
    bulkEndFloorController.dispose();
    bulkRoomsController.dispose();
    for (var config in floorConfigs) {
      config.controller.dispose();
    }
    super.dispose();
  }

  bool _isSmallScreen(BuildContext context) => MediaQuery.of(context).size.width < 600;

  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.95;
    if (screenWidth < 1200) return 600;
    return 800;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    return EdgeInsets.all(_isSmallScreen(context) ? 12.0 : 16.0);
  }

  void _updateFloorConfigs() {
    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) {
      setState(() => floorConfigs = []);
      return;
    }

    setState(() {
      // Add or remove configs to match floor count
      while (floorConfigs.length < floors) {
        final floorNum = floorConfigs.length + 1;
        floorConfigs.add(FloorConfig(
          floorNumber: floorNum,
          controller: TextEditingController(text: '10'), // Default 10 rooms
        ));
      }
      while (floorConfigs.length > floors) {
        floorConfigs.removeLast().controller.dispose();
      }
    });
  }

  void _applyBulkEdit() {
    final startFloor = int.tryParse(bulkStartFloorController.text.trim());
    final endFloor = int.tryParse(bulkEndFloorController.text.trim());
    final rooms = int.tryParse(bulkRoomsController.text.trim());

    if (startFloor == null || endFloor == null || rooms == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin')),
      );
      return;
    }

    if (startFloor < 1 || endFloor > floorConfigs.length || startFloor > endFloor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Khoảng tầng không hợp lệ (1-${floorConfigs.length})'),
        ),
      );
      return;
    }

    if (rooms <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số phòng phải lớn hơn 0')),
      );
      return;
    }

    setState(() {
      for (int i = startFloor - 1; i < endFloor; i++) {
        floorConfigs[i].controller.text = rooms.toString();
      }
      showBulkEdit = false;
      bulkStartFloorController.clear();
      bulkEndFloorController.clear();
      bulkRoomsController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã cập nhật tầng $startFloor-$endFloor: $rooms phòng'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _generatePreview() {
    final prefix = roomPrefixController.text.trim();
    final floors = int.tryParse(floorsController.text.trim());
    
    if (floors == null || floors <= 0) {
      return 'Nhập số tầng hợp lệ';
    }

    if (uniformRoomsPerFloor) {
      final roomsPerFloor = int.tryParse(uniformRoomsController.text.trim());
      if (roomsPerFloor == null || roomsPerFloor <= 0) {
        return 'Nhập số phòng hợp lệ';
      }
      return _generateUniformPreview(prefix, floors, roomsPerFloor);
    } else {
      if (floorConfigs.isEmpty) {
        return 'Đang cấu hình...';
      }
      return _generateCustomPreview(prefix);
    }
  }

  String _generateUniformPreview(String prefix, int floors, int roomsPerFloor) {
    final examples = <String>[];
    
    for (int i = 1; i <= 3 && i <= roomsPerFloor; i++) {
      examples.add('$prefix${1}${i.toString().padLeft(2, '0')}');
    }
    
    if (roomsPerFloor > 3) examples.add('...');
    if (roomsPerFloor > 1) {
      examples.add('$prefix${1}${roomsPerFloor.toString().padLeft(2, '0')}');
    }
    
    if (floors > 1) {
      examples.add('...');
      examples.add('$prefix$floors${1.toString().padLeft(2, '0')}');
    }
    
    return examples.join(', ');
  }

  String _generateCustomPreview(String prefix) {
    final examples = <String>[];
    
    if (floorConfigs.isNotEmpty) {
      final firstFloorRooms = int.tryParse(floorConfigs[0].controller.text.trim()) ?? 0;
      if (firstFloorRooms > 0) {
        examples.add('$prefix${1}${1.toString().padLeft(2, '0')}');
        if (firstFloorRooms > 1) {
          examples.add('$prefix${1}${2.toString().padLeft(2, '0')}');
        }
        if (firstFloorRooms > 2) {
          examples.add('...');
          examples.add('$prefix${1}${firstFloorRooms.toString().padLeft(2, '0')}');
        }
      }
    }
    
    if (floorConfigs.length > 1) {
      examples.add('...');
      final lastFloor = floorConfigs.last;
      final lastFloorRooms = int.tryParse(lastFloor.controller.text.trim()) ?? 0;
      if (lastFloorRooms > 0) {
        examples.add('$prefix${lastFloor.floorNumber}${1.toString().padLeft(2, '0')}');
      }
    }
    
    return examples.isNotEmpty ? examples.join(', ') : 'Cấu hình số phòng cho từng tầng';
  }

  int _calculateTotalRooms() {
    if (uniformRoomsPerFloor) {
      final floors = int.tryParse(floorsController.text.trim()) ?? 0;
      final roomsPerFloor = int.tryParse(uniformRoomsController.text.trim()) ?? 0;
      return floors * roomsPerFloor;
    } else {
      return floorConfigs.fold<int>(0, (sum, config) {
        final rooms = int.tryParse(config.controller.text.trim()) ?? 0;
        return sum + rooms;
      });
    }
  }

  Map<String, dynamic>? _validateAndGetResult() {
    if (nameController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng điền đầy đủ thông tin bắt buộc'),
        ),
      );
      return null;
    }

    if (!autoGenerateRooms) {
      return {
        'name': nameController.text.trim(),
        'address': addressController.text.trim(),
        'autoGenerateRooms': false,
      };
    }

    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số tầng không hợp lệ')),
      );
      return null;
    }

    if (uniformRoomsPerFloor) {
      final roomsPerFloor = int.tryParse(uniformRoomsController.text.trim());
      if (roomsPerFloor == null || roomsPerFloor <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Số phòng mỗi tầng không hợp lệ')),
        );
        return null;
      }

      return {
        'name': nameController.text.trim(),
        'address': addressController.text.trim(),
        'autoGenerateRooms': true,
        'uniformRooms': true,
        'floors': floors,
        'roomsPerFloor': roomsPerFloor,
        'roomPrefix': roomPrefixController.text.trim(),
      };
    } else {
      final floorRoomCounts = <int>[];
      for (var config in floorConfigs) {
        final rooms = int.tryParse(config.controller.text.trim());
        if (rooms == null || rooms <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Số phòng tầng ${config.floorNumber} không hợp lệ')),
          );
          return null;
        }
        floorRoomCounts.add(rooms);
      }

      return {
        'name': nameController.text.trim(),
        'address': addressController.text.trim(),
        'autoGenerateRooms': true,
        'uniformRooms': false,
        'floors': floors,
        'floorRoomCounts': floorRoomCounts,
        'roomPrefix': roomPrefixController.text.trim(),
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = _isSmallScreen(context);
    final padding = _getResponsivePadding(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _getDialogWidth(context),
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: padding,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEditMode ? 'Chỉnh Sửa Toà Nhà' : 'Thêm Toà Nhà',
                      style: TextStyle(
                        fontSize: isSmall ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: isSmall ? 40 : 48,
                      minHeight: isSmall ? 40 : 48,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Building Name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên toà nhà *',
                        hintText: 'vd: Toà A',
                        hintStyle: const TextStyle(
                          color: Color(0xFFBDBDBD),
                          fontStyle: FontStyle.italic,
                        ),
                        labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                      ),
                      style: TextStyle(fontSize: isSmall ? 13 : 14),
                    ),
                    SizedBox(height: isSmall ? 12 : 16),

                    // Address
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: 'Địa chỉ *',
                        hintText: 'vd: 123 Đường ABC',
                        hintStyle: const TextStyle(
                          color: Color(0xFFBDBDBD),
                          fontStyle: FontStyle.italic,
                        ),
                        labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                      ),
                      style: TextStyle(fontSize: isSmall ? 13 : 14),
                      maxLines: 2,
                    ),
                    SizedBox(height: isSmall ? 16 : 24),

                    // Auto-generate toggle
                    CheckboxListTile(
                      title: Text(
                        widget.isEditMode ? 'Thêm phòng mới' : 'Tự động tạo phòng',
                        style: TextStyle(fontSize: isSmall ? 13 : 14),
                      ),
                      subtitle: Text(
                        widget.isEditMode
                            ? 'Tạo thêm phòng cho toà nhà này'
                            : 'Tạo phòng tự động khi thêm toà nhà',
                        style: TextStyle(fontSize: isSmall ? 12 : 13),
                      ),
                      value: autoGenerateRooms,
                      onChanged: (value) {
                        setState(() {
                          autoGenerateRooms = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),

                    if (autoGenerateRooms) ...[
                      SizedBox(height: isSmall ? 12 : 16),
                      const Divider(),
                      SizedBox(height: isSmall ? 12 : 16),

                      // Room Configuration Section
                      Text(
                        'Cấu hình phòng',
                        style: TextStyle(
                          fontSize: isSmall ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isSmall ? 12 : 16),

                      // Number of floors
                      TextField(
                        controller: floorsController,
                        decoration: InputDecoration(
                          labelText: 'Số tầng *',
                          hintText: '1',
                          hintStyle: const TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontStyle: FontStyle.italic,
                          ),
                          helperText: 'Số tầng trong toà nhà',
                          labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                          helperStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                        ),
                        style: TextStyle(fontSize: isSmall ? 13 : 14),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          if (!uniformRoomsPerFloor) {
                            _updateFloorConfigs();
                          }
                          setState(() {});
                        },
                      ),
                      SizedBox(height: isSmall ? 12 : 16),

                      // Room distribution toggle
                      Container(
                        padding: EdgeInsets.all(isSmall ? 10 : 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phân bổ phòng',
                              style: TextStyle(
                                fontSize: isSmall ? 12 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        uniformRoomsPerFloor = true;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Radio<bool>(
                                            value: true,
                                            groupValue: uniformRoomsPerFloor,
                                            onChanged: (value) {
                                              setState(() {
                                                uniformRoomsPerFloor = value!;
                                              });
                                            },
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Đồng đều',
                                                  style: TextStyle(fontSize: isSmall ? 12 : 13),
                                                ),
                                                Text(
                                                  'Số phòng giống nhau mỗi tầng',
                                                  style: TextStyle(
                                                    fontSize: isSmall ? 10 : 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        uniformRoomsPerFloor = false;
                                        _updateFloorConfigs();
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Radio<bool>(
                                            value: false,
                                            groupValue: uniformRoomsPerFloor,
                                            onChanged: (value) {
                                              setState(() {
                                                uniformRoomsPerFloor = value!;
                                                if (!uniformRoomsPerFloor) {
                                                  _updateFloorConfigs();
                                                }
                                              });
                                            },
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Tùy chỉnh',
                                                  style: TextStyle(fontSize: isSmall ? 12 : 13),
                                                ),
                                                Text(
                                                  'Số phòng khác nhau mỗi tầng',
                                                  style: TextStyle(
                                                    fontSize: isSmall ? 10 : 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isSmall ? 12 : 16),

                      // Uniform rooms per floor
                      if (uniformRoomsPerFloor) ...[
                        TextField(
                          controller: uniformRoomsController,
                          decoration: InputDecoration(
                            labelText: 'Số phòng mỗi tầng *',
                            hintText: '10',
                            hintStyle: const TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                            helperText: 'Số phòng trên mỗi tầng',
                            labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                            helperStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                          ),
                          style: TextStyle(fontSize: isSmall ? 13 : 14),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => setState(() {}),
                        ),
                      ],

                      // Custom rooms per floor with bulk edit
                      if (!uniformRoomsPerFloor && floorConfigs.isNotEmpty) ...[
                        // Bulk edit button
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Cấu hình từng tầng',
                                style: TextStyle(
                                  fontSize: isSmall ? 12 : 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  showBulkEdit = !showBulkEdit;
                                });
                              },
                              icon: Icon(
                                showBulkEdit ? Icons.close : Icons.edit_note,
                                size: isSmall ? 16 : 18,
                              ),
                              label: Text(
                                showBulkEdit ? 'Đóng' : 'Chỉnh hàng loạt',
                                style: TextStyle(fontSize: isSmall ? 11 : 12),
                              ),
                            ),
                          ],
                        ),
                        
                        // Bulk edit panel
                        if (showBulkEdit) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Áp dụng số phòng cho nhiều tầng cùng lúc',
                                  style: TextStyle(
                                    fontSize: isSmall ? 11 : 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: bulkStartFloorController,
                                        decoration: InputDecoration(
                                          labelText: 'Từ tầng',
                                          hintText: '1',
                                          labelStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          border: const OutlineInputBorder(),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: TextStyle(fontSize: isSmall ? 12 : 13),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: bulkEndFloorController,
                                        decoration: InputDecoration(
                                          labelText: 'Đến tầng',
                                          hintText: floorConfigs.length.toString(),
                                          labelStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          border: const OutlineInputBorder(),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: TextStyle(fontSize: isSmall ? 12 : 13),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: bulkRoomsController,
                                        decoration: InputDecoration(
                                          labelText: 'Số phòng',
                                          hintText: '10',
                                          labelStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          border: const OutlineInputBorder(),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: TextStyle(fontSize: isSmall ? 12 : 13),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _applyBulkEdit,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: Text(
                                      'Áp dụng',
                                      style: TextStyle(fontSize: isSmall ? 11 : 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Floor list
                        Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: floorConfigs.length,
                            itemBuilder: (context, index) {
                              final config = floorConfigs[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextField(
                                  controller: config.controller,
                                  decoration: InputDecoration(
                                    labelText: 'Tầng ${config.floorNumber} - Số phòng *',
                                    hintText: '10',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFFBDBDBD),
                                      fontStyle: FontStyle.italic,
                                    ),
                                    labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                                    prefixIcon: Icon(
                                      Icons.layers,
                                      size: isSmall ? 18 : 20,
                                    ),
                                  ),
                                  style: TextStyle(fontSize: isSmall ? 13 : 14),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) => setState(() {}),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      SizedBox(height: isSmall ? 12 : 16),

                      // Room prefix
                      TextField(
                        controller: roomPrefixController,
                        decoration: InputDecoration(
                          labelText: 'Tiền tố số phòng (tùy chọn)',
                          hintText: 'A',
                          hintStyle: const TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontStyle: FontStyle.italic,
                          ),
                          helperText: 'VD: "A" sẽ tạo phòng A101, A102, ...',
                          labelStyle: TextStyle(fontSize: isSmall ? 13 : 14),
                          helperStyle: TextStyle(fontSize: isSmall ? 11 : 12),
                        ),
                        style: TextStyle(fontSize: isSmall ? 13 : 14),
                        onChanged: (value) => setState(() {}),
                      ),
                      SizedBox(height: isSmall ? 12 : 16),

                      // Preview
                      Container(
                        padding: EdgeInsets.all(isSmall ? 10 : 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: isSmall ? 14 : 16,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Ví dụ số phòng:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSmall ? 11 : 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _generatePreview(),
                              style: TextStyle(
                                fontSize: isSmall ? 11 : 12,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tổng số phòng: ${_calculateTotalRooms()}',
                              style: TextStyle(
                                fontSize: isSmall ? 11 : 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: isSmall ? 12 : 16),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: EdgeInsets.all(isSmall ? 8.0 : 12.0),
              child: isSmall
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: () {
                              final result = _validateAndGetResult();
                              if (result != null) {
                                Navigator.of(context).pop(result);
                              }
                            },
                            child: Text(widget.isEditMode ? 'Cập nhật' : 'Thêm'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            final result = _validateAndGetResult();
                            if (result != null) {
                              Navigator.of(context).pop(result);
                            }
                          },
                          child: Text(widget.isEditMode ? 'Cập nhật' : 'Thêm'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FloorConfig {
  final int floorNumber;
  final TextEditingController controller;

  FloorConfig({
    required this.floorNumber,
    required this.controller,
  });
}