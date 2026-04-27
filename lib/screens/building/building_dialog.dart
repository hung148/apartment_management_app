import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS (mirrors dashboard _DS)
// ─────────────────────────────────────────────────────────────
class _DS {
  static const primary      = Color(0xFF1A56DB);
  static const primaryDeep  = Color(0xFF0E3A9F);
  static const primaryMid   = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFEFF6FF);
  static const surface      = Color(0xFFF4F6FB);
  static const textPrimary  = Color(0xFF0C1C3E);
  static const textSecondary= Color(0xFF64748B);
}

// ─────────────────────────────────────────────────────────────
// BUILDING DIALOG
// ─────────────────────────────────────────────────────────────
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

class _BuildingDialogState extends State<BuildingDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final nameController    = TextEditingController();
  final addressController = TextEditingController();
  final floorsController  = TextEditingController();
  final roomPrefixController = TextEditingController();

  bool autoGenerateRooms   = true;
  bool uniformRoomsPerFloor = true;

  final uniformRoomsController = TextEditingController();
  late final TextEditingController uniformTypeController;
  final uniformAreaController  = TextEditingController();

  List<FloorConfig> floorConfigs = [];

  bool showBulkEdit = false;
  final bulkStartFloorController = TextEditingController();
  final bulkEndFloorController   = TextEditingController();
  final bulkRoomsController      = TextEditingController();
  late final TextEditingController bulkTypeController;
  final bulkAreaController = TextEditingController();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    uniformTypeController = TextEditingController();
    bulkTypeController    = TextEditingController();
    _animCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = AppTranslations.of(context);

    if (uniformTypeController.text.isEmpty) {
      uniformTypeController.text = t['building_room_type_standard'];
    }
    if (bulkTypeController.text.isEmpty) {
      bulkTypeController.text = t['building_room_type_standard'];
    }

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
    _animCtrl.dispose();
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
    for (var config in floorConfigs) config.dispose();
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
    final end   = int.tryParse(bulkEndFloorController.text);
    if (start == null || end == null ||
        start < 1 || end > floorConfigs.length || start > end) return;
    setState(() {
      for (int i = start - 1; i < end; i++) {
        if (bulkRoomsController.text.isNotEmpty)
          floorConfigs[i].countController.text = bulkRoomsController.text;
        if (bulkTypeController.text.isNotEmpty)
          floorConfigs[i].typeController.text = bulkTypeController.text;
        if (bulkAreaController.text.isNotEmpty)
          floorConfigs[i].areaController.text = bulkAreaController.text;
      }
      showBulkEdit = false;
    });
  }

  String? _validate() {
    final t = AppTranslations.of(context);
    if (nameController.text.trim().isEmpty)
      return t['building_error_name_required'];
    if (addressController.text.trim().isEmpty)
      return t['building_error_address_required'];
    if (!autoGenerateRooms) return null;
    final floors = int.tryParse(floorsController.text.trim());
    if (floors == null || floors <= 0)
      return t['building_error_floors_invalid'];
    if (uniformRoomsPerFloor) {
      final rp = int.tryParse(uniformRoomsController.text.trim());
      if (rp == null || rp <= 0) return t['building_error_rooms_invalid'];
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
    while (config.customNames.length < roomCount) config.customNames.add('');
    while (config.customNames.length > roomCount) config.customNames.removeLast();

    final controllers = config.customNames
        .map((name) => TextEditingController(text: name))
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_DS.primaryMid, _DS.primaryDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.badge_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.textWithParams('building_custom_names_title',
                            {'floor': config.floorNumber}),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                ),
                // List
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    itemCount: roomCount,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controllers[index],
                        maxLength: 50,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: t.textWithParams(
                              'building_room_label', {'n': index + 1}),
                          hintText: t['building_room_name_hint'],
                          filled: true,
                          fillColor: _DS.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: _DS.primary, width: 1.6),
                          ),
                          isDense: true,
                          prefixIcon: Container(
                            width: 32,
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: _DS.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _DS.textSecondary,
                          side: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t['cancel'],
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          for (int i = 0; i < controllers.length; i++) {
                            config.customNames[i] = controllers[i].text.trim();
                          }
                          Navigator.pop(context);
                          setState(() {});
                        },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(t['building_save'],
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: _DS.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      for (var c in controllers) c.dispose();
    });
  }

  // ── BUILD ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final isSmall = MediaQuery.of(context).size.width < 600;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isSmall
                ? MediaQuery.of(context).size.width * 0.95
                : 680,
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(t),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Basic info ─────────────────
                        _sectionLabel(
                            Icons.business_rounded, t['building_section_basic']),
                        const SizedBox(height: 10),
                        _styledField(
                          controller: nameController,
                          label: t['building_name_label'],
                          hint: t['building_name_hint'],
                          icon: Icons.apartment_rounded,
                          maxLength: 100,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? t['building_error_name_required']
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _styledField(
                          controller: addressController,
                          label: t['building_address_label'],
                          hint: t['building_address_hint'],
                          icon: Icons.location_on_rounded,
                          maxLength: 200,
                          maxLines: 2,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? t['building_error_address_required']
                              : null,
                        ),

                        const SizedBox(height: 20),

                        // ── Room generation toggle ──────
                        _buildAutoGenerateToggle(t),

                        if (autoGenerateRooms) ...[
                          const SizedBox(height: 20),
                          _sectionLabel(Icons.layers_rounded,
                              t['building_section_rooms']),
                          const SizedBox(height: 10),
                          _styledField(
                            controller: floorsController,
                            label: t['building_floors_label'],
                            hint: '1',
                            icon: Icons.stairs_rounded,
                            maxLength: 3,
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              if (!uniformRoomsPerFloor) _updateFloorConfigs();
                              setState(() {});
                            },
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return t['building_error_floors_required'];
                              final f = int.tryParse(v);
                              if (f == null || f <= 0)
                                return t['building_error_floors_positive'];
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _buildDistributionToggle(t),
                          const SizedBox(height: 14),
                          if (uniformRoomsPerFloor)
                            _buildUniformSection(t)
                          else
                            _buildCustomSection(t),
                          const SizedBox(height: 14),
                          _styledField(
                            controller: roomPrefixController,
                            label: t['building_room_prefix_label'],
                            hint: 'A',
                            icon: Icons.tag_rounded,
                            maxLength: 10,
                          ),
                        ],

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              _buildActions(t),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────
  Widget _buildHeader(AppTranslations t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_DS.primaryMid, _DS.primaryDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            widget.isEditMode
                ? Icons.edit_rounded
                : Icons.add_business_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isEditMode
                    ? t['building_dialog_title_edit']
                    : t['building_dialog_title_add'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.isEditMode
                    ? t['building_header_subtitle_edit']
                    : t['building_header_subtitle_add'],
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.close_rounded,
                color: Colors.white, size: 18),
          ),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }

  // ── SECTION LABEL ────────────────────────────────────────────
  Widget _sectionLabel(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 14, color: _DS.primary),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _DS.primary,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Divider(
          color: _DS.primary.withValues(alpha: 0.15),
          thickness: 1,
        ),
      ),
    ]);
  }

  // ── STYLED FIELD ─────────────────────────────────────────────
  Widget _styledField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType? keyboardType,
    Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: _DS.textSecondary),
        filled: true,
        fillColor: _DS.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _DS.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.8),
        ),
        labelStyle: const TextStyle(
            fontSize: 13, color: _DS.textSecondary),
        hintStyle: TextStyle(
            fontSize: 13, color: _DS.textSecondary.withValues(alpha: 0.5)),
      ),
    );
  }

  // ── AUTO-GENERATE TOGGLE ─────────────────────────────────────
  Widget _buildAutoGenerateToggle(AppTranslations t) {
    return GestureDetector(
      onTap: () => setState(() => autoGenerateRooms = !autoGenerateRooms),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: autoGenerateRooms ? _DS.primaryLight : _DS.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: autoGenerateRooms
                ? _DS.primary.withValues(alpha: 0.35)
                : Colors.grey.withValues(alpha: 0.2),
            width: autoGenerateRooms ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: autoGenerateRooms
                  ? _DS.primary
                  : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.meeting_room_rounded,
              color: autoGenerateRooms ? Colors.white : _DS.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['building_auto_generate_rooms'],
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: autoGenerateRooms
                        ? _DS.primary
                        : _DS.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t['building_auto_generate_hint'],
                  style: const TextStyle(
                      fontSize: 11, color: _DS.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: autoGenerateRooms,
            onChanged: (v) => setState(() => autoGenerateRooms = v),
            activeColor: _DS.primary,
          ),
        ]),
      ),
    );
  }

  // ── DISTRIBUTION TOGGLE ──────────────────────────────────────
  Widget _buildDistributionToggle(AppTranslations t) {
    return Container(
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        _toggleOption(
          label: t['building_uniform'],
          icon: Icons.grid_view_rounded,
          selected: uniformRoomsPerFloor,
          onTap: () => setState(() => uniformRoomsPerFloor = true),
          isLeft: true,
        ),
        _toggleOption(
          label: t['building_custom'],
          icon: Icons.tune_rounded,
          selected: !uniformRoomsPerFloor,
          onTap: () {
            setState(() => uniformRoomsPerFloor = false);
            _updateFloorConfigs();
          },
          isLeft: false,
        ),
      ]),
    );
  }

  Widget _toggleOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isLeft,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.all(selected ? 3 : 3),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _DS.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _DS.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? Colors.white
                      : _DS.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _DS.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UNIFORM SECTION ──────────────────────────────────────────
  Widget _buildUniformSection(AppTranslations t) {
    return Column(children: [
      _styledField(
        controller: uniformRoomsController,
        label: t['building_rooms_per_floor_label'],
        hint: '10',
        icon: Icons.door_front_door_rounded,
        maxLength: 4,
        keyboardType: TextInputType.number,
        validator: (v) {
          if (v == null || v.trim().isEmpty)
            return t['building_error_rooms_required'];
          final r = int.tryParse(v);
          if (r == null || r <= 0)
            return t['building_error_rooms_positive'];
          return null;
        },
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          flex: 3,
          child: _styledField(
            controller: uniformTypeController,
            label: t['building_room_type_label'],
            hint: '',
            icon: Icons.category_rounded,
            maxLength: 50,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _styledField(
            controller: uniformAreaController,
            label: t['building_area_label'],
            hint: '50',
            icon: Icons.square_foot_rounded,
            keyboardType: TextInputType.number,
            maxLength: 7,
          ),
        ),
      ]),
    ]);
  }

  // ── CUSTOM SECTION ───────────────────────────────────────────
  Widget _buildCustomSection(AppTranslations t) {
    return Column(children: [
      // Bulk edit header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _DS.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Icon(Icons.layers_rounded, size: 14, color: _DS.textSecondary),
          const SizedBox(width: 8),
          Text(
            t['building_floor_config_title'],
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: _DS.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => showBulkEdit = !showBulkEdit),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: showBulkEdit
                    ? _DS.primary
                    : _DS.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  showBulkEdit ? Icons.close_rounded : Icons.edit_note_rounded,
                  size: 13,
                  color: showBulkEdit ? Colors.white : _DS.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  showBulkEdit
                      ? t['building_bulk_close']
                      : t['building_bulk_edit'],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: showBulkEdit ? Colors.white : _DS.primary,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),

      if (showBulkEdit) ...[
        const SizedBox(height: 10),
        _buildBulkEditPanel(t),
      ],

      const SizedBox(height: 8),

      if (floorConfigs.isNotEmpty) ...[
        // Column headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const SizedBox(width: 44),
            Expanded(
              child: Text(t['building_col_count'],
                  style: _headerStyle, textAlign: TextAlign.center),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Text(t['building_col_type'],
                  style: _headerStyle, textAlign: TextAlign.center),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(t['building_col_area'],
                  style: _headerStyle, textAlign: TextAlign.center),
            ),
            const SizedBox(width: 38),
          ]),
        ),
        const SizedBox(height: 6),
        ...floorConfigs.map((c) => _buildFloorRow(c, t)),
      ],
    ]);
  }

  TextStyle get _headerStyle => const TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: _DS.textSecondary,
    letterSpacing: 0.5,
  );

  Widget _buildBulkEditPanel(AppTranslations t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DS.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DS.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: 14, color: _DS.primary),
          const SizedBox(width: 6),
          Text(
            t['building_bulk_edit'].toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _DS.primary,
              letterSpacing: 0.6,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _compactField(
                bulkStartFloorController, t['building_bulk_from_floor'],
                '1', TextInputType.number),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(
                bulkEndFloorController, t['building_bulk_to_floor'],
                floorsController.text, TextInputType.number),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _compactField(bulkRoomsController,
                t['building_bulk_rooms'], '10', TextInputType.number),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _compactField(
                bulkTypeController, t['building_bulk_type'], '',
                TextInputType.text),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(bulkAreaController,
                t['building_bulk_area'], '50', TextInputType.number),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _applyBulkEdit,
            icon: const Icon(Icons.check_rounded, size: 15),
            label: Text(t['building_bulk_apply'],
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: _DS.primary,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildFloorRow(FloorConfig config, AppTranslations t) {
    final hasCustomNames = config.customNames.any((n) => n.isNotEmpty);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        // Floor badge
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_DS.primaryMid, _DS.primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '${config.floorNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _compactField(
            config.countController, '', '', TextInputType.number,
            maxLength: 4)),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _compactField(
              config.typeController, '', '', TextInputType.text,
              maxLength: 50),
        ),
        const SizedBox(width: 4),
        Expanded(child: _compactField(
            config.areaController, '', '', TextInputType.number,
            maxLength: 7)),
        const SizedBox(width: 4),
        // Custom names button
        GestureDetector(
          onTap: () => _showCustomRoomNamesDialog(config),
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: hasCustomNames
                  ? Colors.green.withValues(alpha: 0.12)
                  : _DS.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasCustomNames
                    ? Colors.green.withValues(alpha: 0.4)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              Icons.badge_rounded,
              size: 15,
              color: hasCustomNames ? Colors.green[600] : _DS.textSecondary,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _compactField(
    TextEditingController c,
    String label,
    String hint,
    TextInputType type, {
    int? maxLength,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      maxLength: maxLength,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        hintText: hint.isEmpty ? null : hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _DS.primary, width: 1.6),
        ),
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }

  // ── ACTIONS ──────────────────────────────────────────────────
  Widget _buildActions(AppTranslations t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(children: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: _DS.textSecondary,
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(t['cancel'],
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final error = _validate();
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
                return;
              }
              final r = _validateAndGetResult();
              if (r != null) Navigator.pop(context, r);
            }
          },
          icon: Icon(
            widget.isEditMode
                ? Icons.save_rounded
                : Icons.add_rounded,
            size: 17,
          ),
          label: Text(
            widget.isEditMode
                ? t['building_action_update']
                : t['building_action_add'],
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _DS.primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FLOOR CONFIG
// ─────────────────────────────────────────────────────────────
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