import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/screens/payment/delete_payment_dialog.dart';
import 'package:apartment_management_project_2/screens/payment/payment_dialog.dart';
import 'package:apartment_management_project_2/screens/payment/payment_pdf_export.dart';
import 'package:apartment_management_project_2/screens/payment/view_edit_dialogs.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/payments_notifier.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// ─── Gradient presets ─────────────────────────────────────────────────────────
const LinearGradient _kDefaultHeaderGradient = LinearGradient(
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

// ─── Dialog header ────────────────────────────────────────────────────────────
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
      decoration: BoxDecoration(gradient: gradient ?? _kDefaultHeaderGradient),
      child: Row(
        children: [
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
                  Text(subtitle!,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ],
            ),
          ),
          if (actions != null)
            ...actions!.map((a) => Theme(
                  data: Theme.of(context).copyWith(
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                    iconTheme: const IconThemeData(color: Colors.white70),
                  ),
                  child: a,
                )),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────
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
                Text(label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: disabled ? Colors.grey.shade500 : Colors.white,
                    )),
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
                Text(label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE74C3C),
                    )),
              ],
            ),
          ),
        ),
      );
    }

    // Secondary / cancel
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
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  )),
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
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
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

// ─── Section label ────────────────────────────────────────────────────────────
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
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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

// ─── Detail card ──────────────────────────────────────────────────────────────
class _DetailCard extends StatelessWidget {
  final List<Widget> rows;
  final Color? borderColor;
  final Color? fillColor;

  const _DetailCard({required this.rows, this.borderColor, this.fillColor});

  @override
  Widget build(BuildContext context) => Container(
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

// ─── Content divider ──────────────────────────────────────────────────────────
class _ContentDivider extends StatelessWidget {
  const _ContentDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1, color: Colors.grey.shade100),
      );
}

