import 'dart:ui';

import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/owner_model.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/update_services.dart';
import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:apartment_management_project_2/widgets/loading.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:async';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────
class _DS {
  static const primary      = Color(0xFF1A56DB);
  static const primaryDeep  = Color(0xFF0E3A9F);
  static const primaryMid   = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFEFF6FF);
  static const surface      = Color(0xFFF4F6FB);
  static const card         = Colors.white;
  static const textPrimary  = Color(0xFF0C1C3E);
  static const textSecondary= Color(0xFF64748B);
  static const adminGold    = Color(0xFFF59E0B);
  static const adminGoldBg  = Color(0xFFFFFBEB);
  static const memberBlue   = Color(0xFF1A56DB);
  static const memberBlueBg = Color(0xFFEFF6FF);

  static const orgColors = [
    [Color(0xFF1A56DB), Color(0xFF0E3A9F)],
    [Color(0xFF0891B2), Color(0xFF0E7490)],
    [Color(0xFF7C3AED), Color(0xFF5B21B6)],
    [Color(0xFF059669), Color(0xFF047857)],
    [Color(0xFFD97706), Color(0xFFB45309)],
    [Color(0xFFDC2626), Color(0xFFB91C1C)],
    [Color(0xFF0284C7), Color(0xFF0369A1)],
    [Color(0xFF9333EA), Color(0xFF7E22CE)],
  ];

  static List<Color> orgGradient(String id) =>
      orgColors[id.hashCode.abs() % orgColors.length];

  static Color orgColor(String id) => orgGradient(id)[0];

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF1A56DB).withValues(alpha: 0.07),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> avatarGlow(String id) => [
    BoxShadow(
      color: orgColor(id).withValues(alpha: 0.35),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────
// HERO WAVE CLIPPER
// ─────────────────────────────────────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width * 0.5, size.height + 28,
      size.width, size.height - 40,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

// ─────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final AuthService _authService = getIt<AuthService>();
  final OrganizationService _organizationService = getIt<OrganizationService>();
  final UpdateService _updateService = getIt<UpdateService>();

  Future<Owner?>? _ownerFuture;
  Future<List<Organization>>? _orgsFuture;
  final Map<String, Future<Membership?>> _membershipFutures = {};

  late final AnimationController _listAnimCtrl;

  final AsyncLock _createOrgLock = AsyncLock();
  final AsyncLock _joinOrgLock   = AsyncLock();
  final AsyncLock _dialogLock    = AsyncLock();
  final AsyncLock _logoutLock    = AsyncLock();
  final AsyncLock _leaveOrgLock  = AsyncLock();

  int  _overlayCount    = 0;
  bool _updateAvailable = false;
  bool _checkingUpdate  = false;
  bool _isDisposed      = false;
  Timer? _updateCheckTimer;
  Timer? _resizeDebounceTimer;
  bool  _isDismissing   = false;
  bool  _isResizing     = false;
  Size  _lastSize       = Size.zero;
  
  bool get _hasOpenOverlay => _overlayCount > 0;

  final ScrollController _scrollCtrl = ScrollController();
  double _appBarOpacity = 0.0;

  // ── lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _lastSize = PlatformDispatcher.instance.implicitView?.physicalSize ?? Size.zero;
    _listAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _ownerFuture = _authService.getCurrentOwner();
    _ownerFuture?.then((owner) {
      if (owner != null && mounted) {
        setState(() {
          _orgsFuture = _organizationService.getUserOrganizations(owner.id);
        });
        _orgsFuture?.then((_) {
          if (mounted) _listAnimCtrl.forward();
        });
      }
    });

    WidgetsBinding.instance.addObserver(this);

    _scrollCtrl.addListener(() {
      if (_isResizing) return;
      const double scrollFadeStart = 160.0;
      const double scrollFadeEnd   = 280.0;
      final raw = (_scrollCtrl.offset - scrollFadeStart) /
          (scrollFadeEnd - scrollFadeStart);
      final opacity = raw.clamp(0.0, 1.0);
      if ((opacity - _appBarOpacity).abs() > 0.01) {
        setState(() => _appBarOpacity = opacity);
      }
    });

    _updateCheckTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isDisposed) _backgroundUpdateCheck();
    });
  }

  @override
  void dispose() {
    _listAnimCtrl.dispose();
    _scrollCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _resizeDebounceTimer?.cancel();
    _updateCheckTimer?.cancel();
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final newSize = PlatformDispatcher.instance.implicitView?.physicalSize ?? Size.zero;
    if (newSize == _lastSize) return;
    _lastSize = newSize;

    if (!_isResizing && mounted) {
      // plain assignment, no rebuild:
      _isResizing = true;
      // Then force a single repaint after resize ends, not a full rebuild:
      WidgetsBinding.instance.scheduleFrame();
    }
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _isResizing = false);
      final w = MediaQuery.sizeOf(context).width;
      final h = MediaQuery.sizeOf(context).height;
      if (w < 360 || h < 600) {
        if (_hasOpenOverlay) _dismissAllOverlays();
      }
    });
  }

  // ── helpers ────────────────────────────────────────────────

  void _refreshOrgs(String ownerId) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _membershipFutures.clear();
      _orgsFuture = _organizationService.getUserOrganizations(ownerId);
    });
    _listAnimCtrl.reset();
    _orgsFuture?.then((_) {
      if (mounted) _listAnimCtrl.forward();
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

  bool   _isSmallScreen(BuildContext ctx) => MediaQuery.of(ctx).size.width < 600;
  double _getDialogWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w < 600)  return w * 0.92;
    if (w < 1200) return 500;
    return 600;
  }

  // ── update ─────────────────────────────────────────────────

  Future<void> _backgroundUpdateCheck() async {
    if (_isDisposed || !mounted) return;
    setState(() => _checkingUpdate = true);
    try {
      final available = await _updateService
          .isUpdateAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!_isDisposed && mounted) {
        setState(() {
          _updateAvailable = available;
          _checkingUpdate  = false;
        });
      }
    } catch (_) {
      if (!_isDisposed && mounted) {
        setState(() {
          _updateAvailable = false;
          _checkingUpdate  = false;
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate || _isDisposed) return;
    setState(() => _checkingUpdate = true);
    try {
      final available = await _updateService
          .isUpdateAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!_isDisposed && mounted) {
        setState(() {
          _updateAvailable = available;
          _checkingUpdate  = false;
        });
      }
    } catch (_) {
      if (!_isDisposed && mounted) {
        setState(() {
          _checkingUpdate  = false;
          _updateAvailable = false;
        });
      }
    }
  }

  Future<void> _performUpdate() async {
    if (!kIsWeb && Platform.isWindows) {
      final confirm = await _showTrackedDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppTranslations.of(ctx).text('available_update'),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(children: [
                    Text(
                      AppTranslations.of(ctx).text('new_update_ready'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoBanner(AppTranslations.of(ctx).text('click_update_button')),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _DS.textSecondary,
                          side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppTranslations.of(ctx).text('later'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(AppTranslations.of(ctx).text('update'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );

      if (confirm == true && mounted) {
        // Capture navigator before async gap
        final nav = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final failedText = AppTranslations.of(context).text('update_failed');

        final progressNotifier = ValueNotifier<double>(0.0);
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: true),
        );
        await _updateService.performUpdate(
            onProgress: (p) => progressNotifier.value = p);
        if (mounted) {
          nav.pop();
          messenger.showSnackBar(SnackBar(
            content: Text(failedText),
            backgroundColor: Colors.red,
          ));
        }
      }
      return;
    }

    // Non-Windows path
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final successText = AppTranslations.of(context).text('update_success');
    final failedText  = AppTranslations.of(context).text('update_failed');

    final progressNotifier = ValueNotifier<double>(0.0);
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: true),
    );
    final success = await _updateService.performFlexibleUpdate();
    if (mounted) {
      nav.pop();
      if (success) {
        setState(() => _updateAvailable = false);
        messenger.showSnackBar(SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(failedText),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// Shared progress dialog used for update and delete flows.
  Widget _buildProgressDialog(
    BuildContext ctx,
    ValueNotifier<double> progressNotifier, {
    bool isGreen = false,
    String? titleKey,
    String? subtitleKey,
  }) {
    final color = isGreen ? const Color(0xFF16A34A) : Colors.red;
    final bgColor = isGreen ? const Color(0xFFDCFCE7) : const Color(0xFFFFEBEB);
    final icon = isGreen ? Icons.download_rounded : Icons.delete_forever_rounded;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (ctx2, progress, _) {
              final isDone = progress >= 1.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                    child: Icon(
                      isDone ? Icons.check_rounded : icon,
                      color: color, size: 30,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isDone
                        ? AppTranslations.of(ctx2).text('installing')
                        : AppTranslations.of(ctx2).text(titleKey ?? 'downloading_update'),
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _DS.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isDone
                        ? AppTranslations.of(ctx2).text('please_dont_close')
                        : AppTranslations.of(ctx2).text(subtitleKey ?? 'connecting'),
                    style: const TextStyle(fontSize: 13, color: _DS.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress <= 0 || progress >= 1.0 ? null : progress,
                      minHeight: 8,
                      backgroundColor: bgColor,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  if (progress > 0 && progress < 1.0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: color,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── dialogs ────────────────────────────────────────────────

  void _showLanguageDialog() {
    final notifier = getIt<LocaleNotifier>();
    Locale tempLocale = notifier.locale;
    _showTrackedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_DS.primaryMid, _DS.primaryDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.language_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppTranslations.of(ctx).text('select_language'),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: RadioGroup<Locale>(
                    groupValue: tempLocale,
                    onChanged: (v) {
                      if (v != null) setDialogState(() => tempLocale = v);
                    },
                    child: Column(children: [
                      _buildLanguageTile(
                        locale: const Locale('vi', 'VN'),
                        countryCode: 'VN',
                        label: AppTranslations.of(ctx).text('vietnamese'),
                        selected: tempLocale == const Locale('vi', 'VN'),
                        onTap: () => setDialogState(() => tempLocale = const Locale('vi', 'VN')),
                      ),
                      const SizedBox(height: 8),
                      _buildLanguageTile(
                        locale: const Locale('en', 'US'),
                        countryCode: 'US',
                        label: AppTranslations.of(ctx).text('english'),
                        selected: tempLocale == const Locale('en', 'US'),
                        onTap: () => setDialogState(() => tempLocale = const Locale('en', 'US')),
                      ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _DS.textSecondary,
                          side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppTranslations.of(ctx).text('cancel'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          notifier.setLocale(tempLocale);
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _DS.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(AppTranslations.of(ctx).text('confirm'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile({
    required Locale locale,
    required String countryCode,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _DS.primaryLight : _DS.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _DS.primary.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 38, height: 26,
              child: FittedBox(
                fit: BoxFit.cover,
                child: CountryFlag.fromCountryCode(countryCode),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15,
                color: selected ? _DS.primary : _DS.textPrimary,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(color: _DS.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
            ),
        ]),
      ),
    );
  }

  Future<void> _showCreateOrganizationDialog() async {
    final nameCtrl    = TextEditingController();
    final addressCtrl = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final emailCtrl   = TextEditingController();
    final taxCtrl     = TextEditingController();
    final formKey     = GlobalKey<FormState>();
    bool isSubmitting = false;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  color: _DS.primaryLight,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _DS.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_business, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('tooltip_create'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildField(nameCtrl, AppTranslations.of(ctx).text('org_name_required'),
                            hint: AppTranslations.of(ctx).text('org_name_example'),
                            icon: Icons.business, maxLength: 100,
                            autofocus: !_isSmallScreen(ctx),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? AppTranslations.of(ctx).text('please_enter_org_name')
                                : null),
                        const SizedBox(height: 14),
                        _buildField(addressCtrl, AppTranslations.of(ctx).text('address'),
                            hint: AppTranslations.of(ctx).text('address_example'),
                            icon: Icons.location_on, maxLength: 300, maxLines: 2,
                            textCapitalization: TextCapitalization.words,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 14),
                        _buildField(phoneCtrl, AppTranslations.of(ctx).text('phone'),
                            hint: AppTranslations.of(ctx).text('phone_example'),
                            icon: Icons.phone, maxLength: 20,
                            keyboardType: TextInputType.phone,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 14),
                        _buildField(emailCtrl, AppTranslations.of(ctx).text('email'),
                            hint: AppTranslations.of(ctx).text('email_example'),
                            icon: Icons.email, maxLength: 254,
                            keyboardType: TextInputType.emailAddress,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                final re = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                if (!re.hasMatch(v)) return AppTranslations.of(ctx).text('email_invalid');
                              }
                              return null;
                            }),
                        const SizedBox(height: 14),
                        _buildField(taxCtrl, AppTranslations.of(ctx).text('tax_code'),
                            hint: '0123456789 or 0123456789-001',
                            icon: Icons.receipt_long, maxLength: 14,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty && !_organizationService.isValidTaxCode(v)) {
                                return 'Invalid tax code format';
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildInfoBanner(AppTranslations.of(ctx).text('contact_info_on_invoice')),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    StatefulBuilder(
                      builder: (ctx2, setButtonState) {
                        return FilledButton.icon(
                          onPressed: isSubmitting ? null : () async {
                            if (_createOrgLock.isLocked) return;
                            if (!formKey.currentState!.validate()) return;
                            setButtonState(() => isSubmitting = true);
                            await _createOrgLock.run(() async {
                              // Capture navigator from the dialog context before async
                              final dialogNav = Navigator.of(ctx);
                              final screenMessenger = ScaffoldMessenger.of(context);
                              _showTrackedDialog(
                                context: ctx,
                                barrierDismissible: false,
                                builder: (lctx) => _buildLoadingDialog(
                                  AppTranslations.of(lctx).text('create_action'),
                                ),
                              );
                              try {
                                final owner = await _authService.getCurrentOwner();
                                if (owner == null) {
                                  if (mounted) dialogNav.pop();
                                  return;
                                }
                                await _organizationService.createOrganization(
                                  name: nameCtrl.text.trim(),
                                  ownerId: owner.id,
                                  address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                  email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                  taxCode: taxCtrl.text.trim().isEmpty ? null : taxCtrl.text.trim(),
                                );
                                if (!mounted) return;
                                dialogNav.pop(); // pop loader
                                dialogNav.pop(); // pop create dialog
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _showSuccessSnack(AppTranslations.of(context).text('org_created_success'));
                                    _refreshOrgs(owner.id);
                                  }
                                });
                              } catch (e) {
                                if (mounted) {
                                  dialogNav.pop(); // pop loader
                                  screenMessenger.showSnackBar(SnackBar(
                                    content: Text(e.toString()),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            });
                            if (mounted) setButtonState(() => isSubmitting = false);
                          },
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(AppTranslations.of(ctx).text('create_action')),
                          style: FilledButton.styleFrom(backgroundColor: _DS.primary),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    taxCtrl.dispose();
  }

  Future<void> _showJoinOrganizationDialog() async {
    final ctrl = TextEditingController();
    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx) * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  color: _DS.primaryLight,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _DS.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.group_add, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('tooltip_join'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppTranslations.of(ctx).text('enter_invite_code'),
                      style: const TextStyle(fontSize: 14, color: _DS.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 8,
                      autofocus: !_isSmallScreen(ctx),
                      style: const TextStyle(
                          letterSpacing: 4, fontWeight: FontWeight.w700, fontSize: 18),
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: AppTranslations.of(ctx).text('invite_code'),
                        hintText: AppTranslations.of(ctx).text('invite_code_example'),
                        prefixIcon: const Icon(Icons.vpn_key),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _DS.primary, width: 1.8),
                        ),
                        filled: true,
                        fillColor: _DS.surface,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        _joinOrgLock.run(() async {
                          final code = ctrl.text.trim().toUpperCase();
                          // Capture before async
                          final dialogNav      = Navigator.of(ctx);
                          final screenMessenger = ScaffoldMessenger.of(context);
                          if (code.length != 8) {
                            screenMessenger.showSnackBar(SnackBar(
                              content: Text(AppTranslations.of(context).text('invite_code_8_chars')),
                              backgroundColor: Colors.orange,
                            ));
                            return;
                          }
                          final owner = await _authService.getCurrentOwner();
                          if (owner == null || !mounted) return;
                          _showTrackedDialog(
                            context: ctx,
                            barrierDismissible: false,
                            builder: (lctx) => _buildLoadingDialog(
                              AppTranslations.of(lctx).text('join_org'),
                            ),
                          );
                          final success = await _organizationService.joinOrganization(
                              ownerId: owner.id, inviteCode: code);
                          if (!mounted) return;
                          dialogNav.pop(); // pop loader
                          dialogNav.pop(); // pop join dialog
                          screenMessenger.showSnackBar(SnackBar(
                            content: Text(success
                                ? AppTranslations.of(context).text('join_org_success')
                                : AppTranslations.of(context).text('invite_code_invalid')),
                            backgroundColor: success ? Colors.green : Colors.red,
                          ));
                          if (success) _refreshOrgs(owner.id);
                        });
                      },
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(AppTranslations.of(ctx).text('join')),
                      style: FilledButton.styleFrom(backgroundColor: _DS.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showLeaveOrganizationDialog(Organization org, String ownerId) async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange[400]!, Colors.orange[700]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppTranslations.of(ctx).text('leave_org'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Text(
                    AppTranslations.of(ctx).textWithParams('leave_org_confirm', {'name': org.name}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  _buildWarningBanner(AppTranslations.of(ctx).text('lose_access_warning'), Colors.orange),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _DS.textSecondary,
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppTranslations.of(ctx).text('cancel'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.exit_to_app_rounded, size: 16),
                      label: Text(AppTranslations.of(ctx).text('leave_action'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      final nav       = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final successText = AppTranslations.of(context).text('left_org_success');
      final failText    = AppTranslations.of(context).text('cannot_leave_org');

      _leaveOrgLock.run(() async {
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (lctx) => _buildLoadingDialog(AppTranslations.of(lctx).text('leaving_org')),
        );
        final success = await _organizationService.leaveOrganization(ownerId, org.id);
        if (!mounted) return;
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(success ? successText : failText),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
        if (success) _refreshOrgs(ownerId);
      });
    }
  }

  Future<void> _showDeleteOrganizationDialog(Organization org, String ownerId) async {
    final nameCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.delete_forever, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('delete_org'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppTranslations.of(ctx).textWithParams('delete_org_warning', {'name': org.name}),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_buildings')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_rooms')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_tenants')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_payments')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_members')),
                        const SizedBox(height: 12),
                        _buildWarningBanner(AppTranslations.of(ctx).text('warning_cannot_undo'), Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.of(ctx).text('confirm_enter_org_name'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: nameCtrl,
                          maxLength: 100,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: org.name,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.edit),
                          ),
                          validator: (v) => (v == null || v.trim() != org.name)
                              ? AppTranslations.of(ctx).text('name_mismatch')
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        nameCtrl.dispose();
                        Navigator.pop(ctx, false);
                      },
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
                      },
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: Text(AppTranslations.of(ctx).text('delete_permanently')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      // Capture before async
      final nav       = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final successText = AppTranslations.of(context).text('deleted_org_success');
      final failText    = AppTranslations.of(context).text('cannot_delete_org');

      final progressNotifier = ValueNotifier<double>(0.0);
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: false,
            titleKey: 'deleting_org'),
      );
      final success = await _organizationService.deleteOrganization(
          ownerId, org.id,
          onProgress: (p) => progressNotifier.value = p);
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Row(children: [
          Icon(success ? Icons.check_circle : Icons.error, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(success ? successText : failText)),
        ]),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      if (success) _refreshOrgs(ownerId);
    }
  }

  void _showOrganizationInfo(Organization org) {
    _showTrackedDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        org.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppTranslations.of(ctx).text('org_info'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          org.name,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 17,
                            fontWeight: FontWeight.w800, letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoTile(Icons.badge_outlined,
                          AppTranslations.of(ctx).text('id'), org.id, monospace: true),
                      _buildInfoTile(Icons.calendar_today_outlined,
                          AppTranslations.of(ctx).text('created_date'),
                          _formatDate(org.createdAt, ctx)),
                      if (org.updatedAt != null)
                        _buildInfoTile(Icons.update_rounded,
                            AppTranslations.of(ctx).text('last_updated'),
                            _formatDate(org.updatedAt!, ctx)),
                      if (org.address?.isNotEmpty == true)
                        _buildInfoTile(Icons.location_on_outlined,
                            AppTranslations.of(ctx).text('address_label'), org.address!),
                      if (org.phone?.isNotEmpty == true)
                        _buildInfoTile(Icons.phone_outlined,
                            AppTranslations.of(ctx).text('phone_label'), org.phone!),
                      if (org.email?.isNotEmpty == true)
                        _buildInfoTile(Icons.email_outlined,
                            AppTranslations.of(ctx).text('email_label'), org.email!),
                      if (org.bankName?.isNotEmpty == true)
                        _buildInfoTile(Icons.account_balance_outlined,
                            AppTranslations.of(ctx).text('bank_name'), org.bankName!),
                      if (org.bankAccountNumber?.isNotEmpty == true)
                        _buildInfoTile(Icons.credit_card_outlined,
                            AppTranslations.of(ctx).text('account_number'), org.bankAccountNumber!),
                      if (org.bankAccountName?.isNotEmpty == true)
                        _buildInfoTile(Icons.person_outline_rounded,
                            AppTranslations.of(ctx).text('account_holder'), org.bankAccountName!),
                      if (org.taxCode?.isNotEmpty == true)
                        _buildInfoTile(Icons.receipt_long_outlined,
                            AppTranslations.of(ctx).text('tax_code'), org.taxCode!),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _DS.textSecondary,
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppTranslations.of(ctx).text('close'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value,
      {bool monospace = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _DS.primaryLight, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 14, color: _DS.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _DS.textSecondary, letterSpacing: 0.3,
                    )),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: _DS.textPrimary,
                    fontFamily: monospace ? 'monospace' : null,
                    letterSpacing: monospace ? 0.5 : 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMigrateOrganizationDialog(
      Organization sourceOrg, String ownerId, bool deleteAfter) async {
    final targetCtrl = TextEditingController();
    Map<String, int>? preview;
    String? status;
    bool loading = false;
    bool started = false;
    double progress = 0.0;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: !started,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _getDialogWidth(ctx),
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: deleteAfter
                          ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                          : [_DS.primaryMid, _DS.primaryDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        deleteAfter ? Icons.delete_sweep_rounded : Icons.compare_arrows_rounded,
                        color: Colors.white, size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      deleteAfter
                          ? AppTranslations.of(ctx).text('migrate_and_delete')
                          : AppTranslations.of(ctx).text('migrate_org_data'),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _DS.primaryLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _DS.primary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppTranslations.of(ctx).text('source_org_info'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 11,
                                    color: _DS.primary, letterSpacing: 0.5,
                                  )),
                              const SizedBox(height: 6),
                              Text(
                                AppTranslations.of(ctx).textWithParams('name_with_value', {'name': sourceOrg.name}),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: _DS.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppTranslations.of(ctx).textWithParams('id_with_value', {'id': sourceOrg.id}),
                                style: const TextStyle(fontSize: 12, color: _DS.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: targetCtrl,
                          maxLength: 50,
                          enabled: !started,
                          decoration: InputDecoration(
                            counterText: '',
                            labelText: AppTranslations.of(ctx).text('target_org_id'),
                            hintText: AppTranslations.of(ctx).text('enter_target_org_id'),
                            helperText: AppTranslations.of(ctx).text('target_org_id_placeholder'),
                            prefixIcon: const Icon(Icons.business_outlined),
                            filled: true,
                            fillColor: _DS.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _DS.primary, width: 1.8),
                            ),
                          ),
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.preview_rounded, size: 15, color: Color(0xFF16A34A)),
                                  SizedBox(width: 6),
                                  Text('Preview',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12, color: Color(0xFF16A34A),
                                      )),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                  AppTranslations.of(ctx).textWithParams('preview_stats', {
                                    'buildings': preview?['buildings'] ?? 0,
                                    'rooms': preview?['rooms'] ?? 0,
                                    'tenants': preview?['tenants'] ?? 0,
                                    'payments': preview?['payments'] ?? 0,
                                  }),
                                  style: const TextStyle(fontSize: 13, color: _DS.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (status != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _DS.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                            ),
                            child: Text(status!,
                                style: const TextStyle(fontSize: 13, color: _DS.textSecondary)),
                          ),
                        ],
                        if (loading) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: deleteAfter ? const Color(0xFFFFEBEB) : _DS.primaryLight,
                              valueColor: AlwaysStoppedAnimation(deleteAfter ? Colors.red : _DS.primary),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: deleteAfter ? Colors.red : _DS.primary,
                            ),
                          ),
                        ],
                        if (deleteAfter && !started) ...[
                          const SizedBox(height: 14),
                          _buildWarningBanner(
                              AppTranslations.of(ctx).text('warning_cannot_undo'), Colors.red),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!started) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(AppTranslations.of(ctx).text('cancel'),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          setDialogState(() => status = null);
                          final id = targetCtrl.text.trim();
                          if (id.isEmpty) {
                            setDialogState(() =>
                                status = AppTranslations.of(ctx).text('please_enter_target_id'));
                            return;
                          }
                          setDialogState(() =>
                              status = AppTranslations.of(ctx).text('fetching_preview'));
                          try {
                            final result =
                                await _organizationService.getMigrationPreview(sourceOrg.id);
                            setDialogState(() {
                              preview = result;
                              status = AppTranslations.of(ctx).text('fetched_preview');
                            });
                          } catch (e) {
                            setDialogState(() => status = AppTranslations.of(ctx)
                                .textWithParams('preview_error', {'error': e}));
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _DS.primary,
                          side: BorderSide(color: _DS.primary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppTranslations.of(ctx).text('preview'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final targetId = targetCtrl.text.trim();
                            if (targetId.isEmpty) {
                              setDialogState(() => status =
                                  AppTranslations.of(ctx).text('please_enter_target_id'));
                              return;
                            }
                            setDialogState(() {
                              loading  = true;
                              started  = true;
                              status   = deleteAfter
                                  ? AppTranslations.of(ctx).text('migrating_and_deleting')
                                  : AppTranslations.of(ctx).text('migrating_data');
                              progress = 0.0;
                            });
                            // Capture before async
                            final dialogNav = Navigator.of(ctx);
                            bool success = false;
                            try {
                              if (deleteAfter) {
                                success = await _organizationService.migrateAndDeleteOrganization(
                                  ownerId: ownerId,
                                  sourceOrgId: sourceOrg.id,
                                  targetOrgId: targetId,
                                  onProgress: (p) => setDialogState(() => progress = p),
                                  onStatusUpdate: (msg) => setDialogState(() => status = msg),
                                );
                              } else {
                                success = await _organizationService.migrateOrganization(
                                  ownerId: ownerId,
                                  sourceOrgId: sourceOrg.id,
                                  targetOrgId: targetId,
                                  onProgress: (p) => setDialogState(() => progress = p),
                                  onStatusUpdate: (msg) => setDialogState(() => status = msg),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => status = AppTranslations.of(ctx)
                                  .textWithParams('error', {'error': e}));
                            }
                            setDialogState(() { loading = false; started = false; });
                            if (success && mounted) {
                              dialogNav.pop();
                              _showSuccessSnack(deleteAfter
                                  ? AppTranslations.of(context).text('migrated_and_deleted_success')
                                  : AppTranslations.of(context).text('migrated_data_success'));
                              _refreshOrgs(ownerId);
                            } else {
                              setDialogState(() =>
                                  status = AppTranslations.of(ctx).text('operation_failed'));
                            }
                          },
                          icon: Icon(
                            deleteAfter ? Icons.delete_sweep_rounded : Icons.compare_arrows_rounded,
                            size: 16,
                          ),
                          label: Text(
                            deleteAfter
                                ? AppTranslations.of(ctx).text('migrate_and_delete_action')
                                : AppTranslations.of(ctx).text('migrate_action'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: deleteAfter ? Colors.red : _DS.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditOrganizationDialog(Organization org, String ownerId) async {
    final nameCtrl            = TextEditingController(text: org.name);
    final addressCtrl         = TextEditingController(text: org.address ?? '');
    final phoneCtrl           = TextEditingController(text: org.phone ?? '');
    final emailCtrl           = TextEditingController(text: org.email ?? '');
    final taxCtrl             = TextEditingController(text: org.taxCode ?? '');
    final bankNameCtrl        = TextEditingController(text: org.bankName ?? '');
    final bankAccountCtrl     = TextEditingController(text: org.bankAccountNumber ?? '');
    final bankAccountNameCtrl = TextEditingController(text: org.bankAccountName ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('edit_org'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionLabel(ctx, Icons.business_rounded,
                            AppTranslations.of(ctx).text('basic_info')),
                        const SizedBox(height: 10),
                        _buildField(nameCtrl, AppTranslations.of(ctx).text('org_name_required'),
                            hint: AppTranslations.of(ctx).text('org_name_example'),
                            icon: Icons.business, maxLength: 100,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? AppTranslations.of(ctx).text('please_enter_org_name')
                                : null),
                        const SizedBox(height: 12),
                        _buildField(addressCtrl, AppTranslations.of(ctx).text('address'),
                            hint: AppTranslations.of(ctx).text('address_example'),
                            icon: Icons.location_on, maxLength: 300, maxLines: 2,
                            textCapitalization: TextCapitalization.words,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(phoneCtrl, AppTranslations.of(ctx).text('phone'),
                            hint: AppTranslations.of(ctx).text('phone_example'),
                            icon: Icons.phone, maxLength: 20,
                            keyboardType: TextInputType.phone,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(emailCtrl, AppTranslations.of(ctx).text('email'),
                            hint: AppTranslations.of(ctx).text('email_example'),
                            icon: Icons.email, maxLength: 254,
                            keyboardType: TextInputType.emailAddress,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                final re = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                if (!re.hasMatch(v)) return AppTranslations.of(ctx).text('email_invalid');
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildField(taxCtrl, AppTranslations.of(ctx).text('tax_code'),
                            hint: '0123456789 or 0123456789-001',
                            icon: Icons.receipt_long, maxLength: 14,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty &&
                                  !_organizationService.isValidTaxCode(v)) {
                                return 'Invalid tax code format';
                              }
                              return null;
                            }),
                        const SizedBox(height: 20),
                        _buildSectionLabel(ctx, Icons.account_balance_rounded,
                            AppTranslations.of(ctx).text('bank_info')),
                        const SizedBox(height: 10),
                        _buildField(bankNameCtrl, AppTranslations.of(ctx).text('bank_name'),
                            hint: 'Vietcombank, Techcombank...',
                            icon: Icons.account_balance, maxLength: 100,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(bankAccountCtrl, AppTranslations.of(ctx).text('account_number'),
                            hint: '1234567890',
                            icon: Icons.credit_card, maxLength: 20,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty &&
                                  !_organizationService.isValidBankAccountNumber(v)) {
                                return AppTranslations.of(ctx).text('invalid_bank_account');
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildField(bankAccountNameCtrl, AppTranslations.of(ctx).text('account_holder'),
                            hint: 'NGUYEN VAN A',
                            icon: Icons.person, maxLength: 100,
                            textCapitalization: TextCapitalization.characters,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildInfoBanner(AppTranslations.of(ctx).text('contact_info_on_invoice')),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    StatefulBuilder(
                      builder: (ctx2, setButtonState) {
                        return FilledButton.icon(
                          onPressed: isSubmitting ? null : () async {
                            if (!formKey.currentState!.validate()) return;
                            setButtonState(() => isSubmitting = true);
                            // Capture before async
                            final dialogNav      = Navigator.of(ctx);
                            final screenMessenger = ScaffoldMessenger.of(context);
                            _showTrackedDialog(
                              context: ctx,
                              barrierDismissible: false,
                              builder: (lctx) =>
                                  _buildLoadingDialog(AppTranslations.of(lctx).text('saving')),
                            );
                            try {
                              final success = await _organizationService.updateOrganization(
                                ownerId: ownerId,
                                orgId: org.id,
                                name: nameCtrl.text.trim(),
                                address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                taxCode: taxCtrl.text.trim().isEmpty ? null : taxCtrl.text.trim(),
                                bankName: bankNameCtrl.text.trim().isEmpty ? null : bankNameCtrl.text.trim(),
                                bankAccountNumber: bankAccountCtrl.text.trim().isEmpty
                                    ? null : bankAccountCtrl.text.trim(),
                                bankAccountName: bankAccountNameCtrl.text.trim().isEmpty
                                    ? null : bankAccountNameCtrl.text.trim(),
                              );
                              if (!mounted) return;
                              dialogNav.pop(); // pop loader
                              if (success) {
                                dialogNav.pop(); // pop edit dialog
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _showSuccessSnack(AppTranslations.of(context).text('org_updated_success'));
                                    _refreshOrgs(ownerId);
                                  }
                                });
                              } else {
                                screenMessenger.showSnackBar(SnackBar(
                                  content: Text(AppTranslations.of(context).text('update_failed')),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            } catch (e) {
                              if (mounted) {
                                dialogNav.pop(); // pop loader
                                screenMessenger.showSnackBar(SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            }
                            if (mounted) setButtonState(() => isSubmitting = false);
                          },
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(AppTranslations.of(ctx).text('save')),
                          style: FilledButton.styleFrom(backgroundColor: Colors.green[600]),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    taxCtrl.dispose();
    bankNameCtrl.dispose();
    bankAccountCtrl.dispose();
    bankAccountNameCtrl.dispose();
  }

  Widget _buildSectionLabel(BuildContext ctx, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _DS.primary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _DS.primary, letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: _DS.primary.withValues(alpha: 0.2))),
      ],
    );
  }

  void _showOrganizationOptions(Organization org, String ownerId, bool isAdmin) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLarge = screenWidth >= 600;
    final gradient = _DS.orgGradient(org.id);

    Widget sheetHeader = Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            if (isLarge)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  padding: EdgeInsets.zero,
                ),
              ),
            if (!isLarge) ...[
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
              ),
              child: Center(
                child: Text(
                  org.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              org.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            _buildRoleBadgeLight(isAdmin),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );

    List<Widget> menuItems = [
      _buildOptionTile(
        icon: Icons.open_in_new_rounded,
        iconColor: _DS.primary,
        title: AppTranslations.of(context).text('open_org'),
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, AppRouter.oranizationScreen,
              arguments: {'organization': org});
        },
      ),
      _buildOptionTile(
        icon: Icons.info_outline_rounded,
        iconColor: Colors.blue[600]!,
        title: AppTranslations.of(context).text('view_org_info'),
        subtitle: AppTranslations.of(context).text('org_details_and_id'),
        onTap: () {
          Navigator.pop(context);
          _showOrganizationInfo(org);
        },
      ),
      if (isAdmin) ...[
        _buildOptionTile(
          icon: Icons.edit_rounded,
          iconColor: Colors.green[600]!,
          title: AppTranslations.of(context).text('edit_org'),
          subtitle: AppTranslations.of(context).text('edit_org_details'),
          onTap: () {
            Navigator.pop(context);
            _showEditOrganizationDialog(org, ownerId);
          },
        ),
        _buildOptionTile(
          icon: Icons.compare_arrows_rounded,
          iconColor: Colors.blue[600]!,
          title: AppTranslations.of(context).text('migrate_to_other_org'),
          subtitle: AppTranslations.of(context).text('copy_all_data'),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, false);
          },
        ),
        _buildOptionTile(
          icon: Icons.delete_sweep_rounded,
          iconColor: Colors.red[600]!,
          title: AppTranslations.of(context).text('migrate_and_delete_org'),
          subtitle: AppTranslations.of(context).text('transfer_and_delete'),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, true);
          },
        ),
        _buildOptionTile(
          icon: Icons.delete_forever_rounded,
          iconColor: Colors.red[700]!,
          title: AppTranslations.of(context).text('delete_org_action'),
          subtitle: AppTranslations.of(context).text('delete_org_permanently'),
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _showDeleteOrganizationDialog(org, ownerId);
          },
        ),
      ] else ...[
        _buildOptionTile(
          icon: Icons.exit_to_app_rounded,
          iconColor: Colors.orange[700]!,
          title: AppTranslations.of(context).text('leave_org_action'),
          subtitle: AppTranslations.of(context).text('will_lose_access'),
          onTap: () {
            Navigator.pop(context);
            _showLeaveOrganizationDialog(org, ownerId);
          },
        ),
      ],
      const SizedBox(height: 8),
    ];

    if (isLarge) {
      _showTrackedDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 420,
            child: SafeArea(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    sheetHeader,
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: menuItems),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      _showTrackedBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              sheetHeader,
              Flexible(
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: menuItems),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildRoleBadgeLight(bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isAdmin ? Icons.star_rounded : Icons.person_rounded,
          size: 12, color: Colors.white,
        ),
        const SizedBox(width: 4),
        Text(
          isAdmin
              ? AppTranslations.of(context).text('admin')
              : AppTranslations.of(context).text('member'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ]),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.logout_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppTranslations.of(ctx).text('confirm_logout'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  AppTranslations.of(ctx).text('confirm_logout_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _DS.textSecondary,
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppTranslations.of(ctx).text('cancel'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: Text(AppTranslations.of(ctx).text('logout_action'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      _logoutLock.run(() async {
        if (mounted) {
          setState(() {
            _ownerFuture = null;
            _orgsFuture  = null;
            _membershipFutures.clear();
          });
        }
        await _authService.signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSmall = _isSmallScreen(context);
    const minWidth  = 360.0;
    const minHeight = 600.0;

    return Scaffold(
      backgroundColor: _DS.surface,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          return _buildTooSmallWarning(context, constraints, minWidth, minHeight);
        }
        return FutureBuilder<Owner?>(
          future: _ownerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Loading3(size: 50));
            }
            final owner = snapshot.data;
            if (owner == null) return _buildNoUserState(context, isSmall);

            return RefreshIndicator(
              color: _DS.primary,
              onRefresh: () async {
                _refreshOrgs(owner.id);
                await _checkForUpdate();
              },
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  SliverToBoxAdapter(child: _buildHero(context, owner, isSmall)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isSmall ? 16 : 20, isSmall ? 16 : 24, isSmall ? 16 : 20, 12,
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _DS.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.business_rounded, color: _DS.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppTranslations.of(context).text('your_organizations'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: isSmall ? 17 : 19,
                              color: _DS.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        _buildHeaderButton(
                          label: AppTranslations.of(context).text('join'),
                          icon: Icons.group_add_rounded,
                          outlined: true,
                          onTap: () => _dialogLock.run(_showJoinOrganizationDialog),
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderButton(
                          label: AppTranslations.of(context).text('create'),
                          icon: Icons.add_rounded,
                          outlined: false,
                          onTap: () => _dialogLock.run(_showCreateOrganizationDialog),
                        ),
                      ]),
                    ),
                  ),
                  FutureBuilder<List<Organization>>(
                    future: _orgsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator(color: _DS.primary)),
                        );
                      }
                      final orgs = snapshot.data ?? [];
                      if (orgs.isEmpty) {
                        return SliverFillRemaining(child: _buildEmptyState(context, isSmall));
                      }
                      return SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _buildOrgCard(context, orgs[index], owner, isSmall, index),
                            childCount: orgs.length,
                          ),
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            );
          },
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HERO
  // ─────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Owner owner, bool isSmall) {
    final calendarText =
        '${AppTranslations.of(context).text('joined_at')}: ${_formatDate(owner.createdAt, context)}';

    final chips = [
      _buildHeroChip(Icons.email_outlined, owner.email),
      _buildHeroChip(Icons.calendar_today_outlined, calendarText),
    ];

    // FIX: BackdropFilter always stays in the tree — only sigma changes.
    // Conditionally adding/removing BackdropFilter destroys/recreates a
    // compositor layer mid-frame, which causes context loss during resize.
    final blurSigma = _isResizing ? 0.0 : 6.0;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A56DB).withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipPath(
        clipper: _WaveClipper(),
        child: IntrinsicHeight(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image/background_image3.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.08),
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                isSmall ? 20 : 28,
                kToolbarHeight + 44,
                isSmall ? 20 : 28,
                isSmall ? 80 : 90,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _DS.primaryMid.withValues(alpha: 0.5),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: isSmall ? 28 : 34,
                          backgroundColor: _DS.primaryMid.withValues(alpha: 0.3),
                          child: Text(
                            owner.name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: isSmall ? 24 : 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isSmall ? 14 : 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppTranslations.of(context).text('hello').toUpperCase(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              owner.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmall ? 22 : 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmall ? 16 : 20),
                  // BackdropFilter always present — sigma goes to 0 during resize
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // APPBAR
  // ─────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final t = _appBarOpacity;
    final bgT   = Curves.easeIn.transform(t.clamp(0.0, 1.0));
    final textT = Curves.easeOut.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));

    final titleColor     = Color.lerp(Colors.white, _DS.textPrimary, textT)!;
    final bgColor        = Color.lerp(Colors.transparent, _DS.card, bgT)!;
    final dividerOpacity = bgT;

    // Solid dark pill when over photo, transitions to surface when scrolled
    final langBg = Color.lerp(
      const Color(0xFF1E293B),        // solid dark slate over photo
      _DS.surface,
      bgT,
    )!;
    final langBorder = Color.lerp(
      Colors.white.withValues(alpha: 0.15),
      Colors.grey.withValues(alpha: 0.25),
      bgT,
    )!;
    final langIcon = Color.lerp(Colors.white, _DS.textSecondary, textT)!;

    final logoutBg = Color.lerp(
      const Color(0xFF7F1D1D),        // solid dark red over photo
      Colors.red.withValues(alpha: 0.08),
      bgT,
    )!;
    final logoutBorder = Color.lerp(
      const Color(0xFFEF4444).withValues(alpha: 0.6),
      Colors.red.withValues(alpha: 0.25),
      bgT,
    )!;
    final logoutIcon = Color.lerp(
      const Color(0xFFFCA5A5),        // light red icon on dark red bg
      Colors.red[400]!,
      textT,
    )!;

    // FIX: BackdropFilter always stays in the tree for both title and actions.
    // We zero the sigma when resizing or when fully scrolled (opacity == 1).
    // This prevents compositor layer destruction mid-frame.
    final titleBlur = (_isResizing || _appBarOpacity >= 1.0)
        ? 0.0
        : 12.0 * (1 - _appBarOpacity);

    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      centerTitle: false,
      title: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: titleBlur, sigmaY: titleBlur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              // Glass pill fades out as appbar bg fades in
              color: Colors.white.withValues(alpha: 0.15 * (1 - _appBarOpacity)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              AppTranslations.of(context).text('dashboard'),
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Opacity(
          opacity: dividerOpacity,
          child: Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_updateAvailable && !_checkingUpdate)
              _buildAppBarBtn(
                icon: Icons.system_update_rounded,
                onTap: _performUpdate,
                tooltip: AppTranslations.of(context).text('update'),
                bgColor: const Color(0xFF1A3D2A),
                borderColor: Colors.green.withValues(alpha: 0.5),
                iconColor: const Color(0xFF81C784),
              ),
            _buildAppBarBtn(
              icon: Icons.language_rounded,
              onTap: _showLanguageDialog,
              tooltip: AppTranslations.of(context).text('lang'),
              bgColor: langBg,
              borderColor: langBorder,
              iconColor: langIcon,
            ),
            _buildAppBarBtn(
              icon: Icons.logout_rounded,
              onTap: _handleLogout,
              tooltip: AppTranslations.of(context).text('logout'),
              bgColor: logoutBg,
              borderColor: logoutBorder,
              iconColor: logoutIcon,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ],
    );
  }

  Widget _buildAppBarBtn({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required Color bgColor,
    required Color borderColor,
    required Color iconColor,
  }) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.8),
        ),
        child: IconButton(
          onPressed: onTap,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: iconColor, size: 19),
        ),
      );
    }

  // ─────────────────────────────────────────────────────────
  // ORG CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildOrgCard(
      BuildContext context, Organization org, Owner owner, bool isSmall, int index) {
    final gradient = _DS.orgGradient(org.id);
    final delay = index * 0.12;
    final animation = CurvedAnimation(
      parent: _listAnimCtrl,
      curve: Interval(
        delay.clamp(0.0, 0.9),
        (delay + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _DS.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _DS.cardShadow,
          border: Border.all(color: const Color(0x0F000000)),
        ),
        child: FutureBuilder<Membership?>(
          future: _membershipFutures.putIfAbsent(org.id, () {
            if (FirebaseAuth.instance.currentUser == null) return Future.value(null);
            return _organizationService.getUserMembership(owner.id, org.id);
          }),
          builder: (context, snapshot) {
            final role    = snapshot.data?.role ?? 'member';
            final isAdmin = role == 'admin';

            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.pushNamed(context, AppRouter.oranizationScreen,
                  arguments: {'organization': org}),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradient,
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(isSmall ? 14 : 16),
                          child: Row(children: [
                            Container(
                              width: isSmall ? 50 : 54,
                              height: isSmall ? 50 : 54,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: _DS.avatarGlow(org.id),
                              ),
                              child: Center(
                                child: Text(
                                  org.name[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: isSmall ? 20 : 22,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: isSmall ? 12 : 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    org.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: isSmall ? 14 : 15,
                                      color: _DS.textPrimary,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatDate(org.createdAt, context),
                                    style: TextStyle(
                                      color: _DS.textSecondary,
                                      fontSize: isSmall ? 11 : 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildRoleBadge(isAdmin),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showOrganizationOptions(org, owner.id, isAdmin),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: _DS.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x10000000)),
                                ),
                                child: Icon(Icons.more_horiz_rounded,
                                    color: _DS.textSecondary, size: 20),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SMALL UI PIECES
  // ─────────────────────────────────────────────────────────

  Widget _buildRoleBadge(bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin ? _DS.adminGoldBg : _DS.memberBlueBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAdmin
              ? _DS.adminGold.withValues(alpha: 0.35)
              : _DS.memberBlue.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isAdmin ? Icons.star_rounded : Icons.person_rounded,
          size: 12,
          color: isAdmin ? _DS.adminGold : _DS.memberBlue,
        ),
        const SizedBox(width: 4),
        Text(
          isAdmin
              ? AppTranslations.of(context).text('admin')
              : AppTranslations.of(context).text('member'),
          style: TextStyle(
            color: isAdmin ? _DS.adminGold : _DS.memberBlue,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ]),
    );
  }

  Widget _buildHeroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _buildHeaderButton({
    required String label,
    required IconData icon,
    required bool outlined,
    required VoidCallback onTap,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _DS.primary,
          side: BorderSide(color: _DS.primary.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: _DS.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 14,
          color: isDestructive ? Colors.red[700] : _DS.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12, color: _DS.textSecondary))
          : null,
      onTap: onTap,
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    required IconData icon,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autofocus = false,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autofocus: autofocus,
      validator: validator,
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: _DS.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _DS.primary, width: 1.8),
        ),
        helperText: helper,
        helperStyle: const TextStyle(fontSize: 11, color: _DS.textSecondary),
      ),
    );
  }

  Widget _buildInfoBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _DS.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DS.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: _DS.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, color: _DS.primary, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _buildWarningBanner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(Icons.remove_circle_outline_rounded, size: 15, color: Colors.red[600]),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.red[700]))),
      ]),
    );
  }

  Widget _buildLoadingDialog(String message) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(color: _DS.primaryLight, shape: BoxShape.circle),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(color: _DS.primary, strokeWidth: 3),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _DS.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text('...', style: TextStyle(fontSize: 13, color: _DS.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTooSmallWarning(BuildContext context,
      BoxConstraints constraints, double minW, double minH) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              AppTranslations.of(context).text('window_size_too_small'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppTranslations.of(context).textWithParams('minimum_size',
                  {'width': minW.toInt(), 'height': minH.toInt()}),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              AppTranslations.of(context).textWithParams('current_size', {
                'width': constraints.maxWidth.toInt(),
                'height': constraints.maxHeight.toInt(),
              }),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoUserState(BuildContext context, bool isSmall) {
    return Center(
      child: Card(
        margin: EdgeInsets.all(isSmall ? 16 : 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(isSmall ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: isSmall ? 48 : 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                AppTranslations.of(context).text('user_data_not_found'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: isSmall ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout),
                label: Text(AppTranslations.of(context).text('logout_action')),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isSmall) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: _DS.primaryLight, shape: BoxShape.circle),
            child: Icon(Icons.business_outlined,
                size: isSmall ? 48 : 56, color: _DS.primary),
          ),
          const SizedBox(height: 20),
          Text(
            AppTranslations.of(context).text('no_orgs'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isSmall ? 18 : 20,
              color: _DS.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.of(context).text('no_orgs_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _DS.textSecondary, fontSize: isSmall ? 13 : 14),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12, runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _showJoinOrganizationDialog,
                icon: const Icon(Icons.group_add_rounded, size: 18),
                label: Text(AppTranslations.of(context).text('join'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _DS.primary,
                  side: BorderSide(color: _DS.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
              FilledButton.icon(
                onPressed: _showCreateOrganizationDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(AppTranslations.of(context).text('create'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: _DS.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.green[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────
  // DATE FORMATTING
  // ─────────────────────────────────────────────────────────

  String _formatDate(DateTime date, BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'vi') {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────
// ASYNC LOCK
// ─────────────────────────────────────────────────────────────
class AsyncLock {
  bool _locked = false;
  bool get isLocked => _locked;

  Future<void> run(Future<void> Function() action) async {
    if (_locked) return;
    _locked = true;
    try {
      await action();
    } finally {
      _locked = false;
    }
  }
}