import 'dart:async';

import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';

// ─── Color palette ───────────────────────────────────────────────────────────
const List<Color> _tenantAccentColors = [
  Color(0xFF185FA5),
  Color(0xFF0F6E56),
  Color(0xFF854F0B),
  Color(0xFF534AB7),
  Color(0xFF993556),
  Color(0xFF1A7E5A),
  Color(0xFF6B4226),
];

// ─── Gradient presets per accent color ───────────────────────────────────────
LinearGradient _headerGradient(Color accentColor) {
  return LinearGradient(
    colors: [
      Color.lerp(accentColor, const Color(0xFF0D1B40), 0.35)!,
      accentColor,
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

// The default blue gradient used for most dialogs
const LinearGradient _defaultHeaderGradient = LinearGradient(
  colors: [Color(0xFF1035A0), Color(0xFF2563EB)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// ─── Shared dialog chrome ─────────────────────────────────────────────────────
class _DialogShell extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double maxHeightFactor;

  const _DialogShell({
    required this.child,
    this.maxWidth = 520,
    this.maxHeightFactor = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 600 ? 12 : 32,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * maxHeightFactor,
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

// ─── Dialog header bar (new blue gradient style) ──────────────────────────────
class _DialogHeader extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final List<Widget>? actions;
  final Gradient? gradient;

  const _DialogHeader({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onClose,
    this.actions,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: BoxDecoration(
        gradient: gradient ?? _defaultHeaderGradient,
      ),
      child: Row(
        children: [
          // Leading icon in frosted container
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: leading),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null)
            ...actions!.map((a) => Theme(
                  data: Theme.of(context).copyWith(
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white70),
                    ),
                    iconTheme:
                        const IconThemeData(color: Colors.white70),
                  ),
                  child: a,
                )),
          const SizedBox(width: 4),
          // Close button circle
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom-sheet handle ──────────────────────────────────────────────────────
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

// ─── Styled action button for dialogs ────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;
  final IconData? icon;

  const _ActionButton({
    required this.label,
    this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;

    if (primary && !destructive) {
      return Material(
        color: disabled ? Colors.grey.shade300 : const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: disabled ? Colors.grey.shade500 : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (destructive) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE74C3C), width: 1.5),
              color: const Color(0xFFFFF0EF),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: const Color(0xFFE74C3C)),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE74C3C),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Cancel / secondary
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: Colors.grey.shade600),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dialog action bar ────────────────────────────────────────────────────────
class _DialogActions extends StatelessWidget {
  final List<Widget> children;

  const _DialogActions({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: children
              .expand((w) => [w, const SizedBox(width: 10)])
              .toList()
            ..removeLast(),
        ),
      );
}

// ─── Section label inside dialog ─────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const _SectionLabel(this.text, {this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final labelColor = color ?? const Color(0xFF2563EB);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: labelColor),
            const SizedBox(width: 6),
          ] else ...[
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: labelColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: labelColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: labelColor.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail row ───────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 145,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.grey.shade800,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
}

// ─── Divider inside dialog content ───────────────────────────────────────────
class _ContentDivider extends StatelessWidget {
  const _ContentDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1, color: Colors.grey.shade100),
      );
}

// ─── Input field ─────────────────────────────────────────────────────────────
Widget _inputField(
  TextEditingController controller,
  String label,
  IconData icon, {
  String? suffix,
  TextInputType? keyboardType,
  int? maxLength,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade400),
        suffixText: suffix,
        suffixStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        isDense: true,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
  );
}

// ─── Dropdown field ───────────────────────────────────────────────────────────
Widget _dropdownField<T>({
  required String label,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required void Function(T?) onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      items: items,
      onChanged: onChanged,
    ),
  );
}

// ─── Info/warning banner ──────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _InfoBanner({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
          ],
        ),
      );
}

// ─── Vehicle card ─────────────────────────────────────────────────────────────
class _VehicleCard extends StatelessWidget {
  final VehicleInfo vehicle;
  final IconData typeIcon;
  final String typeLabel;
  final String? parkingLabel;
  final List<PopupMenuEntry<String>> menuItems;
  final void Function(String) onMenuSelected;

  const _VehicleCard({
    required this.vehicle,
    required this.typeIcon,
    required this.typeLabel,
    this.parkingLabel,
    required this.menuItems,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD4CFFA)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF534AB7).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(typeIcon, size: 20, color: const Color(0xFF534AB7)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.licensePlate,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF26215C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [typeLabel, vehicle.brand, vehicle.model]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF534AB7)),
                  ),
                  if (parkingLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.local_parking_rounded,
                            size: 12, color: Color(0xFF0F6E56)),
                        const SizedBox(width: 4),
                        Text(
                          parkingLabel!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF0F6E56)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  size: 18, color: Colors.grey.shade400),
              itemBuilder: (_) => menuItems,
              onSelected: onMenuSelected,
            ),
          ],
        ),
      );
}

// ─── Rental history entry ─────────────────────────────────────────────────────
class _RentalHistoryEntry extends StatelessWidget {
  final String locationText;
  final String dateRangeText;
  final String durationText;

