import 'package:flutter/material.dart';

class BuildingDialog extends StatefulWidget {
  final bool isEditMode;
  final String? initialName;
  final String? initialAddress;
  final int? initialFloors;
  final String? initialRoomPrefix;
  final bool? initialUniformRooms;
  final int? initialRoomsPerFloor;
  final String? initialRoomType;
  final double? initialRoomArea;
  
  final List<Map<String, dynamic>>? initialFloorDetails;
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
    this.initialRoomType,
    this.initialRoomArea,
    this.initialFloorDetails,
    this.initialFloorRoomCounts,
  });

  @override
  State<BuildingDialog> createState() => _BuildingDialogState();
}

class _BuildingDialogState extends State<BuildingDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController floorsController = TextEditingController();
  final TextEditingController roomPrefixController = TextEditingController();
  
  bool autoGenerateRooms = true;
  bool uniformRoomsPerFloor = true;
  
  final TextEditingController uniformRoomsController = TextEditingController();
  final TextEditingController uniformTypeController = TextEditingController(text: 'Tiêu chuẩn');
  final TextEditingController uniformAreaController = TextEditingController();
  
  List<FloorConfig> floorConfigs = [];
  
  bool showBulkEdit = false;
  final TextEditingController bulkStartFloorController = TextEditingController();
  final TextEditingController bulkEndFloorController = TextEditingController();
  final TextEditingController bulkRoomsController = TextEditingController();
  final TextEditingController bulkTypeController = TextEditingController(text: 'Tiêu chuẩn');
  final TextEditingController bulkAreaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    if (widget.initialName != null) nameController.text = widget.initialName!;
    if (widget.initialAddress != null) addressController.text = widget.initialAddress!;
    
    if (widget.isEditMode && widget.initialFloors != null) {
      floorsController.text = widget.initialFloors.toString();
      roomPrefixController.text = widget.initialRoomPrefix ?? '';
      uniformRoomsPerFloor = widget.initialUniformRooms ?? true;
      
      if (uniformRoomsPerFloor) {
        uniformRoomsController.text = widget.initialRoomsPerFloor?.toString() ?? '';
        uniformTypeController.text = widget.initialRoomType ?? 'Tiêu chuẩn';
        uniformAreaController.text = widget.initialRoomArea?.toString() ?? '';
      } else {
        if (widget.initialFloorDetails != null) {
          _loadFloorConfigs(widget.initialFloorDetails!);
        } else if (widget.initialFloorRoomCounts != null) {
          floorConfigs = widget.initialFloorRoomCounts!.asMap().entries.map((entry) {
            return FloorConfig(
              floorNumber: entry.key + 1,
              countController: TextEditingController(text: entry.value.toString()),
              typeController: TextEditingController(text: 'Tiêu chuẩn'),
              areaController: TextEditingController(text: '50'),
              customNames: [],
            );
          }).toList();
        }
      }
    }
  }

  void _loadFloorConfigs(List<Map<String, dynamic>> details) {
    floorConfigs = details.asMap().entries.map((entry) {
      final detail = entry.value;
      final List<String> customNames = detail['customNames'] != null 
          ? List<String>.from(detail['customNames'])
          : [];
      
      return FloorConfig(
        floorNumber: entry.key + 1,
        countController: TextEditingController(text: detail['count']?.toString() ?? '10'),
        typeController: TextEditingController(text: detail['type'] ?? 'Tiêu chuẩn'),
        areaController: TextEditingController(text: detail['area']?.toString() ?? '50'),
        customNames: customNames,
      );
    }).toList();
  }

  @override
  void dispose() {
    nameController.dispose(); 
    addressController.dispose(); 
    floorsController.dispose();
    roomPrefixController.dispose(); 
    uniformRoomsController.dispose(); 
    uniformTypeController.dispose();
    uniformAreaController.dispose(); 
    bulkStartFloorController.dispose(); 
    bulkEndFloorController.dispose();
    bulkRoomsController.dispose(); 
    bulkTypeController.dispose(); 
    bulkAreaController.dispose();
    for (var config in floorConfigs) { 
      config.dispose(); 
    }
    super.dispose();
  }

  void _updateFloorConfigs() {
    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) return;
    setState(() {
      while (floorConfigs.length < floors) {
        floorConfigs.add(FloorConfig(
          floorNumber: floorConfigs.length + 1,
          countController: TextEditingController(text: '10'),
          typeController: TextEditingController(text: 'Tiêu chuẩn'),
          areaController: TextEditingController(text: '50'),
          customNames: [],
        ));
      }
      while (floorConfigs.length > floors) { 
        floorConfigs.removeLast().dispose(); 
      }
    });
  }

  void _applyBulkEdit() {
    final start = int.tryParse(bulkStartFloorController.text);
    final end = int.tryParse(bulkEndFloorController.text);
    if (start == null || end == null || start < 1 || end > floorConfigs.length || start > end) return;
    setState(() {
      for (int i = start - 1; i < end; i++) {
        if (bulkRoomsController.text.isNotEmpty) floorConfigs[i].countController.text = bulkRoomsController.text;
        if (bulkTypeController.text.isNotEmpty) floorConfigs[i].typeController.text = bulkTypeController.text;
        if (bulkAreaController.text.isNotEmpty) floorConfigs[i].areaController.text = bulkAreaController.text;
      }
      showBulkEdit = false;
    });
  }

  // ✅ UPDATED: Validate with error messages
  String? _validate() {
    // Check basic fields
    if (nameController.text.trim().isEmpty) {
      return 'Vui lòng nhập tên toà nhà';
    }
    if (addressController.text.trim().isEmpty) {
      return 'Vui lòng nhập địa chỉ';
    }

    // If auto-generate is disabled, we're done
    if (!autoGenerateRooms) return null;

    // Check floors
    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) {
      return 'Vui lòng nhập số tầng hợp lệ';
    }

    // Check uniform mode
    if (uniformRoomsPerFloor) {
      final roomsPerFloor = int.tryParse(uniformRoomsController.text.trim());
      if (roomsPerFloor == null || roomsPerFloor <= 0) {
        return 'Vui lòng nhập số phòng mỗi tầng hợp lệ';
      }
    }

    return null; // All valid
  }

  Map<String, dynamic>? _validateAndGetResult() {
    final baseData = {
      'name': nameController.text.trim(),
      'address': addressController.text.trim(),
      'autoGenerateRooms': autoGenerateRooms,
    };
    if (!autoGenerateRooms) return baseData;

    if (uniformRoomsPerFloor) {
      return {
        ...baseData,
        'uniformRooms': true,
        'floors': int.tryParse(floorsController.text) ?? 0,
        'roomsPerFloor': int.tryParse(uniformRoomsController.text) ?? 0,
        'roomType': uniformTypeController.text.trim(),
        'roomArea': double.tryParse(uniformAreaController.text) ?? 0.0,
        'roomPrefix': roomPrefixController.text.trim(),
      };
    } else {
      final details = floorConfigs.map((c) => {
        'count': int.tryParse(c.countController.text) ?? 0,
        'type': c.typeController.text.trim(),
        'area': double.tryParse(c.areaController.text) ?? 0.0,
        'customNames': c.customNames,
      }).toList();
      return {
        ...baseData,
        'uniformRooms': false,
        'floors': int.tryParse(floorsController.text) ?? 0,
        'floorDetails': details,
        'floorRoomCounts': details.map((e) => e['count'] as int).toList(),
        'roomPrefix': roomPrefixController.text.trim(),
      };
    }
  }

  void _showCustomRoomNamesDialog(FloorConfig config) {
    final int roomCount = int.tryParse(config.countController.text) ?? 0;
    if (roomCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số lượng phòng trước')),
      );
      return;
    }

    while (config.customNames.length < roomCount) {
      config.customNames.add('');
    }
    while (config.customNames.length > roomCount) {
      config.customNames.removeLast();
    }

    final controllers = config.customNames
        .map((name) => TextEditingController(text: name))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tên phòng tầng ${config.floorNumber}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: roomCount,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[index],
                  decoration: InputDecoration(
                    labelText: 'Phòng ${index + 1}',
                    hintText: 'VD: Phòng VIP, Studio A...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              for (int i = 0; i < controllers.length; i++) {
                config.customNames[i] = controllers[i].text.trim();
              }
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ).then((_) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width * 0.95 : 700,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(widget.isEditMode ? 'Sửa Toà Nhà' : 'Thêm Toà Nhà', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // ✅ Use TextFormField with validator
                      TextFormField(
                        controller: nameController,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'Tên toà nhà *',
                          hintText: 'vd: Toà A',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tên toà nhà';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: addressController,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'Địa chỉ *',
                          hintText: 'vd: 123 Đường ABC',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập địa chỉ';
                          }
                          return null;
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('Tự động tạo phòng'),
                        value: autoGenerateRooms,
                        onChanged: (v) => setState(() => autoGenerateRooms = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (autoGenerateRooms) ...[
                        TextFormField(
                          controller: floorsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Số tầng *',
                            hintText: '1',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (!uniformRoomsPerFloor) _updateFloorConfigs();
                            setState(() {});
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập số tầng';
                            }
                            final floors = int.tryParse(value);
                            if (floors == null || floors <= 0) {
                              return 'Số tầng phải lớn hơn 0';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDistributionToggle(),
                        const SizedBox(height: 16),
                        if (uniformRoomsPerFloor) _buildUniformSection() else _buildCustomSection(),
                        const SizedBox(height: 16),
                        _buildTextField(roomPrefixController, 'Tiền tố số phòng', 'A'),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String label, 
    String hint, {
      int maxLines = 1, 
      TextInputType? keyboardType, 
      Function(String)? onChanged,
      int? maxLength, 
  }) {
    return TextField(
      controller: controller, 
      maxLines: maxLines, 
      keyboardType: keyboardType, 
      onChanged: onChanged, 
      maxLength: maxLength,
      decoration: InputDecoration(
        counterText: maxLength != null ? null : '',
        labelText: label, 
        hintText: hint, 
        border: const OutlineInputBorder()
      ),
    );
  }

  Widget _buildDistributionToggle() {
    return ToggleButtons(
      isSelected: [uniformRoomsPerFloor, !uniformRoomsPerFloor],
      onPressed: (i) => setState(() { uniformRoomsPerFloor = i == 0; if (!uniformRoomsPerFloor) _updateFloorConfigs(); }),
      borderRadius: BorderRadius.circular(8),
      children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Đồng đều')), Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Tùy chỉnh'))],
    );
  }

  Widget _buildUniformSection() {
    return Column(children: [
      TextFormField(
        controller: uniformRoomsController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Số phòng mỗi tầng',
          hintText: '10',
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng nhập số phòng';
          }
          final rooms = int.tryParse(value);
          if (rooms == null || rooms <= 0) {
            return 'Số phòng phải lớn hơn 0';
          }
          return null;
        },
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _buildTextField(uniformTypeController, 'Loại phòng', '')),
        const SizedBox(width: 8),
        Expanded(child: _buildTextField(uniformAreaController, 'Diện tích (m²)', '50', keyboardType: TextInputType.number)),
      ])
    ]);
  }

  Widget _buildCustomSection() {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Cấu hình tầng', style: TextStyle(fontWeight: FontWeight.bold)),
        TextButton.icon(onPressed: () => setState(() => showBulkEdit = !showBulkEdit), icon: Icon(showBulkEdit ? Icons.close : Icons.edit_note), label: Text(showBulkEdit ? 'Đóng' : 'Chỉnh hàng loạt'))
      ]),
      if (showBulkEdit) _buildBulkEditPanel(),
      ...floorConfigs.map((c) => _buildFloorRow(c)),
    ]);
  }

  Widget _buildBulkEditPanel() {
    return Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
      child: Column(children: [
        Row(children: [
          Expanded(child: _buildTextField(bulkStartFloorController, 'Từ tầng', '1', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _buildTextField(bulkEndFloorController, 'Đến tầng', floorsController.text, keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildTextField(bulkRoomsController, 'Số phòng', '10', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _buildTextField(bulkTypeController, 'Loại', '')),
          const SizedBox(width: 8),
          Expanded(child: _buildTextField(bulkAreaController, 'm²', '50', keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _applyBulkEdit, child: const Text('Áp dụng hàng loạt'))
      ]),
    );
  }

  Widget _buildFloorRow(FloorConfig config) {
    final hasCustomNames = config.customNames.any((name) => name.isNotEmpty);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        CircleAvatar(radius: 16, child: Text('${config.floorNumber}', style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(child: _buildCompactField(config.countController, 'SL', TextInputType.number)),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: _buildCompactField(config.typeController, 'Loại', TextInputType.text)),
        const SizedBox(width: 4),
        Expanded(child: _buildCompactField(config.areaController, 'm²', TextInputType.number)),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            Icons.badge,
            color: hasCustomNames ? Colors.green : Colors.grey,
            size: 20,
          ),
          tooltip: 'Đặt tên phòng',
          onPressed: () => _showCustomRoomNamesDialog(config),
        ),
      ]),
    );
  }

  Widget _buildCompactField(
    TextEditingController c, 
    String l, 
    TextInputType t,
    {int? maxLength}
  ) {
      return TextField(
        controller: c, 
        keyboardType: t, 
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: l, 
          isDense: true, 
          border: const OutlineInputBorder(),
          counterText: maxLength != null ? null : '',
        ),
      );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            // ✅ Validate form
            if (_formKey.currentState!.validate()) {
              // Check additional validation
              final error = _validate();
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error), backgroundColor: Colors.red),
                );
                return;
              }
              
              // Get result and close
              final r = _validateAndGetResult();
              if (r != null) {
                Navigator.pop(context, r);
              }
            }
          },
          child: Text(widget.isEditMode ? 'Cập nhật' : 'Thêm'),
        ),
      ]),
    );
  }
}

class FloorConfig {
  final int floorNumber;
  final TextEditingController countController;
  final TextEditingController typeController;
  final TextEditingController areaController;
  final List<String> customNames;
  
  FloorConfig({
    required this.floorNumber, 
    required this.countController, 
    required this.typeController, 
    required this.areaController,
    required this.customNames,
  });
  
  void dispose() { 
    countController.dispose(); 
    typeController.dispose(); 
    areaController.dispose(); 
  }
}