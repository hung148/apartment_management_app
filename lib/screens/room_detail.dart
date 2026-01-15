import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> with SingleTickerProviderStateMixin {
  final TenantService _tenantService = TenantService();
  final PaymentService _paymentService = PaymentService();
  
  Room? room;
  late TabController _tabController;
  
  StreamSubscription<List<Tenant>>? _tenantSubscription;
  StreamSubscription<List<Payment>>? _paymentSubscription;
  
  List<Tenant>? _tenants;
  List<Payment>? _payments;
  
  bool _isLoadingTenants = true;
  bool _isLoadingPayments = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (_isInitialized) return;
    
    print('═══════════════════════════════════════');
    print('RoomDetailScreen: didChangeDependencies called');
    
    try {
      final args = ModalRoute.of(context)?.settings.arguments;
      
      if (args == null) {
        print('❌ ERROR: No room data received');
        return;
      }
      
      room = args as Room;
      print('Room received: ${room!.roomNumber} (ID: ${room!.id})');
      
      _isInitialized = true;
      _initializeStreams();
      
    } catch (e, stackTrace) {
      print('❌ ERROR in didChangeDependencies: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _initializeStreams() {
    if (room == null) return;
    
    // Stream tenants
    _tenantSubscription = _tenantService
        .streamRoomTenants(room!.id)
        .listen(
          (tenants) {
            print('✓ Received ${tenants.length} tenants');
            if (mounted) {
              setState(() {
                _tenants = tenants;
                _isLoadingTenants = false;
              });
            }
          },
          onError: (error) {
            print('❌ Tenant stream error: $error');
            if (mounted) {
              setState(() {
                _isLoadingTenants = false;
              });
            }
          },
        );
    
    // Stream payments
    _paymentSubscription = _paymentService
        .streamRoomPayments(room!.id)
        .listen(
          (payments) {
            print('✓ Received ${payments.length} payments');
            if (mounted) {
              setState(() {
                _payments = payments;
                _isLoadingPayments = false;
              });
            }
          },
          onError: (error) {
            print('❌ Payment stream error: $error');
            if (mounted) {
              setState(() {
                _isLoadingPayments = false;
              });
            }
          },
        );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tenantSubscription?.cancel();
    _paymentSubscription?.cancel();
    super.dispose();
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
  // TENANT CRUD OPERATIONS
  // =========================
  
  void _showAddEditTenantDialog({Tenant? tenant}) {
    final isEditing = tenant != null;
    
    // Controllers
    final nameController = TextEditingController(text: tenant?.fullName ?? '');
    final phoneController = TextEditingController(text: tenant?.phoneNumber ?? '');
    final emailController = TextEditingController(text: tenant?.email ?? '');
    final nationalIdController = TextEditingController(text: tenant?.nationalId ?? '');
    final rentController = TextEditingController(
      text: tenant?.monthlyRent?.toString() ?? '',
    );
    final depositController = TextEditingController(
      text: tenant?.deposit?.toString() ?? '',
    );
    
    Gender? selectedGender = tenant?.gender;
    bool isMainTenant = tenant?.isMainTenant ?? (_tenants?.isEmpty ?? true);
    DateTime moveInDate = tenant?.moveInDate ?? DateTime.now();
    DateTime? contractStartDate = tenant?.contractStartDate;
    DateTime? contractEndDate = tenant?.contractEndDate;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
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
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên *',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Phone Number
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại *',
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Email
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // National ID
                    TextField(
                      controller: nationalIdController,
                      decoration: const InputDecoration(
                        labelText: 'CMND/CCCD',
                        prefixIcon: Icon(Icons.credit_card),
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
                    
                    // Monthly Rent
                    TextField(
                      controller: rentController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tiền thuê hàng tháng',
                        prefixIcon: Icon(Icons.attach_money),
                        suffixText: 'VND',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Deposit
                    TextField(
                      controller: depositController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tiền cọc',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                        suffixText: 'VND',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Move In Date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Ngày vào ở'),
                      subtitle: Text(_formatDate(moveInDate)),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: moveInDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setDialogState(() {
                            moveInDate = date;
                          });
                        }
                      },
                    ),
                    
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
                        organizationId: room!.organizationId,
                        buildingId: room!.buildingId,
                        roomId: room!.id,
                        fullName: nameController.text.trim(),
                        phoneNumber: phoneController.text.trim(),
                        email: emailController.text.trim().isNotEmpty 
                            ? emailController.text.trim() 
                            : null,
                        nationalId: nationalIdController.text.trim().isNotEmpty
                            ? nationalIdController.text.trim()
                            : null,
                        gender: selectedGender,
                        isMainTenant: isMainTenant,
                        monthlyRent: rentController.text.isNotEmpty
                            ? double.tryParse(rentController.text)
                            : null,
                        deposit: depositController.text.isNotEmpty
                            ? double.tryParse(depositController.text)
                            : null,
                        moveInDate: moveInDate,
                        contractStartDate: contractStartDate,
                        contractEndDate: contractEndDate,
                        status: TenantStatus.active,
                        createdAt: tenant?.createdAt ?? DateTime.now(),
                      );

                      if (isEditing) {
                        // Update existing tenant
                        final success = await _tenantService.updateTenant(
                          tenant!.id,
                          {
                            'fullName': newTenant.fullName,
                            'phoneNumber': newTenant.phoneNumber,
                            'email': newTenant.email,
                            'nationalId': newTenant.nationalId,
                            'gender': newTenant.gender?.name,
                            'isMainTenant': newTenant.isMainTenant,
                            'monthlyRent': newTenant.monthlyRent,
                            'deposit': newTenant.deposit,
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
                        final tenantId = await _tenantService.addTenant(newTenant);
                        
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

  void _showTenantDetailDialog(Tenant tenant) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
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
                  _buildDetailSection('Thông tin liên hệ', [
                    _buildDetailRow('Số điện thoại', tenant.phoneNumber),
                    if (tenant.email != null) _buildDetailRow('Email', tenant.email!),
                  ]),
                  const Divider(),
                  _buildDetailSection('Thông tin cá nhân', [
                    if (tenant.gender != null) 
                      _buildDetailRow('Giới tính', tenant.getGenderDisplayName()!),
                    if (tenant.nationalId != null)
                      _buildDetailRow('CMND/CCCD', tenant.nationalId!),
                  ]),
                  const Divider(),
                  _buildDetailSection('Thông tin thuê', [
                    _buildDetailRow('Ngày vào ở', _formatDate(tenant.moveInDate)),
                    _buildDetailRow('Số ngày ở', '${tenant.daysLiving} ngày'),
                    if (tenant.monthlyRent != null)
                      _buildDetailRow('Tiền thuê', _formatCurrency(tenant.monthlyRent!)),
                    if (tenant.deposit != null)
                      _buildDetailRow('Tiền cọc', _formatCurrency(tenant.deposit!)),
                  ]),
                  if (tenant.contractStartDate != null || tenant.contractEndDate != null) ...[
                    const Divider(),
                    _buildDetailSection('Hợp đồng', [
                      if (tenant.contractStartDate != null)
                        _buildDetailRow('Bắt đầu', _formatDate(tenant.contractStartDate!)),
                      if (tenant.contractEndDate != null) ...[
                        _buildDetailRow('Kết thúc', _formatDate(tenant.contractEndDate!)),
                        if (tenant.daysUntilContractEnd != null)
                          _buildDetailRow(
                            'Còn lại',
                            '${tenant.daysUntilContractEnd} ngày',
                          ),
                      ],
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
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddEditTenantDialog(tenant: tenant);
                },
                child: const Text('Chỉnh sửa'),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _deleteTenant(Tenant tenant) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
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
                    final success = await _tenantService.deleteTenant(tenant.id);
                    
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
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
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
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    tenant.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(tenant.phoneNumber),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text('Tiền thuê: ${_formatCurrency(tenant.monthlyRent!)}'),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
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
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    _showTenantDetailDialog(tenant);
                    break;
                  case 'edit':
                    _showAddEditTenantDialog(tenant: tenant);
                    break;
                  case 'delete':
                    _deleteTenant(tenant);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Chi tiết'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                PopupMenuItem(
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
            ),
            onTap: () => _showTenantDetailDialog(tenant),
          ),
        );
      },
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

  void _showAddPaymentDialog() async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    PaymentType selectedType = PaymentType.other;
    Tenant? selectedTenant;

    // Load tenants BEFORE showing dialog
    final tenants = await _tenantService.getActiveRoomTenants(room!.id);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 2 / 3,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Thêm khoản thanh toán'),
                  contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        // ------------------------------------
                        // TENANT DROPDOWN
                        // ------------------------------------
                        DropdownButtonFormField<Tenant>(
                          decoration: const InputDecoration(
                            labelText: 'Người thuê',
                          ),
                          items: tenants.map((tenant) {
                            return DropdownMenuItem(
                              value: tenant,
                              child: Text(
                                tenant.fullName +
                                    (tenant.isMainTenant == true ? ' (Chính)' : ''),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedTenant = value;
                            });
                          },
                        ),
                    
                        const SizedBox(height: 16),
                    
                        // ------------------------------------
                        // PAYMENT TYPE
                        // ------------------------------------
                        DropdownButtonFormField<PaymentType>(
                          value: selectedType,
                          decoration: const InputDecoration(labelText: 'Loại thanh toán'),
                          items: PaymentType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedType = value!;
                            });
                          },
                        ),
                    
                        const SizedBox(height: 16),
                    
                        TextField(
                          controller: amountController,
                          decoration: const InputDecoration(labelText: 'Số tiền'),
                          keyboardType: TextInputType.number,
                        ),
                    
                        const SizedBox(height: 16),
                    
                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(labelText: 'Ghi chú'),
                        ),
                      ],
                    ),
                  ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),

                    // ------------------------------------
                    // ADD PAYMENT BUTTON
                    // ------------------------------------
                    ElevatedButton(
                      onPressed: selectedTenant == null
                          ? null
                          : () async {
                              final payment = Payment(
                                id: '',
                                organizationId: room!.organizationId,
                                buildingId: room!.buildingId,
                                roomId: room!.id,
                                tenantId: selectedTenant!.id,
                                tenantName: selectedTenant!.fullName,
                                type: selectedType,
                                status: PaymentStatus.pending,
                                amount: double.tryParse(amountController.text) ?? 0,
                                dueDate: DateTime.now().add(const Duration(days: 7)),
                                createdAt: DateTime.now(),
                                notes: notesController.text.trim(),
                              );

                              await PaymentService().addPayment(payment);
                              Navigator.pop(context);
                            },
                      child: const Text('Thêm'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // =========================
  // BUILD PAYMENTS TAB
  // =========================
  Widget _buildPaymentsTab() {
    if (_isLoadingPayments) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_payments == null || _payments!.isEmpty) {
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
            ElevatedButton.icon(
              onPressed: () {
                _showAddPaymentDialog();
              },
              icon: const Icon(Icons.add),
              label: const Text('Tạo hóa đơn'),
            ),
          ],
        ),
      );
    }

    // Group payments by status
    final pendingPayments = _payments!.where((p) => p.status == PaymentStatus.pending).toList();
    final overduePayments = _payments!.where((p) => p.isOverdue).toList();
    final paidPayments = _payments!.where((p) => p.status == PaymentStatus.paid).toList();

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
        ...(_payments!.map((payment) => _buildPaymentCard(payment))),
      ],
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

  Widget _buildPaymentCard(Payment payment) {
    final statusColor = _getPaymentStatusColor(payment.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          _showPaymentDetailDialog(payment);
        },
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
                          payment.getTypeDisplayName(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hạn thanh toán: ${_formatDate(payment.dueDate)}',
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

  void _showPaymentDetailDialog(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 2 / 3,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: AlertDialog(
            title: Text(payment.getTypeDisplayName()),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  _buildDetailRow('Số tiền', _formatCurrency(payment.amount)),
                  _buildDetailRow('Đã thanh toán', _formatCurrency(payment.paidAmount)),
                  _buildDetailRow('Còn lại', _formatCurrency(payment.remainingAmount)),
                  if (payment.lateFee != null && payment.lateFee! > 0)
                    _buildDetailRow('Phí phạt', _formatCurrency(payment.lateFee!)),
                  const Divider(),
                  _buildDetailRow('Hạn thanh toán', _formatDate(payment.dueDate)),
                  _buildDetailRow('Trạng thái', payment.getStatusDisplayName()),
                  if (payment.paidAt != null)
                    _buildDetailRow('Ngày thanh toán', _formatDate(payment.paidAt!)),
                  if (payment.paymentMethod != null)
                    _buildDetailRow('Phương thức', payment.getPaymentMethodDisplayName() ?? ''),
                  if (payment.transactionId != null)
                    _buildDetailRow('Mã giao dịch', payment.transactionId!),
                  if (payment.notes != null) ...[
                    const Divider(),
                    const Text('Ghi chú:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(payment.notes!),
                  ],
                ],
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
              if (payment.status == PaymentStatus.pending)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Mark as paid
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chức năng thanh toán đang phát triển')),
                    );
                  },
                  child: const Text('Thanh toán'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
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
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lỗi')),
        body: const Center(child: Text('Không tìm thấy dữ liệu phòng')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Phòng ${room!.roomNumber}'),
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
      floatingActionButton: FloatingActionButton(
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
      ),
    );
  }
}