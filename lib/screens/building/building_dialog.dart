import 'package:apartment_management_project_2/utils/app_localizations.dart';
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
  late final TextEditingController uniformTypeController;
  final TextEditingController uniformAreaController = TextEditingController();

  List<FloorConfig> floorConfigs = [];

  bool showBulkEdit = false;
  final TextEditingController bulkStartFloorController =
      TextEditingController();
  final TextEditingController bulkEndFloorController = TextEditingController();
  final TextEditingController bulkRoomsController = TextEditingController();
  late final TextEditingController bulkTypeController;
  final TextEditingController bulkAreaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Controllers whose defaults are translatable are initialised in
    // didChangeDependencies so that the BuildContext (and thus the locale) is
    // available.
    uniformTypeController = TextEditingController();
    bulkTypeController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = AppTranslations.of(context);

    // Set locale-aware defaults only on first run (controllers are empty).
    if (uniformTypeController.text.isEmpty) {
      uniformTypeController.text = t['building_room_type_standard'];
    }
    if (bulkTypeController.text.isEmpty) {
      bulkTypeController.text = t['building_room_type_standard'];
    }

    // Populate from initial values (edit mode) once.
    if (widget.initialName != null && nameController.text.isEmpty) {
      nameController.text = widget.initialName!;
    }
    if (widget.initialAddress != null && addressController.text.isEmpty) {
      addressController.text = widget.initialAddress!;
    }

    if (widget.isEditMode &&
        widget.initialFloors != null &&
        floorsController.text.isEmpty) {
      floorsController.text = widget.initialFloors.toString();
      roomPrefixController.text = widget.initialRoomPrefix ?? '';
      uniformRoomsPerFloor = widget.initialUniformRooms ?? true;

      if (uniformRoomsPerFloor) {
        uniformRoomsController.text =
            widget.initialRoomsPerFloor?.toString() ?? '';
        uniformTypeController.text =
            widget.initialRoomType ?? t['building_room_type_standard'];
        uniformAreaController.text =
            widget.initialRoomArea?.toString() ?? '';
      } else {
        if (widget.initialFloorDetails != null) {
          _loadFloorConfigs(widget.initialFloorDetails!);
        } else if (widget.initialFloorRoomCounts != null) {
          floorConfigs =
              widget.initialFloorRoomCounts!.asMap().entries.map((entry) {
            return FloorConfig(
              floorNumber: entry.key + 1,
              countController:
                  TextEditingController(text: entry.value.toString()),
              typeController: TextEditingController(
                  text: t['building_room_type_standard']),
              areaController: TextEditingController(text: '50'),
              customNames: [],
            );
          }).toList();
        }
      }
    }
  }

  void _loadFloorConfigs(List<Map<String, dynamic>> details) {
    final t = AppTranslations.of(context);
    floorConfigs = details.asMap().entries.map((entry) {
      final detail = entry.value;
      final List<String> customNames = detail['customNames'] != null
          ? List<String>.from(detail['customNames'])
          : [];

      return FloorConfig(
        floorNumber: entry.key + 1,
        countController:
            TextEditingController(text: detail['count']?.toString() ?? '10'),
        typeController: TextEditingController(
            text: detail['type'] ?? t['building_room_type_standard']),
        areaController:
            TextEditingController(text: detail['area']?.toString() ?? '50'),
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
    final t = AppTranslations.of(context);
    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) return;
    setState(() {
      while (floorConfigs.length < floors) {
        floorConfigs.add(FloorConfig(
          floorNumber: floorConfigs.length + 1,
          countController: TextEditingController(text: '10'),
          typeController: TextEditingController(
              text: t['building_room_type_standard']),
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
    if (start == null ||
        end == null ||
        start < 1 ||
        end > floorConfigs.length ||
        start > end) return;
    setState(() {
      for (int i = start - 1; i < end; i++) {
        if (bulkRoomsController.text.isNotEmpty) {
          floorConfigs[i].countController.text = bulkRoomsController.text;
        }
        if (bulkTypeController.text.isNotEmpty) {
          floorConfigs[i].typeController.text = bulkTypeController.text;
        }
        if (bulkAreaController.text.isNotEmpty) {
          floorConfigs[i].areaController.text = bulkAreaController.text;
        }
      }
      showBulkEdit = false;
    });
  }

  String? _validate() {
    final t = AppTranslations.of(context);
    if (nameController.text.trim().isEmpty) {
      return t['building_error_name_required'];
    }
    if (addressController.text.trim().isEmpty) {
      return t['building_error_address_required'];
    }

    if (!autoGenerateRooms) return null;

    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0) {
      return t['building_error_floors_invalid'];
    }

    if (uniformRoomsPerFloor) {
      final roomsPerFloor = int.tryParse(uniformRoomsController.text.trim());
      if (roomsPerFloor == null || roomsPerFloor <= 0) {
        return t['building_error_rooms_invalid'];
      }
    }

    return null;
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
    final t = AppTranslations.of(context);
    final int roomCount = int.tryParse(config.countController.text) ?? 0;
    if (roomCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t['building_enter_room_count_first'])),
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
      builder: (context) {
        final t = AppTranslations.of(context);
        return AlertDialog(
          title: Text(
            t.textWithParams(
                'building_custom_names_title', {'floor': config.floorNumber}),
          ),
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
                    maxLength: 50,
                    decoration: InputDecoration(
                      labelText: t.textWithParams(
                          'building_room_label', {'n': index + 1}),
                      hintText: t['building_room_name_hint'],
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
              child: Text(t['cancel']),
            ),
            ElevatedButton(
              onPressed: () {
                for (int i = 0; i < controllers.length; i++) {
                  config.customNames[i] = controllers[i].text.trim();
                }
                Navigator.pop(context);
                setState(() {});
              },
              child: Text(t['building_save']),
            ),
          ],
        );
      },
    ).then((_) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width < 600
              ? MediaQuery.of(context).size.width * 0.95
              : 700,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    widget.isEditMode
                        ? t['building_dialog_title_edit']
                        : t['building_dialog_title_add'],
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
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
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: nameController,
                        maxLength: 100,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: t['building_name_label'],
                          hintText: t['building_name_hint'],
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return t['building_error_name_required'];
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: addressController,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: t['building_address_label'],
                          hintText: t['building_address_hint'],
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return t['building_error_address_required'];
                          }
                          return null;
                        },
                      ),
                      CheckboxListTile(
                        title: Text(t['building_auto_generate_rooms']),
                        value: autoGenerateRooms,
                        onChanged: (v) =>
                            setState(() => autoGenerateRooms = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (autoGenerateRooms) ...[
                        TextFormField(
                          controller: floorsController,
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          decoration: InputDecoration(
                            counterText: '',
                            labelText: t['building_floors_label'],
                            hintText: '1',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (!uniformRoomsPerFloor) _updateFloorConfigs();
                            setState(() {});
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return t['building_error_floors_required'];
                            }
                            final floors = int.tryParse(value);
                            if (floors == null || floors <= 0) {
                              return t['building_error_floors_positive'];
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDistributionToggle(),
                        const SizedBox(height: 16),
                        if (uniformRoomsPerFloor)
                          _buildUniformSection()
                        else
                          _buildCustomSection(),
                        const SizedBox(height: 16),
                        _buildTextField(
                          roomPrefixController,
                          t['building_room_prefix_label'],
                          'A',
                          maxLength: 10,
                        ),
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
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildDistributionToggle() {
    final t = AppTranslations.of(context);
    return ToggleButtons(
      isSelected: [uniformRoomsPerFloor, !uniformRoomsPerFloor],
      onPressed: (i) => setState(() {
        uniformRoomsPerFloor = i == 0;
        if (!uniformRoomsPerFloor) _updateFloorConfigs();
      }),
      borderRadius: BorderRadius.circular(8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(t['building_uniform']),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(t['building_custom']),
        ),
      ],
    );
  }

  Widget _buildUniformSection() {
    final t = AppTranslations.of(context);
    return Column(children: [
      TextFormField(
        controller: uniformRoomsController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: InputDecoration(
          counterText: '',
          labelText: t['building_rooms_per_floor_label'],
          hintText: '10',
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return t['building_error_rooms_required'];
          }
          final rooms = int.tryParse(value);
          if (rooms == null || rooms <= 0) {
            return t['building_error_rooms_positive'];
          }
          return null;
        },
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _buildTextField(
            uniformTypeController,
            t['building_room_type_label'],
            '',
            maxLength: 50,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTextField(
            uniformAreaController,
            t['building_area_label'],
            '50',
            keyboardType: TextInputType.number,
            maxLength: 7,
          ),
        ),
      ])
    ]);
  }

  Widget _buildCustomSection() {
    final t = AppTranslations.of(context);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(t['building_floor_config_title'],
            style: const TextStyle(fontWeight: FontWeight.bold)),
        TextButton.icon(
          onPressed: () => setState(() => showBulkEdit = !showBulkEdit),
          icon: Icon(showBulkEdit ? Icons.close : Icons.edit_note),
          label: Text(showBulkEdit
              ? t['building_bulk_close']
              : t['building_bulk_edit']),
        ),
      ]),
      if (showBulkEdit) _buildBulkEditPanel(),
      ...floorConfigs.map((c) => _buildFloorRow(c)),
    ]);
  }

  Widget _buildBulkEditPanel() {
    final t = AppTranslations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _buildTextField(
              bulkStartFloorController,
              t['building_bulk_from_floor'],
              '1',
              keyboardType: TextInputType.number,
              maxLength: 3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTextField(
              bulkEndFloorController,
              t['building_bulk_to_floor'],
              floorsController.text,
              keyboardType: TextInputType.number,
              maxLength: 3,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _buildTextField(
              bulkRoomsController,
              t['building_bulk_rooms'],
              '10',
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTextField(
              bulkTypeController,
              t['building_bulk_type'],
              '',
              maxLength: 50,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTextField(
              bulkAreaController,
              t['building_bulk_area'],
              '50',
              keyboardType: TextInputType.number,
              maxLength: 7,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _applyBulkEdit,
          child: Text(t['building_bulk_apply']),
        ),
      ]),
    );
  }

  Widget _buildFloorRow(FloorConfig config) {
    final t = AppTranslations.of(context);
    final hasCustomNames = config.customNames.any((name) => name.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          child: Text('${config.floorNumber}',
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactField(
            config.countController,
            t['building_col_count'],
            TextInputType.number,
            maxLength: 4,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _buildCompactField(
            config.typeController,
            t['building_col_type'],
            TextInputType.text,
            maxLength: 50,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildCompactField(
            config.areaController,
            t['building_col_area'],
            TextInputType.number,
            maxLength: 7,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            Icons.badge,
            color: hasCustomNames ? Colors.green : Colors.grey,
            size: 20,
          ),
          tooltip: t['building_set_room_names_tooltip'],
          onPressed: () => _showCustomRoomNamesDialog(config),
        ),
      ]),
    );
  }

  Widget _buildCompactField(
    TextEditingController c,
    String l,
    TextInputType t, {
    int? maxLength,
  }) {
    return TextField(
      controller: c,
      keyboardType: t,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: l,
        isDense: true,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    );
  }

  Widget _buildActions() {
    final t = AppTranslations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t['cancel']),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final error = _validate();
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(error), backgroundColor: Colors.red),
                );
                return;
              }
              final r = _validateAndGetResult();
              if (r != null) {
                Navigator.pop(context, r);
              }
            }
          },
          child: Text(widget.isEditMode
              ? t['building_action_update']
              : t['building_action_add']),
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