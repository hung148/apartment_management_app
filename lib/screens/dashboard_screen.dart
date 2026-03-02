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
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform; 
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final AuthService _authService = getIt<AuthService>();
  final OrganizationService _organizationService = getIt<OrganizationService>();
  final UpdateService _updateService = getIt<UpdateService>();

  Future<Owner?>? _ownerFuture;

  void _showLanguageDialog() {
    final notifier = getIt<LocaleNotifier>();
    // Biến tạm để lưu lựa chọn trong Dialog
    Locale tempLocale = notifier.locale;

    _showTrackedDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(AppTranslations.of(context).text('select_language')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<Locale>(
                    groupValue: tempLocale, // Giá trị đang được chọn tạm thời
                    onChanged: (Locale? value) {
                      if (value != null) {
                        // Cập nhật giao diện của riêng Dialog khi chọn
                        setDialogState(() => tempLocale = value);
                      }
                    },
                    child: Column(
                      children: [
                        // Tiếng Việt
                        RadioListTile<Locale>(
                          value: const Locale('vi', 'VN'),
                          title: Text(AppTranslations.of(context).text('vietnamese')),
                          secondary: const Text('🇻🇳', style: TextStyle(fontSize: 24)),
                        ),
                        // Tiếng Anh
                        RadioListTile<Locale>(
                          value: const Locale('en', 'US'),
                          title: Text(AppTranslations.of(context).text('english')),
                          secondary: const Text('🇺🇸', style: TextStyle(fontSize: 24)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                // Nút Hủy
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppTranslations.of(context).text('cancel')),
                ),
                // Nút Xác nhận - Lúc này ngôn ngữ mới chính thức thay đổi
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Cập nhật ngôn ngữ toàn App thông qua notifier
                    notifier.setLocale(tempLocale);
                    Navigator.pop(context);
                  },
                  child: Text(AppTranslations.of(context).text('confirm')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  final AsyncLock _createOrgLock = AsyncLock();
  final AsyncLock _joinOrgLock = AsyncLock();
  final AsyncLock _dialogLock = AsyncLock();
  final AsyncLock _logoutLock = AsyncLock();
  final AsyncLock _leaveOrgLock = AsyncLock();

  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;

  // Update-related state
  bool _updateAvailable = false;
  bool _checkingUpdate = false;
  
  // Cancellation flag and timer
  bool _isDisposed = false;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    _ownerFuture = _authService.getCurrentOwner();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🟢 DashboardScreen.initState() called');
    
    debugPrint('🔧 Scheduling update check...');
    _updateCheckTimer = Timer(const Duration(milliseconds: 800), () {
      debugPrint('⏰ Timer fired after 800ms');
      if (mounted && !_isDisposed) {
        debugPrint('✅ Widget is mounted and not disposed, calling _backgroundUpdateCheck');
        _backgroundUpdateCheck();
      } else {
        debugPrint('⚠️ Timer fired but widget is disposed=$_isDisposed or not mounted=$mounted');
      }
    });
    debugPrint('🏁 initState completed');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeDebounceTimer?.cancel();
    debugPrint('🔴 DashboardScreen.dispose() called');
    _updateCheckTimer?.cancel();
    _isDisposed = true;
    super.dispose();
  }

  // Debounce timer for resize handling
  Timer? _resizeDebounceTimer;

  // Guard to prevent overlapping dismiss calls
  bool _isDismissing = false;

  // ─── Called whenever screen size / metrics change ───
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Cancel any pending debounce before setting a new one
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

  // Pops all open dialogs/bottom sheets by popping until only the base route remains.
  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;

    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        // Yield to the framework between each pop so it can finish
        // destroying the previous overlay before we pop the next one.
        // This prevents back-to-back surface destruction that triggers EGL errors.
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

  // ─── Overlay helpers ───

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

  /// Background update check that won't freeze the UI
  Future<void> _backgroundUpdateCheck() async {
    debugPrint('📱 >>> _backgroundUpdateCheck() STARTED <<<');
    
    if (_isDisposed || !mounted) {
      debugPrint('❌ Aborted early: disposed=$_isDisposed, mounted=$mounted');
      return;
    }
    
    debugPrint('📝 Calling setState to set _checkingUpdate = true');
    setState(() {
      _checkingUpdate = true;
    });
    debugPrint('✅ setState completed');

    try {
      debugPrint('🌐 About to call _updateService.isUpdateAvailable()...');
      
      final available = await _updateService.isUpdateAvailable().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏱️ ⏱️ ⏱️ TIMEOUT after 5 seconds!');
          return false;
        },
      );
      
      debugPrint('📥 ✅ isUpdateAvailable() returned: $available');
      
      if (!_isDisposed && mounted) {
        debugPrint('📝 Calling setState to update _updateAvailable=$available');
        setState(() {
          _updateAvailable = available;
          _checkingUpdate = false;
        });
        debugPrint('✅ Final setState completed successfully');
      } else {
        debugPrint('⚠️ Widget disposed/unmounted after check, skipping setState');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ❌ ❌ EXCEPTION CAUGHT: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (!_isDisposed && mounted) {
        setState(() {
          _updateAvailable = false;
          _checkingUpdate = false;
        });
      }
    }
    
    debugPrint('🏁 >>> _backgroundUpdateCheck() COMPLETED <<<');
  }

  /// Manual update check (for pull-to-refresh)
  Future<void> _checkForUpdate() async {
    if (_checkingUpdate || _isDisposed) return;
    
    setState(() {
      _checkingUpdate = true;
    });

    try {
      final available = await _updateService.isUpdateAvailable().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      
      if (!_isDisposed && mounted) {
        setState(() {
          _updateAvailable = available;
          _checkingUpdate = false;
        });
      }
    } catch (e) {
      debugPrint('Update check error: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _checkingUpdate = false;
          _updateAvailable = false;
        });
      }
    }
  }

  Future<void> _performUpdate() async {
    if (!kIsWeb && Platform.isWindows) {
      final confirm = await _showTrackedDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(child: Text(AppTranslations.of(context).text('available_update'))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTranslations.of(context).text('new_update_ready')),
              SizedBox(height: 8),
              Text(
                AppTranslations.of(context).text('click_update_button'),
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTranslations.of(context).text('later')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download),
              label: Text(AppTranslations.of(context).text('later')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final progressNotifier = ValueNotifier<double>(0.0);

        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(AppTranslations.of(context).text('downloading_update')),
            content: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress <= 0 ? null : progress),
                  const SizedBox(height: 8),
                  Text(progress <= 0
                    ? '${AppTranslations.of(context).text("connecting")}...'
                    : '${(progress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ),
        );

        await _updateService.performUpdate(
          onProgress: (p) => progressNotifier.value = p,
        );

        // Only reached if download failed (success calls exit(0))
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppTranslations.of(context).text('update_failed')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(AppTranslations.of(context).text('updating')),
          ],
        ),
      ),
    );

    final success = await _updateService.performFlexibleUpdate();

    if (mounted) {
      Navigator.pop(context);
      
      if (success) {
        setState(() => _updateAvailable = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.of(context).text('update_success')),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.of(context).text('update_failed')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========================================
  // RESPONSIVE HELPER METHODS
  // ========================================
  
  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }
  
  bool _isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }
  
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1200;
  }
  
  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) {
      return screenWidth * 0.9; // 90% on small screens
    } else if (screenWidth < 1200) {
      return 500; // Fixed 500px on medium screens
    } else {
      return 600; // Fixed 600px on large screens
    }
  }
  
  int _getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 1;
    if (width < 900) return 2;
    if (width < 1200) return 3;
    return 4;
  }

  // ========================================
  // CREATE ORGANIZATION
  // ========================================

  Future<void> _showCreateOrganizationDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final taxCodeController = TextEditingController(); // ADDED: Tax code controller
    final formKey = GlobalKey<FormState>();

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(context),
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.add_business, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(child: Text(AppTranslations.of(context).text('tooltip_create'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          maxLength: 100,
                          autofocus: !_isSmallScreen(context),
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            counterText: "",
                            labelText: AppTranslations.of(context).text('org_name_required'),
                            hintText: AppTranslations.of(context).text('org_name_example'),
                            prefixIcon: const Icon(Icons.business),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppTranslations.of(context).text('please_enter_org_name');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: addressController,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 300,
                          maxLines: 2,
                          decoration: InputDecoration(
                            counterText: "",
                            labelText: AppTranslations.of(context).text('address'),
                            hintText: AppTranslations.of(context).text('address_example'),
                            prefixIcon: const Icon(Icons.location_on),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText: AppTranslations.of(context).text('optional_on_invoice'),
                            helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: phoneController,
                          maxLength: 20,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            counterText: "",
                            labelText: AppTranslations.of(context).text('phone'),
                            hintText: AppTranslations.of(context).text('phone_example'),
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText: AppTranslations.of(context).text('optional_on_invoice'),
                            helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: emailController,
                          maxLength: 254,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            counterText: "",
                            labelText: AppTranslations.of(context).text('email'),
                            hintText: AppTranslations.of(context).text('email_example'),
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText: AppTranslations.of(context).text('optional_on_invoice'),
                            helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                              if (!emailRegex.hasMatch(value)) {
                                return AppTranslations.of(context).text('email_invalid');
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // ADDED: Tax Code Field
                        TextFormField(
                          controller: taxCodeController,
                          maxLength: 14,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            counterText: "",
                            labelText: AppTranslations.of(context).text('tax_code'),
                            hintText: '0123456789 or 0123456789-001',
                            prefixIcon: const Icon(Icons.receipt_long),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText: AppTranslations.of(context).text('optional_on_invoice'),
                            helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              // Basic validation: 10-14 digits with optional hyphen
                              if (!_organizationService.isValidTaxCode(value)) {
                                return 'Invalid tax code format';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppTranslations.of(context).text('contact_info_on_invoice'),
                                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
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
              const Divider(height: 1),
              // Actions
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text(AppTranslations.of(context).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        _createOrgLock.run(() async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          
                          final owner = await _authService.getCurrentOwner();
                          if (owner == null) return;

                          await _organizationService.createOrganization(
                            name: nameController.text.trim(),
                            ownerId: owner.id,
                            address: addressController.text.trim().isEmpty 
                                ? null 
                                : addressController.text.trim(),
                            phone: phoneController.text.trim().isEmpty 
                                ? null 
                                : phoneController.text.trim(),
                            email: emailController.text.trim().isEmpty 
                                ? null 
                                : emailController.text.trim(),
                            taxCode: taxCodeController.text.trim().isEmpty  // ADDED: Tax code parameter
                                ? null 
                                : taxCodeController.text.trim(),
                          );

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppTranslations.of(context).text('org_created_success')),
                                backgroundColor: Colors.green,
                              ),
                            );
                            setState(() {});
                          }
                        });
                      },
                      icon: const Icon(Icons.check),
                      label: Text(AppTranslations.of(context).text('create_action')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Dispose controllers after dialog closes
    nameController.dispose();
    addressController.dispose();
    phoneController.dispose();
    emailController.dispose();
    taxCodeController.dispose(); // ADDED: Dispose tax code controller
  }

  // ========================================
  // JOIN ORGANIZATION
  // ========================================

  Future<void> _showJoinOrganizationDialog() async {
    final controller = TextEditingController();

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.group_add, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(AppTranslations.of(context).text('tooltip_join'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppTranslations.of(context).text('enter_invite_code'),
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              autofocus: !_isSmallScreen(context),
              decoration: InputDecoration(
                labelText: AppTranslations.of(context).text('invite_code'),
                hintText: AppTranslations.of(context).text('invite_code_example'),
                prefixIcon: const Icon(Icons.vpn_key),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppTranslations.of(context).text('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _joinOrgLock.run(() async {
                final code = controller.text.trim().toUpperCase();
                if (code.length != 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppTranslations.of(context).text('invite_code_8_chars')),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                final owner = await _authService.getCurrentOwner();
                if (owner == null) return;

                final success = await _organizationService.joinOrganization(
                  ownerId: owner.id,
                  inviteCode: code,
                );

                if (!mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? AppTranslations.of(context).text('join_org_success')
                          : AppTranslations.of(context).text('invite_code_invalid'),
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );

                if (success) setState(() {});
              });
            },
            icon: const Icon(Icons.login),
            label: Text(AppTranslations.of(context).text('join')),
          ),
        ],
      ),
    );
  }

  // ========================================
  // LEAVE ORGANIZATION (Members)
  // ========================================

  Future<void> _showLeaveOrganizationDialog(
    Organization org,
    String ownerId,
  ) async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.orange[700]),
            const SizedBox(width: 8),
            Flexible(child: Text(AppTranslations.of(context).text('leave_org'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTranslations.of(context).textWithParams('leave_org_confirm', {'name': org.name})),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 20, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(context).text('lose_access_warning'),
                      style: TextStyle(fontSize: 13, color: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTranslations.of(context).text('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(AppTranslations.of(context).text('leave_action')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _leaveOrgLock.run(() async {
        // Show loading
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(AppTranslations.of(context).text('leaving_org')),
              ],
            ),
          ),
        );

        final success = await _organizationService.leaveOrganization(
          ownerId,
          org.id,
        );

        if (!mounted) return;

        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? AppTranslations.of(context).text('left_org_success')
                  : AppTranslations.of(context).text('cannot_leave_org'),
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );

        if (success) setState(() {});
      });
    }
  }

  // ========================================
  // DELETE ORGANIZATION (Admins)
  // ========================================

  Future<void> _showDeleteOrganizationDialog(
    Organization org,
    String ownerId,
  ) async {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(context),
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Flexible(child: Text(AppTranslations.of(context).text('delete_org'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppTranslations.of(context).textWithParams('delete_org_warning', {'name': org.name}),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildDeleteWarningItem(AppTranslations.of(context).text('all_buildings')),
                        _buildDeleteWarningItem(AppTranslations.of(context).text('all_rooms')),
                        _buildDeleteWarningItem(AppTranslations.of(context).text('all_tenants')),
                        _buildDeleteWarningItem(AppTranslations.of(context).text('all_payments')),
                        _buildDeleteWarningItem(AppTranslations.of(context).text('all_members')),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning, size: 20, color: Colors.red[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppTranslations.of(context).text('warning_cannot_undo'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.of(context).text('confirm_enter_org_name'),
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: nameController,
                          maxLength: 100,
                          decoration: InputDecoration(
                            counterText: "",
                            hintText: org.name,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.edit),
                          ),
                          validator: (value) {
                            if (value == null || value.trim() != org.name) {
                              return AppTranslations.of(context).text('name_mismatch');
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Actions
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        nameController.dispose();
                        Navigator.pop(context, false);
                      },
                      child: Text(AppTranslations.of(context).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        debugPrint('DEBUG: Delete button pressed');
                        if (formKey.currentState!.validate()) {
                          debugPrint('DEBUG: Form validated, skipping controller dispose');
                          debugPrint('DEBUG: About to pop dialog');
                          Navigator.pop(context, true);
                          debugPrint('DEBUG: Dialog pop called');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(AppTranslations.of(context).text('delete_permanently')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      // Let the dialog close and UI update before starting deletion
      await Future.delayed(const Duration(milliseconds: 100));

      // Create a ValueNotifier to track deletion progress
      final progressNotifier = ValueNotifier<double>(0.0);

      // Show dialog-based progress indicator
      if (mounted) {
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(AppTranslations.of(context).text('deleting_org'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, progress, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        Text('${(progress * 100).toStringAsFixed(0)}%'),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(AppTranslations.of(context).text('please_dont_close'), style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      }
      // Start deletion after dialog is shown
      final success = await _organizationService.deleteOrganization(
        ownerId,
        org.id,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(); // Close progress dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  success
                      ? AppTranslations.of(context).text('deleted_org_success')
                      : AppTranslations.of(context).text('cannot_delete_org')
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      if (success) setState(() {});
    }
  }

  // ========================================
  // VIEW ORGANIZATION INFO
  // ========================================
  void _showOrganizationInfo(Organization org) {
    _showTrackedDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppTranslations.of(context).text('org_info')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrgInfoRow(AppTranslations.of(context).text('org_name_label'), org.name),
              const SizedBox(height: 12),
              _buildOrgInfoRow(AppTranslations.of(context).text('id'), org.id),
              const SizedBox(height: 12),
              _buildOrgInfoRow(AppTranslations.of(context).text('created_date'), _formatDate(org.createdAt, context)),
              if (org.updatedAt != null) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('last_updated'), _formatDate(org.updatedAt!, context)),
              ],
              if (org.address != null && org.address!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('address_label'), org.address!),
              ],
              if (org.phone != null && org.phone!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('phone_label'), org.phone!),
              ],
              if (org.email != null && org.email!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('email_label'), org.email!),
              ],
              if (org.bankName != null && org.bankName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('bank_name'), org.bankName!),
              ],
              if (org.bankAccountNumber != null && org.bankAccountNumber!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('account_number'), org.bankAccountNumber!),
              ],
              if (org.bankAccountName != null && org.bankAccountName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('account_holder'), org.bankAccountName!),
              ],
              if (org.taxCode != null && org.taxCode!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow(AppTranslations.of(context).text('tax_code'), org.taxCode!),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppTranslations.of(context).text('close')),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ========================================
  // MIGRATE ORGANIZATION
  // ========================================
  void _showMigrateOrganizationDialog(Organization sourceOrg, String ownerId, bool deleteAfter) async {
    final targetController = TextEditingController();
    Map<String, int>? preview;
    String? status;
    bool loading = false;
    bool started = false;
    double progress = 0.0;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: !started,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(deleteAfter ? AppTranslations.of(context).text('migrate_and_delete') : AppTranslations.of(context).text('migrate_org_data')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppTranslations.of(context).text('source_org_info'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(AppTranslations.of(context).textWithParams('name_with_value', {'name':  sourceOrg.name}), style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(AppTranslations.of(context).textWithParams('id_with_value', {'id':  sourceOrg.id}), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: targetController,
                      maxLength: 50,
                      decoration: InputDecoration(
                        counterText: "",
                        labelText: AppTranslations.of(context).text('target_org_id'),
                        hintText: AppTranslations.of(context).text('enter_target_org_id'),
                        helperText: AppTranslations.of(context).text('target_org_id_placeholder'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (preview != null) ...[
                      Text(AppTranslations.of(context).text('preview_data_migrate'), style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(AppTranslations.of(context).textWithParams('preview_stats', {'buildings':preview?['buildings'] ?? 0, 'rooms': preview?['rooms'] ?? 0, 'tenants': preview?['tenants'] ?? 0, 'payments': preview?['payments'] ?? 0})),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: 8),
                      Text(status!, style: const TextStyle(fontSize: 13)),
                    ],
                    if (loading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).toStringAsFixed(0)}%'),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!started) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppTranslations.of(context).text('cancel')),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => status = null);
                      final id = targetController.text.trim();
                      if (id.isEmpty) {
                        setState(() => status = AppTranslations.of(context).text('please_enter_target_id'));
                        return;
                      }
                      setState(() => status = AppTranslations.of(context).text('fetching_preview'));
                      try {
                        final result = await _organizationService.getMigrationPreview(sourceOrg.id);
                        setState(() => preview = result);
                        setState(() => status = AppTranslations.of(context).text('fetched_preview'));
                      } catch (e) {
                        setState(() => status = AppTranslations.of(context).textWithParams('preview_error', {'error': e})); 
                      }
                    },
                    child: Text(AppTranslations.of(context).text('preview')),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final targetId = targetController.text.trim();
                      if (targetId.isEmpty) {
                        setState(() => status = AppTranslations.of(context).text('please_enter_target_id'));
                        return;
                      }
                      setState(() {
                        loading = true;
                        started = true;
                        status = deleteAfter ? AppTranslations.of(context).text('migrating_and_deleting') : AppTranslations.of(context).text('migrating_data');
                        progress = 0.0;
                      });
                      bool success = false;
                      try {
                        if (deleteAfter) {
                          success = await _organizationService.migrateAndDeleteOrganization(
                            ownerId: ownerId,
                            sourceOrgId: sourceOrg.id,
                            targetOrgId: targetId,
                            onProgress: (p) => setState(() => progress = p),
                            onStatusUpdate: (msg) => setState(() => status = msg),
                          );
                        } else {
                          success = await _organizationService.migrateOrganization(
                            ownerId: ownerId,
                            sourceOrgId: sourceOrg.id,
                            targetOrgId: targetId,
                            onProgress: (p) => setState(() => progress = p),
                            onStatusUpdate: (msg) => setState(() => status = msg),
                          );
                        }
                      } catch (e) {
                        setState(() => status = AppTranslations.of(context).textWithParams('error', {'error': e})); 
                      }
                      setState(() {
                        loading = false;
                        started = false;
                      });
                      if (success) {
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(deleteAfter
                                  ? AppTranslations.of(context).text('migrated_and_deleted_success')
                                  : AppTranslations.of(context).text('migrated_data_success')),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        this.setState(() {});
                      } else {
                        setState(() => status = AppTranslations.of(context).text('operation_failed'));
                      }
                    },
                    child: Text(deleteAfter ? AppTranslations.of(context).text('migrate_and_delete_action') : AppTranslations.of(context).text('migrate_action') ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDeleteWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.close, size: 16, color: Colors.red[700]),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: TextStyle(color: Colors.red[800]))),
        ],
      ),
    );
  }

  // ========================================
  // SHOW ORGANIZATION OPTIONS
  // ========================================

  void _showOrganizationOptions(
    Organization org,
    String ownerId,
    bool isAdmin,
  ) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    // Shared header
    List<Widget> header = [
      const SizedBox(height: 12),
      Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          org.name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          isAdmin ? AppTranslations.of(context).text('admin') : AppTranslations.of(context).text('member'),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ),
      const Divider(height: 32),
    ];

    // Shared menu items
    List<Widget> menuItems = [
      ListTile(
        leading: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary),
        title: Text(AppTranslations.of(context).text('open_org')),
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(
            context,
            AppRouter.oranizationScreen,
            arguments: {'organization': org},
          );
        },
      ),
      const Divider(height: 1),
      ListTile(
        leading: Icon(Icons.info_outline, color: Colors.blue[700]),
        title: Text(AppTranslations.of(context).text('view_org_info')),
        subtitle: Text(AppTranslations.of(context).text('org_details_and_id')),
        onTap: () {
          Navigator.pop(context);
          _showOrganizationInfo(org);
        },
      ),
      const Divider(height: 1),
      if (isAdmin) ...[
        ListTile(
          leading: Icon(Icons.compare_arrows, color: Colors.blue[700]),
          title: Text(AppTranslations.of(context).text('migrate_to_other_org')),
          subtitle: Text(AppTranslations.of(context).text('copy_all_data')),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, false);
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_sweep, color: Colors.red[700]),
          title: Text(AppTranslations.of(context).text('migrate_and_delete_org')),
          subtitle: Text(AppTranslations.of(context).text('transfer_and_delete')),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, true);
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_forever, color: Colors.red[700]),
          title: Text(AppTranslations.of(context).text('delete_org_action')),
          subtitle: Text(AppTranslations.of(context).text('delete_org_permanently')),
          onTap: () {
            Navigator.pop(context);
            _showDeleteOrganizationDialog(org, ownerId);
          },
        ),
      ] else ...[
        ListTile(
          leading: Icon(Icons.exit_to_app, color: Colors.orange[700]),
          title: Text(AppTranslations.of(context).text('leave_org_action')),
          subtitle: Text(AppTranslations.of(context).text('will_lose_access')),
          onTap: () {
            Navigator.pop(context);
            _showLeaveOrganizationDialog(org, ownerId);
          },
        ),
      ],
      const SizedBox(height: 16),
    ];

    if (isLargeScreen) {
      // ─── Tablet / Desktop: centered Dialog ───
      _showTrackedDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 400,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  // Org name & role (reuse without the drag handle)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      org.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      isAdmin ? AppTranslations.of(context).text('admin') : AppTranslations.of(context).text('member'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  // Scrollable menu
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: menuItems,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // ─── Mobile: ModalBottomSheet ───
      _showTrackedBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...header,
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: menuItems,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  // ========================================
  // LOGOUT
  // ========================================

  Future<void> _handleLogout() async {
    debugPrint('DEBUG: Showing delete confirmation dialog');
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppTranslations.of(context).text('confirm_logout')),
        content: Text(AppTranslations.of(context).text('confirm_logout_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTranslations.of(context).text('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppTranslations.of(context).text('logout_action')),
          ),
        ],
      ),
    );

    debugPrint('DEBUG: Dialog closed, confirm value: '
      + confirm.toString());
    if (confirm == true) {
      _logoutLock.run(() async {
        await _authService.signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
        }
      });
    }
  }

  // ========================================
  // BUILD UI
  // ========================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmall = _isSmallScreen(context);
    
    // Set minimum window size constraints
    const minWidth = 360.0;
    const minHeight = 600.0;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.of(context).text('dashboard')),
        elevation: 0,
        actions: [
          if (_updateAvailable && !_checkingUpdate)
            Padding(
              padding: EdgeInsets.only(right: isSmall ? 4 : 8),
              child: isSmall
                  ? IconButton(
                      onPressed: _performUpdate,
                      icon: const Icon(Icons.system_update),
                      tooltip: AppTranslations.of(context).text('update'),
                    )
                  : TextButton.icon(
                      onPressed: _performUpdate,
                      icon: const Icon(Icons.system_update, color: Colors.white),
                      label: Text(
                        AppTranslations.of(context).text('update'),
                        style: TextStyle(color: Colors.white),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
            ),
          IconButton(
            onPressed: _showLanguageDialog,
            icon: const Icon(Icons.language),
            tooltip: AppTranslations.of(context).text('lang'),
          ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            tooltip: AppTranslations.of(context).text('logout'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Check minimum size
          if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
                    const SizedBox(height: 16),
                    Text(
                      AppTranslations.of(context).text('window_size_too_small'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppTranslations.of(context).textWithParams('minimum_size', {'width': minWidth.toInt(), 'height': minHeight.toInt()}), 
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppTranslations.of(context).textWithParams('current_size', {'width': constraints.maxWidth.toInt(), 'height': constraints.maxHeight.toInt()}), 
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          
          return FutureBuilder<Owner?>(
            future: _ownerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Loading3(size: 50));
              }

              final owner = snapshot.data;
              if (owner == null) {
                return Center(
                  child: Card(
                    margin: EdgeInsets.all(isSmall ? 16 : 24),
                    child: Padding(
                      padding: EdgeInsets.all(isSmall ? 16 : 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: isSmall ? 48 : 64,
                            color: Theme.of(context).colorScheme.error,
                          ),
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
                          ElevatedButton.icon(
                            onPressed: _handleLogout,
                            icon: const Icon(Icons.logout),
                            label: Text(AppTranslations.of(context).text('logout_action')),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                  await _checkForUpdate();
                },
                child: CustomScrollView(
                  slivers: [
                    // User Info Header
                    SliverToBoxAdapter(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isSmall ? 16 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: isSmall ? 24 : 32,
                                    backgroundColor: Colors.white,
                                    child: Text(
                                      owner.name[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: isSmall ? 24 : 32,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isSmall ? 12 : 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppTranslations.of(context).text('hello'),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            fontSize: isSmall ? 12 : 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          owner.name,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isSmall ? 18 : 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _buildInfoRow(Icons.email, owner.email),
                                    const SizedBox(height: 8),
                                    _buildInfoRow(
                                      Icons.calendar_today,
                                      '${AppTranslations.of(context).text('joined_at')}: ${_formatDate(owner.createdAt, context)}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Organizations Section Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isSmall ? 12 : 16,
                          isSmall ? 16 : 24,
                          isSmall ? 12 : 16,
                          8,
                        ),
                        child: isSmall
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          AppTranslations.of(context).text('your_organizations'),
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.group_add, size: 18),
                                          label: Text(AppTranslations.of(context).text('join')),
                                          onPressed: () => _dialogLock.run(_showJoinOrganizationDialog),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.add, size: 18),
                                          label: Text(AppTranslations.of(context).text('create')),
                                          onPressed: () => _dialogLock.run(_showCreateOrganizationDialog),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppTranslations.of(context).text('your_organizations'),
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.group_add),
                                        tooltip: AppTranslations.of(context).text('tooltip_join'),
                                        onPressed: () => _dialogLock.run(_showJoinOrganizationDialog),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        tooltip: AppTranslations.of(context).text('tooltip_create'),
                                        onPressed: () => _dialogLock.run(_showCreateOrganizationDialog),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),

                    // Organizations List
                    FutureBuilder<List<Organization>>(
                      future: _organizationService.getUserOrganizations(owner.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final orgs = snapshot.data ?? [];
                        if (orgs.isEmpty) {
                          return SliverFillRemaining(
                            child: Center(
                              child: Card(
                                margin: EdgeInsets.all(isSmall ? 16 : 24),
                                child: Padding(
                                  padding: EdgeInsets.all(isSmall ? 24 : 32),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.business_outlined,
                                        size: isSmall ? 64 : 80,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        AppTranslations.of(context).text('no_orgs'),
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontSize: isSmall ? 18 : null,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        AppTranslations.of(context).text('no_orgs_sub'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: isSmall ? 13 : null,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      isSmall
                                          ? Column(
                                              children: [
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    onPressed: _showJoinOrganizationDialog,
                                                    icon: const Icon(Icons.group_add),
                                                    label: Text(AppTranslations.of(context).text('join')),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    onPressed: _showCreateOrganizationDialog,
                                                    icon: const Icon(Icons.add),
                                                    label: Text(AppTranslations.of(context).text('create')),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: _showJoinOrganizationDialog,
                                                  icon: const Icon(Icons.group_add),
                                                  label: Text(AppTranslations.of(context).text('join')),
                                                ),
                                                const SizedBox(width: 12),
                                                ElevatedButton.icon(
                                                  onPressed: _showCreateOrganizationDialog,
                                                  icon: const Icon(Icons.add),
                                                  label: Text(AppTranslations.of(context).text('create')),
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final org = orgs[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: FutureBuilder<Membership?>(
                                    future: _organizationService.getUserMembership(
                                      owner.id,
                                      org.id,
                                    ),
                                    builder: (context, snapshot) {
                                      final role = snapshot.data?.role ?? 'member';
                                      final isAdmin = role == 'admin';
                                      final roleText = isAdmin ? AppTranslations.of(context).text('admin') : AppTranslations.of(context).text('member');

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () {
                                          Navigator.pushNamed(
                                            context,
                                            AppRouter.oranizationScreen,
                                            arguments: {
                                              'organization': org
                                            },
                                          );
                                        },
                                        child: Padding(
                                          padding: EdgeInsets.all(isSmall ? 12 : 16),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: isSmall ? 48 : 56,
                                                height: isSmall ? 48 : 56,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Theme.of(context).colorScheme.primary,
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withAlpha((0.7 * 255).round()),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    org.name[0].toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: isSmall ? 20 : 24,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: isSmall ? 12 : 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      org.name,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: isSmall ? 14 : 16,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _formatDate(org.createdAt, context),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: isSmall ? 11 : 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isAdmin
                                                            ? Colors.amber.withValues(alpha: 0.2)
                                                            : Colors.blue.withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            isAdmin
                                                                ? Icons.admin_panel_settings
                                                                : Icons.person,
                                                            size: isSmall ? 12 : 14,
                                                            color: isAdmin
                                                                ? Colors.amber[700]
                                                                : Colors.blue[700],
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            roleText,
                                                            style: TextStyle(
                                                              color: isAdmin
                                                                  ? Colors.amber[700]
                                                                  : Colors.blue[700],
                                                              fontWeight: FontWeight.w600,
                                                              fontSize: isSmall ? 11 : 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Three-dot menu button
                                              Tooltip(
                                                message: AppTranslations.of(context).text('org_options'),
                                                child: Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () {
                                                      _showOrganizationOptions(org, owner.id, isAdmin);
                                                    },
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(8.0),
                                                      child: Icon(
                                                        Icons.more_vert,
                                                        color: Colors.blue[700],
                                                        size: isSmall ? 24 : 28,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                              childCount: orgs.length,
                            ),
                          ),
                        );
                      },
                    ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: 24),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    final isSmall = _isSmallScreen(context);
    return Row(
      children: [
        Icon(icon, size: isSmall ? 14 : 16, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmall ? 12 : 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

 String _formatDate(DateTime date, BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    
    if (locale == 'vi') {
      // Vietnamese format: DD/MM/YYYY HH:mm
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } else {
      // English format: MM/DD/YYYY HH:mm
      return '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
  }
}

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