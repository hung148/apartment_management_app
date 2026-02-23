import 'dart:async';

import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/screens/payment/payment_pdf_export.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/utils/currency_formatter.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Helper class for invoice line items with meter readings
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;
  
  // Electricity fields
  double? electricityStartReading;
  DateTime? electricityStartDate;
  double? electricityEndReading;
  DateTime? electricityEndDate;
  double? electricityPricePerUnit;
  
  // Water fields
  double? waterStartReading;
  DateTime? waterStartDate;
  double? waterEndReading;
  DateTime? waterEndDate;
  double? waterPricePerUnit;
  
  // Billing period
  DateTime? billingStartDate;
  DateTime? billingEndDate;

  InvoiceLineItem({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
    this.electricityStartReading,
    this.electricityStartDate,
    this.electricityEndReading,
    this.electricityEndDate,
    this.electricityPricePerUnit,
    this.waterStartReading,
    this.waterStartDate,
    this.waterEndReading,
    this.waterEndDate,
    this.waterPricePerUnit,
    this.billingStartDate,
    this.billingEndDate,
  });
}

// Parse line items from payment
List<InvoiceLineItem> _parseLineItems(Payment payment) {
  // For single-type payments with meter readings, create detailed line item
  if (payment.type == PaymentType.electricity && payment.electricityStartReading != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        electricityStartReading: payment.electricityStartReading,
        electricityStartDate: payment.electricityStartDate,
        electricityEndReading: payment.electricityEndReading,
        electricityEndDate: payment.electricityEndDate,
        electricityPricePerUnit: payment.electricityPricePerUnit,
      ),
    ];
  }
  
  if (payment.type == PaymentType.water && payment.waterStartReading != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        waterStartReading: payment.waterStartReading,
        waterStartDate: payment.waterStartDate,
        waterEndReading: payment.waterEndReading,
        waterEndDate: payment.waterEndDate,
        waterPricePerUnit: payment.waterPricePerUnit,
      ),
    ];
  }
  
  if (payment.type == PaymentType.rent && payment.billingStartDate != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        billingStartDate: payment.billingStartDate,
        billingEndDate: payment.billingEndDate,
      ),
    ];
  }
  
  // Try to parse multi-line format from description
  final description = payment.description;
  if (description != null && description.contains('\n')) {
    final lines = description.split('\n');
    final items = <InvoiceLineItem>[];
    
    for (var line in lines) {
      final match = RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$').firstMatch(line.trim());
      if (match != null) {
        final typeLabel = match.group(1)?.trim() ?? '';
        final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
        final desc = match.group(3);
        
        PaymentType type = PaymentType.other;
        const labelToType = {
          'Tiền thuê': PaymentType.rent,
          'Tiền điện': PaymentType.electricity,
          'Tiền nước': PaymentType.water,
          'Tiền internet': PaymentType.internet,
          'Tiền gửi xe': PaymentType.parking,
          'Phí bảo trì': PaymentType.maintenance,
          'Tiền cọc': PaymentType.deposit,
          'Tiền phạt': PaymentType.penalty,
          'Khác': PaymentType.other,
        };
        
        type = labelToType[typeLabel] ?? PaymentType.other;
        
        items.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() + items.length.toString(),
          type: type,
          amount: double.tryParse(amountStr) ?? 0,
          description: desc,
        ));
      }
    }
    
    if (items.isNotEmpty) return items;
  }
  
  // Default: single line item
  return [
    InvoiceLineItem(
      id: payment.id,
      type: payment.type,
      amount: payment.amount,
      description: description,
      billingStartDate: payment.billingStartDate,
      billingEndDate: payment.billingEndDate,
    ),
  ];
}

// ========================================
// VIEW PAYMENT DETAILS DIALOG (unchanged)
// ========================================
class ViewPaymentDetailsDialog extends StatefulWidget {
  final Payment payment;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final Organization organization;
  final RoomService roomService;
  final BuildingService buildingService;
  final PaymentService paymentService;
  final TenantService tenantService;

  const ViewPaymentDetailsDialog({
    super.key,
    required this.payment,
    required this.isAdmin,
    required this.organization,
    required this.roomService,
    required this.buildingService,
    required this.paymentService,
    required this.tenantService,
    this.onEdit,
  });

