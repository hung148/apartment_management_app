import 'package:flutter/material.dart';

/// Enhanced dialog that allows different room counts per floor
class BuildingDialog extends StatefulWidget {
  final bool isEditMode;
  final String? initialName;
  final String? initialAddress;

  const BuildingDialog({
    super.key,
    this.isEditMode = false,
    this.initialName,
    this.initialAddress,
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
  bool uniformRoomsPerFloor = true; // New: toggle between uniform and custom
  
  // For uniform mode
  final TextEditingController uniformRoomsController = TextEditingController();
  
  // For custom mode
  List<FloorConfig> floorConfigs = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) nameController.text = widget.initialName!;
    if (widget.initialAddress != null) addressController.text = widget.initialAddress!;
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    floorsController.dispose();
    roomPrefixController.dispose();
    uniformRoomsController.dispose();
    for (var config in floorConfigs) {
      config.controller.dispose();
    }
    super.dispose();
  }

  // Helper methods moved inside the state class
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
    
    // Show first 3 rooms on first floor
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
    
    // Show first floor examples
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
    
    // Show last floor example
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
    // Validate required fields
    if (nameController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng điền đầy đủ thông tin bắt buộc'),
        ),
      );
      return null;
    }

    // If not auto-generating, return basic info
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
      // Validate all floor configs
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

                      // Custom rooms per floor
                      if (!uniformRoomsPerFloor && floorConfigs.isNotEmpty) ...[
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