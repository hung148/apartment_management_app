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

  RoomDetailScreen({
    Key? key,
    required this.room,
    required this.organization
  }) : super(key: key);


  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;

  bool _isSmallScreen(BuildContext context) => MediaQuery.of(context).size.width < 600;
  bool _isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }

  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.95;
    if (screenWidth < 1200) return 600;
    return 800;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    return EdgeInsets.all(_isSmallScreen(context) ? 12.0 : 16.0);
  }

  Widget _buildMinimumSizeWarning(BuildContext context, BoxConstraints constraints) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              'Kích thước cửa sổ quá nhỏ',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Kích thước tối thiểu: 360x600',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Hiện tại: ${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}',
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
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _initializeStreams();
    // Load payments for this room
    widget.paymentsNotifier.loadRoomPayments(widget.room.id, widget.organization.id);
  }

  void _initializeStreams() {
    _tenantSubscription = widget.tenantService
    .streamRoomTenants(widget.room.id, widget.organization.id)
    .listen(
      (tenants) {
        if (mounted) {
          setState(() {
            _tenants = tenants;
            _isLoadingTenants = false;
          });
        }
      },
      onError: (error) {
        debugPrint('❌ Firestore Error: $error');
        if (mounted) {
          setState(() {
            _isLoadingTenants = false; // Stop the spinner!
            _tenants = []; // Prevent null errors
          });
          // Show a snackbar so you know why it "froze"
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải dữ liệu: $error')),
          );
        }
      },
    );
  }

  String? get _userId => widget.authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);

    return widget.organizationService.getUserMembership(
      _userId!,
      widget.organization.id,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _tenantSubscription?.cancel();
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

  // =========================
  // FORMAT HELPERS
  // =========================
  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} ₫';
  }

  // =========================
  // TENANT CRUD OPERATIONS (UPDATED TO MATCH TENANTS_TAB)
  // =========================
  
  void _showAddEditTenantDialog({Tenant? tenant}) {
    final isEditing = tenant != null;
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    // Controllers
    final nameController = TextEditingController(text: tenant?.fullName ?? '');
    final phoneController = TextEditingController(text: tenant?.phoneNumber ?? '');
    final emailController = TextEditingController(text: tenant?.email ?? '');
    final nationalIdController = TextEditingController(text: tenant?.nationalId ?? '');
    final occupationController = TextEditingController(text: tenant?.occupation ?? '');
    final workplaceController = TextEditingController(text: tenant?.workplace ?? '');
    final rentController = TextEditingController(
      text: tenant?.monthlyRent?.toString() ?? '',
    );
    final depositController = TextEditingController(
      text: tenant?.deposit?.toString() ?? '',
    );
    final areaController = TextEditingController(text: tenant?.apartmentArea?.toString() ?? '');
    final typeController = TextEditingController(text: tenant?.apartmentType ?? '');
    
    Gender? selectedGender = tenant?.gender;
    bool isMainTenant = tenant?.isMainTenant ?? (_tenants?.isEmpty ?? true);
    DateTime moveInDate = tenant?.moveInDate ?? DateTime.now();
    DateTime? contractStartDate = tenant?.contractStartDate;
    DateTime? contractEndDate = tenant?.contractEndDate;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(isEditing ? 'Chỉnh sửa người thuê' : 'Thêm người thuê'),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    // Full Name
                    TextField(
                      controller: nameController,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Họ và tên *',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Phone Number
                    TextField(
                      controller: phoneController,
                      maxLength: 20,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        counterText: "", 
                        labelText: 'Số điện thoại *',
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Monthly Rent
                    TextField(
                      controller: rentController,
                      maxLength: 20,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Tiền thuê hàng tháng',
                        prefixIcon: Icon(Icons.attach_money),
                        suffixText: 'VND',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Move In Date
                    LocalizedDatePicker(
                      labelText: 'Ngày vào ở',
                      initialDate: moveInDate,
                      required: true,
                      prefixIcon: Icons.calendar_today,
                      onDateChanged: (date) {
                        if (date != null) {
                          setDialogState(() {
                            moveInDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    const Divider(height: 32),
                    const Text('Thông tin bổ sung (Dùng cho hóa đơn)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(
                          controller: typeController,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            counterText: "",
                            labelText: 'Loại căn hộ',
                            prefixIcon: Icon(Icons.category, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(
                          controller: areaController,
                          maxLength: 10,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            counterText: "",
                            labelText: 'Diện tích',
                            prefixIcon: Icon(Icons.square_foot, size: 20),
                            suffixText: 'm²',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Email
                    TextField(
                      controller: emailController,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // National ID
                    TextField(
                      controller: nationalIdController,
                      maxLength: 20,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'CMND/CCCD',
                        prefixIcon: Icon(Icons.credit_card),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Occupation
                    TextField(
                      controller: occupationController,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Nghề nghiệp',
                        prefixIcon: Icon(Icons.work),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Workplace
                    TextField(
                      controller: workplaceController,
                      maxLength: 150,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Nơi làm việc',
                        prefixIcon: Icon(Icons.business),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Gender
                    DropdownButtonFormField<Gender>(
                      value: selectedGender,
                      decoration: const InputDecoration(
                        labelText: 'Giới tính',
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: Gender.values.map((gender) {
                        return DropdownMenuItem(
                          value: gender,
                          child: Text(_getGenderDisplayName(gender)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedGender = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Is Main Tenant
                    CheckboxListTile(
                      title: const Text('Người thuê chính'),
                      value: isMainTenant,
                      onChanged: (value) {
                        setDialogState(() {
                          isMainTenant = value ?? true;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Deposit
                    TextField(
                      controller: depositController,
                      maxLength: 20,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        counterText: "", 
                        labelText: 'Tiền cọc',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                        suffixText: 'VND',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Contract Start Date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description),
                      title: const Text('Ngày bắt đầu hợp đồng'),
                      subtitle: Text(
                        contractStartDate != null 
                            ? _formatDate(contractStartDate!) 
                            : 'Chưa có',
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: contractStartDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setDialogState(() {
                            contractStartDate = date;
                          });
                        }
                      },
                      trailing: contractStartDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setDialogState(() {
                                  contractStartDate = null;
                                });
                              },
                            )
                          : null,
                    ),
                    
                    // Contract End Date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_busy),
                      title: const Text('Ngày kết thúc hợp đồng'),
                      subtitle: Text(
                        contractEndDate != null 
                            ? _formatDate(contractEndDate!) 
                            : 'Chưa có',
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: contractEndDate ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setDialogState(() {
                            contractEndDate = date;
                          });
                        }
                      },
                      trailing: contractEndDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setDialogState(() {
                                  contractEndDate = null;
                                });
                              },
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Validation
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập họ tên')),
                      );
                      return;
                    }
                    
                    if (phoneController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập số điện thoại')),
                      );
                      return;
                    }

                    try {
                      final newTenant = Tenant(
                        id: tenant?.id ?? '',
                        organizationId: widget.room.organizationId,
                        buildingId: widget.room.buildingId,
                        roomId: widget.room.id,
                        fullName: nameController.text.trim(),
                        phoneNumber: phoneController.text.trim(),
                        email: emailController.text.trim().isNotEmpty 
                            ? emailController.text.trim() 
                            : null,
                        nationalId: nationalIdController.text.trim().isNotEmpty
                            ? nationalIdController.text.trim()
                            : null,
                        occupation: occupationController.text.trim().isNotEmpty
                            ? occupationController.text.trim()
                            : null,
                        workplace: workplaceController.text.trim().isNotEmpty
                            ? workplaceController.text.trim()
                            : null,
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
                        apartmentType: typeController.text.trim().isEmpty ? null : typeController.text.trim(),
                        moveInDate: moveInDate,
                        contractStartDate: contractStartDate,
                        contractEndDate: contractEndDate,
                        status: TenantStatus.active,
                        createdAt: tenant?.createdAt ?? DateTime.now(),
                      );

                      if (isEditing) {
                        // Update existing tenant
                        final success = await widget.tenantService.updateTenant(
                          tenant!.id,
                          {
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
                          },
                        );
                        
                        if (success && mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cập nhật người thuê thành công')),
                          );
                        }
                      } else {
                        // Add new tenant
                        final tenantId = await widget.tenantService.addTenant(newTenant);
                        
                        if (tenantId != null && mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Thêm người thuê thành công')),
                          );
                        }
                      }
                    } catch (e, stackTrace) {
                      print('❌ ERROR saving tenant: $e');
                      print('Stack trace: $stackTrace');
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isEditing ? 'Cập nhật' : 'Thêm'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getGenderDisplayName(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Nam';
      case Gender.female:
        return 'Nữ';
      case Gender.other:
        return 'Khác';
    }
  }

  // Updated tenant detail dialog to match tenants_tab
  void _showTenantDetailDialog(Tenant tenant) async {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;
    
    // Get building name for display
    final building = await widget.buildingService.getBuildingById(tenant.buildingId);
    final buildingName = building?.name ?? 'Không xác định';
    
    if (!mounted) return;
    
    _showTrackedDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: AlertDialog(
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: tenant.isMainTenant 
                      ? Colors.blue.shade100 
                      : Colors.grey.shade200,
                  child: Text(
                    tenant.fullName[0].toUpperCase(),
                    style: TextStyle(
                      color: tenant.isMainTenant 
                          ? Colors.blue.shade700 
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.fullName,
                        style: const TextStyle(fontSize: 18),
                      ),
                      if (tenant.isMainTenant)
                        Text(
                          'Chủ phòng',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ========================================
                    // LOCATION SECTION
                    // ========================================
                    _buildDetailSection(
                      isMovedOut ? 'Vị trí trước đây' : 'Vị trí',
                      [
                        _buildDetailRow('Toà nhà', buildingName),
                        _buildDetailRow('Phòng', widget.room.roomNumber),
                      ],
                    ),
                    const Divider(),
                    
                    // ========================================
                    // CONTACT INFORMATION
                    // ========================================
                    _buildDetailSection('Thông tin liên hệ', [
                      _buildDetailRow('Số điện thoại', tenant.phoneNumber),
                      if (tenant.email != null) _buildDetailRow('Email', tenant.email!),
                    ]),
                    const Divider(),
                    
                    // ========================================
                    // PERSONAL INFORMATION
                    // ========================================
                    _buildDetailSection('Thông tin cá nhân', [
                      if (tenant.gender != null) 
                        _buildDetailRow('Giới tính', tenant.getGenderDisplayName()!),
                      if (tenant.nationalId != null)
                        _buildDetailRow('CMND/CCCD', tenant.nationalId!),
                      if (tenant.occupation != null)
                        _buildDetailRow('Nghề nghiệp', tenant.occupation!),
                      if (tenant.workplace != null)
                        _buildDetailRow('Nơi làm việc', tenant.workplace!),
                    ]),
                    
                    // ========================================
                    // RENTAL INFORMATION - Only show if NOT moved out
                    // ========================================
                    if (!isMovedOut) ...[
                      const Divider(),
                      _buildDetailSection('Thông tin thuê', [
                        _buildDetailRow('Ngày vào ở', _formatDate(tenant.moveInDate)),
                        _buildDetailRow('Số ngày ở', '${tenant.daysLiving} ngày'),
                        if (tenant.monthlyRent != null)
                          _buildDetailRow('Tiền thuê', _formatCurrency(tenant.monthlyRent!)),
                        if (tenant.deposit != null)
                          _buildDetailRow('Tiền cọc', _formatCurrency(tenant.deposit!)),
                      ]),
                    ],
                    
                    // ========================================
                    // MOVED OUT INFORMATION - Only show if moved out
                    // ========================================
                    if (isMovedOut && tenant.moveOutDate != null) ...[
                      const Divider(),
                      _buildDetailSection('Thông tin chuyển đi', [
                        _buildDetailRow('Ngày chuyển đi', _formatDate(tenant.moveOutDate!)),
                        _buildDetailRow(
                          'Thời gian ở',
                          '${tenant.moveOutDate!.difference(tenant.moveInDate).inDays} ngày',
                        ),
                        if (tenant.contractTerminationReason != null)
                          _buildDetailRow('Lý do', tenant.contractTerminationReason!),
                        if (tenant.notes != null && tenant.notes!.isNotEmpty)
                          _buildDetailRow('Ghi chú', tenant.notes!),
                      ]),
                    ],
                    
                    // ========================================
                    // CONTRACT INFORMATION - Updated to show termination status
                    // ========================================
                    if (tenant.contractStartDate != null || tenant.contractEndDate != null) ...[
                      const Divider(),
                      _buildDetailSection('Hợp đồng', [
                        if (tenant.contractStartDate != null)
                          _buildDetailRow('Bắt đầu', _formatDate(tenant.contractStartDate!)),
                        if (tenant.contractEndDate != null)
                          _buildDetailRow(
                            isMovedOut ? 'Ngày kết thúc hợp đồng' : 'Kết thúc', 
                            _formatDate(tenant.contractEndDate!)
                          ),
                        
                        // Show contract status
                        if (isMovedOut) ...[
                          _buildDetailRow('Trạng thái hợp đồng', tenant.getContractStatusDisplayName()),
                          if (tenant.moveOutDate != null && tenant.contractEndDate != null)
                            _buildDetailRow(
                              tenant.moveOutDate!.isBefore(tenant.contractEndDate!) 
                                ? 'Chấm dứt sớm' 
                                : 'Kết thúc',
                              tenant.moveOutDate!.isBefore(tenant.contractEndDate!)
                                ? '${tenant.contractEndDate!.difference(tenant.moveOutDate!).inDays} ngày trước hạn'
                                : 'Đúng thời hạn hợp đồng',
                            ),
                        ] else ...[
                          if (tenant.daysUntilContractEnd != null)
                            _buildDetailRow(
                              'Còn lại',
                              '${tenant.daysUntilContractEnd} ngày',
                            ),
                        ],
                      ]),
                    ],
                    
                    // Rest remains the same (vehicles, rental history, etc.)
                    if (tenant.vehicles != null && tenant.vehicles!.isNotEmpty) ...[
                      const Divider(),
                      _buildDetailSection('Phương tiện (${tenant.vehicles!.length})', [
                        ...tenant.vehicles!.map((vehicle) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_getVehicleIcon(vehicle.type), 
                                        size: 16, 
                                        color: Colors.purple.shade700),
                                    const SizedBox(width: 8),
                                    Text(
                                      vehicle.licensePlate,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                if (vehicle.brand != null || vehicle.model != null)
                                  Text(
                                    '${vehicle.brand ?? ''} ${vehicle.model ?? ''}'.trim(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                if (vehicle.isParkingRegistered && vehicle.parkingSpot != null)
                                  Text(
                                    'Bãi đỗ: ${vehicle.parkingSpot}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )),
                      ]),
                    ],
                    if (tenant.previousRentals != null && tenant.previousRentals!.isNotEmpty) ...[
                      const Divider(),
                      _buildDetailSection('Lịch sử thuê (${tenant.previousRentals!.length})', [
                        ...tenant.previousRentals!.map((rental) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${rental.buildingName} - Phòng ${rental.roomNumber}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Từ ${_formatDate(rental.moveInDate)} đến ${_formatDate(rental.moveOutDate)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                Text(
                                  '${rental.duration} ngày',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                      ]),
                    ],
                    const Divider(),
                    _buildDetailRow('Trạng thái', tenant.getStatusDisplayName()),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
              FutureBuilder<Membership?>(
                future: _getMyMembership(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.role == 'admin') {
                    return TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showTenantOptionsMenu(tenant);
                      },
                      child: const Text('Tùy chọn'),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  // =========================
  // TENANT OPTIONS MENU (UPDATED TO MATCH TENANTS_TAB)
  // =========================
  Future<void> _showTenantOptionsMenu(Tenant tenant) async {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    // Shared list of menu items
    List<Widget> menuItems = [
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Xem chi tiết'),
        onTap: () {
          Navigator.pop(context);
          _showTenantDetailDialog(tenant);
        },
      ),
      ListTile(
        leading: const Icon(Icons.edit),
        title: const Text('Chỉnh sửa thông tin'),
        onTap: () {
          Navigator.pop(context);
          _showAddEditTenantDialog(tenant: tenant);
        },
      ),
      ListTile(
        leading: const Icon(Icons.directions_car),
        title: const Text('Quản lý phương tiện'),
        subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
            ? Text('${tenant.vehicles!.length} phương tiện')
            : null,
        onTap: () {
          Navigator.pop(context);
          _showVehicleManagementDialog(tenant);
        },
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Lịch sử thuê phòng'),
        onTap: () {
          Navigator.pop(context);
          _showRentalHistoryDialog(tenant);
        },
      ),
      if (tenant.status != TenantStatus.moveOut)
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Đánh dấu đã chuyển đi'),
          onTap: () {
            Navigator.pop(context);
            _confirmMoveOut(tenant);
          },
        ),
      ListTile(
        leading: Icon(Icons.delete, color: Colors.red.shade700),
        title: Text('Xóa', style: TextStyle(color: Colors.red.shade700)),
        onTap: () {
          Navigator.pop(context);
          _deleteTenant(tenant);
        },
      ),
    ];

    if (isLargeScreen) {
      // ─── Tablet / Desktop: show as a centered Dialog ───
      await _showTrackedDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 360,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text(
                      'Tùy chọn',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Divider(height: 0),
                  ...menuItems,
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // ─── Mobile: show as a ModalBottomSheet ───
      await _showTrackedBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: menuItems,
          ),
        ),
      );
    }
  }

  // =========================
  // VEHICLE MANAGEMENT (UPDATED TO MATCH TENANTS_TAB)
  // =========================
  Future<void> _showVehicleManagementDialog(Tenant tenant) async {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    await _showTrackedDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Quản lý phương tiện',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                tenant.fullName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            try {
                              final result = await _showAddVehicleDialog();
                              if (result != null) {
                                final success = await widget.tenantService.addVehicle(
                                  tenant.id,
                                  result,
                                );
                                if (success) {
                                  // Fetch updated tenant
                                  final updatedTenant = await widget.tenantService.getTenantById(tenant.id);
                                  if (updatedTenant != null) {
                                    setDialogState(() {});
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Đã thêm phương tiện')),
                                    );
                                  }
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Lỗi: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          tooltip: 'Thêm phương tiện',
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: tenant.vehicles == null || tenant.vehicles!.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('Chưa có phương tiện nào'),
                              ],
                            ),
                          )
                        : FutureBuilder<Tenant?>(
                            future: widget.tenantService.getTenantById(tenant.id),
                            builder: (context, snapshot) {
                              final currentTenant = snapshot.data ?? tenant;
                              return ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: currentTenant.vehicles?.length ?? 0,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  final vehicle = currentTenant.vehicles![index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.purple.shade100,
                                      child: Icon(
                                        _getVehicleIcon(vehicle.type),
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      vehicle.licensePlate,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${_getVehicleTypeDisplayName(vehicle.type)}${vehicle.brand != null ? ' • ${vehicle.brand}' : ''}'),
                                        if (vehicle.isParkingRegistered && vehicle.parkingSpot != null)
                                          Text(
                                            'Bãi đỗ: ${vehicle.parkingSpot}',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton(
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, size: 20),
                                              SizedBox(width: 8),
                                              Text('Chỉnh sửa'),
                                            ],
                                          ),
                                        ),
                                        if (!vehicle.isParkingRegistered)
                                          const PopupMenuItem(
                                            value: 'parking',
                                            child: Row(
                                              children: [
                                                Icon(Icons.local_parking, size: 20),
                                                SizedBox(width: 8),
                                                Text('Đăng ký bãi đỗ'),
                                              ],
                                            ),
                                          )
                                        else
                                          const PopupMenuItem(
                                            value: 'unparking',
                                            child: Row(
                                              children: [
                                                Icon(Icons.cancel, size: 20),
                                                SizedBox(width: 8),
                                                Text('Hủy bãi đỗ'),
                                              ],
                                            ),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, size: 20, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Xóa', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          final result = await _showEditVehicleDialog(vehicle);
                                          if (result != null) {
                                            final success = await widget.tenantService.updateVehicle(
                                              currentTenant.id,
                                              index,
                                              result,
                                            );
                                            if (success) {
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã cập nhật')),
                                                );
                                              }
                                            }
                                          }
                                        } else if (value == 'parking') {
                                          final spot = await _showParkingSpotDialog();
                                          if (spot != null) {
                                            final success = await widget.tenantService.registerParkingSpot(
                                              currentTenant.id,
                                              index,
                                              spot,
                                            );
                                            if (success) {
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã đăng ký bãi đỗ')),
                                                );
                                              }
                                            }
                                          }
                                        } else if (value == 'unparking') {
                                          final success = await widget.tenantService.unregisterParkingSpot(
                                            currentTenant.id,
                                            index,
                                          );
                                          if (success) {
                                            setDialogState(() {});
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Đã hủy bãi đỗ')),
                                              );
                                            }
                                          }
                                        } else if (value == 'delete') {
                                          final ok = await _showTrackedDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Xóa phương tiện'),
                                              content: Text('Xóa phương tiện ${vehicle.licensePlate}?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text('Hủy'),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Xóa'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            final success = await widget.tenantService.removeVehicle(
                                              currentTenant.id,
                                              index,
                                            );
                                            if (success) {
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã xóa phương tiện')),
                                                );
                                              }
                                            }
                                          }
                                        }
                                      },
                                    ),
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
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Thêm phương tiện'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: licensePlateController,
                      maxLength: 15,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Biển số xe *',
                        hintText: '29A-12345',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<VehicleType>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Loại xe *'),
                      items: VehicleType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_getVehicleTypeDisplayName(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: brandController,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Hãng xe',
                        hintText: 'Honda, Yamaha, Toyota...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Model',
                        hintText: 'Wave, Vision, Vios...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: colorController,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        counterText: "",
                        labelText: 'Màu sắc',
                        hintText: 'Đen, Trắng, Xanh...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (licensePlateController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập biển số xe')),
                      );
                      return;
                    }

                    final vehicle = VehicleInfo(
                      licensePlate: licensePlateController.text.trim().toUpperCase(),
                      type: selectedType,
                      brand: brandController.text.trim().isEmpty ? null : brandController.text.trim(),
                      model: modelController.text.trim().isEmpty ? null : modelController.text.trim(),
                      color: colorController.text.trim().isEmpty ? null : colorController.text.trim(),
                    );

                    Navigator.pop(context, vehicle);
                  },
                  child: const Text('Thêm'),
                ),
              ],
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
    final licensePlateController = TextEditingController(text: vehicle.licensePlate);
    final brandController = TextEditingController(text: vehicle.brand);
    final modelController = TextEditingController(text: vehicle.model);
    final colorController = TextEditingController(text: vehicle.color);
    VehicleType selectedType = vehicle.type;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Chỉnh sửa phương tiện'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: licensePlateController,
                      decoration: const InputDecoration(labelText: 'Biển số xe *'),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<VehicleType>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Loại xe *'),
                      items: VehicleType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_getVehicleTypeDisplayName(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: brandController,
                      decoration: const InputDecoration(labelText: 'Hãng xe'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      decoration: const InputDecoration(labelText: 'Model'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(labelText: 'Màu sắc'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (licensePlateController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập biển số xe')),
                      );
                      return;
                    }

                    final updatedVehicle = VehicleInfo(
                      licensePlate: licensePlateController.text.trim().toUpperCase(),
                      type: selectedType,
                      brand: brandController.text.trim().isEmpty ? null : brandController.text.trim(),
                      model: modelController.text.trim().isEmpty ? null : modelController.text.trim(),
                      color: colorController.text.trim().isEmpty ? null : colorController.text.trim(),
                      isParkingRegistered: vehicle.isParkingRegistered,
                      parkingSpot: vehicle.parkingSpot,
                    );

                    Navigator.pop(context, updatedVehicle);
                  },
                  child: const Text('Lưu'),
                ),
              ],
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
        builder: (context) => AlertDialog(
          title: const Text('Đăng ký bãi đỗ'),
          content: TextField(
            controller: controller,
            maxLength: 10,
            decoration: const InputDecoration(
              counterText: "",
              labelText: 'Vị trí bãi đỗ',
              hintText: 'A1, B2, C3...',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập vị trí')),
                  );
                  return;
                }
                Navigator.pop(context, controller.text.trim().toUpperCase());
              },
              child: const Text('Đăng ký'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _getVehicleTypeDisplayName(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:
        return 'Xe máy';
      case VehicleType.car:
        return 'Ô tô';
      case VehicleType.bicycle:
        return 'Xe đạp';
      case VehicleType.electricBike:
        return 'Xe đạp điện';
      case VehicleType.other:
        return 'Khác';
    }
  }

  // =========================
  // RENTAL HISTORY
  // =========================
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    await _showTrackedDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.history),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Lịch sử thuê phòng',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tenant.previousRentals == null || tenant.previousRentals!.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Không có lịch sử thuê'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: tenant.previousRentals!.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final r = tenant.previousRentals![i];
                          final durationDays = r.duration;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(Icons.home, color: Colors.orange.shade700),
                            ),
                            title: Text('${r.buildingName} - Phòng ${r.roomNumber}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Từ ${DateFormat.yMd().format(r.moveInDate)} đến ${DateFormat.yMd().format(r.moveOutDate)}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '$durationDays ngày',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // MOVE OUT CONFIRMATION
  // =========================
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
          return AlertDialog(
            title: const Text('Đánh dấu đã chuyển đi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Đánh dấu ${tenant.fullName} là đã chuyển đi?'),
                const SizedBox(height: 16),
                
                LocalizedDatePicker(
                  labelText: 'Ngày chuyển đi',
                  initialDate: selectedDate,
                  required: true,
                  prefixIcon: Icons.calendar_today,
                  onDateChanged: (date) {
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
                
                const SizedBox(height: 16),
                
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: const InputDecoration(
                    labelText: 'Lý do',
                    border: OutlineInputBorder(),
                  ),
                  items: reasonOptions.map((reason) {
                    return DropdownMenuItem(
                      value: reason,
                      child: Text(reason),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedReason = value);
                  },
                ),
                
                // Show warning if moving out before contract end
                if (tenant.contractEndDate != null && 
                    selectedDate.isBefore(tenant.contractEndDate!)) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chấm dứt sớm ${tenant.contractEndDate!.difference(selectedDate).inDays} ngày',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                  'date': selectedDate,
                  'reason': selectedReason,
                }),
                child: const Text('Xác nhận'),
              ),
            ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'Đã đánh dấu chuyển đi' : 'Thất bại')),
        );
      }
    }
  }

  void _deleteTenant(Tenant tenant) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    _showTrackedDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : MediaQuery.of(context).size.width * 0.6,
          ),
          child: AlertDialog(
            title: const Text('Xóa người thuê'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            content: SizedBox(
              width: double.maxFinite,
              child: Text(
                'Bạn có chắc muốn xóa người thuê "${tenant.fullName}"?\n\nThao tác này không thể hoàn tác.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    final success = await widget.tenantService.deleteTenant(tenant.id);
                    
                    if (success && mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã xóa người thuê thành công')),
                      );
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Không thể xóa người thuê'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    print('❌ ERROR deleting tenant: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Lỗi: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Xóa'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // BUILD TENANTS TAB
  // =========================
  Widget _buildTenantsTab() {
    if (_isLoadingTenants) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tenants == null || _tenants!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Chưa có người thuê',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm người thuê để bắt đầu quản lý',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddEditTenantDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('Thêm người thuê'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tenants!.length,
      itemBuilder: (context, index) {
        final tenant = _tenants![index];
        return _buildTenantCard(tenant);
      },
    );
  }

  Widget _buildTenantCard(Tenant tenant) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showTenantDetailDialog(tenant),
        onLongPress: () => _showTenantOptionsMenu(tenant),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: tenant.isMainTenant 
                    ? Colors.blue.shade100 
                    : Colors.grey.shade200,
                child: Text(
                  tenant.fullName.isNotEmpty ? tenant.fullName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: tenant.isMainTenant 
                        ? Colors.blue.shade700 
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tenant.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        if (tenant.isMainTenant)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Chủ phòng',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    if (tenant.occupation != null) ...[
                      Row(
                        children: [
                          Icon(Icons.work, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tenant.occupation!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          tenant.phoneNumber,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('Vào ở: ${_formatDate(tenant.moveInDate)}'),
                      ],
                    ),
                    if (tenant.monthlyRent != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _formatCurrency(tenant.monthlyRent!),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getTenantStatusColor(tenant.status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tenant.getStatusDisplayName(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getTenantStatusColor(tenant.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (tenant.vehicles != null && tenant.vehicles!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_car, size: 12, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '${tenant.vehicles!.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.purple.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        if (tenant.previousRentals != null && tenant.previousRentals!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history, size: 12, color: Colors.orange.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '${tenant.previousRentals!.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                onPressed: () => _showTenantOptionsMenu(tenant),
                tooltip: 'Tùy chọn',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:
        return Colors.green;
      case TenantStatus.inactive:
        return Colors.orange;
      case TenantStatus.moveOut:
        return Colors.red;
      case TenantStatus.suspended:
        return Colors.grey;
    }
  }

  // =========================
  // PAYMENT METHODS - USING NEW DIALOGS AND PDF
  // =========================
  
  void _showAddPaymentDialog() {
    _showTrackedDialog(
      context: context,
      builder: (context) => ImprovedPaymentFormDialog(
        organization: widget.organization,
        buildingService: widget.buildingService,
        roomService: widget.roomService,
        tenantService: widget.tenantService,
        paymentService: widget.paymentService,
        room: widget.room, // Pass the room to filter tenants
      ),
    ).then((result) {
      if (result == true) {
        // Refresh the payment list from database
        widget.paymentsNotifier.loadRoomPayments(widget.room.id, widget.organization.id);
      }
    });
  }

  void _showPaymentDetailDialog(Payment payment, bool isAdmin) async {
    // Get tenant info for the payment
    Tenant? tenant;
    if (payment.tenantId != null) {
      tenant = await widget.tenantService.getTenantById(payment.tenantId!);
    }

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
        // TODO: Add these callbacks when ViewPaymentDetailsDialog is updated:
        // onDelete: () => _showDeletePaymentDialog(payment),
        // onExportPDF: () => _exportPDFQuick(payment, tenant),
        // onPreviewPDF: () => _showPDFPreview(payment, tenant),
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
      if (result == true) {
        // Refresh the payment list from database
        widget.paymentsNotifier.loadRoomPayments(widget.room.id, widget.organization.id);
      }
    });
  }

  void _showDeletePaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => DeletePaymentDialog(
        payment: payment,
        paymentService: widget.paymentService,
        onDeleted: () {
          // Refresh the payment list from database
          widget.paymentsNotifier.loadRoomPayments(widget.room.id, widget.organization.id);
        },
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

  // =========================
  // BUILD PAYMENTS TAB
  // =========================
  Widget _buildPaymentsTab() {
    return ListenableBuilder(
      listenable: widget.paymentsNotifier,
      builder: (context, _) {
        final allPayments = widget.paymentsNotifier.payments
            .where((p) => p.roomId == widget.room.id)
            .toList();
        
        if (allPayments.isEmpty) {
          return FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, membershipSnapshot) {
              final isAdmin = membershipSnapshot.hasData &&
                  membershipSnapshot.data!.role == 'admin';

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có hóa đơn',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tạo hóa đơn để bắt đầu quản lý thanh toán',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    if (isAdmin)
                      ElevatedButton.icon(
                        onPressed: _showAddPaymentDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Tạo hóa đơn'),
                      ),
                  ],
                ),
              );
            },
          );
        }

        final sortedPayments = List<Payment>.from(allPayments);
        sortedPayments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Group payments by status
        final pendingPayments = sortedPayments.where((p) => p.status == PaymentStatus.pending).toList();
        final overduePayments = sortedPayments.where((p) => p.isOverdue).toList();
        final paidPayments = sortedPayments.where((p) => p.status == PaymentStatus.paid).toList();

        return FutureBuilder<Membership?>(
          future: _getMyMembership(),
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Chưa thanh toán',
                        pendingPayments.length.toString(),
                        Icons.pending_outlined,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Quá hạn',
                        overduePayments.length.toString(),
                        Icons.warning_outlined,
                        Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Đã thanh toán',
                        paidPayments.length.toString(),
                        Icons.check_circle_outline,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Payment list
                ...sortedPayments.map((payment) => _buildPaymentCard(payment, isAdmin)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(Payment payment, bool isAdmin) {
    final statusColor = _getPaymentStatusColor(payment.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showPaymentDetailDialog(payment, isAdmin),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getPaymentTypeColor(payment.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getPaymentTypeIcon(payment.type),
                      color: _getPaymentTypeColor(payment.type),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getPaymentTypeDisplayName(payment.type),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          payment.tenantName ?? 'Không xác định',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(payment.totalAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          payment.getStatusDisplayName(),
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Billing period for recurring payments
              if (payment.billingStartDate != null && payment.billingEndDate != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Kỳ: ${_formatDate(payment.billingStartDate!)} - ${_formatDate(payment.billingEndDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (payment.billingStartDate != null) const SizedBox(height: 8),
              
              // Due date
              Row(
                children: [
                  Icon(Icons.event_available, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    'Hạn: ${_formatDate(payment.dueDate)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  if (payment.paidAmount > 0 && payment.status != PaymentStatus.paid)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Đã trả: ${_formatCurrency(payment.paidAmount)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              
              // Overdue warning
              if (payment.isOverdue) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Quá hạn ${payment.daysOverdue} ngày',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (payment.lateFee != null && payment.lateFee! > 0) ...[
                        const Spacer(),
                        Text(
                          '+${_formatCurrency(payment.lateFee!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              // Payment completed indicator
              if (payment.status == PaymentStatus.paid && payment.paidAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Đã thanh toán: ${_formatDate(payment.paidAt!)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (payment.paymentMethod != null) ...[
                        const Spacer(),
                        Text(
                          payment.getPaymentMethodDisplayName() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.purple;
      case PaymentStatus.partial:
        return Colors.blue;
    }
  }

  Color _getPaymentTypeColor(PaymentType type) {
    switch (type) {
      case PaymentType.rent:
        return Colors.blue;
      case PaymentType.electricity:
        return Colors.yellow.shade700;
      case PaymentType.water:
        return Colors.cyan;
      case PaymentType.internet:
        return Colors.purple;
      case PaymentType.parking:
        return Colors.brown;
      case PaymentType.maintenance:
        return Colors.orange;
      case PaymentType.deposit:
        return Colors.green;
      case PaymentType.penalty:
        return Colors.red;
      case PaymentType.other:
        return Colors.grey;
    }
  }

  IconData _getPaymentTypeIcon(PaymentType type) {
    switch (type) {
      case PaymentType.rent:
        return Icons.home;
      case PaymentType.electricity:
        return Icons.bolt;
      case PaymentType.water:
        return Icons.water_drop;
      case PaymentType.internet:
        return Icons.wifi;
      case PaymentType.parking:
        return Icons.local_parking;
      case PaymentType.maintenance:
        return Icons.build;
      case PaymentType.deposit:
        return Icons.account_balance_wallet;
      case PaymentType.penalty:
        return Icons.warning;
      case PaymentType.other:
        return Icons.more_horiz;
    }
  }

  String _getPaymentTypeDisplayName(PaymentType type) {
    switch (type) {
      case PaymentType.rent:
        return 'Tiền thuê nhà';
      case PaymentType.electricity:
        return 'Tiền điện';
      case PaymentType.water:
        return 'Tiền nước';
      case PaymentType.internet:
        return 'Tiền Internet';
      case PaymentType.parking:
        return 'Phí gửi xe';
      case PaymentType.maintenance:
        return 'Phí bảo trì';
      case PaymentType.deposit:
        return 'Tiền cọc';
      case PaymentType.penalty:
        return 'Phí phạt';
      case PaymentType.other:
        return 'Khác';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // BUILD UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check minimum size
        const minWidth = 360.0;
        const minHeight = 600.0;
        
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          return Scaffold(
            body: _buildMinimumSizeWarning(context, constraints),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('Phòng ${widget.room.roomNumber}'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.people), text: 'Người thuê'),
                Tab(icon: Icon(Icons.receipt_long), text: 'Hóa đơn'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTenantsTab(),
              _buildPaymentsTab(),
            ],
          ),
          floatingActionButton: FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.role == 'admin') {
                return FloatingActionButton(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      // Add tenant
                      _showAddEditTenantDialog();
                    } else {
                      // Add payment
                      _showAddPaymentDialog();
                    }
                  },
                  child: const Icon(Icons.add),
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