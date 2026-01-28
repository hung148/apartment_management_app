import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/owner_model.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/update_services.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:apartment_management_project_2/widgets/loading.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = getIt<AuthService>();
  final OrganizationService _organizationService = getIt<OrganizationService>();
  final UpdateService _updateService = getIt<UpdateService>();

  final AsyncLock _createOrgLock = AsyncLock();
  final AsyncLock _joinOrgLock = AsyncLock();
  final AsyncLock _dialogLock = AsyncLock();
  final AsyncLock _logoutLock = AsyncLock();
  final AsyncLock _leaveOrgLock = AsyncLock();
  final AsyncLock _deleteOrgLock = AsyncLock();

  // Update-related state
  bool _updateAvailable = false;
  bool _checkingUpdate = false;
  
  // Cancellation flag and timer
  bool _isDisposed = false;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
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
    debugPrint('🔴 DashboardScreen.dispose() called');
    _updateCheckTimer?.cancel();
    _isDisposed = true;
    super.dispose();
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
    if (Platform.isWindows) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Cập nhật có sẵn'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Phiên bản mới đã sẵn sàng!'),
              SizedBox(height: 8),
              Text(
                'Nhấn "Tải xuống" để mở trang tải xuống phiên bản mới.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download),
              label: const Text('Tải xuống'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final success = await _updateService.performUpdate();
        
        if (mounted) {
          if (success) {
            setState(() => _updateAvailable = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đang mở trang tải xuống...'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể mở trình duyệt. Vui lòng kiểm tra kết nối.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang cập nhật...'),
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
          const SnackBar(
            content: Text('Cập nhật thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể cập nhật. Vui lòng thử lại sau.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========================================
  // CREATE ORGANIZATION
  // ========================================

  Future<void> _showCreateOrganizationDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.add_business, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Tạo Tổ Chức Mới'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Tên tổ chức *',
                    hintText: 'VD: Chung cư ABC',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập tên tổ chức';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: addressController,
                  textCapitalization: TextCapitalization.words,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ',
                    hintText: 'VD: 123 Nguyễn Huệ, Q1, TP.HCM',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Tùy chọn - Hiển thị trên hóa đơn',
                    helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại',
                    hintText: 'VD: 028-1234-5678',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Tùy chọn - Hiển thị trên hóa đơn',
                    helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'VD: contact@abc.com',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Tùy chọn - Hiển thị trên hóa đơn',
                    helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value)) {
                        return 'Email không hợp lệ';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Thông tin liên hệ sẽ hiển thị trên hóa đơn PDF',
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
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Hủy'),
          ),
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
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tạo tổ chức thành công!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              });
            },
            icon: const Icon(Icons.check),
            label: const Text('Tạo'),
          ),
        ],
      ),
    );

    // Dispose controllers after dialog closes
    nameController.dispose();
    addressController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }

  // ========================================
  // JOIN ORGANIZATION
  // ========================================

  Future<void> _showJoinOrganizationDialog() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.group_add, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Tham Gia Tổ Chức'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nhập mã mời 8 ký tự để tham gia tổ chức',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mã mời',
                hintText: 'VD: A3F7B2C9',
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
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _joinOrgLock.run(() async {
                final code = controller.text.trim().toUpperCase();
                if (code.length != 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mã mời phải có 8 ký tự'),
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
                          ? 'Tham gia tổ chức thành công!'
                          : 'Mã mời không hợp lệ hoặc bạn đã là thành viên',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );

                if (success) setState(() {});
              });
            },
            icon: const Icon(Icons.login),
            label: const Text('Tham Gia'),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Text('Rời khỏi tổ chức'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bạn có chắc chắn muốn rời khỏi tổ chức "${org.name}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 20, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bạn sẽ mất quyền truy cập vào tất cả dữ liệu của tổ chức này.',
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
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rời khỏi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _leaveOrgLock.run(() async {
        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang rời khỏi tổ chức...'),
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
                  ? 'Đã rời khỏi tổ chức thành công!'
                  : 'Không thể rời khỏi tổ chức. Bạn có thể là quản trị viên cuối cùng.',
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Xóa tổ chức'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hành động này sẽ XÓA VĨNH VIỄN tổ chức "${org.name}" và TẤT CẢ dữ liệu liên quan bao gồm:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildDeleteWarningItem('Tất cả tòa nhà'),
              _buildDeleteWarningItem('Tất cả phòng'),
              _buildDeleteWarningItem('Tất cả người thuê'),
              _buildDeleteWarningItem('Tất cả thanh toán'),
              _buildDeleteWarningItem('Tất cả thành viên'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning, size: 20, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'CẢNH BÁO: Hành động này KHÔNG THỂ HOÀN TÁC!',
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
              const Text(
                'Để xác nhận, vui lòng nhập tên tổ chức:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: org.name,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.edit),
                ),
                validator: (value) {
                  if (value == null || value.trim() != org.name) {
                    return 'Tên không khớp';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              nameController.dispose();
              Navigator.pop(context, false);
            },
            child: const Text('Hủy'),
          ),
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
            child: const Text('XÓA VĨNH VIỄN'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Let the dialog close and UI update before starting deletion
      await Future.delayed(const Duration(milliseconds: 100));

      // Create a ValueNotifier to track deletion progress
      final progressNotifier = ValueNotifier<double>(0.0);

      // Show dialog-based progress indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Đang xóa tổ chức...', style: TextStyle(fontWeight: FontWeight.bold)),
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
              const Text('Vui lòng không đóng ứng dụng', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );

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
                      ? 'Đã xóa tổ chức thành công!'
                      : 'Không thể xóa tổ chức. Vui lòng thử lại.',
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thông tin tổ chức'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrgInfoRow('Tên tổ chức:', org.name),
              const SizedBox(height: 12),
              _buildOrgInfoRow('ID:', org.id),
              const SizedBox(height: 12),
              _buildOrgInfoRow('Ngày tạo:', _formatDate(org.createdAt)),
              if (org.updatedAt != null) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Cập nhật lần cuối:', _formatDate(org.updatedAt!)),
              ],
              if (org.address != null && org.address!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Địa chỉ:', org.address!),
              ],
              if (org.phone != null && org.phone!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Số điện thoại:', org.phone!),
              ],
              if (org.email != null && org.email!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Email:', org.email!),
              ],
              if (org.bankName != null && org.bankName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Tên ngân hàng:', org.bankName!),
              ],
              if (org.bankAccountNumber != null && org.bankAccountNumber!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Số tài khoản:', org.bankAccountNumber!),
              ],
              if (org.bankAccountName != null && org.bankAccountName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Chủ tài khoản:', org.bankAccountName!),
              ],
              if (org.taxCode != null && org.taxCode!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildOrgInfoRow('Mã số thuế:', org.taxCode!),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
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

    await showDialog(
      context: context,
      barrierDismissible: !started,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(deleteAfter ? 'Di chuyển & xóa tổ chức' : 'Di chuyển dữ liệu tổ chức'),
              content: Column(
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
                        const Text('Thông tin tổ chức nguồn:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('Tên: ${sourceOrg.name}', style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('ID: ${sourceOrg.id}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: targetController,
                    decoration: const InputDecoration(
                      labelText: 'ID tổ chức đích',
                      hintText: 'Nhập ID tổ chức đích nơi muốn di chuyển',
                      helperText: 'ID của tổ chức đích (không phải tên)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (preview != null) ...[
                    Text('Xem trước dữ liệu sẽ di chuyển:', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Tòa nhà: ${preview?['buildings'] ?? 0}, Phòng: ${preview?['rooms'] ?? 0}, Người thuê: ${preview?['tenants'] ?? 0}, Thanh toán: ${preview?['payments'] ?? 0}'),
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
              actions: [
                if (!started) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => status = null);
                      final id = targetController.text.trim();
                      if (id.isEmpty) {
                        setState(() => status = 'Vui lòng nhập ID tổ chức đích.');
                        return;
                      }
                      setState(() => status = 'Đang lấy xem trước...');
                      try {
                        final result = await _organizationService.getMigrationPreview(sourceOrg.id);
                        setState(() => preview = result);
                        setState(() => status = 'Đã lấy xem trước.');
                      } catch (e) {
                        setState(() => status = 'Lỗi khi lấy xem trước: $e');
                      }
                    },
                    child: const Text('Xem trước'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final targetId = targetController.text.trim();
                      if (targetId.isEmpty) {
                        setState(() => status = 'Vui lòng nhập ID tổ chức đích.');
                        return;
                      }
                      setState(() {
                        loading = true;
                        started = true;
                        status = deleteAfter ? 'Đang di chuyển và xóa...' : 'Đang di chuyển dữ liệu...';
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
                        setState(() => status = 'Lỗi: $e');
                      }
                      setState(() {
                        loading = false;
                        started = false;
                      });
                      if (success) {
                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(deleteAfter
                                ? 'Đã di chuyển và xóa tổ chức thành công!'
                                : 'Đã di chuyển dữ liệu thành công!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {});
                      } else {
                        setState(() => status = 'Thao tác thất bại.');
                      }
                    },
                    child: Text(deleteAfter ? 'Di chuyển & XÓA' : 'Di chuyển'),
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
          Text(text, style: TextStyle(color: Colors.red[800])),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  isAdmin ? 'Quản trị viên' : 'Thành viên',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const Divider(height: 32),
              
              // Open Organization
              ListTile(
                leading: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary),
                title: const Text('Mở tổ chức'),
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
              
              // View Organization Info
              ListTile(
                leading: Icon(Icons.info_outline, color: Colors.blue[700]),
                title: const Text('Xem thông tin tổ chức'),
                subtitle: const Text('Chi tiết tổ chức và ID'),
                onTap: () {
                  Navigator.pop(context);
                  _showOrganizationInfo(org);
                },
              ),
              
              const Divider(height: 1),
              
              // Migration options (admin only)
              if (isAdmin) ...[
                ListTile(
                  leading: Icon(Icons.compare_arrows, color: Colors.blue[700]),
                  title: const Text('Di chuyển dữ liệu sang tổ chức khác'),
                  subtitle: const Text('Sao chép toàn bộ dữ liệu sang tổ chức khác'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMigrateOrganizationDialog(org, ownerId, false);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep, color: Colors.red[700]),
                  title: const Text('Di chuyển & xóa tổ chức'),
                  subtitle: const Text('Chuyển dữ liệu và xóa tổ chức này'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMigrateOrganizationDialog(org, ownerId, true);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red[700]),
                  title: const Text('Xóa tổ chức'),
                  subtitle: const Text('Xóa vĩnh viễn tổ chức và tất cả dữ liệu'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteOrganizationDialog(org, ownerId);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(Icons.exit_to_app, color: Colors.orange[700]),
                  title: const Text('Rời khỏi tổ chức'),
                  subtitle: const Text('Bạn sẽ mất quyền truy cập'),
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveOrganizationDialog(org, ownerId);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ========================================
  // LOGOUT
  // ========================================

  Future<void> _handleLogout() async {
    debugPrint('DEBUG: Showing delete confirmation dialog');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đăng xuất'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang chủ'),
        elevation: 0,
        actions: [
          if (_updateAvailable && !_checkingUpdate)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _performUpdate,
                icon: const Icon(Icons.system_update, color: Colors.white),
                label: const Text(
                  'Cập nhật',
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
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
          ),
        ],
      ),
      body: FutureBuilder<Owner?>(
        future: _authService.getCurrentOwner(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Loading3(size: 50));
          }

          final owner = snapshot.data;
          if (owner == null) {
            return Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Không tìm thấy dữ liệu người dùng',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Đăng xuất'),
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
                          Theme.of(context).colorScheme.primary.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: Colors.white,
                                child: Text(
                                  owner.name[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Xin chào!',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      owner.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildInfoRow(Icons.email, owner.email),
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.calendar_today,
                                  'Tham gia: ${_formatDate(owner.createdAt)}',
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
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
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
                              'Tổ Chức Của Bạn',
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
                              tooltip: 'Tham gia tổ chức',
                              onPressed: () => _dialogLock.run(_showJoinOrganizationDialog),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'Tạo tổ chức mới',
                              onPressed: () => _dialogLock.run(_showCreateOrganizationDialog),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
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
                            margin: const EdgeInsets.all(24),
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.business_outlined,
                                    size: 80,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Chưa có tổ chức nào',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tạo tổ chức mới hoặc tham gia bằng mã mời',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _showJoinOrganizationDialog,
                                        icon: const Icon(Icons.group_add),
                                        label: const Text('Tham Gia'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: _showCreateOrganizationDialog,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Tạo Mới'),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  final roleText = isAdmin ? 'Quản trị viên' : 'Thành viên';

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
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
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
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  org.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _formatDate(org.createdAt),
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
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
                                                        ? Colors.amber.withOpacity(0.2)
                                                        : Colors.blue.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isAdmin
                                                            ? Icons.admin_panel_settings
                                                            : Icons.person,
                                                        size: 14,
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
                                                          fontSize: 12,
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
                                            message: 'Tùy chọn tổ chức',
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
                                                    size: 28,
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
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
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