  @override
  State<ViewPaymentDetailsDialog> createState() => _ViewPaymentDetailsDialogState();
}

class _ViewPaymentDetailsDialogState extends State<ViewPaymentDetailsDialog> with WidgetsBindingObserver {
  Room? _room;
  Building? _building;
  Tenant? _tenant;
  bool _isLoadingRoomData = true;

  int _overlayCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoomAndBuildingData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _loadRoomAndBuildingData() async {
    try {
      final room = await widget.roomService.getRoomById(widget.payment.roomId);
      if (room != null && mounted) {
        setState(() {
          _room = room;
        });
        
        final building = await widget.buildingService.getBuildingById(room.buildingId);
        if (building != null && mounted) {
          setState(() {
            _building = building;
          });
        }

        if (widget.payment.tenantId != null) {
          final tenant = await widget.tenantService.getTenantById(widget.payment.tenantId!);
          if (tenant != null && mounted) {
            setState(() => _tenant = tenant);
          }
        }
      }
    } catch (e) {
      print('Error loading room/building data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoomData = false;
        });
      }
    }
  }

  Future<void> _exportToPDF() async {
    await PaymentPDFExporter.showPDFPreview(
      context: context,
      payment: widget.payment,
      organization: widget.organization,
      roomNumber: _room?.roomNumber,
      buildingName: _building?.name,
      email: _tenant?.email ?? '',
    );
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.blue;
      case PaymentStatus.partial:
        return Colors.amber;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemCard(InvoiceLineItem item, int index, BuildContext context) {
    const labels = {
      'rent': 'Tiền thuê',
      'electricity': 'Tiền điện',
      'water': 'Tiền nước',
      'internet': 'Tiền internet',
      'parking': 'Tiền gửi xe',
      'maintenance': 'Phí bảo trì',
      'deposit': 'Tiền cọc',
      'penalty': 'Tiền phạt',
      'other': 'Khác',
    };
    final typeLabel = labels[item.type.name] ?? item.type.name;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    typeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  NumberFormat('#,###').format(item.amount) + ' đ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            
            if (item.type == PaymentType.electricity) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chỉ số đầu',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        Text(
                          item.electricityStartReading != null 
                              ? '${item.electricityStartReading} kWh'
                              : 'N/A',
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w500,
                            color: item.electricityStartReading == null ? Colors.grey : null,
                          ),
                        ),
                        if (item.electricityStartDate != null)
                          Text(
                            DateFormat('dd/MM/yyyy').format(item.electricityStartDate!),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chỉ số cuối',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        Text(
                          item.electricityEndReading != null 
                              ? '${item.electricityEndReading} kWh'
                              : 'N/A',
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w500,
                            color: item.electricityEndReading == null ? Colors.grey : null,
                          ),
                        ),
                        if (item.electricityEndDate != null)
                          Text(
                            DateFormat('dd/MM/yyyy').format(item.electricityEndDate!),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.electricityStartReading != null && item.electricityEndReading != null
                    ? 'Tiêu thụ: ${(item.electricityEndReading! - item.electricityStartReading!).toStringAsFixed(1)} kWh${item.electricityPricePerUnit != null ? " × ${NumberFormat('#,###').format(item.electricityPricePerUnit)} đ/kWh" : ""}'
                    : 'Tiêu thụ: N/A',
                style: TextStyle(
                  fontSize: 11, 
                  color: item.electricityStartReading != null && item.electricityEndReading != null 
                      ? Colors.grey[600] 
                      : Colors.grey[400],
                ),
              ),
            ],
            
            if (item.type == PaymentType.water) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chỉ số đầu',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        Text(
                          item.waterStartReading != null 
                              ? '${item.waterStartReading} m³'
                              : 'N/A',
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w500,
                            color: item.waterStartReading == null ? Colors.grey : null,
                          ),
                        ),
                        if (item.waterStartDate != null)
                          Text(
                            DateFormat('dd/MM/yyyy').format(item.waterStartDate!),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chỉ số cuối',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        Text(
                          item.waterEndReading != null 
                              ? '${item.waterEndReading} m³'
                              : 'N/A',
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w500,
                            color: item.waterEndReading == null ? Colors.grey : null,
                          ),
                        ),
                        if (item.waterEndDate != null)
                          Text(
                            DateFormat('dd/MM/yyyy').format(item.waterEndDate!),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.waterStartReading != null && item.waterEndReading != null
                    ? 'Tiêu thụ: ${(item.waterEndReading! - item.waterStartReading!).toStringAsFixed(1)} m³${item.waterPricePerUnit != null ? " × ${NumberFormat('#,###').format(item.waterPricePerUnit)} đ/m³" : ""}'
                    : 'Tiêu thụ: N/A',
                style: TextStyle(
                  fontSize: 11, 
                  color: item.waterStartReading != null && item.waterEndReading != null 
                      ? Colors.grey[600] 
                      : Colors.grey[400],
                ),
              ),
            ],
            
            if (item.billingStartDate != null && item.billingEndDate != null) ...[
              const SizedBox(height: 8),
              Text(
                'Kỳ: ${DateFormat('dd/MM/yyyy').format(item.billingStartDate!)} - ${DateFormat('dd/MM/yyyy').format(item.billingEndDate!)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
            
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.description!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final lineItems = _parseLineItems(widget.payment);
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getPaymentStatusColor(widget.payment.status).withOpacity(0.2),
                    child: Icon(
                      widget.payment.status == PaymentStatus.paid
                          ? Icons.check_circle
                          : Icons.pending,
                      color: _getPaymentStatusColor(widget.payment.status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chi Tiết Hóa Đơn',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.payment.getStatusDisplayName(),
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPaymentStatusColor(widget.payment.status),
                          ),
                        ),
                      ],
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDetailRow('Người Thuê', widget.payment.tenantName ?? 'Chưa xác định'),
                      if (_room != null)
                        _buildDetailRow('Phòng', _room!.roomNumber),
                      if (_building != null)
                        _buildDetailRow('Tòa nhà', _building!.name),
                      _buildDetailRow('Hạn Thanh Toán', DateFormat('dd/MM/yyyy').format(widget.payment.dueDate)),
                      if (widget.payment.paidAt != null)
                        _buildDetailRow('Ngày Thanh Toán', DateFormat('dd/MM/yyyy').format(widget.payment.paidAt!)),
                      
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      const Text(
                        'Chi Tiết Các Khoản',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      ...List.generate(
                        lineItems.length,
                        (index) => _buildLineItemCard(lineItems[index], index, context),
                      ),
                      
                      const SizedBox(height: 8),
                      const Divider(thickness: 2),
                      const SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TỔNG CỘNG:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            NumberFormat('#,###').format(widget.payment.amount) + ' VND',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      
                      if (widget.payment.lateFee != null && widget.payment.lateFee! > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Phí trễ hạn:',
                              style: TextStyle(fontSize: 14, color: Colors.red),
                            ),
                            Text(
                              NumberFormat('#,###').format(widget.payment.lateFee!) + ' VND',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                      
                      const SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TỔNG CỘNG:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            NumberFormat('#,###').format(widget.payment.amount + (widget.payment.lateFee ?? 0)) + ' VND',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tiền thuế:',
                            style: TextStyle(fontSize: 14, color: Colors.orange),
                          ),
                          Text(
                            NumberFormat('#,###').format(widget.payment.taxAmount ?? 0) + ' VND',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      const Divider(),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TỔNG THANH TOÁN:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            NumberFormat('#,###').format(widget.payment.totalAmount) + ' VND',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Đóng'),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete),
                          label: const Text('Xóa'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => _showDeleteConfirmation(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (widget.isAdmin && widget.onEdit != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('Chỉnh Sửa'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onEdit!();
                            },
                          ),
                        ),
                      if (widget.isAdmin && widget.onEdit != null)
                        const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isLoadingRoomData
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: const Text('Xuất PDF'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          onPressed: _isLoadingRoomData ? null : _exportToPDF,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    _showTrackedDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xóa phiếu thanh toán'),
          content: const Text('Bạn có chắc muốn xóa phiếu thanh toán này không?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await widget.paymentService.deletePayment(widget.payment.id);
                if (mounted) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa phiếu thanh toán')),
                  );
                }
              },
              child: const Text('Xóa', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}

// ========================================
// EDIT PAYMENT DIALOG - WITH UPDATED DATE PICKERS
// ========================================
class EditPaymentDialog extends StatefulWidget {
  final Payment payment;
  final Organization organization;
  final BuildingService buildingService;
  final RoomService roomService;
  final TenantService tenantService;
  final PaymentService paymentService;

  const EditPaymentDialog({
    super.key,
    required this.payment,
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
  });

  @override
  State<EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<EditPaymentDialog> with WidgetsBindingObserver {
  int _overlayCount = 0;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _notesController;
  late TextEditingController _taxAmountController;
  late TextEditingController _paidAmountController;
  
  late String? _selectedTenantId;
  late String? _selectedTenantName;
  late PaymentStatus _selectedPaymentStatus;
  late DateTime _dueDate;
  
  List<Tenant> _tenants = [];
  List<InvoiceLineItem> _lineItems = [];
  
  double get _totalAmount => _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notesController = TextEditingController(text: widget.payment.notes);
    _taxAmountController = TextEditingController(
      text: widget.payment.taxAmount != null ? widget.payment.taxAmount.toString() : '0.0',
    );
    _paidAmountController = TextEditingController(
      text: widget.payment.paidAmount.toStringAsFixed(0),
    );
    _selectedTenantId = widget.payment.tenantId;
    _selectedTenantName = widget.payment.tenantName;
    _selectedPaymentStatus = widget.payment.status;
    _dueDate = widget.payment.dueDate;
    
    _lineItems = _parseLineItems(widget.payment);
    
    _loadData();
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

  Future<void> _loadData() async {
    try {
      final tenants = await widget.tenantService.getOrganizationTenants(widget.organization.id);
      setState(() {
        _tenants = tenants;
        
        if (_selectedTenantId != null) {
          final tenantExists = _tenants.any((t) => t.id == _selectedTenantId);
          if (!tenantExists) {
            _selectedTenantId = null;
            _selectedTenantName = null;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  Future<void> _showAddLineItemDialog() async {
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    
    final electricityStartReadingController = TextEditingController();
    DateTime? electricityStartDate;
    final electricityEndReadingController = TextEditingController();
    DateTime? electricityEndDate;
    final electricityPriceController = TextEditingController();
    
    final waterStartReadingController = TextEditingController();
    DateTime? waterStartDate;
    final waterEndReadingController = TextEditingController();
    DateTime? waterEndDate;
    final waterPriceController = TextEditingController();
    
    DateTime? billingStart;
    DateTime? billingEnd;
    
    final result = await _showTrackedDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calculateAmount() {
            if (selectedType == PaymentType.electricity) {
              final startReading = double.tryParse(electricityStartReadingController.text) ?? 0;
              final endReading = double.tryParse(electricityEndReadingController.text) ?? 0;
              final price = double.tryParse(electricityPriceController.text) ?? 0;
              final usage = endReading - startReading;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            } else if (selectedType == PaymentType.water) {
              final startReading = double.tryParse(waterStartReadingController.text) ?? 0;
              final endReading = double.tryParse(waterEndReadingController.text) ?? 0;
              final price = double.tryParse(waterPriceController.text) ?? 0;
              final usage = endReading - startReading;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            }
          }
          
          return AlertDialog(
            title: const Text('Thêm Mục Hóa Đơn'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PaymentType>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Loại thanh toán *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: PaymentType.values.map((t) {
                      const labels = {
                        'rent': 'Tiền thuê',
                        'electricity': 'Tiền điện',
                        'water': 'Tiền nước',
                        'internet': 'Tiền internet',
                        'parking': 'Tiền gửi xe',
                        'maintenance': 'Phí bảo trì',
                        'deposit': 'Tiền cọc',
                        'penalty': 'Tiền phạt',
                        'other': 'Khác',
                      };
                      return DropdownMenuItem(
                        value: t, 
                        child: Text(labels[t.name] ?? ''),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),
                  
                  // UPDATED: Electricity fields with Vietnamese date pickers
                  if (selectedType == PaymentType.electricity) ...[
                    const Text(
                      'Chỉ số điện',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: electricityStartReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số đầu *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: electricityStartDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() => electricityStartDate = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: electricityEndReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số cuối *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: electricityEndDate ?? DateTime.now(),
                            firstDate: electricityStartDate ?? DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() {
                                electricityEndDate = date;
                                calculateAmount();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: electricityPriceController,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Giá điện (VND/kWh) *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // UPDATED: Water fields with Vietnamese date pickers
                  if (selectedType == PaymentType.water) ...[
                    const Text(
                      'Chỉ số nước',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waterStartReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số đầu *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: waterStartDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() => waterStartDate = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waterEndReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số cuối *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: waterEndDate ?? DateTime.now(),
                            firstDate: waterStartDate ?? DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() {
                                waterEndDate = date;
                                calculateAmount();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: waterPriceController,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Giá nước (VND/m³) *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // UPDATED: Billing period with Vietnamese date pickers
                  if (selectedType == PaymentType.rent || selectedType == PaymentType.water) ...[
                    const Text(
                      'Kỳ thanh toán',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: billingStart,
                            firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                            lastDate: DateTime.now().add(const Duration(days: 180)),
                            onDateChanged: (date) {
                              setDialogState(() => billingStart = date);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: billingEnd,
                            firstDate: billingStart ?? DateTime.now().subtract(const Duration(days: 365 * 2)),
                            lastDate: DateTime.now().add(const Duration(days: 180)),
                            onDateChanged: (date) {
                              setDialogState(() => billingEnd = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  TextFormField(
                    controller: amountController,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Số tiền *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixText: 'VND',
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: selectedType == PaymentType.electricity || selectedType == PaymentType.water,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Mô tả',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedType != null && amountController.text.isNotEmpty) {
                    final amount = double.tryParse(amountController.text);
                    if (amount != null && amount > 0) {
                      final result = <String, dynamic>{
                        'type': selectedType!,
                        'amount': amount,
                        'description': descriptionController.text.isEmpty ? null : descriptionController.text,
                      };
                      
                      if (selectedType == PaymentType.electricity) {
                        result['electricityStartReading'] = double.tryParse(electricityStartReadingController.text);
                        result['electricityStartDate'] = electricityStartDate;
                        result['electricityEndReading'] = double.tryParse(electricityEndReadingController.text);
                        result['electricityEndDate'] = electricityEndDate;
                        result['electricityPricePerUnit'] = double.tryParse(electricityPriceController.text);
                      }
                      
                      if (selectedType == PaymentType.water) {
                        result['waterStartReading'] = double.tryParse(waterStartReadingController.text);
                        result['waterStartDate'] = waterStartDate;
                        result['waterEndReading'] = double.tryParse(waterEndReadingController.text);
                        result['waterEndDate'] = waterEndDate;
                        result['waterPricePerUnit'] = double.tryParse(waterPriceController.text);
                      }
                      
                      if (selectedType == PaymentType.rent || selectedType == PaymentType.water) {
                        result['billingStartDate'] = billingStart;
                        result['billingEndDate'] = billingEnd;
                      }
                      
                      Navigator.pop(context, result);
                    }
                  }
                },
                child: const Text('Thêm'),
              ),
            ],
          );
        },
      ),
    );
    
    if (result != null) {
      setState(() {
        _lineItems.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: result['type'] as PaymentType,
          amount: result['amount'] as double,
          description: result['description'] as String?,
          electricityStartReading: result['electricityStartReading'] as double?,
          electricityStartDate: result['electricityStartDate'] as DateTime?,
          electricityEndReading: result['electricityEndReading'] as double?,
          electricityEndDate: result['electricityEndDate'] as DateTime?,
          electricityPricePerUnit: result['electricityPricePerUnit'] as double?,
          waterStartReading: result['waterStartReading'] as double?,
          waterStartDate: result['waterStartDate'] as DateTime?,
          waterEndReading: result['waterEndReading'] as double?,
          waterEndDate: result['waterEndDate'] as DateTime?,
          waterPricePerUnit: result['waterPricePerUnit'] as double?,
          billingStartDate: result['billingStartDate'] as DateTime?,
          billingEndDate: result['billingEndDate'] as DateTime?,
        ));
      });
    }
  }

  void _removeLineItem(String id) {
    setState(() {
      _lineItems.removeWhere((item) => item.id == id);
    });
  }

  Widget _buildLineItemsList() {
    if (_lineItems.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'Chưa có mục nào',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
          const labels = {
            'rent': 'Tiền thuê',
            'electricity': 'Tiền điện',
            'water': 'Tiền nước',
            'internet': 'Tiền internet',
            'parking': 'Tiền gửi xe',
            'maintenance': 'Phí bảo trì',
            'deposit': 'Tiền cọc',
            'penalty': 'Tiền phạt',
            'other': 'Khác',
          };
          final typeLabel = labels[item.type.name] ?? item.type.name;
          
          String detailText = '';
          if (item.type == PaymentType.electricity && item.electricityStartReading != null) {
            final usage = (item.electricityEndReading ?? 0) - (item.electricityStartReading ?? 0);
            detailText = 'Từ ${item.electricityStartReading} đến ${item.electricityEndReading} (${usage.toStringAsFixed(1)} kWh)';
          } else if (item.type == PaymentType.water && item.waterStartReading != null) {
            final usage = (item.waterEndReading ?? 0) - (item.waterStartReading ?? 0);
            detailText = 'Từ ${item.waterStartReading} đến ${item.waterEndReading} (${usage.toStringAsFixed(1)} m³)';
          } else if (item.description != null) {
            detailText = item.description!;
          }
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(typeLabel),
              subtitle: detailText.isNotEmpty 
                  ? Text(detailText, style: const TextStyle(fontSize: 12))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    NumberFormat('#,###').format(item.amount) + ' đ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeLineItem(item.id),
                  ),
                ],
              ),
            ),
          );
        }),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TỔNG CỘNG:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                NumberFormat('#,###').format(_totalAmount) + ' VND',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm ít nhất một mục hóa đơn')),
      );
      return;
    }

    try {
      final lineItemsDescription = _lineItems.map((item) {
        const labels = {
          'rent': 'Tiền thuê',
          'electricity': 'Tiền điện',
          'water': 'Tiền nước',
          'internet': 'Tiền internet',
          'parking': 'Tiền gửi xe',
          'maintenance': 'Phí bảo trì',
          'deposit': 'Tiền cọc',
          'penalty': 'Tiền phạt',
          'other': 'Khác',
        };
        final typeLabel = labels[item.type.name] ?? item.type.name;
        final desc = item.description != null ? ' (${item.description})' : '';
        return '${typeLabel}: ${NumberFormat('#,###').format(item.amount)} VND$desc';
      }).join('\n');

      // --- CALCULATE TOTALS ---
      final double tax = _taxAmountController.text.isEmpty ? 0 : double.parse(_taxAmountController.text.replaceAll(',', ''));
      final double totalToCollect = _totalAmount + tax + (widget.payment.lateFee ?? 0);

      final Map<String, dynamic> updates = {
        'tenantId': _selectedTenantId,
        'tenantName': _selectedTenantName,
        'amount': _totalAmount,
        'dueDate': _dueDate,
        'status': _selectedPaymentStatus.name,
        'description': lineItemsDescription,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'taxAmount': _taxAmountController.text.isEmpty ? null : double.parse(_taxAmountController.text),
      };
      
      if (_selectedPaymentStatus == PaymentStatus.paid) {
        updates['paidAmount'] = totalToCollect;
        updates['paidAt'] = widget.payment.paidAt != null
            ? Timestamp.fromDate(widget.payment.paidAt!)
            : Timestamp.now();
      } else if (_selectedPaymentStatus == PaymentStatus.partial) {
        final partialAmount = double.tryParse(
          _paidAmountController.text.replaceAll(',', '')
        ) ?? 0.0;
        updates['paidAmount'] = partialAmount;
        updates['paidAt'] = Timestamp.now();
      } else {
        // pending, overdue, cancelled, refunded
        updates['paidAmount'] = 0.0;
        updates['paidAt'] = null;
      }

      if (_lineItems.length == 1) {
        final item = _lineItems.first;
        if (item.electricityStartReading != null) {
          updates['electricityStartReading'] = item.electricityStartReading;
          updates['electricityStartDate'] = item.electricityStartDate;
          updates['electricityEndReading'] = item.electricityEndReading;
          updates['electricityEndDate'] = item.electricityEndDate;
          updates['electricityPricePerUnit'] = item.electricityPricePerUnit;
        }
        if (item.waterStartReading != null) {
          updates['waterStartReading'] = item.waterStartReading;
          updates['waterStartDate'] = item.waterStartDate;
          updates['waterEndReading'] = item.waterEndReading;
          updates['waterEndDate'] = item.waterEndDate;
          updates['waterPricePerUnit'] = item.waterPricePerUnit;
        }
        if (item.billingStartDate != null) {
          updates['billingStartDate'] = item.billingStartDate;
          updates['billingEndDate'] = item.billingEndDate;
        }
      }

      await widget.paymentService.updatePayment(widget.payment.id, updates);
      
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật hóa đơn thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesController.dispose();
    _taxAmountController.dispose();
    _paidAmountController.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.edit),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Chỉnh Sửa Hóa Đơn',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String?>(
                              value: _tenants.any((t) => t.id == _selectedTenantId) ? _selectedTenantId : null,
                              decoration: InputDecoration(
                                labelText: 'Người thuê',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Không chọn')),
                                ..._tenants.map((t) => DropdownMenuItem<String?>(value: t.id, child: Text(t.fullName ?? ''))).toList(),
                              ],
                              onChanged: (v) {
                                if (v != null && v.isNotEmpty) {
                                  final tenant = _tenants.firstWhere((t) => t.id == v);
                                  setState(() {
                                    _selectedTenantId = v;
                                    _selectedTenantName = tenant.fullName;
                                  });
                                } else {
                                  setState(() {
                                    _selectedTenantId = null;
                                    _selectedTenantName = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Các Mục Hóa Đơn',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _showAddLineItemDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Thêm Mục'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildLineItemsList(),
                            const SizedBox(height: 24),
                            
                            // UPDATED: Due Date with Vietnamese date picker
                            LocalizedDatePicker(
                              labelText: 'Hạn thanh toán',
                              prefixIcon: Icons.event,
                              required: true,
                              initialDate: _dueDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              onDateChanged: (date) {
                                if (date != null) {
                                  setState(() {
                                    _dueDate = date;
                                  });
                                }
                              },
                              validator: (date) {
                                if (date == null) {
                                  return 'Vui lòng chọn hạn thanh toán';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            
                            DropdownButtonFormField<PaymentStatus>(
                              initialValue: _selectedPaymentStatus,
                              decoration: InputDecoration(
                                labelText: 'Trạng thái *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: PaymentStatus.values.map((s) {
                                const labels = {
                                  'pending': 'Chờ thanh toán',
                                  'paid': 'Đã thanh toán',
                                  'overdue': 'Quá hạn',
                                  'cancelled': 'Đã hủy',
                                  'refunded': 'Đã hoàn tiền',
                                  'partial': 'Thanh toán 1 phần',
                                };
                                return DropdownMenuItem(value: s, child: Text(labels[s.name] ?? ''));
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedPaymentStatus = v!),
                            ),
                            const SizedBox(height: 12),
                            
                            if (_selectedPaymentStatus == PaymentStatus.partial) ...[
                              TextFormField(
                                controller: _paidAmountController,
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  labelText: 'Số tiền đã thanh toán (VND) *',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  helperText: 'Tổng hóa đơn: ${NumberFormat('#,###').format(_totalAmount)} VND',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (_selectedPaymentStatus == PaymentStatus.partial) {
                                    final val = double.tryParse(v?.replaceAll(',', '') ?? '');
                                    if (val == null || val <= 0) return 'Vui lòng nhập số tiền đã thanh toán';
                                    if (val >= _totalAmount) return 'Phải nhỏ hơn tổng hóa đơn';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                            ],

                            TextFormField(
                              controller: _notesController,
                              decoration: InputDecoration(
                                labelText: 'Ghi chú',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            
                            TextFormField(
                              controller: _taxAmountController,
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Tiền thuế (VND)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v!.isNotEmpty) {
                                  try {
                                    double.parse(v);
                                  } catch (e) {
                                    return 'Vui lòng nhập số hợp lệ';
                                  }
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                const Divider(height: 1),
                
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _savePayment,
                          child: const Text('Lưu'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}