// ─── Info banner ──────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _InfoBanner({required this.text, required this.color, required this.icon});

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
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
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
                  Text(vehicle.licensePlate,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF26215C),
                      )),
                  const SizedBox(height: 2),
                  Text(
                    [typeLabel, vehicle.brand, vehicle.model]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF534AB7)),
                  ),
                  if (parkingLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.local_parking_rounded,
                          size: 12, color: Color(0xFF0F6E56)),
                      const SizedBox(width: 4),
                      Text(parkingLabel!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF0F6E56))),
                    ]),
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
          border: Border.all(color: const Color(0xFFF0C97A).withValues(alpha: 0.6)),
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
                  Text(locationText,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF412402))),
                  const SizedBox(height: 3),
                  Text(dateRangeText,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF854F0B))),
                  Text(durationText,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─── Input field ──────────────────────────────────────────────────────────────
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

// ═════════════════════════════════════════════════════════════════════════════
// ROOM DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class RoomDetailScreen extends StatefulWidget {
  final Room room;
  final Organization organization;
  final TenantService tenantService = getIt<TenantService>();
  final BuildingService buildingService = getIt<BuildingService>();
  final RoomService roomService = getIt<RoomService>();
  final OrganizationService organizationService = getIt<OrganizationService>();
  final AuthService authService = getIt<AuthService>();
  final PaymentService paymentService = getIt<PaymentService>();
  final PaymentsNotifier paymentsNotifier = getIt<PaymentsNotifier>();

  RoomDetailScreen({Key? key, required this.room, required this.organization})
      : super(key: key);

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _overlayCount = 0;

  bool _isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  double _getDialogWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 600) return w * 0.95;
    if (w < 1200) return 600;
    return 800;
  }

  Widget _buildMinimumSizeWarning(BuildContext context, BoxConstraints c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text('Kích thước cửa sổ quá nhỏ',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Kích thước tối thiểu: 360x600',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Hiện tại: ${c.maxWidth.toInt()}x${c.maxHeight.toInt()}',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  late TabController _tabController;
  StreamSubscription<List<Tenant>>? _tenantSubscription;
  List<Tenant>? _tenants;
  bool _isLoadingTenants = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _initializeStreams();
    widget.paymentsNotifier
        .loadRoomPayments(widget.room.id, widget.organization.id);
  }

  void _initializeStreams() {
    _tenantSubscription = widget.tenantService
        .streamRoomTenants(widget.room.id, widget.organization.id)
        .listen(
      (tenants) {
        if (mounted) setState(() { _tenants = tenants; _isLoadingTenants = false; });
      },
      onError: (error) {
        debugPrint('❌ Firestore Error: $error');
        if (mounted) {
          setState(() { _isLoadingTenants = false; _tenants = []; });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi tải dữ liệu: $error')));
        }
      },
    );
  }

  String? get _userId => widget.authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);
    return widget.organizationService.getUserMembership(
        _userId!, widget.organization.id);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _tenantSubscription?.cancel();
    _resizeDebounceTimer?.cancel();
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
      final w = MediaQuery.sizeOf(context).width;
      final h = MediaQuery.sizeOf(context).height;
      if (w < 360 || h < 600) _dismissAllOverlays();
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
          builder: builder);
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
  }) async {
    _overlayCount++;
    try {
      return await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: isScrollControlled,
          shape: shape,
          builder: builder);
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  // ─── Format helpers ───────────────────────────────────────────────────────
  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _formatCurrency(double amount) {
    final f = NumberFormat('#,###', 'vi_VN');
    return '${f.format(amount)} ₫';
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(1)}B';
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
    return amount.toStringAsFixed(0);
  }

  // ─── Generic confirm dialog ───────────────────────────────────────────────
  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return _showTrackedDialog<bool>(
      context: context,
      builder: (context) => _DialogShell(
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
                  : _kDefaultHeaderGradient,
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
                child: Text(message,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              ),
            ),
            const SizedBox(height: 8),
            _DialogActions(children: [
              _ActionButton(
                  label: 'Hủy',
                  onPressed: () => Navigator.pop(context, false)),
              _ActionButton(
                label: confirmLabel,
                destructive: destructive,
                icon: destructive ? Icons.delete_outline_rounded : null,
                onPressed: () => Navigator.pop(context, true),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ADD / EDIT TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showAddEditTenantDialog({Tenant? tenant}) {
    final isEditing = tenant != null;
    final nameController = TextEditingController(text: tenant?.fullName ?? '');
    final phoneController =
        TextEditingController(text: tenant?.phoneNumber ?? '');
    final emailController = TextEditingController(text: tenant?.email ?? '');
    final nationalIdController =
        TextEditingController(text: tenant?.nationalId ?? '');
    final occupationController =
        TextEditingController(text: tenant?.occupation ?? '');
    final workplaceController =
        TextEditingController(text: tenant?.workplace ?? '');
    final rentController =
        TextEditingController(text: tenant?.monthlyRent?.toString() ?? '');
    final depositController =
        TextEditingController(text: tenant?.deposit?.toString() ?? '');
    final areaController =
        TextEditingController(text: tenant?.apartmentArea?.toString() ?? '');
    final typeController =
        TextEditingController(text: tenant?.apartmentType ?? '');

    Gender? selectedGender = tenant?.gender;
    bool isMainTenant = tenant?.isMainTenant ?? (_tenants?.isEmpty ?? true);
    DateTime moveInDate = tenant?.moveInDate ?? DateTime.now();
    DateTime? contractStartDate = tenant?.contractStartDate;
    DateTime? contractEndDate = tenant?.contractEndDate;
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => _DialogShell(
        maxWidth: 520,
        child: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                gradient: isEditing
                    ? const LinearGradient(
                        colors: [Color(0xFF633806), Color(0xFFBA7517)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : _kDefaultHeaderGradient,
                leading: Icon(
                  isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                title: isEditing ? 'Chỉnh sửa người thuê' : 'Thêm người thuê',
                subtitle: isEditing ? tenant!.fullName : null,
                onClose: isSaving ? () {} : () => Navigator.pop(dialogContext),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('Thông tin liên hệ',
                          icon: Icons.contact_phone_rounded),
                      _inputField(nameController, 'Họ và tên *',
                          Icons.person_rounded,
                          maxLength: 100),
                      _inputField(phoneController, 'Số điện thoại *',
                          Icons.phone_rounded,
                          keyboardType: TextInputType.phone, maxLength: 20),
                      _inputField(rentController, 'Tiền thuê hàng tháng',
                          Icons.payments_rounded,
                          suffix: '₫',
                          keyboardType: TextInputType.number,
                          maxLength: 20),
                      const SizedBox(height: 4),
                      LocalizedDatePicker(
                        labelText: 'Ngày vào ở',
                        initialDate: moveInDate,
                        required: true,
                        prefixIcon: Icons.calendar_today_rounded,
                        onDateChanged: (date) {
                          if (date != null)
                            setDialogState(() => moveInDate = date);
                        },
                      ),
                      const _ContentDivider(),
                      const _SectionLabel('Thông tin căn hộ',
                          icon: Icons.apartment_rounded),
                      Row(children: [
                        Expanded(
                            child: _inputField(typeController, 'Loại căn hộ',
                                Icons.category_rounded,
                                maxLength: 50)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _inputField(areaController, 'Diện tích',
                                Icons.square_foot_rounded,
                                suffix: 'm²',
                                keyboardType: TextInputType.number,
                                maxLength: 10)),
                      ]),
                      const _ContentDivider(),
                      const _SectionLabel('Thông tin cá nhân',
                          icon: Icons.person_rounded),
                      _inputField(emailController, 'Email', Icons.email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          maxLength: 254),
                      _inputField(nationalIdController, 'CMND/CCCD',
                          Icons.badge_rounded,
                          maxLength: 20),
                      _inputField(occupationController, 'Nghề nghiệp',
                          Icons.work_rounded,
                          maxLength: 100),
                      _inputField(workplaceController, 'Nơi làm việc',
                          Icons.location_city_rounded,
                          maxLength: 150),
                      _dropdownField<Gender>(
                        label: 'Giới tính',
                        value: selectedGender,
                        items: Gender.values
                            .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(_getGenderDisplayName(g))))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedGender = v),
                      ),
                      const _ContentDivider(),
                      const _SectionLabel('Hợp đồng & cọc',
                          icon: Icons.description_rounded),
                      _inputField(depositController, 'Tiền cọc',
                          Icons.account_balance_wallet_rounded,
                          suffix: '₫',
                          keyboardType: TextInputType.number,
                          maxLength: 20),
                      // Main tenant checkbox
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: CheckboxListTile(
                          title: const Text('Người thuê chính',
                              style: TextStyle(fontSize: 14)),
                          value: isMainTenant,
                          activeColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          onChanged: (v) =>
                              setDialogState(() => isMainTenant = v ?? true),
                        ),
                      ),
                      // Contract start
                      _ContractDateTile(
                        label: 'Ngày bắt đầu hợp đồng',
                        icon: Icons.description_rounded,
                        date: contractStartDate,
                        formatDate: _formatDate,
                        onPick: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: contractStartDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null)
                            setDialogState(() => contractStartDate = d);
                        },
                        onClear: () =>
                            setDialogState(() => contractStartDate = null),
                      ),
                      const SizedBox(height: 8),
                      // Contract end
                      _ContractDateTile(
                        label: 'Ngày kết thúc hợp đồng',
                        icon: Icons.event_busy_rounded,
                        date: contractEndDate,
                        formatDate: _formatDate,
                        onPick: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: contractEndDate ??
                                DateTime.now()
                                    .add(const Duration(days: 365)),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null)
                            setDialogState(() => contractEndDate = d);
                        },
                        onClear: () =>
                            setDialogState(() => contractEndDate = null),
                      ),
                    ],
                  ),
                ),
              ),
              _DialogActions(children: [
                _ActionButton(
                    label: 'Hủy',
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext)),
                _ActionButton(
                  label: isEditing ? 'Lưu thay đổi' : 'Thêm người thuê',
                  primary: true,
                  icon: isEditing ? Icons.check_rounded : Icons.person_add_rounded,
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Vui lòng nhập họ tên')));
                            return;
                          }
                          if (phoneController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Vui lòng nhập số điện thoại')));
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final newTenant = Tenant(
                              id: tenant?.id ?? '',
                              organizationId: widget.room.organizationId,
                              buildingId: widget.room.buildingId,
                              roomId: widget.room.id,
                              fullName: nameController.text.trim(),
                              phoneNumber: phoneController.text.trim(),
                              email: emailController.text.trim().isEmpty
                                  ? null
                                  : emailController.text.trim(),
                              nationalId:
                                  nationalIdController.text.trim().isEmpty
                                      ? null
                                      : nationalIdController.text.trim(),
                              occupation:
                                  occupationController.text.trim().isEmpty
                                      ? null
                                      : occupationController.text.trim(),
                              workplace:
                                  workplaceController.text.trim().isEmpty
                                      ? null
                                      : workplaceController.text.trim(),
                              gender: selectedGender,
                              isMainTenant: isMainTenant,
                              monthlyRent: rentController.text.isNotEmpty
                                  ? double.tryParse(rentController.text)
                                  : null,
                              deposit: depositController.text.isNotEmpty
                                  ? double.tryParse(depositController.text)
                                  : null,
                              apartmentArea: areaController.text.isNotEmpty
                                  ? double.tryParse(areaController.text)
                                  : null,
                              apartmentType:
                                  typeController.text.trim().isEmpty
                                      ? null
                                      : typeController.text.trim(),
                              moveInDate: moveInDate,
                              contractStartDate: contractStartDate,
                              contractEndDate: contractEndDate,
                              status: TenantStatus.active,
                              createdAt: tenant?.createdAt ?? DateTime.now(),
                            );

                            if (isEditing) {
                              await widget.tenantService.updateTenant(
                                  tenant!.id, {
                                'fullName': newTenant.fullName,
                                'phoneNumber': newTenant.phoneNumber,
                                'email': newTenant.email,
                                'nationalId': newTenant.nationalId,
                                'occupation': newTenant.occupation,
                                'workplace': newTenant.workplace,
                                'gender': newTenant.gender?.name,
                                'isMainTenant': newTenant.isMainTenant,
                                'monthlyRent': newTenant.monthlyRent,
                                'deposit': newTenant.deposit,
                                'apartmentArea': newTenant.apartmentArea,
                                'apartmentType': newTenant.apartmentType,
                                'moveInDate': newTenant.moveInDate,
                                'contractStartDate':
                                    newTenant.contractStartDate,
                                'contractEndDate': newTenant.contractEndDate,
                              });
                              if (mounted) {
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Cập nhật người thuê thành công')));
                              }
                            } else {
                              await widget.tenantService.addTenant(newTenant);
                              if (mounted) {
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Thêm người thuê thành công')));
                              }
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Lỗi: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _getGenderDisplayName(Gender g) {
    switch (g) {
      case Gender.male: return 'Nam';
      case Gender.female: return 'Nữ';
      case Gender.other: return 'Khác';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT DETAIL DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showTenantDetailDialog(Tenant tenant) async {
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;
    final accentColor =
        isMovedOut ? Colors.grey.shade600 : const Color(0xFF185FA5);
    final gradient = isMovedOut
        ? LinearGradient(
            colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade500],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : _kDefaultHeaderGradient;

    final building =
        await widget.buildingService.getBuildingById(tenant.buildingId);
    final buildingName = building?.name ?? 'Không xác định';
    if (!mounted) return;

    final membership = await _getMyMembership();
    if (!mounted) return;

    _showTrackedDialog(
      context: context,
      builder: (context) => _DialogShell(
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
                        color: Colors.white),
                  ),
                ),
              ),
              title: tenant.fullName,
              subtitle: tenant.isMainTenant ? 'Chủ phòng' : tenant.phoneNumber,
              actions: membership?.role == 'admin'
                  ? [
                      TextButton.icon(
                        icon: const Icon(Icons.more_horiz_rounded, size: 16),
                        label: const Text('Tùy chọn'),
                        onPressed: () {
                          Navigator.pop(context);
                          _showTenantOptionsMenu(tenant);
                        },
                      ),
                    ]
                  : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                        isMovedOut ? 'Vị trí trước đây' : 'Vị trí',
                        color: accentColor,
                        icon: Icons.location_on_rounded),
                    _DetailCard(
                      borderColor: accentColor.withValues(alpha: 0.2),
                      fillColor: accentColor.withValues(alpha: 0.05),
                      rows: [
                        _DetailRow('Toà nhà', buildingName),
                        _DetailRow('Phòng', widget.room.roomNumber),
                      ],
                    ),
                    const _ContentDivider(),
                    const _SectionLabel('Thông tin liên hệ',
                        icon: Icons.contact_phone_rounded),
                    _DetailCard(rows: [
                      _DetailRow('Số điện thoại', tenant.phoneNumber),
                      if (tenant.email != null)
                        _DetailRow('Email', tenant.email!),
                    ]),
                    const _ContentDivider(),
                    const _SectionLabel('Thông tin cá nhân',
                        icon: Icons.person_rounded),
                    _DetailCard(rows: [
                      if (tenant.gender != null)
                        _DetailRow('Giới tính', tenant.getGenderDisplayName()!),
                      if (tenant.nationalId != null)
                        _DetailRow('CMND/CCCD', tenant.nationalId!),
                      if (tenant.occupation != null)
                        _DetailRow('Nghề nghiệp', tenant.occupation!),
                      if (tenant.workplace != null)
                        _DetailRow('Nơi làm việc', tenant.workplace!),
                    ]),
                    if (!isMovedOut) ...[
                      const _ContentDivider(),
                      const _SectionLabel('Thông tin thuê',
                          icon: Icons.home_rounded),
                      _DetailCard(rows: [
                        _DetailRow('Ngày vào ở', _formatDate(tenant.moveInDate)),
                        _DetailRow('Số ngày ở', '${tenant.daysLiving} ngày'),
                        if (tenant.monthlyRent != null)
                          _DetailRow('Tiền thuê',
                              _formatCurrency(tenant.monthlyRent!),
                              valueColor: const Color(0xFF3B6D11)),
                        if (tenant.deposit != null)
                          _DetailRow('Tiền cọc',
                              _formatCurrency(tenant.deposit!)),
                        if (tenant.apartmentType != null &&
                            tenant.apartmentType!.isNotEmpty)
                          _DetailRow('Loại căn hộ', tenant.apartmentType!),
                        if (tenant.apartmentArea != null &&
                            tenant.apartmentArea! > 0)
                          _DetailRow('Diện tích',
                              '${tenant.apartmentArea} m²'),
                      ]),
                    ],
                    if (isMovedOut && tenant.moveOutDate != null) ...[
                      const _ContentDivider(),
                      _SectionLabel('Thông tin chuyển đi',
                          icon: Icons.logout_rounded,
                          color: const Color(0xFF854F0B)),
                      _DetailCard(
                        borderColor:
                            const Color(0xFF854F0B).withValues(alpha: 0.2),
                        fillColor:
                            const Color(0xFF854F0B).withValues(alpha: 0.04),
                        rows: [
                          _DetailRow('Ngày chuyển đi',
                              _formatDate(tenant.moveOutDate!)),
                          _DetailRow('Thời gian ở',
                              '${tenant.moveOutDate!.difference(tenant.moveInDate).inDays} ngày'),
                          if (tenant.contractTerminationReason != null)
                            _DetailRow('Lý do',
                                tenant.contractTerminationReason!),
                          if (tenant.notes != null &&
                              tenant.notes!.isNotEmpty)
                            _DetailRow('Ghi chú', tenant.notes!),
                        ],
                      ),
                    ],
                    if (tenant.contractStartDate != null ||
                        tenant.contractEndDate != null) ...[
                      const _ContentDivider(),
                      const _SectionLabel('Hợp đồng',
                          icon: Icons.description_rounded),
                      _DetailCard(rows: [
                        if (tenant.contractStartDate != null)
                          _DetailRow('Bắt đầu',
                              _formatDate(tenant.contractStartDate!)),
                        if (tenant.contractEndDate != null)
                          _DetailRow(
                              isMovedOut
                                  ? 'Ngày kết thúc hợp đồng'
                                  : 'Kết thúc',
                              _formatDate(tenant.contractEndDate!)),
                        if (isMovedOut) ...[
                          _DetailRow('Trạng thái hợp đồng',
                              tenant.getContractStatusDisplayName()),
                          if (tenant.moveOutDate != null &&
                              tenant.contractEndDate != null)
                            _DetailRow(
                              tenant.moveOutDate!
                                      .isBefore(tenant.contractEndDate!)
                                  ? 'Chấm dứt sớm'
                                  : 'Kết thúc',
                              tenant.moveOutDate!
                                      .isBefore(tenant.contractEndDate!)
                                  ? '${tenant.contractEndDate!.difference(tenant.moveOutDate!).inDays} ngày trước hạn'
                                  : 'Đúng thời hạn',
                              valueColor: tenant.moveOutDate!
                                      .isBefore(tenant.contractEndDate!)
                                  ? const Color(0xFF854F0B)
                                  : const Color(0xFF3B6D11),
                            ),
                        ] else if (tenant.daysUntilContractEnd != null)
                          _DetailRow('Còn lại',
                              '${tenant.daysUntilContractEnd} ngày'),
                      ]),
                    ],
                    if (tenant.vehicles != null &&
                        tenant.vehicles!.isNotEmpty) ...[
                      const _ContentDivider(),
                      _SectionLabel(
                          'Phương tiện (${tenant.vehicles!.length})',
                          icon: Icons.directions_car_rounded,
                          color: const Color(0xFF534AB7)),
                      ...tenant.vehicles!.map((v) => _VehicleCard(
                            vehicle: v,
                            typeIcon: _getVehicleIcon(v.type),
                            typeLabel: _getVehicleTypeDisplayName(v.type),
                            parkingLabel: v.isParkingRegistered &&
                                    v.parkingSpot != null
                                ? 'Bãi đỗ: ${v.parkingSpot}'
                                : null,
                            menuItems: const [],
                            onMenuSelected: (_) {},
                          )),
                    ],
                    if (tenant.previousRentals != null &&
                        tenant.previousRentals!.isNotEmpty) ...[
                      const _ContentDivider(),
                      _SectionLabel(
                          'Lịch sử thuê (${tenant.previousRentals!.length})',
                          icon: Icons.history_rounded,
                          color: const Color(0xFF854F0B)),
                      ...tenant.previousRentals!.map((r) =>
                          _RentalHistoryEntry(
                            locationText:
                                '${r.buildingName} - Phòng ${r.roomNumber}',
                            dateRangeText:
                                'Từ ${_formatDate(r.moveInDate)} đến ${_formatDate(r.moveOutDate)}',
                            durationText: '${r.duration} ngày',
                          )),
                    ],
                    const _ContentDivider(),
                    _DetailRow(
                      'Trạng thái',
                      tenant.getStatusDisplayName(),
                      valueColor: _getTenantStatusColor(tenant.status),
                    ),
                  ],
                ),
              ),
            ),
            _DialogActions(children: [
              _ActionButton(
                  label: 'Đóng',
                  onPressed: () => Navigator.pop(context)),
            ]),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT OPTIONS MENU
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showTenantOptionsMenu(Tenant tenant) async {
    final isMovedOut = tenant.status == TenantStatus.moveOut;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    Widget menuTile({
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

    Widget menuDivider() => Divider(
        height: 1, indent: 20, endIndent: 20, color: Colors.grey.shade100);

    final menuItems = [
      menuTile(
          icon: Icons.info_outline_rounded,
          title: 'Xem chi tiết',
          onTap: () {
            Navigator.pop(context);
            _showTenantDetailDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.edit_rounded,
          title: 'Chỉnh sửa thông tin',
          color: const Color(0xFF2563EB),
          onTap: () {
            Navigator.pop(context);
            _showAddEditTenantDialog(tenant: tenant);
          }),
      menuDivider(),
      if (!isMovedOut) ...[
        menuTile(
            icon: Icons.logout_rounded,
            title: 'Đánh dấu đã chuyển đi',
            color: const Color(0xFF854F0B),
            onTap: () {
              Navigator.pop(context);
              _confirmMoveOut(tenant);
            }),
        menuDivider(),
      ],
      menuTile(
          icon: Icons.directions_car_rounded,
          title: 'Quản lý phương tiện',
          subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
              ? '${tenant.vehicles!.length} phương tiện'
              : null,
          color: const Color(0xFF534AB7),
          onTap: () {
            Navigator.pop(context);
            _showVehicleManagementDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.history_rounded,
          title: 'Lịch sử thuê phòng',
          onTap: () {
            Navigator.pop(context);
            _showRentalHistoryDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.delete_outline_rounded,
          title: 'Xóa người thuê',
          color: const Color(0xFFE74C3C),
          onTap: () {
            Navigator.pop(context);
            _confirmDeleteTenant(tenant);
          }),
    ];

    // Header widget
    Widget sheetHeader = Container(
      decoration: const BoxDecoration(gradient: _kDefaultHeaderGradient),
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
                BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) =>
            SafeArea(child: SingleChildScrollView(child: sheetContent)),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE OUT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmMoveOut(Tenant tenant) async {
    DateTime selectedDate = DateTime.now();
    String? selectedReason = 'Chuyển đi';
    final reasonOptions = [
      'Chuyển đi',
      'Hết hạn hợp đồng',
      'Chấm dứt hợp đồng sớm',
      'Vi phạm hợp đồng',
      'Khác',
    ];

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool isEarly = tenant.contractEndDate != null &&
              selectedDate.isBefore(tenant.contractEndDate!);
          return _DialogShell(
            maxWidth: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DialogHeader(
                  gradient: LinearGradient(
                    colors: [Color(0xFF633806), Color(0xFF854F0B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: Icon(Icons.logout_rounded,
                      size: 20, color: Colors.white),
                  title: 'Đánh dấu đã chuyển đi',
                  onClose: _doNothing,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('Xác nhận',
                            icon: Icons.info_outline_rounded,
                            color: const Color(0xFF854F0B)),
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
                            'Đánh dấu ${tenant.fullName} là đã chuyển đi?',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LocalizedDatePicker(
                          labelText: 'Ngày chuyển đi',
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
                          label: 'Lý do',
                          value: selectedReason,
                          items: reasonOptions
                              .map((r) => DropdownMenuItem(
                                  value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedReason = v),
                        ),
                        if (isEarly) ...[
                          const SizedBox(height: 4),
                          _InfoBanner(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFF854F0B),
                            text:
                                'Chấm dứt sớm ${tenant.contractEndDate!.difference(selectedDate).inDays} ngày so với hợp đồng',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: 'Hủy',
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: 'Xác nhận',
                    primary: true,
                    icon: Icons.logout_rounded,
                    onPressed: () => Navigator.pop(context, {
                      'date': selectedDate,
                      'reason': selectedReason,
                    }),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );

    if (result != null) {
      final success = await widget.tenantService.markTenantAsMovedOut(
        tenant.id,
        moveOutDate: result['date'],
        moveOutReason: result['reason'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              success ? 'Đã đánh dấu chuyển đi' : 'Thất bại'),
          backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE TENANT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final ok = await _showConfirmDialog(
      title: 'Xóa người thuê',
      message:
          'Bạn có chắc muốn xóa người thuê "${tenant.fullName}"?\n\nThao tác này không thể hoàn tác.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (ok == true) {
      final success = await widget.tenantService.deleteTenant(tenant.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Đã xóa người thuê thành công'
              : 'Không thể xóa người thuê'),
          backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
        ));
      }
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
          builder: (context, setDialogState) => Column(
            children: [
              _DialogHeader(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                leading: const Icon(Icons.directions_car_rounded,
                    size: 22, color: Colors.white),
                title: 'Quản lý phương tiện',
                subtitle: tenant.fullName,
                onClose: () => Navigator.pop(context),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded,
                        size: 22, color: Colors.white),
                    tooltip: 'Thêm phương tiện',
                    onPressed: () async {
                      try {
                        final result = await _showAddVehicleDialog();
                        if (result != null) {
                          final success = await widget.tenantService
                              .addVehicle(tenant.id, result);
                          if (success) {
                            final updated = await widget.tenantService
                                .getTenantById(tenant.id);
                            if (updated != null)
                              setDialogState(() => tenant = updated);
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Đã thêm phương tiện')));
                          }
                        }
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Lỗi: $e'),
                              backgroundColor: Colors.red));
                      }
                    },
                  ),
                ],
              ),
              Flexible(
                child: tenant.vehicles == null || tenant.vehicles!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_outlined,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Chưa có phương tiện nào',
                                style: TextStyle(
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : FutureBuilder<Tenant?>(
                        future: widget.tenantService
                            .getTenantById(tenant.id),
                        builder: (context, snapshot) {
                          final current = snapshot.data ?? tenant;
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: current.vehicles?.length ?? 0,
                            itemBuilder: (context, index) {
                              final v = current.vehicles![index];
                              return _VehicleCard(
                                vehicle: v,
                                typeIcon: _getVehicleIcon(v.type),
                                typeLabel:
                                    _getVehicleTypeDisplayName(v.type),
                                parkingLabel: v.isParkingRegistered &&
                                        v.parkingSpot != null
                                    ? 'Bãi đỗ: ${v.parkingSpot}'
                                    : null,
                                menuItems: [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      const Icon(Icons.edit_rounded,
                                          size: 18),
                                      const SizedBox(width: 10),
                                      const Text('Chỉnh sửa'),
                                    ]),
                                  ),
                                  if (!v.isParkingRegistered)
                                    PopupMenuItem(
                                      value: 'parking',
                                      child: Row(children: [
                                        const Icon(
                                            Icons.local_parking_rounded,
                                            size: 18),
                                        const SizedBox(width: 10),
                                        const Text('Đăng ký bãi đỗ'),
                                      ]),
                                    )
                                  else
                                    PopupMenuItem(
                                      value: 'unparking',
                                      child: Row(children: [
                                        const Icon(Icons.cancel_rounded,
                                            size: 18),
                                        const SizedBox(width: 10),
                                        const Text('Hủy bãi đỗ'),
                                      ]),
                                    ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Color(0xFFE74C3C)),
                                      const SizedBox(width: 10),
                                      const Text('Xóa',
                                          style: TextStyle(
                                              color: Color(0xFFE74C3C))),
                                    ]),
                                  ),
                                ],
                                onMenuSelected: (value) async {
                                  if (value == 'edit') {
                                    final result =
                                        await _showEditVehicleDialog(v);
                                    if (result != null) {
                                      final ok = await widget.tenantService
                                          .updateVehicle(
                                              tenant.id, index, result);
                                      if (ok) {
                                        setDialogState(() {});
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content:
                                                      Text('Đã cập nhật')));
                                      }
                                    }
                                  } else if (value == 'parking') {
                                    final spot =
                                        await _showParkingSpotDialog();
                                    if (spot != null) {
                                      final ok = await widget.tenantService
                                          .registerParkingSpot(
                                              tenant.id, index, spot);
                                      if (ok) {
                                        setDialogState(() {});
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Đã đăng ký bãi đỗ')));
                                      }
                                    }
                                  } else if (value == 'unparking') {
                                    final ok = await widget.tenantService
                                        .unregisterParkingSpot(
                                            tenant.id, index);
                                    if (ok) {
                                      setDialogState(() {});
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content:
                                                    Text('Đã hủy bãi đỗ')));
                                    }
                                  } else if (value == 'delete') {
                                    final ok = await _showConfirmDialog(
                                      title: 'Xóa phương tiện',
                                      message:
                                          'Xóa phương tiện ${v.licensePlate}?',
                                      confirmLabel: 'Xóa',
                                      destructive: true,
                                    );
                                    if (ok == true) {
                                      final success = await widget
                                          .tenantService
                                          .removeVehicle(tenant.id, index);
                                      if (success) {
                                        setDialogState(() {});
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Đã xóa phương tiện')));
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
          ),
        ),
      ),
    );
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
          builder: (context, setDialogState) => _DialogShell(
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _DialogHeader(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: Icon(Icons.add_rounded,
                      size: 22, color: Colors.white),
                  title: 'Thêm phương tiện',
                  onClose: _doNothing,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('Thông tin xe',
                            icon: Icons.confirmation_number_rounded,
                            color: const Color(0xFF534AB7)),
                        _inputField(
                            licensePlateController, 'Biển số xe *',
                            Icons.confirmation_number_rounded,
                            maxLength: 11),
                        _dropdownField<VehicleType>(
                          label: 'Loại xe *',
                          value: selectedType,
                          items: VehicleType.values
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(
                                        _getVehicleTypeDisplayName(t)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null)
                              setDialogState(() => selectedType = v);
                          },
                        ),
                        _SectionLabel('Chi tiết',
                            icon: Icons.info_outline_rounded,
                            color: const Color(0xFF534AB7)),
                        _inputField(brandController, 'Hãng xe',
                            Icons.branding_watermark_rounded,
                            maxLength: 30),
                        _inputField(modelController, 'Model',
                            Icons.directions_car_rounded,
                            maxLength: 50),
                        _inputField(colorController, 'Màu sắc',
                            Icons.palette_rounded,
                            maxLength: 30),
                      ],
                    ),
                  ),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: 'Hủy',
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: 'Thêm xe',
                    primary: true,
                    icon: Icons.add_rounded,
                    onPressed: () {
                      if (licensePlateController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Vui lòng nhập biển số xe')));
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
                ]),
              ],
            ),
          ),
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
          builder: (context, setDialogState) => _DialogShell(
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
                  title: 'Chỉnh sửa phương tiện',
                  subtitle: vehicle.licensePlate,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _inputField(
                            licensePlateController, 'Biển số xe *',
                            Icons.confirmation_number_rounded,
                            maxLength: 12),
                        _dropdownField<VehicleType>(
                          label: 'Loại xe *',
                          value: selectedType,
                          items: VehicleType.values
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(
                                        _getVehicleTypeDisplayName(t)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null)
                              setDialogState(() => selectedType = v);
                          },
                        ),
                        _inputField(brandController, 'Hãng xe',
                            Icons.branding_watermark_rounded,
                            maxLength: 30),
                        _inputField(modelController, 'Model',
                            Icons.directions_car_rounded,
                            maxLength: 50),
                        _inputField(colorController, 'Màu sắc',
                            Icons.palette_rounded,
                            maxLength: 30),
                      ],
                    ),
                  ),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: 'Hủy',
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: 'Lưu',
                    primary: true,
                    icon: Icons.check_rounded,
                    onPressed: () {
                      if (licensePlateController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Vui lòng nhập biển số xe')));
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
                ]),
              ],
            ),
          ),
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
        builder: (context) => _DialogShell(
          maxWidth: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DialogHeader(
                gradient: LinearGradient(
                  colors: [Color(0xFF085041), Color(0xFF0F6E56)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                leading: Icon(Icons.local_parking_rounded,
                    size: 22, color: Colors.white),
                title: 'Đăng ký bãi đỗ',
                onClose: _doNothing,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: _inputField(controller, 'Vị trí bãi đỗ',
                    Icons.local_parking_rounded,
                    maxLength: 10),
              ),
              _DialogActions(children: [
                _ActionButton(
                    label: 'Hủy',
                    onPressed: () => Navigator.pop(context)),
                _ActionButton(
                  label: 'Đăng ký',
                  primary: true,
                  icon: Icons.check_rounded,
                  onPressed: () {
                    if (controller.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Vui lòng nhập vị trí')));
                      return;
                    }
                    Navigator.pop(
                        context, controller.text.trim().toUpperCase());
                  },
                ),
              ]),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RENTAL HISTORY DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) => _DialogShell(
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
              title: 'Lịch sử thuê phòng',
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
                          Text('Không có lịch sử thuê',
                              style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: tenant.previousRentals!.length,
                      itemBuilder: (context, i) {
                        final r = tenant.previousRentals![i];
                        return _RentalHistoryEntry(
                          locationText:
                              '${r.buildingName} - Phòng ${r.roomNumber}',
                          dateRangeText:
                              'Từ ${DateFormat.yMd().format(r.moveInDate)} đến ${DateFormat.yMd().format(r.moveOutDate)}',
                          durationText: '${r.duration} ngày',
                        );
                      },
                    ),
            ),
            _DialogActions(children: [
              _ActionButton(
                  label: 'Đóng',
                  onPressed: () => Navigator.pop(context)),
            ]),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VEHICLE / TENANT TYPE HELPERS
  // ═══════════════════════════════════════════════════════════════
  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle: return Icons.two_wheeler;
      case VehicleType.car: return Icons.directions_car;
      case VehicleType.bicycle: return Icons.pedal_bike;
      case VehicleType.electricBike: return Icons.electric_bike;
      case VehicleType.other: return Icons.local_shipping;
    }
  }

  String _getVehicleTypeDisplayName(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle: return 'Xe máy';
      case VehicleType.car: return 'Ô tô';
      case VehicleType.bicycle: return 'Xe đạp';
      case VehicleType.electricBike: return 'Xe đạp điện';
      case VehicleType.other: return 'Khác';
    }
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active: return Colors.green;
      case TenantStatus.inactive: return Colors.orange;
      case TenantStatus.moveOut: return Colors.red;
      case TenantStatus.suspended: return Colors.grey;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PAYMENT METHODS
  // ═══════════════════════════════════════════════════════════════
  void _showAddPaymentDialog() {
    _showTrackedDialog(
      context: context,
      builder: (context) => ImprovedPaymentFormDialog(
        organization: widget.organization,
        buildingService: widget.buildingService,
        roomService: widget.roomService,
        tenantService: widget.tenantService,
        paymentService: widget.paymentService,
        room: widget.room,
      ),
    ).then((result) {
      if (result == true)
        widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id);
    });
  }

  void _showPaymentDetailDialog(Payment payment, bool isAdmin) async {
    if (!mounted) return;
    _showTrackedDialog(
      context: context,
      builder: (context) => ViewPaymentDetailsDialog(
        payment: payment,
        isAdmin: isAdmin,
        roomService: widget.roomService,
        buildingService: widget.buildingService,
        organization: widget.organization,
        paymentService: widget.paymentService,
        tenantService: widget.tenantService,
        onEdit: () => _showEditPaymentDialog(payment),
      ),
    );
  }

  void _showEditPaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => EditPaymentDialog(
        payment: payment,
        organization: widget.organization,
        buildingService: widget.buildingService,
        roomService: widget.roomService,
        tenantService: widget.tenantService,
        paymentService: widget.paymentService,
      ),
    ).then((result) {
      if (result == true)
        widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id);
    });
  }

  void _showDeletePaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => DeletePaymentDialog(
        payment: payment,
        paymentService: widget.paymentService,
        onDeleted: () => widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id),
      ),
    );
  }

  Future<void> _showPDFPreview(Payment payment, Tenant? tenant) async {
    await PaymentPDFExporter.showPDFPreview(
      context: context,
      payment: payment,
      organization: widget.organization,
      tenant: tenant,
      room: widget.room,
      roomNumber: widget.room.roomNumber,
    );
  }

  Future<void> _exportPDFQuick(Payment payment, Tenant? tenant) async {
    await PaymentPDFExporter.quickExportPDF(
      context: context,
      payment: payment,
      organization: widget.organization,
      tenant: tenant,
      room: widget.room,
      roomNumber: widget.room.roomNumber,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD TENANTS TAB
  // ═══════════════════════════════════════════════════════════════
  Widget _buildTenantsTab() {
    if (_isLoadingTenants) {
      return Center(child: CircularProgressIndicator(color: Colors.blue.shade700));
    }

    if (_tenants == null || _tenants!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(Icons.people_outline_rounded,
                  size: 48, color: Colors.blue.shade300),
            ),
            const SizedBox(height: 20),
            Text('Chưa có người thuê',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text('Thêm người thuê để bắt đầu quản lý',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddEditTenantDialog(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: const Text('Thêm người thuê',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final activeTenants =
        _tenants!.where((t) => t.status != TenantStatus.moveOut).toList();
    final movedOutTenants =
        _tenants!.where((t) => t.status == TenantStatus.moveOut).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        if (activeTenants.isNotEmpty) ...[
          _sectionLabel('ĐANG THUÊ', activeTenants.length),
          const SizedBox(height: 8),
          ...activeTenants.map((t) => _buildRichTenantCard(t)),
        ],
        if (movedOutTenants.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('ĐÃ CHUYỂN ĐI', movedOutTenants.length),
          const SizedBox(height: 8),
          ...movedOutTenants.map((t) => _buildRichTenantCard(t)),
        ],
      ],
    );
  }

  Widget _sectionLabel(String label, int count) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
              color: Colors.blue.shade400,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Colors.grey.shade500)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10)),
          child: Text(count.toString(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  Widget _buildRichTenantCard(Tenant tenant) {
    final isMovedOut = tenant.status == TenantStatus.moveOut;
    final Color accentColor =
        isMovedOut ? Colors.grey.shade400 : Colors.blue.shade700;
    final Color accentBg =
        isMovedOut ? Colors.grey.shade50 : Colors.blue.shade50;
    final statusColor = _getTenantStatusColor(tenant.status);
    final words = tenant.fullName.trim().split(' ');
    final initials = words.length >= 2
        ? '${words.first[0]}${words.last[0]}'.toUpperCase()
        : tenant.fullName.isNotEmpty
            ? tenant.fullName[0].toUpperCase()
            : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: accentColor.withOpacity(0.07),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTenantDetailDialog(tenant),
        onLongPress: () => _showTenantOptionsMenu(tenant),
        child: Column(
          children: [
            Container(height: 4, color: accentColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: accentBg,
                        borderRadius: BorderRadius.circular(13)),
                    child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: accentColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(tenant.fullName,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (tenant.isMainTenant) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Chủ phòng',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade700)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.phone_rounded,
                              size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(tenant.phoneNumber,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                          if (tenant.occupation != null) ...[
                            Text('  ·  ',
                                style: TextStyle(
                                    color: Colors.grey.shade400)),
                            Icon(Icons.work_outline_rounded,
                                size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(tenant.occupation!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(tenant.getStatusDisplayName(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor)),
                            ),
                            _tenantInfoChip(
                                Icons.calendar_today_rounded,
                                _formatDate(tenant.moveInDate),
                                Colors.grey.shade600),
                            if (tenant.monthlyRent != null)
                              _tenantInfoChip(
                                  Icons.payments_rounded,
                                  _formatCurrency(tenant.monthlyRent!),
                                  Colors.green.shade700),
                            if (tenant.vehicles != null &&
                                tenant.vehicles!.isNotEmpty)
                              _tenantInfoChip(
                                  Icons.directions_car_rounded,
                                  '${tenant.vehicles!.length} xe',
                                  Colors.purple.shade700),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18, color: Colors.grey.shade400),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showTenantOptionsMenu(tenant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tenantInfoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD PAYMENTS TAB
  // ═══════════════════════════════════════════════════════════════
  Widget _buildPaymentsTab() {
    return ListenableBuilder(
      listenable: widget.paymentsNotifier,
      builder: (context, _) {
        final allPayments = widget.paymentsNotifier.payments
            .where((p) => p.roomId == widget.room.id)
            .toList();

        return FutureBuilder<Membership?>(
          future: _getMyMembership(),
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            if (allPayments.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: Colors.indigo.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 48, color: Colors.indigo.shade300),
                    ),
                    const SizedBox(height: 20),
                    Text('Chưa có hóa đơn',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text('Tạo hóa đơn để quản lý thanh toán',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500)),
                    if (isAdmin) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _showAddPaymentDialog,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: const Text('Tạo hóa đơn',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              );
            }

            final sorted = List<Payment>.from(allPayments)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            final pending = sorted
                .where((p) => p.status == PaymentStatus.pending)
                .length;
            final overdue = sorted.where((p) => p.isOverdue).length;
            final paid =
                sorted.where((p) => p.status == PaymentStatus.paid).length;
            final totalCollected = sorted.fold<double>(0, (s, p) {
              if (p.status == PaymentStatus.paid)
                return s + (p.paidAmount > 0 ? p.paidAmount : p.totalAmount);
              return s + p.paidAmount;
            });

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              children: [
                // KPI bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    children: [
                      _payKpiCell(pending.toString(), 'Chờ thanh toán',
                          const Color(0xFF854F0B)),
                      _kpiDivider(),
                      _payKpiCell(
                          overdue.toString(), 'Quá hạn', const Color(0xFFA32D2D)),
                      _kpiDivider(),
                      _payKpiCell(
                          paid.toString(), 'Đã thu', const Color(0xFF3B6D11)),
                      _kpiDivider(),
                      _payKpiCell(_formatCurrencyShort(totalCollected), 'Tổng thu',
                          const Color(0xFF185FA5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel('HÓA ĐƠN', sorted.length),
                const SizedBox(height: 8),
                ...sorted.map((p) => _buildRichPaymentCard(p, isAdmin)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _payKpiCell(String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _kpiDivider() =>
      Container(width: 0.5, height: 38, color: Colors.grey.shade200);

  Widget _buildRichPaymentCard(Payment payment, bool isAdmin) {
    final statusColor = _getPaymentStatusColor(payment.status);
    final words = (payment.tenantName ?? '?').trim().split(' ');
    final initials = words.length >= 2
        ? '${words.first[0]}${words.last[0]}'.toUpperCase()
        : (payment.tenantName?.isNotEmpty == true
            ? payment.tenantName![0].toUpperCase()
            : '?');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: statusColor.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPaymentDetailDialog(payment, isAdmin),
        child: Column(
          children: [
            Container(height: 4, color: statusColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: statusColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(payment.tenantName ?? '—',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(payment.getStatusDisplayName(),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(_formatCurrency(payment.totalAmount),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _tenantInfoChip(
                                Icons.label_outline_rounded,
                                _getPaymentTypeDisplayName(payment.type),
                                Colors.grey.shade600),
                            _tenantInfoChip(
                                Icons.calendar_today_outlined,
                                'Hạn: ${_formatDate(payment.dueDate)}',
                                payment.isOverdue
                                    ? const Color(0xFFA32D2D)
                                    : Colors.grey.shade600),
                            if (payment.paidAt != null)
                              _tenantInfoChip(
                                  Icons.check_circle_outline_rounded,
                                  _formatDate(payment.paidAt!),
                                  const Color(0xFF3B6D11)),
                            if (payment.status == PaymentStatus.partial &&
                                payment.remainingAmount > 0)
                              _tenantInfoChip(
                                  Icons.pending_outlined,
                                  'Còn: ${_formatCurrencyShort(payment.remainingAmount)}',
                                  const Color(0xFF185FA5)),
                            if (payment.isOverdue)
                              _tenantInfoChip(
                                  Icons.warning_amber_rounded,
                                  'Quá ${payment.daysOverdue} ngày',
                                  const Color(0xFFA32D2D)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    Builder(
                      builder: (btnContext) => IconButton(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 18, color: Colors.grey.shade400),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          final RenderBox button =
                              btnContext.findRenderObject() as RenderBox;
                          final RenderBox overlay =
                              Overlay.of(btnContext).context.findRenderObject() as RenderBox;

                          // Get the button's position and size in global coordinates
                          final Offset buttonTopLeft =
                              button.localToGlobal(Offset.zero, ancestor: overlay);
                          final Offset buttonBottomRight =
                              button.localToGlobal(button.size.bottomRight(Offset.zero),
                                  ancestor: overlay);

                          final RelativeRect position = RelativeRect.fromLTRB(
                            buttonTopLeft.dx,           // left edge aligns with button left
                            buttonBottomRight.dy,       // top of menu = bottom of button
                            overlay.size.width - buttonBottomRight.dx,  // right constraint
                            overlay.size.height - buttonTopLeft.dy,     // bottom constraint
                          );
                          showMenu<String>(
                            context: btnContext,
                            position: position,
                            items: [
                              PopupMenuItem(
                                value: 'view',
                                child: Row(children: [
                                  Icon(Icons.visibility_rounded,
                                      size: 18, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  const Text('Xem chi tiết'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded,
                                      size: 18, color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  const Text('Chỉnh sửa'),
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_rounded,
                                      size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Text('Xóa',
                                      style: TextStyle(color: Colors.red.shade700)),
                                ]),
                              ),
                            ],
                          ).then((value) {
                            if (value == 'view') {
                              _showPaymentDetailDialog(payment, isAdmin);
                            }
                            else if (value == 'edit') {
                              _showEditPaymentDialog(payment);
                            }
                            else if (value == 'delete') {
                              _showDeletePaymentDialog(payment);
                            }
                          });
                        },
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

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending: return Colors.orange;
      case PaymentStatus.paid: return Colors.green;
      case PaymentStatus.overdue: return Colors.red;
      case PaymentStatus.cancelled: return Colors.grey;
      case PaymentStatus.refunded: return Colors.purple;
      case PaymentStatus.partial: return Colors.blue;
    }
  }

  String _getPaymentTypeDisplayName(PaymentType type) {
    switch (type) {
      case PaymentType.rent: return 'Tiền thuê nhà';
      case PaymentType.electricity: return 'Tiền điện';
      case PaymentType.water: return 'Tiền nước';
      case PaymentType.internet: return 'Tiền Internet';
      case PaymentType.parking: return 'Phí gửi xe';
      case PaymentType.maintenance: return 'Phí bảo trì';
      case PaymentType.deposit: return 'Tiền cọc';
      case PaymentType.penalty: return 'Phí phạt';
      case PaymentType.other: return 'Khác';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SLIVER APP BAR
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSliverAppBar(bool innerBoxIsScrolled) {
    final activeTenants =
        _tenants?.where((t) => t.status == TenantStatus.active).length ?? 0;
    final mainTenant =
        _tenants?.where((t) => t.isMainTenant).firstOrNull;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.blue.shade800,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade900, Colors.blue.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(right: -15, top: -20,
              child: Container(width: 90, height: 90,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.14)))),
            Positioned(right: 55, top: -28,
              child: Container(width: 60, height: 60,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.10)))),
            Positioned(left: 280, top: -18,
              child: Container(width: 48, height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.09)))),
            Positioned(left: -18, bottom: 40,
              child: Container(width: 72, height: 72,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.10)))),
            Positioned(left: 42, top: -12,
              child: Container(width: 38, height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08)))),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.meeting_room_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phòng ${widget.room.roomNumber}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.3)),
                              if (widget.room.roomType.isNotEmpty)
                                Text(widget.room.roomType,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.80),
                                        fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        _headerChip(
                            icon: Icons.people_rounded,
                            label: '$activeTenants người thuê'),
                        const SizedBox(width: 8),
                        if (widget.room.area > 0)
                          _headerChip(
                              icon: Icons.square_foot_rounded,
                              label: '${widget.room.area} m²'),
                        if (mainTenant != null) ...[
                          const SizedBox(width: 8),
                          _headerChip(
                              icon: Icons.person_rounded,
                              label: mainTenant.fullName.split(' ').last),
                        ],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          color: Colors.blue.shade800,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.55),
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w400),
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_rounded, size: 17),
                    SizedBox(width: 6),
                    Text('Người thuê'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 17),
                    SizedBox(width: 6),
                    Text('Hóa đơn'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.28), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth ||
            constraints.maxHeight < minHeight) {
          return Scaffold(
              body: _buildMinimumSizeWarning(context, constraints));
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildSliverAppBar(innerBoxIsScrolled),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildTenantsTab(),
                _buildPaymentsTab(),
              ],
            ),
          ),
          floatingActionButton: FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.role == 'admin') {
                return FloatingActionButton(
                  onPressed: () {
                    if (_tabController.index == 0)
                      _showAddEditTenantDialog();
                    else
                      _showAddPaymentDialog();
                  },
                  backgroundColor: Colors.blue.shade700,
                  child: const Icon(Icons.add, color: Colors.white),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

// ─── No-op close callback placeholder (used for dialogs where we manually
//     wire close on the button, not the header X, to avoid const issues) ──────
void _doNothing() {}

// ─── Contract date tile (reusable inline widget for the add/edit form) ────────
class _ContractDateTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final DateTime? date;
  final String Function(DateTime) formatDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ContractDateTile({
    required this.label,
    required this.icon,
    required this.date,
    required this.formatDate,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(icon, size: 18, color: Colors.grey.shade400),
        title: Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        subtitle: Text(
          date != null ? formatDate(date!) : 'Chưa có',
          style: TextStyle(
            fontSize: 14,
            fontWeight:
                date != null ? FontWeight.w600 : FontWeight.normal,
            color: date != null
                ? Colors.grey.shade800
                : Colors.grey.shade400,
          ),
        ),
        onTap: onPick,
        trailing: date != null
            ? IconButton(
                icon: Icon(Icons.clear_rounded,
                    size: 16, color: Colors.grey.shade400),
                onPressed: onClear,
              )
            : Icon(Icons.calendar_today_rounded,
                size: 16, color: Colors.grey.shade400),
      ),
    );
  }
}