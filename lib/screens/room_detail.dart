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
import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const double minWidth  = 360.0;
const double minHeight = 600.0;

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
    final t = AppTranslations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              t['room_detail_window_too_small'],
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t['room_detail_window_min_size'],
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              t.textWithParams('room_detail_window_current_size', {
                'width': c.maxWidth.toInt(),
                'height': c.maxHeight.toInt(),
              }),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
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
          final msg = AppTranslations.of(context).textWithParams(
              'room_detail_loading_error', {'error': error});
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)));
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
                    label: t['cancel'],
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
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ADD / EDIT TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showAddEditTenantDialog({Tenant? tenant}) {
    final isEditing = tenant != null;
    final nameController = TextEditingController(text: tenant?.fullName ?? '');
    final phoneController = TextEditingController(text: tenant?.phoneNumber ?? '');
    final emailController = TextEditingController(text: tenant?.email ?? '');
    final nationalIdController = TextEditingController(text: tenant?.nationalId ?? '');
    final occupationController = TextEditingController(text: tenant?.occupation ?? '');
    final workplaceController = TextEditingController(text: tenant?.workplace ?? '');
    final rentController = TextEditingController(text: tenant?.monthlyRent?.toString() ?? '');
    final depositController = TextEditingController(text: tenant?.deposit?.toString() ?? '');
    final areaController = TextEditingController(text: tenant?.apartmentArea?.toString() ?? '');
    final typeController = TextEditingController(text: tenant?.apartmentType ?? '');

    Gender? selectedGender = tenant?.gender;
    bool isMainTenant = tenant?.isMainTenant ?? (_tenants?.isEmpty ?? true);
    DateTime moveInDate = tenant?.moveInDate ?? DateTime.now();
    DateTime? contractStartDate = tenant?.contractStartDate;
    DateTime? contractEndDate = tenant?.contractEndDate;
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) {
        final t = AppTranslations.of(dialogContext);
        return _DialogShell(
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
                  title: isEditing
                      ? t['room_detail_edit_tenant_title']
                      : t['room_detail_add_tenant_title'],
                  subtitle: isEditing ? tenant!.fullName : null,
                  onClose: isSaving ? () {} : () => Navigator.pop(dialogContext),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(t['room_detail_section_contact'],
                            icon: Icons.contact_phone_rounded),
                        _inputField(nameController, t['room_detail_field_fullname'],
                            Icons.person_rounded, maxLength: 100),
                        _inputField(phoneController, t['room_detail_field_phone'],
                            Icons.phone_rounded,
                            keyboardType: TextInputType.phone, maxLength: 20),
                        _inputField(rentController, t['room_detail_field_rent'],
                            Icons.payments_rounded,
                            suffix: '₫',
                            keyboardType: TextInputType.number,
                            maxLength: 20),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['room_detail_field_movein'],
                          initialDate: moveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(() => moveInDate = date);
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_apartment'],
                            icon: Icons.apartment_rounded),
                        Row(children: [
                          Expanded(
                              child: _inputField(typeController,
                                  t['room_detail_field_apt_type'],
                                  Icons.category_rounded,
                                  maxLength: 50)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _inputField(areaController,
                                  t['room_detail_field_area'],
                                  Icons.square_foot_rounded,
                                  suffix: 'm²',
                                  keyboardType: TextInputType.number,
                                  maxLength: 10)),
                        ]),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_personal'],
                            icon: Icons.person_rounded),
                        _inputField(emailController, t['room_detail_field_email'],
                            Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 254),
                        _inputField(nationalIdController,
                            t['room_detail_field_national_id'],
                            Icons.badge_rounded, maxLength: 20),
                        _inputField(occupationController,
                            t['room_detail_field_occupation'],
                            Icons.work_rounded, maxLength: 100),
                        _inputField(workplaceController,
                            t['room_detail_field_workplace'],
                            Icons.location_city_rounded, maxLength: 150),
                        _dropdownField<Gender>(
                          label: t['room_detail_field_gender'],
                          value: selectedGender,
                          items: Gender.values
                              .map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(_getGenderDisplayName(context, g))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedGender = v),
                        ),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_contract'],
                            icon: Icons.description_rounded),
                        _inputField(depositController,
                            t['room_detail_field_deposit'],
                            Icons.account_balance_wallet_rounded,
                            suffix: '₫',
                            keyboardType: TextInputType.number,
                            maxLength: 20),
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: CheckboxListTile(
                            title: Text(t['room_detail_field_main_tenant'],
                                style: const TextStyle(fontSize: 14)),
                            value: isMainTenant,
                            activeColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onChanged: (v) =>
                                setDialogState(() => isMainTenant = v ?? true),
                          ),
                        ),
                        _ContractDateTile(
                          label: t['room_detail_field_contract_start'],
                          noDateLabel: t['room_detail_contract_no_date'],
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
                        _ContractDateTile(
                          label: t['room_detail_field_contract_end'],
                          noDateLabel: t['room_detail_contract_no_date'],
                          icon: Icons.event_busy_rounded,
                          date: contractEndDate,
                          formatDate: _formatDate,
                          onPick: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: contractEndDate ??
                                  DateTime.now().add(const Duration(days: 365)),
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
                      label: t['cancel'],
                      onPressed: isSaving
                          ? null
                          : () => Navigator.pop(dialogContext)),
                  _ActionButton(
                    label: isEditing
                        ? t['room_detail_save_changes']
                        : t['room_detail_add_action'],
                    primary: true,
                    icon: isEditing
                        ? Icons.check_rounded
                        : Icons.person_add_rounded,
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t['room_detail_err_name'])));
                              return;
                            }
                            if (phoneController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t['room_detail_err_phone'])));
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            // Capture translated strings before async gap
                            final msgUpdate = t['room_detail_update_success'];
                            final msgAdd    = t['room_detail_add_success'];
                            final msgErrTpl = t['room_detail_err_generic'];
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
                                nationalId: nationalIdController.text.trim().isEmpty
                                    ? null
                                    : nationalIdController.text.trim(),
                                occupation: occupationController.text.trim().isEmpty
                                    ? null
                                    : occupationController.text.trim(),
                                workplace: workplaceController.text.trim().isEmpty
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
                                apartmentType: typeController.text.trim().isEmpty
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
                                  'contractStartDate': newTenant.contractStartDate,
                                  'contractEndDate': newTenant.contractEndDate,
                                });
                                if (mounted) {
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msgUpdate)));
                                }
                              } else {
                                await widget.tenantService.addTenant(newTenant);
                                if (mounted) {
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msgAdd)));
                                }
                              }
                            } catch (e) {
                              setDialogState(() => isSaving = false);
                              if (mounted) {
                                final errMsg = msgErrTpl.replaceAll('{{error}}', e.toString());
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(errMsg),
                                    backgroundColor: Colors.red));
                              }
                            }
                          },
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getGenderDisplayName(BuildContext context, Gender g) {
    final t = AppTranslations.of(context);
    switch (g) {
      case Gender.male:   return t['gender_male'];
      case Gender.female: return t['gender_female'];
      case Gender.other:  return t['gender_other'];
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
    final buildingName = building?.name ?? '—';
    if (!mounted) return;

    final membership = await _getMyMembership();
    if (!mounted) return;

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
                          color: Colors.white),
                    ),
                  ),
                ),
                title: tenant.fullName,
                subtitle: tenant.isMainTenant
                    ? t['room_detail_main_tenant_badge']
                    : tenant.phoneNumber,
                actions: membership?.role == 'admin'
                    ? [
                        TextButton.icon(
                          icon: const Icon(Icons.more_horiz_rounded, size: 16),
                          label: Text(t['room_detail_options_btn']),
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
                          isMovedOut
                              ? t['tenant_detail_previous_location']
                              : t['tenant_detail_location'],
                          color: accentColor,
                          icon: Icons.location_on_rounded),
                      _DetailCard(
                        borderColor: accentColor.withValues(alpha: 0.2),
                        fillColor: accentColor.withValues(alpha: 0.05),
                        rows: [
                          _DetailRow(t['tenant_detail_building'], buildingName),
                          _DetailRow(t['tenant_detail_room'], widget.room.roomNumber),
                        ],
                      ),
                      const _ContentDivider(),
                      _SectionLabel(t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded),
                      _DetailCard(rows: [
                        _DetailRow(t['tenant_detail_phone'], tenant.phoneNumber),
                        if (tenant.email != null)
                          _DetailRow(t['tenant_detail_email'], tenant.email!),
                      ]),
                      const _ContentDivider(),
                      _SectionLabel(t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded),
                      _DetailCard(rows: [
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
                      ]),
                      if (!isMovedOut) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_rental_section'],
                            icon: Icons.home_rounded),
                        _DetailCard(rows: [
                          _DetailRow(t['tenant_detail_move_in_date'],
                              _formatDate(tenant.moveInDate)),
                          _DetailRow(t['tenant_detail_days_living'],
                              t.textWithParams('tenant_detail_days_value',
                                  {'days': tenant.daysLiving})),
                          if (tenant.monthlyRent != null)
                            _DetailRow(t['tenant_detail_monthly_rent'],
                                _formatCurrency(tenant.monthlyRent!),
                                valueColor: const Color(0xFF3B6D11)),
                          if (tenant.deposit != null)
                            _DetailRow(t['tenant_detail_deposit'],
                                _formatCurrency(tenant.deposit!)),
                          if (tenant.apartmentType != null &&
                              tenant.apartmentType!.isNotEmpty)
                            _DetailRow(t['tenant_detail_apartment_type'],
                                tenant.apartmentType!),
                          if (tenant.apartmentArea != null &&
                              tenant.apartmentArea! > 0)
                            _DetailRow(t['tenant_detail_area'],
                                t.textWithParams('tenant_detail_area_value',
                                    {'area': tenant.apartmentArea})),
                        ]),
                      ],
                      if (isMovedOut && tenant.moveOutDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_moveout_section'],
                            icon: Icons.logout_rounded,
                            color: const Color(0xFF854F0B)),
                        _DetailCard(
                          borderColor:
                              const Color(0xFF854F0B).withValues(alpha: 0.2),
                          fillColor:
                              const Color(0xFF854F0B).withValues(alpha: 0.04),
                          rows: [
                            _DetailRow(t['tenant_detail_move_out_date'],
                                _formatDate(tenant.moveOutDate!)),
                            _DetailRow(t['tenant_detail_duration'],
                                t.textWithParams('tenant_detail_days_value', {
                                  'days': tenant.moveOutDate!
                                      .difference(tenant.moveInDate)
                                      .inDays
                                })),
                            if (tenant.contractTerminationReason != null)
                              _DetailRow(t['tenant_detail_reason'],
                                  tenant.contractTerminationReason!),
                            if (tenant.notes != null && tenant.notes!.isNotEmpty)
                              _DetailRow(t['tenant_detail_notes'], tenant.notes!),
                          ],
                        ),
                      ],
                      if (tenant.contractStartDate != null ||
                          tenant.contractEndDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_contract_section'],
                            icon: Icons.description_rounded),
                        _DetailCard(rows: [
                          if (tenant.contractStartDate != null)
                            _DetailRow(t['tenant_detail_contract_start'],
                                _formatDate(tenant.contractStartDate!)),
                          if (tenant.contractEndDate != null)
                            _DetailRow(
                                isMovedOut
                                    ? t['tenant_detail_contract_end_date']
                                    : t['tenant_detail_contract_end'],
                                _formatDate(tenant.contractEndDate!)),
                          if (isMovedOut) ...[
                            _DetailRow(t['tenant_detail_contract_status'],
                                tenant.getContractStatusDisplayName()),
                            if (tenant.moveOutDate != null &&
                                tenant.contractEndDate != null)
                              _DetailRow(
                                tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? t['tenant_detail_early_termination']
                                    : t['tenant_detail_end_label'],
                                tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? t.textWithParams(
                                        'tenant_detail_days_early', {
                                        'days': tenant.contractEndDate!
                                            .difference(tenant.moveOutDate!)
                                            .inDays
                                      })
                                    : t['tenant_detail_on_time'],
                                valueColor: tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? const Color(0xFF854F0B)
                                    : const Color(0xFF3B6D11),
                              ),
                          ] else if (tenant.daysUntilContractEnd != null)
                            _DetailRow(
                                t['tenant_detail_remaining'],
                                t.textWithParams('tenant_detail_days_value', {
                                  'days': tenant.daysUntilContractEnd
                                })),
                        ]),
                      ],
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                            t.textWithParams('tenant_detail_vehicles_section',
                                {'count': tenant.vehicles!.length}),
                            icon: Icons.directions_car_rounded,
                            color: const Color(0xFF534AB7)),
                        ...tenant.vehicles!.map((v) => _VehicleCard(
                              vehicle: v,
                              typeIcon: _getVehicleIcon(v.type),
                              typeLabel: _getVehicleTypeDisplayName(context, v.type),
                              parkingLabel: v.isParkingRegistered &&
                                      v.parkingSpot != null
                                  ? t.textWithParams(
                                      'tenant_vehicle_parking_spot',
                                      {'spot': v.parkingSpot!})
                                  : null,
                              menuItems: const [],
                              onMenuSelected: (_) {},
                            )),
                      ],
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                            t.textWithParams('tenant_detail_history_section',
                                {'count': tenant.previousRentals!.length}),
                            icon: Icons.history_rounded,
                            color: const Color(0xFF854F0B)),
                        ...tenant.previousRentals!.map((r) =>
                            _RentalHistoryEntry(
                              locationText:
                                  '${r.buildingName} - ${t['tenant_detail_room']} ${r.roomNumber}',
                              dateRangeText: t.textWithParams(
                                  'tenant_detail_history_dates', {
                                'from': _formatDate(r.moveInDate),
                                'to': _formatDate(r.moveOutDate),
                              }),
                              durationText: t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': r.duration}),
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
              _DialogActions(children: [
                _ActionButton(
                    label: t['room_detail_close_btn'],
                    onPressed: () => Navigator.pop(context)),
              ]),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT OPTIONS MENU
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showTenantOptionsMenu(Tenant tenant) async {
    final isMovedOut = tenant.status == TenantStatus.moveOut;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;
    final t = AppTranslations.of(context);

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
          title: t['room_detail_menu_view'],
          onTap: () {
            Navigator.pop(context);
            _showTenantDetailDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.edit_rounded,
          title: t['room_detail_menu_edit'],
          color: const Color(0xFF2563EB),
          onTap: () {
            Navigator.pop(context);
            _showAddEditTenantDialog(tenant: tenant);
          }),
      menuDivider(),
      if (!isMovedOut) ...[
        menuTile(
            icon: Icons.logout_rounded,
            title: t['room_detail_menu_moveout'],
            color: const Color(0xFF854F0B),
            onTap: () {
              Navigator.pop(context);
              _confirmMoveOut(tenant);
            }),
        menuDivider(),
      ],
      menuTile(
          icon: Icons.directions_car_rounded,
          title: t['room_detail_menu_vehicles'],
          subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
              ? t.textWithParams('room_detail_vehicle_count',
                  {'count': tenant.vehicles!.length})
              : null,
          color: const Color(0xFF534AB7),
          onTap: () {
            Navigator.pop(context);
            _showVehicleManagementDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.history_rounded,
          title: t['room_detail_menu_history'],
          onTap: () {
            Navigator.pop(context);
            _showRentalHistoryDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.delete_outline_rounded,
          title: t['room_detail_menu_delete'],
          color: const Color(0xFFE74C3C),
          onTap: () {
            Navigator.pop(context);
            _confirmDeleteTenant(tenant);
          }),
    ];

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
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) =>
            SafeArea(child: SingleChildScrollView(child: sheetContent)),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE OUT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmMoveOut(Tenant tenant) async {
    // Capture translations before async gap
    final t = AppTranslations.of(context);
    final reasonOptions = [
      t['room_detail_moveout_reason_1'],
      t['room_detail_moveout_reason_2'],
      t['room_detail_moveout_reason_3'],
      t['room_detail_moveout_reason_4'],
      t['room_detail_moveout_reason_5'],
    ];
    final msgSuccess = t['room_detail_moveout_success'];
    final msgFailed  = t['room_detail_moveout_failed'];

    DateTime selectedDate = DateTime.now();
    String? selectedReason = reasonOptions.first;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final td = AppTranslations.of(context);
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
                  title: td['room_detail_moveout_title'],
                  onClose: _doNothing,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(td['confirm'],
                            icon: Icons.info_outline_rounded,
                            color: const Color(0xFF854F0B)),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF854F0B).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF854F0B)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            td.textWithParams('room_detail_moveout_confirm',
                                {'name': tenant.fullName}),
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LocalizedDatePicker(
                          labelText: td['room_detail_moveout_date'],
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
                          label: td['room_detail_moveout_reason'],
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
                            text: td.textWithParams(
                                'room_detail_moveout_early_warn', {
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
                _DialogActions(children: [
                  _ActionButton(
                      label: td['cancel'],
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: td['room_detail_moveout_confirm_btn'],
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
          content: Text(success ? msgSuccess : msgFailed),
          backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE TENANT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final t = AppTranslations.of(context);
    final ok = await _showConfirmDialog(
      title: t['room_detail_del_tenant_title'],
      message: t.textWithParams(
          'room_detail_del_tenant_msg', {'name': tenant.fullName}),
      confirmLabel: t['room_detail_del_tenant_action'],
      destructive: true,
    );
    if (ok == true) {
      // Capture before async
      final msgSuccess = t['room_detail_del_tenant_success'];
      final msgFailed  = t['room_detail_del_tenant_failed'];
      final success = await widget.tenantService.deleteTenant(tenant.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? msgSuccess : msgFailed),
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
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
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
                  title: t['room_detail_vehicle_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 22, color: Colors.white),
                      tooltip: t['room_detail_vehicle_add_title'],
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
                                    SnackBar(content: Text(
                                        t['room_detail_vehicle_added'])));
                            }
                          }
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(t.textWithParams(
                                        'room_detail_err_generic',
                                        {'error': e})),
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
                              Text(t['room_detail_vehicle_no_vehicles'],
                                  style: TextStyle(
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : FutureBuilder<Tenant?>(
                          future: widget.tenantService.getTenantById(tenant.id),
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
                                  typeLabel: _getVehicleTypeDisplayName(
                                      context, v.type),
                                  parkingLabel: v.isParkingRegistered &&
                                          v.parkingSpot != null
                                      ? t.textWithParams(
                                          'tenant_vehicle_parking_spot',
                                          {'spot': v.parkingSpot!})
                                      : null,
                                  menuItems: [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        const Icon(Icons.edit_rounded, size: 18),
                                        const SizedBox(width: 10),
                                        Text(t['room_detail_vehicle_edit_menu']),
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
                                          Text(t['room_detail_vehicle_park_menu']),
                                        ]),
                                      )
                                    else
                                      PopupMenuItem(
                                        value: 'unparking',
                                        child: Row(children: [
                                          const Icon(Icons.cancel_rounded,
                                              size: 18),
                                          const SizedBox(width: 10),
                                          Text(t['room_detail_vehicle_unpark_menu']),
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
                                        Text(t['room_detail_vehicle_del_menu'],
                                            style: const TextStyle(
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
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_updated'])));
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
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_parking_reg'])));
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
                                              .showSnackBar(SnackBar(
                                                  content: Text(t[
                                                      'room_detail_vehicle_parking_unreg'])));
                                      }
                                    } else if (value == 'delete') {
                                      final ok = await _showConfirmDialog(
                                        title: t['room_detail_vehicle_del_title'],
                                        message: t.textWithParams(
                                            'room_detail_vehicle_del_msg',
                                            {'plate': v.licensePlate}),
                                        confirmLabel:
                                            t['room_detail_vehicle_del_menu'],
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
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_deleted'])));
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
        );
      },
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
        builder: (context) {
          final t = AppTranslations.of(context);
          return StatefulBuilder(
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
                    leading: const Icon(Icons.add_rounded,
                        size: 22, color: Colors.white),
                    title: t['room_detail_vehicle_add_title'],
                    onClose: _doNothing,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(t['room_detail_vehicle_section_info'],
                              icon: Icons.confirmation_number_rounded,
                              color: const Color(0xFF534AB7)),
                          _inputField(
                              licensePlateController,
                              t['room_detail_vehicle_field_plate'],
                              Icons.confirmation_number_rounded,
                              maxLength: 11),
                          _dropdownField<VehicleType>(
                            label: t['room_detail_vehicle_field_type'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((vt) => DropdownMenuItem(
                                      value: vt,
                                      child: Text(_getVehicleTypeDisplayName(
                                          context, vt)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                setDialogState(() => selectedType = v);
                            },
                          ),
                          _SectionLabel(
                              t['room_detail_vehicle_section_detail'],
                              icon: Icons.info_outline_rounded,
                              color: const Color(0xFF534AB7)),
                          _inputField(brandController,
                              t['room_detail_vehicle_field_brand'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(modelController,
                              t['room_detail_vehicle_field_model'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(colorController,
                              t['room_detail_vehicle_field_color'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['room_detail_vehicle_add_btn'],
                      primary: true,
                      icon: Icons.add_rounded,
                      onPressed: () {
                        if (licensePlateController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(t['room_detail_vehicle_err_plate'])));
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
          );
        },
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
        builder: (context) {
          final t = AppTranslations.of(context);
          return StatefulBuilder(
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
                    title: t['room_detail_vehicle_edit_title'],
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
                              t['room_detail_vehicle_field_plate'],
                              Icons.confirmation_number_rounded,
                              maxLength: 12),
                          _dropdownField<VehicleType>(
                            label: t['room_detail_vehicle_field_type'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((vt) => DropdownMenuItem(
                                      value: vt,
                                      child: Text(_getVehicleTypeDisplayName(
                                          context, vt)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                setDialogState(() => selectedType = v);
                            },
                          ),
                          _inputField(brandController,
                              t['room_detail_vehicle_field_brand'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(modelController,
                              t['room_detail_vehicle_field_model'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(colorController,
                              t['room_detail_vehicle_field_color'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['save'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        if (licensePlateController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(t['room_detail_vehicle_err_plate'])));
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
                            isParkingRegistered: vehicle.isParkingRegistered,
                            parkingSpot: vehicle.parkingSpot,
                          ),
                        );
                      },
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
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
                  title: t['room_detail_parking_title'],
                  onClose: _doNothing,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: _inputField(controller,
                      t['room_detail_parking_field'],
                      Icons.local_parking_rounded,
                      maxLength: 10),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: t['cancel'],
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: t['room_detail_parking_btn'],
                    primary: true,
                    icon: Icons.check_rounded,
                    onPressed: () {
                      if (controller.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(t['room_detail_parking_err'])));
                        return;
                      }
                      Navigator.pop(
                          context, controller.text.trim().toUpperCase());
                    },
                  ),
                ]),
              ],
            ),
          );
        },
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
                title: t['room_detail_history_title'],
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
                            Text(t['room_detail_history_empty'],
                                style:
                                    TextStyle(color: Colors.grey.shade500)),
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
                                '${r.buildingName} - ${t['tenant_detail_room']} ${r.roomNumber}',
                            dateRangeText: t.textWithParams(
                                'room_detail_history_from_to', {
                              'from': DateFormat.yMd().format(r.moveInDate),
                              'to': DateFormat.yMd().format(r.moveOutDate),
                            }),
                            durationText: t.textWithParams(
                                'room_detail_history_duration',
                                {'days': r.duration}),
                          );
                        },
                      ),
              ),
              _DialogActions(children: [
                _ActionButton(
                    label: t['room_detail_close_btn'],
                    onPressed: () => Navigator.pop(context)),
              ]),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VEHICLE / TENANT TYPE HELPERS
  // ═══════════════════════════════════════════════════════════════
  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:  return Icons.two_wheeler;
      case VehicleType.car:         return Icons.directions_car;
      case VehicleType.bicycle:     return Icons.pedal_bike;
      case VehicleType.electricBike:return Icons.electric_bike;
      case VehicleType.other:       return Icons.local_shipping;
    }
  }

  String _getVehicleTypeDisplayName(BuildContext context, VehicleType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case VehicleType.motorcycle:  return t['tenant_vehicle_motorcycle'];
      case VehicleType.car:         return t['tenant_vehicle_car'];
      case VehicleType.bicycle:     return t['tenant_vehicle_bicycle'];
      case VehicleType.electricBike:return t['tenant_vehicle_electric_bike'];
      case VehicleType.other:       return t['tenant_vehicle_other'];
    }
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:    return Colors.green;
      case TenantStatus.inactive:  return Colors.orange;
      case TenantStatus.moveOut:   return Colors.red;
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
    final t = AppTranslations.of(context);

    if (_isLoadingTenants) {
      return Center(
          child: CircularProgressIndicator(color: Colors.blue.shade700));
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
            Text(t['room_detail_no_tenants'],
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text(t['room_detail_no_tenants_hint'],
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
              label: Text(t['room_detail_add_tenant_title'],
                  style: const TextStyle(color: Colors.white)),
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
          _sectionLabel(t['room_detail_section_active'], activeTenants.length),
          const SizedBox(height: 8),
          ...activeTenants.map((tenant) => _buildRichTenantCard(tenant)),
        ],
        if (movedOutTenants.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel(
              t['room_detail_section_moved_out'], movedOutTenants.length),
          const SizedBox(height: 8),
          ...movedOutTenants.map((tenant) => _buildRichTenantCard(tenant)),
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
    final t = AppTranslations.of(context);
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
                              child: Text(t['room_detail_main_tenant_badge'],
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
                                  fontSize: 12, color: Colors.grey.shade600)),
                          if (tenant.occupation != null) ...[
                            Text('  ·  ',
                                style:
                                    TextStyle(color: Colors.grey.shade400)),
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
                                  t.textWithParams('room_detail_vehicle_count',
                                      {'count': tenant.vehicles!.length}),
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
        final t = AppTranslations.of(context);
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
                          color: Colors.indigo.shade50,
                          shape: BoxShape.circle),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 48, color: Colors.indigo.shade300),
                    ),
                    const SizedBox(height: 20),
                    Text(t['room_detail_no_payments'],
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text(t['room_detail_no_payments_hint'],
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
                        icon: const Icon(Icons.add_rounded,
                            color: Colors.white),
                        label: Text(t['room_detail_create_invoice'],
                            style: const TextStyle(color: Colors.white)),
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
                      _payKpiCell(pending.toString(),
                          t['room_detail_kpi_pending'],
                          const Color(0xFF854F0B)),
                      _kpiDivider(),
                      _payKpiCell(overdue.toString(),
                          t['room_detail_kpi_overdue'],
                          const Color(0xFFA32D2D)),
                      _kpiDivider(),
                      _payKpiCell(paid.toString(),
                          t['room_detail_kpi_collected'],
                          const Color(0xFF3B6D11)),
                      _kpiDivider(),
                      _payKpiCell(
                          _formatCurrencyShort(totalCollected),
                          t['room_detail_kpi_total'],
                          const Color(0xFF185FA5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel(
                    t['room_detail_section_invoices'], sorted.length),
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
    final t = AppTranslations.of(context);
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
                              color: statusColor.withValues(alpha: 0.1),
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
                                _getPaymentTypeDisplayName(
                                    context, payment.type),
                                Colors.grey.shade600),
                            _tenantInfoChip(
                                Icons.calendar_today_outlined,
                                t.textWithParams('room_detail_due_date_chip',
                                    {'date': _formatDate(payment.dueDate)}),
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
                                  t.textWithParams(
                                      'room_detail_remaining_chip', {
                                    'amount': _formatCurrencyShort(
                                        payment.remainingAmount)
                                  }),
                                  const Color(0xFF185FA5)),
                            if (payment.isOverdue)
                              _tenantInfoChip(
                                  Icons.warning_amber_rounded,
                                  t.textWithParams(
                                      'room_detail_overdue_chip',
                                      {'days': payment.daysOverdue}),
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
                          final td = AppTranslations.of(btnContext);
                          final RenderBox button =
                              btnContext.findRenderObject() as RenderBox;
                          final RenderBox overlay =
                              Overlay.of(btnContext).context.findRenderObject()
                                  as RenderBox;
                          final Offset buttonTopLeft = button.localToGlobal(
                              Offset.zero,
                              ancestor: overlay);
                          final Offset buttonBottomRight =
                              button.localToGlobal(
                                  button.size.bottomRight(Offset.zero),
                                  ancestor: overlay);
                          final RelativeRect position =
                              RelativeRect.fromLTRB(
                            buttonTopLeft.dx,
                            buttonBottomRight.dy,
                            overlay.size.width - buttonBottomRight.dx,
                            overlay.size.height - buttonTopLeft.dy,
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
                                  Text(td['room_detail_pay_menu_view']),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded,
                                      size: 18,
                                      color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  Text(td['room_detail_pay_menu_edit']),
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_rounded,
                                      size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Text(td['room_detail_pay_menu_delete'],
                                      style: TextStyle(
                                          color: Colors.red.shade700)),
                                ]),
                              ),
                            ],
                          ).then((value) {
                            if (value == 'view')
                              _showPaymentDetailDialog(payment, isAdmin);
                            else if (value == 'edit')
                              _showEditPaymentDialog(payment);
                            else if (value == 'delete')
                              _showDeletePaymentDialog(payment);
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
      case PaymentStatus.pending:   return Colors.orange;
      case PaymentStatus.paid:      return Colors.green;
      case PaymentStatus.overdue:   return Colors.red;
      case PaymentStatus.cancelled: return Colors.grey;
      case PaymentStatus.refunded:  return Colors.purple;
      case PaymentStatus.partial:   return Colors.blue;
    }
  }

  String _getPaymentTypeDisplayName(BuildContext context, PaymentType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case PaymentType.rent:        return t['payment_type_rent'];
      case PaymentType.electricity: return t['payment_type_electricity'];
      case PaymentType.water:       return t['payment_type_water'];
      case PaymentType.internet:    return t['payment_type_internet'];
      case PaymentType.parking:     return t['payment_type_parking'];
      case PaymentType.maintenance: return t['payment_type_maintenance'];
      case PaymentType.deposit:     return t['payment_type_deposit'];
      case PaymentType.penalty:     return t['payment_type_penalty'];
      case PaymentType.other:       return t['payment_type_other'];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SLIVER APP BAR
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSliverAppBar(bool innerBoxIsScrolled) {
    final t = AppTranslations.of(context);
    final activeTenants =
        _tenants?.where((t) => t.status == TenantStatus.active).length ?? 0;
    final mainTenant = _tenants?.where((t) => t.isMainTenant).firstOrNull;

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
                              Text('${t['manage_rooms']} ${widget.room.roomNumber}',
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
                            label: t.textWithParams(
                                'room_detail_tenants_count',
                                {'count': activeTenants})),
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
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_rounded, size: 17),
                    const SizedBox(width: 6),
                    Text(t['room_detail_tab_tenants']),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 17),
                    const SizedBox(width: 6),
                    Text(t['room_detail_tab_payments']),
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

// ─── No-op close callback ─────────────────────────────────────────────────────
void _doNothing() {}

// ─── Contract date tile ───────────────────────────────────────────────────────
class _ContractDateTile extends StatelessWidget {
  final String label;
  final String noDateLabel;
  final IconData icon;
  final DateTime? date;
  final String Function(DateTime) formatDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ContractDateTile({
    required this.label,
    required this.noDateLabel,
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
          date != null ? formatDate(date!) : noDateLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
            color: date != null ? Colors.grey.shade800 : Colors.grey.shade400,
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