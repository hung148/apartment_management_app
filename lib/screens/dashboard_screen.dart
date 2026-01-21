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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  final OrganizationService _organizationService = OrganizationService();
  final UpdateService _updateService = UpdateService();

  final AsyncLock _createOrgLock = AsyncLock();
  final AsyncLock _joinOrgLock = AsyncLock();
  final AsyncLock _dialogLock = AsyncLock();
  final AsyncLock _logoutLock = AsyncLock();

  // Update-related state
  bool _updateAvailable = false;
  bool _checkingUpdate = true;

  @override
  void initState() {
    super.initState();

    _checkForUpdate();
  }

  // ---------------- UPDATE CHECK ----------------

  Future<void> _checkForUpdate() async {
    final available = await _updateService.isUpdateAvailable();
    if (mounted) {
      setState(() {
        _updateAvailable = available;
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _performUpdate() async {

    if (Platform.isWindows) {
      // Windows: Show dialog and open browser
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

    // Android/iOS update (original code)
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

  // ---------------- CREATE ORG ----------------

  Future<void> _showCreateOrganizationDialog() async {
    final controller = TextEditingController();

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
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Tên tổ chức',
            hintText: 'VD: Chung cư ABC',
            prefixIcon: const Icon(Icons.business),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _createOrgLock.run(() async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập tên tổ chức'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                final owner = await _authService.getCurrentOwner();
                if (owner == null) return;

                await _organizationService.createOrganization(
                  name: name,
                  ownerId: owner.id,
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
  }

  // ---------------- JOIN ORG ----------------

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
                  ownerID: owner.id,
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

  // ---------------- LOGOUT ----------------

  Future<void> _handleLogout() async {
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

    if (confirm == true) {
      _logoutLock.run(() async {
        await _authService.signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
        }
      });
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang chủ'),
        elevation: 0,
        actions: [
          // Update button - only shows when update is available
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
                                        arguments: org,
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
                                                      .withOpacity(0.7),
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
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey[400],
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

                // Bottom padding
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