part of 'tenant_tab.dart';

// Shared dialog frames, fields, buttons, detail cards, and confirmation dialog.
// The tenant tab owns state, services, lifecycle, and refresh callbacks.
extension _TenantDialogComponents on _TenantsTabState {
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

}

// The default blue gradient used for most dialogs
LinearGradient get _defaultHeaderGradient => LinearGradient(
  colors: [AppThemePalette.primaryDeep, AppThemePalette.primary],
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final size = MediaQuery.sizeOf(context);
    return AppDialog(
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final bool disabled = onPressed == null;

    if (primary && !destructive) {
      return Material(
        color: disabled ? Colors.grey.shade300 : AppThemePalette.primary,
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
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: children,
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final labelColor = color ?? AppThemePalette.primary;
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
        padding: const EdgeInsets.symmetric(vertical: 8),
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
      keyboardType: suffix == 'VND' || suffix == 'USD' ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
      inputFormatters: [if (suffix == 'VND' || suffix == 'USD') CurrencyInputFormatter(decimalDigits: suffix == 'USD' ? 2 : 0)],
      maxLength: suffix == 'VND' || suffix == 'USD' ? 24 : maxLength,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade600),
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
          borderSide: BorderSide(color: AppThemePalette.primary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        isDense: false,
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
      initialValue: value,
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
          borderSide: BorderSide(color: AppThemePalette.primary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        isDense: false,
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
          color: AppThemePalette.primaryLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemePalette.primaryLight),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppThemePalette.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(typeIcon, size: 20, color: AppThemePalette.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.licensePlate,
                    style:  TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppThemePalette.primaryDeep,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [typeLabel, vehicle.brand, vehicle.model]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style:  TextStyle(
                        fontSize: 12, color: AppThemePalette.primary),
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
                  size: 18, color: Colors.grey.shade600),
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
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