  const _RentalHistoryEntry({
    required this.locationText,
    required this.dateRangeText,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAEEDA).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFF0C97A).withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF854F0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.home_rounded,
                  size: 18, color: Color(0xFF854F0B)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locationText,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF412402)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateRangeText,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF854F0B)),
                  ),
                  Text(
                    durationText,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─── Detail card container (replaces plain _DetailRow grouping) ───────────────
class _DetailCard extends StatelessWidget {
  final List<Widget> rows;
  final Color? borderColor;
  final Color? fillColor;

  const _DetailCard({required this.rows, this.borderColor, this.fillColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: fillColor ?? Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
      ),
      child: Column(children: rows),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class TenantsTab extends StatefulWidget {
  final Organization organization;
  final TenantService tenantService;
  final BuildingService buildingService;
  final RoomService roomService;
  final OrganizationService organizationService;
  final AuthService authService;
  final VoidCallback? onChanged;

  const TenantsTab({
    Key? key,
    required this.organization,
    required this.tenantService,
    required this.buildingService,
    required this.roomService,
    required this.organizationService,
    required this.authService,
    this.onChanged,
  }) : super(key: key);

  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

class _TenantsTabState extends State<TenantsTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  late Future<List<dynamic>> _initialFuture;

  int _overlayCount = 0;

  List<Tenant> _allTenants = [];
  List<Building> _buildings = [];
  List<Room> _rooms = [];
  Membership? _membership;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialFuture = Future.wait([
      _getAllTenants(),
      _getBuildings(),
      _getAllRooms(),
      _getMyMembership(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
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
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      if (screenWidth < 360 || screenHeight < 600) {
        _dismissAllOverlays();
      }
    });
  }

  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

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

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
    BoxConstraints? constraints,
  }) async {
    _overlayCount++;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        shape: shape,
        constraints: constraints,
        builder: builder,
      );
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  Future<List<Tenant>> _getAllTenants() =>
      widget.tenantService.getOrganizationTenants(widget.organization.id);
  Future<List<Building>> _getBuildings() =>
      widget.buildingService.getOrganizationBuildings(widget.organization.id);
  Future<List<Room>> _getAllRooms() =>
      widget.roomService.getOrganizationRooms(widget.organization.id);
  Future<Membership?> _getMyMembership() {
    final userId = widget.authService.currentUser?.uid;
    if (userId == null) return Future.value(null);
    return widget.organizationService
        .getUserMembership(userId, widget.organization.id);
  }

  Future<void> _refreshAll() async {
    setState(() {
      _initialFuture = Future.wait([
        _getAllTenants(),
        _getBuildings(),
        _getAllRooms(),
        _getMyMembership(),
      ]);
    });
    final data = await _initialFuture;
    _allTenants = List<Tenant>.from(data[0] as List<Tenant>);
    _buildings = List<Building>.from(data[1] as List<Building>);
    _rooms = List<Room>.from(data[2] as List<Room>);
    _membership = data[3] as Membership?;
  }

  String _formatCurrency(double value) {
    final f = NumberFormat.currency(
        locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    return f.format(value);
  }

  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _getVehicleTypeDisplayName(VehicleType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case VehicleType.motorcycle:
        return t['tenant_vehicle_motorcycle'];
      case VehicleType.car:
        return t['tenant_vehicle_car'];
      case VehicleType.bicycle:
        return t['tenant_vehicle_bicycle'];
      case VehicleType.electricBike:
        return t['tenant_vehicle_electric_bike'];
      case VehicleType.other:
        return t['tenant_vehicle_other'];
    }
  }

  String _getTenantStatusDisplayName(TenantStatus status) {
    final t = AppTranslations.of(context);
    switch (status) {
      case TenantStatus.active:   return t['tenant_status_active'];
      case TenantStatus.inactive: return t['tenant_status_inactive'];
      case TenantStatus.moveOut:  return t['tenant_status_moved_out'];
      case TenantStatus.suspended: return t['tenant_status_suspended'];
    }
  }

  // ─── Summary bar ─────────────────────────────────────────────────────────────
  Widget _buildSummaryBar(List<Tenant> tenants) {
    final t = AppTranslations.of(context);
    final active =
        tenants.where((x) => x.status == TenantStatus.active).length;
    final inactive =
        tenants.where((x) => x.status == TenantStatus.inactive).length;
    final movedOut =
        tenants.where((x) => x.status == TenantStatus.moveOut).length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryBarItem(
            value: active.toString(),
            label: t['tenant_status_active'],
            color: const Color(0xFF3B6D11),
            isFirst: true,
          ),
          _summaryBarDivider(),
          _summaryBarItem(
            value: inactive.toString(),
            label: t['tenant_status_inactive'],
            color: const Color(0xFF854F0B),
          ),
          _summaryBarDivider(),
          _summaryBarItem(
            value: movedOut.toString(),
            label: t['tenant_status_moved_out'],
            color: Colors.blueGrey.shade600,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryBarItem({
    required String value,
    required String label,
    required Color color,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBarDivider() => Container(
        width: 0.5,
        height: 40,
        color: Colors.grey.shade200,
      );

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppTranslations.of(context);

    return FutureBuilder<List<dynamic>>(
      future: _initialFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return Center(child: Text(t['tenant_no_data']));
        }

        final allTenants = snapshot.data![0] as List<Tenant>;
        final buildings = snapshot.data![1] as List<Building>;
        final rooms = snapshot.data![2] as List<Room>;
        final membership = snapshot.data![3] as Membership?;

        _allTenants = allTenants;
        _buildings = buildings;
        _rooms = rooms;
        _membership = membership;

        final isAdmin = membership != null && membership.role == 'admin';

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    _buildSummaryBar(allTenants),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, _) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: t['tenant_search_hint'],
                              hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14),
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.grey.shade400, size: 20),
                              suffixIcon: value.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear,
                                          color: Colors.grey.shade400,
                                          size: 18),
                                      onPressed: () =>
                                          _searchController.clear(),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 4),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    if (isAdmin)
                      Material(
                        color: const Color(0xFFE6F1FB),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () =>
                              _showAddTenantDialog(buildings, rooms),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF378ADD),
                                  width: 1.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_add_rounded,
                                    color: Color(0xFF185FA5), size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  t['tenant_add_button'],
                                  style: const TextStyle(
                                    color: Color(0xFF185FA5),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                final query = value.text;
                final tenants = _filterTenants(allTenants, query);

                if (tenants.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              query.isEmpty
                                  ? Icons.people_outline_rounded
                                  : Icons.search_off_rounded,
                              size: 36,
                              color: Colors.blue.shade400,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            query.isEmpty
                                ? t['tenant_no_tenants']
                                : t['tenant_no_results'],
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                          if (query.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              t['tenant_try_other_keyword'],
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t['tenants_tab'].toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const Spacer(),
                            if (query.isNotEmpty)
                              Text(
                                t.textWithParams(
                                    'tenant_found_results',
                                    {'count': tenants.length}),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400),
                              )
                            else
                              Text(
                                '${tenants.length}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tenant = tenants[index];
                            final color = _tenantAccentColors[
                                index % _tenantAccentColors.length];
                            return _buildTenantCard(
                                tenant, isAdmin, color);
                          },
                          childCount: tenants.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ─── Tenant card ──────────────────────────────────────────────────────────────
  Widget _buildTenantCard(
      Tenant tenant, bool isAdmin, Color accentColor) {
    final t = AppTranslations.of(context);
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;

    late final String displayBuildingName;
    late final String displayRoomNumber;
    late final Room room;

    if (isMovedOut &&
        tenant.lastBuildingName != null &&
        tenant.lastRoomNumber != null) {
      displayBuildingName = tenant.lastBuildingName!;
      displayRoomNumber = tenant.lastRoomNumber!;
      room = Room(
        id: '',
        area: 0.0,
        roomType: '',
        organizationId: '',
        buildingId: '',
        roomNumber: displayRoomNumber,
        createdAt: DateTime.now(),
      );
    } else {
      final building = _buildings.firstWhere(
        (b) => b.id == tenant.buildingId,
        orElse: () => Building(
          id: '',
          organizationId: '',
          name: t['tenant_unknown'],
          address: '',
          createdAt: DateTime.now(),
        ),
      );
      room = _rooms.firstWhere(
        (r) => r.id == tenant.roomId,
        orElse: () => Room(
          id: '',
          roomType: '',
          area: 0.0,
          organizationId: '',
          buildingId: '',
          roomNumber: '?',
          createdAt: DateTime.now(),
        ),
      );
      displayBuildingName = building.name;
      displayRoomNumber = room.roomNumber;
    }

    final bool canNavigate = !isMovedOut && room.id.isNotEmpty;
    final Color statusColor = _getTenantStatusColor(tenant.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isMovedOut
            ? Colors.grey.shade50
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color:
                accentColor.withValues(alpha: isMovedOut ? 0.03 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
              height: 5,
              color: isMovedOut ? Colors.grey.shade300 : accentColor),
          InkWell(
            onTap: canNavigate
                ? () => Navigator.pushNamed(
                    context, '/room-detail',
                    arguments: {
                          'room': room,
                          'organization': widget.organization,
                        })
                : () => _showTenantDetailDialog(
                    tenant, displayBuildingName, displayRoomNumber),
            onLongPress: isAdmin
                ? () => _showTenantOptionsMenu(tenant, isMovedOut)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isMovedOut
                              ? Colors.grey.shade200
                              : accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Center(
                          child: Text(
                            tenant.fullName.isNotEmpty
                                ? tenant.fullName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isMovedOut
                                  ? Colors.grey.shade500
                                  : accentColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tenant.fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: isMovedOut
                                          ? Colors.grey.shade600
                                          : null,
                                    ),
                                  ),
                                ),
                                if (tenant.isMainTenant)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: accentColor
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: accentColor
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      t['tenant_main_tenant_badge'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: accentColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.phone_rounded,
                                    size: 12,
                                    color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  tenant.phoneNumber,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (tenant.occupation != null) ...[
                                  Text('  ·  ',
                                      style: TextStyle(
                                          color: Colors.grey.shade400)),
                                  Expanded(
                                    child: Text(
                                      tenant.occupation!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isAdmin)
                        IconButton(
                          icon: Icon(Icons.more_vert,
                              color: Colors.grey.shade400, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          onPressed: () =>
                              _showTenantOptionsMenu(tenant, isMovedOut),
                          tooltip: t['tenant_options_tooltip'],
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _tenantStatChip(
                        icon: Icons.location_on_rounded,
                        label: canNavigate
                            ? t['tenant_location_label']
                            : t['tenant_previous_location_label'],
                        value: t.textWithParams(
                            'tenant_location_value', {
                          'building': displayBuildingName,
                          'room': displayRoomNumber,
                        }),
                        color: canNavigate
                            ? const Color(0xFF185FA5)
                            : Colors.grey.shade500,
                        hasArrow: canNavigate,
                      ),
                      if (tenant.monthlyRent != null) ...[
                        const SizedBox(width: 8),
                        _tenantStatChip(
                          icon: Icons.payments_rounded,
                          label: t['tenant_detail_monthly_rent'],
                          value: _formatCurrency(tenant.monthlyRent!),
                          color: const Color(0xFF3B6D11),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _getTenantStatusDisplayName(tenant.status),
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        _badgeChip(
                          icon: Icons.directions_car_rounded,
                          value: tenant.vehicles!.length.toString(),
                          color: const Color(0xFF534AB7),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty)
                        _badgeChip(
                          icon: Icons.history_rounded,
                          value:
                              tenant.previousRentals!.length.toString(),
                          color: const Color(0xFF854F0B),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isAdmin) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _footerActionBtn(
                    icon: Icons.info_outline_rounded,
                    label: t['tenant_menu_view_detail'],
                    color: accentColor,
                    bgColor: accentColor.withValues(alpha: 0.08),
                    onTap: () => _showTenantDetailDialog(tenant,
                        displayBuildingName, displayRoomNumber),
                  ),
                  const SizedBox(width: 8),
                  _footerActionBtn(
                    icon: Icons.edit_rounded,
                    label: t['edit'],
                    color: Colors.grey.shade600,
                    bgColor: Colors.grey.shade100,
                    onTap: () => _showEditTenantDialog(tenant),
                  ),
                  const SizedBox(width: 8),
                  _footerActionBtn(
                    icon: Icons.more_horiz_rounded,
                    label: t['tenant_options_label'],
                    color: const Color(0xFF854F0B),
                    bgColor: const Color(0xFFFAEEDA),
                    onTap: () =>
                        _showTenantOptionsMenu(tenant, isMovedOut),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tenantStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool hasArrow = false,
  }) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasArrow)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 10, color: color),
          ],
        ),
      ),
    );
  }

  Widget _badgeChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _footerActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Tenant> _filterTenants(List<Tenant> tenants, String query) {
    if (query.isEmpty) return tenants;
    final searchLower = query.toLowerCase().trim();
    return tenants.where((tenant) {
      if (tenant.fullName.toLowerCase().contains(searchLower))
        return true;
      if (tenant.phoneNumber.contains(searchLower)) return true;
      if (tenant.email != null &&
          tenant.email!.toLowerCase().contains(searchLower)) return true;
      if (tenant.nationalId != null &&
          tenant.nationalId!.contains(searchLower)) return true;
      if (tenant.occupation != null &&
          tenant.occupation!.toLowerCase().contains(searchLower))
        return true;
      if (tenant.workplace != null &&
          tenant.workplace!.toLowerCase().contains(searchLower))
        return true;
      return false;
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT DETAIL DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showTenantDetailDialog(
      Tenant tenant, String buildingName, String roomNumber) {
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;
    final accentColor =
        isMovedOut ? Colors.grey.shade600 : const Color(0xFF185FA5);
    final gradient = isMovedOut
        ? LinearGradient(
            colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade500],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : _defaultHeaderGradient;

    _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                gradient: gradient,
                onClose: () => Navigator.pop(context),
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      tenant.fullName.isNotEmpty
                          ? tenant.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                title: tenant.fullName,
                subtitle: tenant.isMainTenant
                    ? t['tenant_main_tenant_badge']
                    : tenant.phoneNumber,
                actions: _membership != null && _membership!.role == 'admin'
                    ? [
                        TextButton.icon(
                          icon: const Icon(Icons.more_horiz_rounded,
                              size: 16),
                          label: Text(t['tenant_options_label']),
                          onPressed: () {
                            Navigator.pop(context);
                            _showTenantOptionsMenu(tenant, isMovedOut);
                          },
                        ),
                      ]
                    : null,
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location section
                      _SectionLabel(
                        isMovedOut
                            ? t['tenant_detail_previous_location']
                            : t['tenant_detail_location'],
                        color: accentColor,
                        icon: Icons.location_on_rounded,
                      ),
                      _DetailCard(
                        borderColor: accentColor.withValues(alpha: 0.2),
                        fillColor: accentColor.withValues(alpha: 0.05),
                        rows: [
                          _DetailRow(t['tenant_detail_building'],
                              buildingName),
                          _DetailRow(
                              t['tenant_detail_room'], roomNumber),
                        ],
                      ),

                      const _ContentDivider(),

                      // Contact
                      _SectionLabel(
                        t['tenant_detail_contact_section'],
                        icon: Icons.contact_phone_rounded,
                      ),
                      _DetailCard(
                        rows: [
                          _DetailRow(t['tenant_detail_phone'],
                              tenant.phoneNumber),
                          if (tenant.email != null)
                            _DetailRow(
                                t['tenant_detail_email'], tenant.email!),
                        ],
                      ),

                      const _ContentDivider(),

                      // Personal
                      _SectionLabel(
                        t['tenant_detail_personal_section'],
                        icon: Icons.person_rounded,
                      ),
                      _DetailCard(
                        rows: [
                          if (tenant.gender != null)
                            _DetailRow(t['tenant_detail_gender'],
                                tenant.getGenderDisplayName()!),
                          if (tenant.nationalId != null)
                            _DetailRow(t['tenant_detail_national_id'],
                                tenant.nationalId!),
                          if (tenant.occupation != null)
                            _DetailRow(t['tenant_detail_occupation'],
                                tenant.occupation!),
                          if (tenant.workplace != null)
                            _DetailRow(t['tenant_detail_workplace'],
                                tenant.workplace!),
                        ],
                      ),

                      // Rental info
                      if (!isMovedOut) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.home_rounded,
                        ),
                        _DetailCard(
                          rows: [
                            _DetailRow(t['tenant_detail_move_in_date'],
                                _formatDate(tenant.moveInDate)),
                            _DetailRow(
                              t['tenant_detail_days_living'],
                              t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': tenant.daysLiving}),
                            ),
                            if (tenant.monthlyRent != null)
                              _DetailRow(
                                  t['tenant_detail_monthly_rent'],
                                  _formatCurrency(tenant.monthlyRent!),
                                  valueColor: const Color(0xFF3B6D11)),
                            if (tenant.deposit != null)
                              _DetailRow(
                                  t['tenant_detail_deposit'],
                                  _formatCurrency(tenant.deposit!)),
                            if (tenant.apartmentType != null &&
                                tenant.apartmentType!.isNotEmpty)
                              _DetailRow(
                                  t['tenant_detail_apartment_type'],
                                  tenant.apartmentType!),
                            if (tenant.apartmentArea != null &&
                                tenant.apartmentArea! > 0)
                              _DetailRow(
                                t['tenant_detail_area'],
                                t.textWithParams(
                                    'tenant_detail_area_value',
                                    {'area': tenant.apartmentArea}),
                              ),
                          ],
                        ),
                      ],

                      // Move-out info
                      if (isMovedOut && tenant.moveOutDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_moveout_section'],
                          icon: Icons.logout_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        _DetailCard(
                          borderColor: const Color(0xFF854F0B)
                              .withValues(alpha: 0.2),
                          fillColor: const Color(0xFF854F0B)
                              .withValues(alpha: 0.04),
                          rows: [
                            _DetailRow(t['tenant_detail_move_out_date'],
                                _formatDate(tenant.moveOutDate!)),
                            _DetailRow(
                              t['tenant_detail_duration'],
                              t.textWithParams(
                                  'tenant_detail_days_value', {
                                'days': tenant.moveOutDate!
                                    .difference(tenant.moveInDate)
                                    .inDays
                              }),
                            ),
                            if (tenant.contractTerminationReason != null)
                              _DetailRow(t['tenant_detail_reason'],
                                  tenant.contractTerminationReason!),
                            if (tenant.notes != null &&
                                tenant.notes!.isNotEmpty)
                              _DetailRow(t['tenant_detail_notes'],
                                  tenant.notes!),
                          ],
                        ),
                      ],

                      // Contract
                      if (tenant.contractStartDate != null ||
                          tenant.contractEndDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_contract_section'],
                          icon: Icons.description_rounded,
                        ),
                        _DetailCard(
                          rows: [
                            if (tenant.contractStartDate != null)
                              _DetailRow(
                                  t['tenant_detail_contract_start'],
                                  _formatDate(
                                      tenant.contractStartDate!)),
                            if (tenant.contractEndDate != null)
                              _DetailRow(
                                isMovedOut
                                    ? t[
                                        'tenant_detail_contract_end_date']
                                    : t['tenant_detail_contract_end'],
                                _formatDate(tenant.contractEndDate!),
                              ),
                            if (isMovedOut) ...[
                              _DetailRow(
                                  t['tenant_detail_contract_status'],
                                  tenant
                                      .getContractStatusDisplayName()),
                              if (tenant.moveOutDate != null &&
                                  tenant.contractEndDate != null)
                                _DetailRow(
                                  tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? t[
                                          'tenant_detail_early_termination']
                                      : t['tenant_detail_end_label'],
                                  tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? t.textWithParams(
                                          'tenant_detail_days_early',
                                          {
                                            'days': tenant.contractEndDate!
                                                .difference(
                                                    tenant.moveOutDate!)
                                                .inDays
                                          })
                                      : t['tenant_detail_on_time'],
                                  valueColor: tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? const Color(0xFF854F0B)
                                      : const Color(0xFF3B6D11),
                                ),
                            ] else if (tenant.daysUntilContractEnd !=
                                null)
                              _DetailRow(
                                t['tenant_detail_remaining'],
                                t.textWithParams(
                                    'tenant_detail_days_value', {
                                  'days': tenant.daysUntilContractEnd
                                }),
                              ),
                          ],
                        ),
                      ],

                      // Vehicles
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t.textWithParams(
                              'tenant_detail_vehicles_section',
                              {'count': tenant.vehicles!.length}),
                          icon: Icons.directions_car_rounded,
                          color: const Color(0xFF534AB7),
                        ),
                        ...tenant.vehicles!.map((vehicle) => _VehicleCard(
                              vehicle: vehicle,
                              typeIcon: _getVehicleIcon(vehicle.type),
                              typeLabel: _getVehicleTypeDisplayName(
                                  vehicle.type),
                              parkingLabel: vehicle.isParkingRegistered &&
                                      vehicle.parkingSpot != null
                                  ? t.textWithParams(
                                      'tenant_vehicle_parking_spot',
                                      {'spot': vehicle.parkingSpot!})
                                  : null,
                              menuItems: const [],
                              onMenuSelected: (_) {},
                            )),
                      ],

                      // Rental history
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t.textWithParams(
                              'tenant_detail_history_section',
                              {'count': tenant.previousRentals!.length}),
                          icon: Icons.history_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        ...tenant.previousRentals!.map((rental) =>
                            _RentalHistoryEntry(
                              locationText: t.textWithParams(
                                  'tenant_location_value', {
                                'building': rental.buildingName,
                                'room': rental.roomNumber,
                              }),
                              dateRangeText: t.textWithParams(
                                  'tenant_detail_history_dates', {
                                'from': _formatDate(rental.moveInDate),
                                'to': _formatDate(rental.moveOutDate),
                              }),
                              durationText: t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': rental.duration}),
                            )),
                      ],

                      const _ContentDivider(),
                      _DetailRow(
                        t['tenant_detail_status'],
                        tenant.getStatusDisplayName(),
                        valueColor: _getTenantStatusColor(tenant.status),
                      ),
                    ],
                  ),
                ),
              ),

              _DialogActions(
                children: [
                  _ActionButton(
                    label: t['close'],
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT OPTIONS MENU
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showTenantOptionsMenu(
      Tenant tenant, bool isMovedOut) async {
    final t = AppTranslations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    Widget _menuTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Color? color,
      required VoidCallback onTap,
    }) {
      final c = color ?? Colors.grey.shade800;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.grey.shade300),
            ],
          ),
        ),
      );
    }

    Widget _menuDivider() => Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: Colors.grey.shade100);

    List<Widget> menuItems = [
      _menuTile(
        icon: Icons.info_outline_rounded,
        title: t['tenant_menu_view_detail'],
        onTap: () {
          Navigator.pop(context);
          final building = _buildings.firstWhere(
            (b) => b.id == tenant.buildingId,
            orElse: () => Building(
              id: '',
              organizationId: '',
              name: tenant.lastBuildingName ?? t['tenant_unknown'],
              address: '',
              createdAt: DateTime.now(),
            ),
          );
          final room = _rooms.firstWhere(
            (r) => r.id == tenant.roomId,
            orElse: () => Room(
              id: '',
              roomType: '',
              area: 0.0,
              organizationId: '',
              buildingId: '',
              roomNumber: tenant.lastRoomNumber ?? '?',
              createdAt: DateTime.now(),
            ),
          );
          _showTenantDetailDialog(
              tenant, building.name, room.roomNumber);
        },
      ),
      _menuDivider(),
      _menuTile(
        icon: Icons.edit_rounded,
        title: t['tenant_menu_edit'],
        color: const Color(0xFF2563EB),
        onTap: () {
          Navigator.pop(context);
          _showEditTenantDialog(tenant);
        },
      ),
      _menuDivider(),
      _menuTile(
        icon: Icons.swap_horiz_rounded,
        title: t['tenant_menu_move_room'],
        color: const Color(0xFF0F6E56),
        onTap: () {
          Navigator.pop(context);
          _showMoveRoomDialog(tenant);
        },
      ),
      if (!isMovedOut) ...[
        _menuDivider(),
        _menuTile(
          icon: Icons.logout_rounded,
          title: t['tenant_menu_move_out'],
          color: const Color(0xFF854F0B),
          onTap: () {
            Navigator.pop(context);
            _showMoveOutDialog(tenant);
          },
        ),
      ],
      _menuDivider(),
      _menuTile(
        icon: Icons.directions_car_rounded,
        title: t['tenant_menu_vehicles'],
        subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
            ? t.textWithParams('tenant_vehicle_count',
                {'count': tenant.vehicles!.length})
            : null,
        color: const Color(0xFF534AB7),
        onTap: () {
          Navigator.pop(context);
          _showVehicleManagementDialog(tenant);
        },
      ),
      _menuDivider(),
      _menuTile(
        icon: Icons.history_rounded,
        title: t['tenant_menu_rental_history'],
        onTap: () {
          Navigator.pop(context);
          _showRentalHistoryDialog(tenant);
        },
      ),
      _menuDivider(),
      _menuTile(
        icon: Icons.delete_outline_rounded,
        title: t['tenant_menu_delete'],
        color: const Color(0xFFE74C3C),
        onTap: () {
          Navigator.pop(context);
          _confirmDeleteTenant(tenant);
        },
      ),
    ];

    // Options sheet header (not using _DialogHeader since it's a sheet)
    Widget sheetHeader = Container(
      decoration: BoxDecoration(gradient: _defaultHeaderGradient),
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                tenant.fullName.isNotEmpty
                    ? tenant.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tenant.fullName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text(tenant.phoneNumber,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );

    final sheetContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isLargeScreen) const _SheetHandle(),
        sheetHeader,
        ...menuItems,
        const SizedBox(height: 8),
      ],
    );

    if (isLargeScreen) {
      await _showTrackedDialog(
        context: context,
        builder: (context) => _DialogShell(
          maxWidth: 380,
          maxHeightFactor: 0.85,
          child: SingleChildScrollView(child: sheetContent),
        ),
      );
    } else {
      await _showTrackedBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: SingleChildScrollView(child: sheetContent),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // VEHICLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showVehicleManagementDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) => _DialogShell(
        maxWidth: 500,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return Column(
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.directions_car_rounded,
                      size: 22, color: Colors.white),
                  title: t['tenant_vehicle_manage_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 22, color: Colors.white),
                      tooltip: t['tenant_vehicle_add_tooltip'],
                      onPressed: () async {
                        try {
                          final result = await _showAddVehicleDialog();
                          if (result != null) {
                            final success = await widget.tenantService
                                .addVehicle(tenant.id, result);
                            if (success) {
                              await _refreshAll();
                              final updatedTenant = await widget
                                  .tenantService
                                  .getTenantById(tenant.id);
                              if (updatedTenant != null) {
                                setDialogState(
                                    () => tenant = updatedTenant);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                        content: Text(
                                            t['tenant_vehicle_added'])));
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                        content: Text(t[
                                            'tenant_vehicle_add_error']),
                                        backgroundColor: Colors.red));
                              }
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text(t.textWithParams(
                                  'tenant_error', {'error': e})),
                              backgroundColor: Colors.red,
                            ));
                          }
                        }
                      },
                    ),
                  ],
                ),
                Flexible(
                  child:
                      tenant.vehicles == null || tenant.vehicles!.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_car_outlined,
                                      size: 48,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(t['tenant_vehicle_empty'],
                                      style: TextStyle(
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : FutureBuilder<Tenant?>(
                              future: widget.tenantService
                                  .getTenantById(tenant.id),
                              builder: (context, snapshot) {
                                final currentTenant =
                                    snapshot.data ?? tenant;
                                return ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount:
                                      currentTenant.vehicles?.length ?? 0,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 0),
                                  itemBuilder: (context, index) {
                                    final vehicle =
                                        currentTenant.vehicles![index];
                                    return _VehicleCard(
                                      vehicle: vehicle,
                                      typeIcon:
                                          _getVehicleIcon(vehicle.type),
                                      typeLabel:
                                          _getVehicleTypeDisplayName(
                                              vehicle.type),
                                      parkingLabel: vehicle
                                                  .isParkingRegistered &&
                                              vehicle.parkingSpot != null
                                          ? t.textWithParams(
                                              'tenant_vehicle_parking_spot',
                                              {
                                                'spot':
                                                    vehicle.parkingSpot!
                                              })
                                          : null,
                                      menuItems: [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [
                                            const Icon(Icons.edit_rounded,
                                                size: 18),
                                            const SizedBox(width: 10),
                                            Text(t[
                                                'tenant_vehicle_menu_edit']),
                                          ]),
                                        ),
                                        if (!vehicle.isParkingRegistered)
                                          PopupMenuItem(
                                            value: 'parking',
                                            child: Row(children: [
                                              const Icon(
                                                  Icons
                                                      .local_parking_rounded,
                                                  size: 18),
                                              const SizedBox(width: 10),
                                              Text(t[
                                                  'tenant_vehicle_menu_register_parking']),
                                            ]),
                                          )
                                        else
                                          PopupMenuItem(
                                            value: 'unparking',
                                            child: Row(children: [
                                              const Icon(
                                                  Icons.cancel_rounded,
                                                  size: 18),
                                              const SizedBox(width: 10),
                                              Text(t[
                                                  'tenant_vehicle_menu_unregister_parking']),
                                            ]),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            Icon(
                                                Icons
                                                    .delete_outline_rounded,
                                                size: 18,
                                                color: const Color(
                                                    0xFFE74C3C)),
                                            const SizedBox(width: 10),
                                            Text(
                                                t['tenant_vehicle_menu_delete'],
                                                style: const TextStyle(
                                                    color: Color(
                                                        0xFFE74C3C))),
                                          ]),
                                        ),
                                      ],
                                      onMenuSelected: (value) async {
                                        if (value == 'edit') {
                                          final result =
                                              await _showEditVehicleDialog(
                                                  vehicle);
                                          if (result != null) {
                                            final success = await widget
                                                .tenantService
                                                .updateVehicle(tenant.id,
                                                    index, result);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(t[
                                                            'tenant_vehicle_updated'])));
                                              }
                                            }
                                          }
                                        } else if (value == 'parking') {
                                          final spot =
                                              await _showParkingSpotDialog();
                                          if (spot != null) {
                                            final success = await widget
                                                .tenantService
                                                .registerParkingSpot(
                                                    tenant.id, index, spot);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(t[
                                                            'tenant_vehicle_parking_registered'])));
                                              }
                                            }
                                          }
                                        } else if (value == 'unparking') {
                                          final success = await widget
                                              .tenantService
                                              .unregisterParkingSpot(
                                                  tenant.id, index);
                                          if (success) {
                                            await _refreshAll();
                                            setDialogState(() {});
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(t[
                                                          'tenant_vehicle_parking_unregistered'])));
                                            }
                                          }
                                        } else if (value == 'delete') {
                                          final ok =
                                              await _showConfirmDialog(
                                            title: t[
                                                'tenant_vehicle_delete_title'],
                                            message: t.textWithParams(
                                                'tenant_vehicle_delete_confirm',
                                                {
                                                  'plate':
                                                      vehicle.licensePlate
                                                }),
                                            confirmLabel: t['delete'],
                                            destructive: true,
                                          );
                                          if (ok == true) {
                                            final success = await widget
                                                .tenantService
                                                .removeVehicle(
                                                    tenant.id, index);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(t[
                                                            'tenant_vehicle_deleted'])));
                                              }
                                            }
                                          }
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await _refreshAll();
  }

  Future<VehicleInfo?> _showAddVehicleDialog() async {
    final licensePlateController = TextEditingController();
    final brandController = TextEditingController();
    final modelController = TextEditingController();
    final colorController = TextEditingController();
    VehicleType selectedType = VehicleType.motorcycle;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.add_rounded,
                        size: 22, color: Colors.white),
                    title: t['tenant_vehicle_add_title'],
                    onClose: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(
                            t['tenant_vehicle_plate_label'],
                            icon: Icons.confirmation_number_rounded,
                            color: const Color(0xFF534AB7),
                          ),
                          _inputField(
                              licensePlateController,
                              t['tenant_vehicle_plate_label'],
                              Icons.confirmation_number_rounded,
                              maxLength: 11),
                          _dropdownField<VehicleType>(
                            label: t['tenant_vehicle_type_label'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                          _getVehicleTypeDisplayName(
                                              type)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selectedType = value);
                              }
                            },
                          ),
                          _SectionLabel(
                            t['tenant_detail_personal_section'],
                            icon: Icons.info_outline_rounded,
                            color: const Color(0xFF534AB7),
                          ),
                          _inputField(
                              brandController,
                              t['tenant_vehicle_brand_label'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(
                              modelController,
                              t['tenant_vehicle_model_label'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(
                              colorController,
                              t['tenant_vehicle_color_label'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(
                    children: [
                      _ActionButton(
                          label: t['cancel'],
                          onPressed: () => Navigator.pop(context)),
                      _ActionButton(
                        label: t['tenant_vehicle_add_action'],
                        primary: true,
                        icon: Icons.add_rounded,
                        onPressed: () {
                          if (licensePlateController.text
                              .trim()
                              .isEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(t[
                                        'tenant_vehicle_plate_required'])));
                            return;
                          }
                          Navigator.pop(
                            context,
                            VehicleInfo(
                              licensePlate: licensePlateController.text
                                  .trim()
                                  .toUpperCase(),
                              type: selectedType,
                              brand: brandController.text.trim().isEmpty
                                  ? null
                                  : brandController.text.trim(),
                              model: modelController.text.trim().isEmpty
                                  ? null
                                  : modelController.text.trim(),
                              color: colorController.text.trim().isEmpty
                                  ? null
                                  : colorController.text.trim(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<VehicleInfo?> _showEditVehicleDialog(VehicleInfo vehicle) async {
    final licensePlateController =
        TextEditingController(text: vehicle.licensePlate);
    final brandController = TextEditingController(text: vehicle.brand);
    final modelController = TextEditingController(text: vehicle.model);
    final colorController = TextEditingController(text: vehicle.color);
    VehicleType selectedType = vehicle.type;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.edit_rounded,
                        size: 20, color: Colors.white),
                    title: t['tenant_vehicle_edit_title'],
                    subtitle: vehicle.licensePlate,
                    onClose: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _inputField(
                            licensePlateController,
                            t['tenant_vehicle_plate_label'],
                            Icons.confirmation_number_rounded,
                            maxLength: 12,
                          ),
                          _dropdownField<VehicleType>(
                            label: t['tenant_vehicle_type_label'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                          _getVehicleTypeDisplayName(
                                              type)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selectedType = value);
                              }
                            },
                          ),
                          _inputField(
                              brandController,
                              t['tenant_vehicle_brand_label'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(
                              modelController,
                              t['tenant_vehicle_model_label'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(
                              colorController,
                              t['tenant_vehicle_color_label'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(
                    children: [
                      _ActionButton(
                          label: t['cancel'],
                          onPressed: () => Navigator.pop(context)),
                      _ActionButton(
                        label: t['tenant_vehicle_save_action'],
                        primary: true,
                        icon: Icons.check_rounded,
                        onPressed: () {
                          if (licensePlateController.text
                              .trim()
                              .isEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(t[
                                        'tenant_vehicle_plate_required'])));
                            return;
                          }
                          Navigator.pop(
                            context,
                            VehicleInfo(
                              licensePlate: licensePlateController.text
                                  .trim()
                                  .toUpperCase(),
                              type: selectedType,
                              brand: brandController.text.trim().isEmpty
                                  ? null
                                  : brandController.text.trim(),
                              model: modelController.text.trim().isEmpty
                                  ? null
                                  : modelController.text.trim(),
                              color: colorController.text.trim().isEmpty
                                  ? null
                                  : colorController.text.trim(),
                              isParkingRegistered:
                                  vehicle.isParkingRegistered,
                              parkingSpot: vehicle.parkingSpot,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<String?> _showParkingSpotDialog() async {
    final controller = TextEditingController();
    try {
      return await _showTrackedDialog<String>(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return _DialogShell(
            maxWidth: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF085041), Color(0xFF0F6E56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.local_parking_rounded,
                      size: 22, color: Colors.white),
                  title: t['tenant_parking_register_title'],
                  onClose: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: _inputField(
                    controller,
                    t['tenant_parking_spot_label'],
                    Icons.local_parking_rounded,
                    maxLength: 10,
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_parking_register_action'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        if (controller.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                                  content: Text(t[
                                      'tenant_parking_spot_required'])));
                          return;
                        }
                        Navigator.pop(context,
                            controller.text.trim().toUpperCase());
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.bicycle:
        return Icons.pedal_bike;
      case VehicleType.electricBike:
        return Icons.electric_bike;
      case VehicleType.other:
        return Icons.local_shipping;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RENTAL HISTORY DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 480,
          child: Column(
            children: [
              _DialogHeader(
                gradient: const LinearGradient(
                  colors: [Color(0xFF633806), Color(0xFF854F0B)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                leading: const Icon(Icons.history_rounded,
                    size: 22, color: Colors.white),
                title: t['tenant_rental_history_title'],
                subtitle: tenant.fullName,
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: tenant.previousRentals == null ||
                        tenant.previousRentals!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(t['tenant_rental_history_empty'],
                                style: TextStyle(
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tenant.previousRentals!.length,
                        itemBuilder: (context, i) {
                          final r = tenant.previousRentals![i];
                          return _RentalHistoryEntry(
                            locationText: t.textWithParams(
                                'tenant_location_value', {
                              'building': r.buildingName,
                              'room': r.roomNumber,
                            }),
                            dateRangeText: t.textWithParams(
                                'tenant_detail_history_dates', {
                              'from': DateFormat.yMd()
                                  .format(r.moveInDate),
                              'to':
                                  DateFormat.yMd().format(r.moveOutDate),
                            }),
                            durationText: t.textWithParams(
                                'tenant_detail_days_value',
                                {'days': r.duration}),
                          );
                        },
                      ),
              ),
              _DialogActions(
                children: [
                  _ActionButton(
                      label: t['close'],
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EDIT TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showEditTenantDialog(Tenant tenant) async {
    await _getBuildings();
    await _getAllRooms();
    if (!mounted) return;

    final nameController = TextEditingController(text: tenant.fullName);
    final phoneController =
        TextEditingController(text: tenant.phoneNumber);
    final emailController = TextEditingController(text: tenant.email);
    final nationalIdController =
        TextEditingController(text: tenant.nationalId);
    final occupationController =
        TextEditingController(text: tenant.occupation);
    final workplaceController =
        TextEditingController(text: tenant.workplace);
    final monthlyRentController = TextEditingController(
        text: tenant.monthlyRent?.toString() ?? '');
    final areaController =
        TextEditingController(text: tenant.apartmentArea?.toString() ?? '');
    final typeController =
        TextEditingController(text: tenant.apartmentType ?? '');

    DateTime editedMoveInDate = tenant.moveInDate;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          return _DialogShell(
            maxWidth: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  leading: const Icon(Icons.edit_rounded,
                      size: 20, color: Colors.white),
                  title: t['tenant_edit_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded,
                        ),
                        _inputField(
                            nameController,
                            t['tenant_field_name'],
                            Icons.person_rounded,
                            maxLength: 100),
                        _inputField(
                          phoneController,
                          t['tenant_field_phone'],
                          Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                        ),
                        _inputField(
                            monthlyRentController,
                            t['tenant_field_rent'],
                            Icons.payments_rounded,
                            suffix: '₫',
                            keyboardType: TextInputType.number,
                            maxLength: 12),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['tenant_field_move_in_date'],
                          initialDate: editedMoveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(
                                  () => editedMoveInDate = date);
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_section_invoice_apt'],
                          icon: Icons.apartment_rounded,
                        ),
                        Row(
                          children: [
                            Expanded(
                                child: _inputField(
                                    typeController,
                                    t['tenant_field_apt_type'],
                                    Icons.category_rounded,
                                    maxLength: 50)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _inputField(
                                    areaController,
                                    t['tenant_field_area'],
                                    Icons.square_foot_rounded,
                                    suffix: 'm²',
                                    keyboardType: TextInputType.number,
                                    maxLength: 6)),
                          ],
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded,
                        ),
                        _inputField(
                            emailController,
                            t['tenant_field_email'],
                            Icons.email_rounded,
                            maxLength: 100),
                        _inputField(
                            nationalIdController,
                            t['tenant_field_national_id'],
                            Icons.badge_rounded,
                            maxLength: 12),
                        _inputField(
                            occupationController,
                            t['tenant_field_occupation'],
                            Icons.work_rounded,
                            maxLength: 100),
                        _inputField(
                            workplaceController,
                            t['tenant_field_workplace'],
                            Icons.location_city_rounded,
                            maxLength: 150),
                      ],
                    ),
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_edit_save'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        Navigator.pop(context, {
                          'fullName': nameController.text.trim(),
                          'phoneNumber': phoneController.text.trim(),
                          'email': emailController.text.trim().isEmpty
                              ? null
                              : emailController.text.trim(),
                          'nationalId': nationalIdController.text
                                  .trim()
                                  .isEmpty
                              ? null
                              : nationalIdController.text.trim(),
                          'occupation': occupationController.text
                                  .trim()
                                  .isEmpty
                              ? null
                              : occupationController.text.trim(),
                          'workplace':
                              workplaceController.text.trim().isEmpty
                                  ? null
                                  : workplaceController.text.trim(),
                          'monthlyRent': double.tryParse(
                              monthlyRentController.text.trim()),
                          'apartmentArea': double.tryParse(
                              areaController.text.trim()),
                          'apartmentType': typeController.text.trim(),
                          'moveInDate': editedMoveInDate,
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    nationalIdController.dispose();
    occupationController.dispose();
    workplaceController.dispose();
    monthlyRentController.dispose();
    areaController.dispose();
    typeController.dispose();

    if (result != null) {
      await widget.tenantService.updateTenant(tenant.id, result);
      if (!mounted) return;
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE ROOM DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showMoveRoomDialog(Tenant tenant) async {
    String? selectedBuildingId =
        tenant.buildingId.isNotEmpty ? tenant.buildingId : null;
    String? selectedRoomId =
        tenant.roomId.isNotEmpty ? tenant.roomId : null;

    final result = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = _rooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return _DialogShell(
            maxWidth: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF085041), Color(0xFF0F6E56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.swap_horiz_rounded,
                      size: 22, color: Colors.white),
                  title: t['tenant_move_room_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context, false),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(
                        t['tenant_detail_location'],
                        icon: Icons.location_on_rounded,
                        color: const Color(0xFF0F6E56),
                      ),
                      _dropdownField<String>(
                        label: t['tenant_move_room_building'],
                        value: selectedBuildingId,
                        items: _buildings
                            .map((b) => DropdownMenuItem(
                                value: b.id, child: Text(b.name)))
                            .toList(),
                        onChanged: (val) => setDialogState(() {
                          selectedBuildingId = val;
                          selectedRoomId = null;
                        }),
                      ),
                      _dropdownField<String>(
                        label: t['tenant_move_room_room'],
                        value: selectedRoomId,
                        items: availableRooms
                            .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(
                                    '${r.roomNumber} (${r.roomType})')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedRoomId = val),
                      ),
                    ],
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context, false)),
                    _ActionButton(
                      label: t['tenant_move_room_confirm'],
                      primary: true,
                      icon: Icons.swap_horiz_rounded,
                      onPressed: (selectedBuildingId == null ||
                              selectedRoomId == null)
                          ? null
                          : () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == true &&
        selectedBuildingId != null &&
        selectedRoomId != null) {
      if (selectedRoomId == tenant.roomId) return;
      final t = AppTranslations.of(context);
      final success = await widget.tenantService.moveTenantToRoom(
          tenant.id, selectedBuildingId!, selectedRoomId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? t['tenant_move_room_success']
              : t['tenant_move_room_error']),
          backgroundColor:
              success ? const Color(0xFF3B6D11) : Colors.red,
        ));
        _refreshAll();
        widget.onChanged?.call();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE OUT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showMoveOutDialog(Tenant tenant) async {
    DateTime selectedDate = DateTime.now();
    String? selectedReason;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final reasonOptions = [
            t['tenant_moveout_reason_1'],
            t['tenant_moveout_reason_2'],
            t['tenant_moveout_reason_3'],
            t['tenant_moveout_reason_4'],
            t['tenant_moveout_reason_5'],
          ];
          selectedReason ??= reasonOptions.first;

          final bool isEarly = tenant.contractEndDate != null &&
              selectedDate.isBefore(tenant.contractEndDate!);

          return _DialogShell(
            maxWidth: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF633806), Color(0xFF854F0B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.logout_rounded,
                      size: 20, color: Colors.white),
                  title: t['tenant_moveout_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_moveout_date_label'],
                          icon: Icons.info_outline_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF854F0B)
                                .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF854F0B)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            t.textWithParams('tenant_moveout_confirm',
                                {'name': tenant.fullName}),
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.calendar_today_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        LocalizedDatePicker(
                          labelText: t['tenant_moveout_date_label'],
                          initialDate: selectedDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(() => selectedDate = date);
                          },
                        ),
                        const SizedBox(height: 12),
                        _dropdownField<String>(
                          label: t['tenant_moveout_reason_label'],
                          value: selectedReason,
                          items: reasonOptions
                              .map((reason) => DropdownMenuItem(
                                  value: reason, child: Text(reason)))
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => selectedReason = value),
                        ),
                        if (isEarly) ...[
                          const SizedBox(height: 4),
                          _InfoBanner(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFF854F0B),
                            text: t.textWithParams(
                                'tenant_moveout_early_warning', {
                              'days': tenant.contractEndDate!
                                  .difference(selectedDate)
                                  .inDays
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_moveout_confirm_action'],
                      primary: true,
                      icon: Icons.logout_rounded,
                      onPressed: () => Navigator.pop(context, {
                        'date': selectedDate,
                        'reason': selectedReason,
                      }),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result != null) {
      final t = AppTranslations.of(context);
      final success = await widget.tenantService.markTenantAsMovedOut(
        tenant.id,
        moveOutDate: result['date'],
        moveOutReason: result['reason'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_moveout_success']
            : t['tenant_moveout_failed']),
        backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
      ));
      await _refreshAll();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIRM DIALOG (generic reusable)
  // ═══════════════════════════════════════════════════════════════
  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return _showTrackedDialog<bool>(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                gradient: destructive
                    ? const LinearGradient(
                        colors: [Color(0xFF7F1D1D), Color(0xFFDC2626)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : _defaultHeaderGradient,
                leading: Icon(
                  destructive
                      ? Icons.warning_amber_rounded
                      : Icons.help_outline_rounded,
                  size: 22,
                  color: Colors.white,
                ),
                title: title,
                onClose: () => Navigator.pop(context, false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: destructive
                        ? const Color(0xFFDC2626).withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: destructive
                          ? const Color(0xFFDC2626).withValues(alpha: 0.2)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _DialogActions(
                children: [
                  _ActionButton(
                      label: t['cancel'],
                      onPressed: () => Navigator.pop(context, false)),
                  _ActionButton(
                    label: confirmLabel,
                    destructive: destructive,
                    icon: destructive
                        ? Icons.delete_outline_rounded
                        : null,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE TENANT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final t = AppTranslations.of(context);
    final ok = await _showConfirmDialog(
      title: t['tenant_delete_title'],
      message: t.textWithParams(
          'tenant_delete_confirm', {'name': tenant.fullName}),
      confirmLabel: t['delete'],
      destructive: true,
    );

    if (ok == true) {
      final success =
          await widget.tenantService.deleteTenant(tenant.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_delete_success']
            : t['tenant_delete_failed']),
        backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
      ));
      await _refreshAll();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ADD TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showAddTenantDialog(
      List<Building> buildings, List<Room> allRooms) async {
    final Set<String> occupiedRoomIds = _allTenants
        .where((t) => t.status == TenantStatus.active && t.isMainTenant)
        .map((t) => t.roomId)
        .toSet();

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final nationalIdController = TextEditingController();
    final occupationController = TextEditingController();
    final workplaceController = TextEditingController();
    final monthlyRentController = TextEditingController();
    final areaController = TextEditingController();
    final typeController = TextEditingController();

    String? selectedBuildingId =
        buildings.isNotEmpty ? buildings.first.id : null;
    String? selectedRoomId;
    TenantStatus selectedStatus = TenantStatus.active;
    bool isMainTenant = true;
    DateTime moveInDate = DateTime.now();

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = allRooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return _DialogShell(
            maxWidth: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  leading: const Icon(Icons.person_add_rounded,
                      size: 20, color: Colors.white),
                  title: t['tenant_add_title'],
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded,
                        ),
                        _inputField(
                            nameController,
                            t['tenant_field_name_required'],
                            Icons.person_rounded,
                            maxLength: 100),
                        _inputField(
                          phoneController,
                          t['tenant_field_phone_required'],
                          Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                        ),
                        const _ContentDivider(),

                        _SectionLabel(
                          t['tenant_detail_location'],
                          icon: Icons.location_on_rounded,
                        ),
                        _dropdownField<String>(
                          label: t['tenant_field_building'],
                          value: selectedBuildingId,
                          items: buildings
                              .map((b) => DropdownMenuItem(
                                  value: b.id, child: Text(b.name)))
                              .toList(),
                          onChanged: (val) => setDialogState(() {
                            selectedBuildingId = val;
                            selectedRoomId = null;
                          }),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            value: selectedRoomId,
                            decoration: InputDecoration(
                              labelText: t['tenant_field_room'],
                              labelStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFF2563EB), width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                            ),
                            items: availableRooms.map((room) {
                              final bool isOccupied =
                                  occupiedRoomIds.contains(room.id);
                              return DropdownMenuItem(
                                value: room.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(
                                          right: 8),
                                      decoration: BoxDecoration(
                                        color: isOccupied
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF3B6D11),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Text(
                                      t.textWithParams(
                                          isOccupied
                                              ? 'tenant_room_occupied'
                                              : 'tenant_room_vacant',
                                          {'number': room.roomNumber}),
                                      style: TextStyle(
                                        color: isOccupied
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF3B6D11),
                                        fontWeight: isOccupied
                                            ? FontWeight.normal
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              final room = allRooms
                                  .firstWhere((r) => r.id == val);
                              setDialogState(() {
                                selectedRoomId = val;
                                areaController.text =
                                    room.area.toString();
                                typeController.text = room.roomType;
                              });
                            },
                          ),
                        ),

                        Row(
                          children: [
                            Expanded(
                              child: _dropdownField<TenantStatus>(
                                label: t['tenant_field_status'],
                                value: selectedStatus,
                                items: TenantStatus.values.map((s) {
                                  String label =
                                      t['tenant_status_active'];
                                  if (s == TenantStatus.inactive)
                                    label = t['tenant_status_inactive'];
                                  if (s == TenantStatus.moveOut)
                                    label =
                                        t['tenant_status_moved_out'];
                                  return DropdownMenuItem(
                                      value: s, child: Text(label));
                                }).toList(),
                                onChanged: (val) => setDialogState(
                                    () => selectedStatus = val!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isMainTenant,
                                    activeColor: const Color(0xFF2563EB),
                                    onChanged: (val) => setDialogState(
                                        () => isMainTenant = val ?? true),
                                  ),
                                  Flexible(
                                    child: Text(
                                        t['tenant_field_main_tenant'],
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.payments_rounded,
                        ),
                        _inputField(
                            monthlyRentController,
                            t['tenant_field_rent_required'],
                            Icons.payments_rounded,
                            suffix: '₫',
                            keyboardType: TextInputType.number,
                            maxLength: 12),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['tenant_field_move_in_date'],
                          initialDate: moveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(() => moveInDate = date);
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_section_invoice_apt'],
                          icon: Icons.apartment_rounded,
                        ),
                        Row(
                          children: [
                            Expanded(
                                child: _inputField(
                                    typeController,
                                    t['tenant_field_apt_type'],
                                    Icons.category_rounded,
                                    maxLength: 50)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _inputField(
                                    areaController,
                                    t['tenant_field_area'],
                                    Icons.square_foot_rounded,
                                    suffix: 'm²',
                                    keyboardType: TextInputType.number,
                                    maxLength: 6)),
                          ],
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded,
                        ),
                        _inputField(
                            emailController,
                            t['tenant_field_email'],
                            Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 100),
                        _inputField(
                            nationalIdController,
                            t['tenant_field_national_id'],
                            Icons.badge_rounded,
                            maxLength: 12),
                        _inputField(
                            occupationController,
                            t['tenant_field_occupation'],
                            Icons.work_rounded,
                            maxLength: 100),
                        _inputField(
                            workplaceController,
                            t['tenant_field_workplace'],
                            Icons.location_city_rounded,
                            maxLength: 150),
                      ],
                    ),
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_add_action'],
                      primary: true,
                      icon: Icons.person_add_rounded,
                      onPressed: () {
                        if (nameController.text.isEmpty ||
                            selectedRoomId == null) return;
                        Navigator.pop(context, {
                          'fullName': nameController.text.trim(),
                          'phoneNumber': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'nationalId': nationalIdController.text.trim(),
                          'occupation':
                              occupationController.text.trim(),
                          'workplace': workplaceController.text.trim(),
                          'buildingId': selectedBuildingId,
                          'roomId': selectedRoomId,
                          'monthlyRent':
                              double.tryParse(
                                  monthlyRentController.text) ??
                              0,
                          'apartmentArea':
                              double.tryParse(areaController.text) ?? 0,
                          'apartmentType': typeController.text.trim(),
                          'isMainTenant': isMainTenant,
                          'status': selectedStatus,
                          'moveInDate': moveInDate,
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    nationalIdController.dispose();
    occupationController.dispose();
    workplaceController.dispose();
    monthlyRentController.dispose();
    areaController.dispose();
    typeController.dispose();

    if (result != null) {
      final tenant = Tenant(
        id: '',
        organizationId: widget.organization.id,
        buildingId: result['buildingId'],
        roomId: result['roomId'],
        fullName: result['fullName'],
        phoneNumber: result['phoneNumber'],
        email: result['email'],
        nationalId: result['nationalId'],
        occupation: result['occupation'],
        workplace: result['workplace'],
        isMainTenant: result['isMainTenant'],
        monthlyRent: result['monthlyRent'],
        apartmentArea: result['apartmentArea'],
        apartmentType: result['apartmentType'],
        status: result['status'],
        moveInDate: result['moveInDate'],
        createdAt: DateTime.now(),
      );
      await widget.tenantService.addTenant(tenant);
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:
        return const Color(0xFF3B6D11);
      case TenantStatus.inactive:
        return const Color(0xFF854F0B);
      case TenantStatus.moveOut:
        return Colors.blueGrey.shade600;
      case TenantStatus.suspended:
        return const Color(0xFFDC2626);
    }
  }
}