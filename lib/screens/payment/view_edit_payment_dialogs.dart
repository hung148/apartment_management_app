import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/responsive_form_row.dart';
import 'dart:async';

import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_excel_export.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_pdf_export.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Shared entry point: existing imports expose both dialogs.
// Invoice parsing and common presentation helpers stay in this file.
part 'view_payment_details_dialog.dart';
part 'edit_payment_dialog.dart';

// ─────────────────────────────────────────────
// SHARED HELPERS & CONSTANTS
// ─────────────────────────────────────────────

Map<String, String> _typeLabels(AppTranslations t) => {
  'rent': t['payment_type_rent'],
  'electricity': t['payment_type_electricity'],
  'water': t['payment_type_water'],
  'internet': t['payment_type_internet'],
  'parking': t['payment_type_parking'],
  'maintenance': t['payment_type_maintenance'],
  'deposit': t['payment_type_deposit'],
  'penalty': t['payment_type_penalty'],
  'buildingRent': t['payment_type_building_rent'],
  'other': t['payment_type_other'],
};

Map<String, String> _statusLabels(AppTranslations t) => {
  'pending': t['status_pending'],
  'paid': t['status_paid'],
  'overdue': t['status_overdue'],
  'cancelled': t['status_cancelled'],
  'refunded': t['status_refunded'],
  'partial': t['status_partial'],
};

Color _statusColor(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.paid:
      return const Color(0xFF22C55E);
    case PaymentStatus.pending:
      return const Color(0xFFF59E0B);
    case PaymentStatus.overdue:
      return const Color(0xFFEF4444);
    case PaymentStatus.cancelled:
      return const Color(0xFF6B7280);
    case PaymentStatus.refunded:
      return const Color(0xFF3B82F6);
    case PaymentStatus.partial:
      return const Color(0xFFF97316);
  }
}

IconData _statusIcon(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.paid:
      return Icons.check_circle_rounded;
    case PaymentStatus.pending:
      return Icons.schedule_rounded;
    case PaymentStatus.overdue:
      return Icons.warning_amber_rounded;
    case PaymentStatus.cancelled:
      return Icons.cancel_rounded;
    case PaymentStatus.refunded:
      return Icons.undo_rounded;
    case PaymentStatus.partial:
      return Icons.incomplete_circle_rounded;
  }
}

Color _typeColor(PaymentType type) {
  switch (type) {
    case PaymentType.rent:
      return const Color(0xFF6366F1);
    case PaymentType.electricity:
      return const Color(0xFFF59E0B);
    case PaymentType.water:
      return const Color(0xFF06B6D4);
    case PaymentType.internet:
      return const Color(0xFF8B5CF6);
    case PaymentType.parking:
      return const Color(0xFF10B981);
    case PaymentType.maintenance:
      return const Color(0xFFEF4444);
    case PaymentType.deposit:
      return const Color(0xFF3B82F6);
    case PaymentType.penalty:
      return const Color(0xFFDC2626);
    case PaymentType.buildingRent:
      return const Color(0xFF475569);
    case PaymentType.hourlyRent:
      return const Color(0xFF4F46E5);
    case PaymentType.other:
      return const Color(0xFF6B7280);
  }
}

// ─────────────────────────────────────────────
// InvoiceLineItem MODEL
// ─────────────────────────────────────────────

class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;
  double? electricityStartReading;
  DateTime? electricityStartDate;
  double? electricityEndReading;
  DateTime? electricityEndDate;
  double? electricityPricePerUnit;
  double? waterStartReading;
  DateTime? waterStartDate;
  double? waterEndReading;
  DateTime? waterEndDate;
  double? waterPricePerUnit;
  DateTime? billingStartDate;
  DateTime? billingEndDate;

  // Rent unit-price calculation (theo ngày / theo tháng / theo năm)
  RentPriceMode? rentPriceMode;
  double? rentUnitPrice;
  double? rentUnitQuantity;

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
    this.rentPriceMode,
    this.rentUnitPrice,
    this.rentUnitQuantity,
  });
}

