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
  
  // Hỗ trợ cả 2 định dạng dữ liệu
  final List<Map<String, dynamic>>? initialFloorDetails; // Định dạng mới
  final List<int>? initialFloorRoomCounts;               // Định dạng cũ (Legacy)

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
    this.initialFloorRoomCounts, // Đã thêm lại
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
  final TextEditingController uniformTypeController = TextEditingController(text: 'Standard');
  final TextEditingController uniformAreaController = TextEditingController();
  
  List<FloorConfig> floorConfigs = [];
  
  bool showBulkEdit = false;
  final TextEditingController bulkStartFloorController = TextEditingController();
  final TextEditingController bulkEndFloorController = TextEditingController();
  final TextEditingController bulkRoomsController = TextEditingController();
  final TextEditingController bulkTypeController = TextEditingController(text: 'Standard');
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
        // LOGIC THÔNG MINH: Kiểm tra dữ liệu mới trước, nếu không có thì dùng dữ liệu cũ
        if (widget.initialFloorDetails != null) {
          _loadFloorConfigs(widget.initialFloorDetails!);
        } else if (widget.initialFloorRoomCounts != null) {
          // Tự động chuyển đổi List<int> cũ sang FloorConfig mới
          floorConfigs = widget.initialFloorRoomCounts!.asMap().entries.map((entry) {
            return FloorConfig(
              floorNumber: entry.key + 1,
              countController: TextEditingController(text: entry.value.toString()),
              typeController: TextEditingController(text: 'Standard'),
              areaController: TextEditingController(text: '50'),
            );
          }).toList();
        }
      }
    }
  }

  void _loadFloorConfigs(List<Map<String, dynamic>> details) {
    floorConfigs = details.asMap().entries.map((entry) {
      return FloorConfig(
        floorNumber: entry.key + 1,
        countController: TextEditingController(text: entry.value['count']?.toString() ?? '10'),
        typeController: TextEditingController(text: entry.value['type'] ?? 'Standard'),
        areaController: TextEditingController(text: entry.value['area']?.toString() ?? '50'),
      );
    }).toList();
  }

  @override
  void dispose() {
    nameController.dispose(); addressController.dispose(); floorsController.dispose();
    roomPrefixController.dispose(); uniformRoomsController.dispose(); uniformTypeController.dispose();
    uniformAreaController.dispose(); bulkStartFloorController.dispose(); bulkEndFloorController.dispose();
    bulkRoomsController.dispose(); bulkTypeController.dispose(); bulkAreaController.dispose();
    for (var config in floorConfigs) { config.dispose(); }
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
          typeController: TextEditingController(text: 'Standard'),
          areaController: TextEditingController(text: '50'),
        ));
      }
      while (floorConfigs.length > floors) { floorConfigs.removeLast().dispose(); }
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

  Map<String, dynamic>? _validateAndGetResult() {
    if (nameController.text.isEmpty || addressController.text.isEmpty) return null;
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
      }).toList();
      return {
        ...baseData,
        'uniformRooms': false,
        'floors': int.tryParse(floorsController.text) ?? 0,
        'floorDetails': details,
        'floorRoomCounts': details.map((e) => e['count'] as int).toList(), // Trả về cả list cũ để tránh lỗi service
        'roomPrefix': roomPrefixController.text.trim(),
      };
    }
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
                      _buildTextField(nameController, 'Tên toà nhà *', 'vd: Toà A'),
                      const SizedBox(height: 16),
                      _buildTextField(addressController, 'Địa chỉ *', 'vd: 123 Đường ABC', maxLines: 2),
                      CheckboxListTile(
                        title: const Text('Tự động tạo phòng'),
                        value: autoGenerateRooms,
                        onChanged: (v) => setState(() => autoGenerateRooms = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (autoGenerateRooms) ...[
                        _buildTextField(floorsController, 'Số tầng *', '1', keyboardType: TextInputType.number, onChanged: (_) { if (!uniformRoomsPerFloor) _updateFloorConfigs(); setState(() {}); }),
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

  // --- UI Helpers (Các Widget phụ trợ giống bản trước) ---
  Widget _buildTextField(TextEditingController controller, String label, String hint, {int maxLines = 1, TextInputType? keyboardType, Function(String)? onChanged}) {
    return TextField(controller: controller, maxLines: maxLines, keyboardType: keyboardType, onChanged: onChanged, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()));
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
      _buildTextField(uniformRoomsController, 'Số phòng mỗi tầng', '10', keyboardType: TextInputType.number),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _buildTextField(uniformTypeController, 'Loại phòng', 'Studio')),
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
          Expanded(child: _buildTextField(bulkTypeController, 'Loại', 'Studio')),
          const SizedBox(width: 8),
          Expanded(child: _buildTextField(bulkAreaController, 'm²', '50', keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _applyBulkEdit, child: const Text('Áp dụng hàng loạt'))
      ]),
    );
  }

  Widget _buildFloorRow(FloorConfig config) {
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
      ]),
    );
  }

  Widget _buildCompactField(TextEditingController c, String l, TextInputType t) {
    return TextField(controller: c, keyboardType: t, decoration: InputDecoration(labelText: l, isDense: true, border: const OutlineInputBorder()));
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: () { final r = _validateAndGetResult(); if (r != null) Navigator.pop(context, r); }, child: Text(widget.isEditMode ? 'Cập nhật' : 'Thêm')),
      ]),
    );
  }
}

class FloorConfig {
  final int floorNumber;
  final TextEditingController countController;
  final TextEditingController typeController;
  final TextEditingController areaController;
  FloorConfig({required this.floorNumber, required this.countController, required this.typeController, required this.areaController});
  void dispose() { countController.dispose(); typeController.dispose(); areaController.dispose(); }
}