List<InvoiceLineItem> _parseLineItems(Payment payment) {
  if (payment.type == PaymentType.electricity &&
      payment.electricityStartReading != null) {
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
        rentPriceMode: payment.rentPriceMode,
        rentUnitPrice: payment.rentUnitPrice,
        rentUnitQuantity: payment.rentUnitQuantity,
      ),
    ];
  }

  final description = payment.description;
  if (description != null && description.contains('\n')) {
    final lines = description.split('\n');
    final items = <InvoiceLineItem>[];
    for (var line in lines) {
      final match = RegExp(r'^([^:]+):\s*([\d,.]+)\s*(?:VND|USD)(?:\s*\((.+)\))?$')
          .firstMatch(line.trim());
      if (match != null) {
        final typeLabel = match.group(1)?.trim() ?? '';
        final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
        final desc = match.group(3);
        const labelToType = {
          'Tiền thuê': PaymentType.rent,
          'Rent': PaymentType.rent,
          'Tiền điện': PaymentType.electricity,
          'Electricity': PaymentType.electricity,
          'Tiền nước': PaymentType.water,
          'Water': PaymentType.water,
          'Tiền internet': PaymentType.internet,
          'Internet': PaymentType.internet,
          'Tiền gửi xe': PaymentType.parking,
          'Parking': PaymentType.parking,
          'Phí bảo trì': PaymentType.maintenance,
          'Maintenance': PaymentType.maintenance,
          'Tiền cọc': PaymentType.deposit,
          'Deposit': PaymentType.deposit,
          'Tiền phạt': PaymentType.penalty,
          'Penalty': PaymentType.penalty,
          'Khác': PaymentType.other,
          'Other': PaymentType.other,
        };
        items.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() +
              items.length.toString(),
          type: labelToType[typeLabel] ?? PaymentType.other,
          amount: double.tryParse(amountStr) ?? 0,
          description: desc,
        ));
      }
    }
    if (items.isNotEmpty) return items;
  }

  return [
    InvoiceLineItem(
      id: payment.id,
      type: payment.type,
      amount: payment.amount,
      description: description,
      billingStartDate: payment.billingStartDate,
      billingEndDate: payment.billingEndDate,
      rentPriceMode: payment.rentPriceMode,
      rentUnitPrice: payment.rentUnitPrice,
      rentUnitQuantity: payment.rentUnitQuantity,
    ),
  ];
}

// ─────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ]),
    );

Widget _infoRow(IconData icon, String label, String value,
    {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.grey.shade800,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Rent unit-price label helpers (theo ngày/tháng/năm) ────────────────────

String _rentUnitPriceLabel(AppTranslations t, RentPriceMode mode) {
  switch (mode) {
    case RentPriceMode.daily:
      return t['add_item_rent_price_daily'];
    case RentPriceMode.monthly:
      return t['add_item_rent_price_monthly'];
    case RentPriceMode.yearly:
      return t['add_item_rent_price_yearly'];
    case RentPriceMode.direct:
      return t['add_item_amount'];
  }
}

String _rentQuantityLabel(AppTranslations t, RentPriceMode mode) {
  switch (mode) {
    case RentPriceMode.daily:
      return t['add_item_rent_qty_daily'];
    case RentPriceMode.monthly:
      return t['add_item_rent_qty_monthly'];
    case RentPriceMode.yearly:
      return t['add_item_rent_qty_yearly'];
    case RentPriceMode.direct:
      return '';
  }
}

String _rentUnitShort(AppTranslations t, RentPriceMode mode) {
  switch (mode) {
    case RentPriceMode.daily:
      return t['unit_short_day'];
    case RentPriceMode.monthly:
      return t['unit_short_month'];
    case RentPriceMode.yearly:
      return t['unit_short_year'];
    case RentPriceMode.direct:
      return '';
  }
}

Widget _rentModeChip({
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
}) {
  const color = Color(0xFF6366F1);
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? color : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: selected ? Colors.white : Colors.grey.shade600),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    ),
  );
}
