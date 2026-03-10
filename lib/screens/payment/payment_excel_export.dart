import 'dart:io';

import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

// ─────────────────────────────────────────────────────────────────────────────
// Internal data class — one row in the Excel line-items table
// ─────────────────────────────────────────────────────────────────────────────
class _XlsLineItem {
  final String typeLabel;
  final double amount;
  final String? detail; // meter readings / billing period / notes

  const _XlsLineItem({
    required this.typeLabel,
    required this.amount,
    this.detail,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────
class PaymentExcelExporter {
  PaymentExcelExporter._();

  // Vietnamese label maps — kept in one place so they never drift out of sync
  static const Map<String, String> _typeToLabel = {
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

  static const Map<String, PaymentType> _labelToType = {
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

  static String _label(PaymentType t) =>
      _typeToLabel[t.name] ?? t.name;

  // ── Entry point ─────────────────────────────────────────────────────────────

  /// Builds the workbook, prompts a save-file dialog (Windows) and writes the
  /// file. Shows a [CircularProgressIndicator] while working.
  static Future<void> exportPayment({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
    String? tenantEmail,
  }) async {
    // Show spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang xuất Excel…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final bytes = _buildWorkbook(
        payment: payment,
        organization: organization,
        roomNumber: roomNumber,
        buildingName: buildingName,
        tenantEmail: tenantEmail,
      );

      if (context.mounted) Navigator.of(context).pop(); // close spinner

      final suggestedName =
          'hoa_don_${payment.id}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

      if (Platform.isWindows) {
        final location = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
          ],
        );
        if (location == null) return;

        await File(location.path).writeAsBytes(bytes, flush: true);

        // Open containing folder so user can see the file
        await Process.run(
          'explorer',
          ['/select,', location.path],
          runInShell: true,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã lưu: ${p.basename(location.path)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Android / iOS — use share_plus or a downloads folder as needed.
        // Extend here when mobile support is required.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã tạo file Excel thành công'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Workbook builder
  // ─────────────────────────────────────────────────────────────────────────

  static List<int> _buildWorkbook({
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
    String? tenantEmail,
  }) {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Hóa Đơn';
    sheet.showGridlines = false;

    final df = DateFormat('dd/MM/yyyy');
    final nf = NumberFormat('#,###');
    final now = DateTime.now();

    int row = 1;

    // ── Colour palette ──────────────────────────────────────────────────────
    const cPrimary = '#1565C0';   // deep blue  — header bg
    const cPrimaryFg = '#FFFFFF'; // white text on blue
    const cAccent = '#E3F2FD';    // light blue — section headers
    const cAlt = '#F5F5F5';       // light grey — alternate rows
    const cTotal = '#1B5E20';     // dark green — grand total bg
    const cTotalFg = '#FFFFFF';
    const cLateFee = '#B71C1C';   // dark red   — late fee text
    const cTax = '#E65100';       // dark orange — tax text

    // ── Helper closures ─────────────────────────────────────────────────────

    xlsio.Range r(int ro, int co, [int? re, int? ce]) {
      if (re != null && ce != null) {
        return sheet.getRangeByIndex(ro, co, re, ce);
      }
      return sheet.getRangeByIndex(ro, co);
    }

    void mergeSet(int ro, int co, int re, int ce, {
      String? text,
      double? number,
      bool bold = false,
      double fontSize = 10,
      String? bg,
      String? fg,
      xlsio.HAlignType hAlign = xlsio.HAlignType.left,
      bool wrap = false,
    }) {
      final range = sheet.getRangeByIndex(ro, co, re, ce);
      range.merge();
      if (text != null) range.setText(text);
      if (number != null) range.setNumber(number);
      range.cellStyle.bold = bold;
      range.cellStyle.fontSize = fontSize;
      range.cellStyle.hAlign = hAlign;
      range.cellStyle.wrapText = wrap;
      if (bg != null) range.cellStyle.backColor = bg;
      if (fg != null) range.cellStyle.fontColor = fg;
    }

    void sectionHeader(int ro, String text) {
      mergeSet(ro, 1, ro, 7,
          text: text,
          bold: true,
          fontSize: 11,
          bg: cAccent);
    }

    void labelValue(int ro, String label, String value) {
      r(ro, 1).setText(label);
      r(ro, 1).cellStyle.bold = true;
      r(ro, 1).cellStyle.fontSize = 10;
      mergeSet(ro, 2, ro, 7, text: value, fontSize: 10);
    }

    // ── Document header ──────────────────────────────────────────────────────

    // Org name — large centred title
    mergeSet(row, 1, row, 7,
        text: organization.name,
        bold: true,
        fontSize: 16,
        hAlign: xlsio.HAlignType.center);
    row++;

    // Invoice title banner
    mergeSet(row, 1, row, 7,
        text: 'HÓA ĐƠN THANH TOÁN',
        bold: true,
        fontSize: 13,
        bg: cPrimary,
        fg: cPrimaryFg,
        hAlign: xlsio.HAlignType.center);
    row += 2;

    // ── Invoice metadata ─────────────────────────────────────────────────────

    sectionHeader(row, 'THÔNG TIN HÓA ĐƠN');
    row++;

    labelValue(row, 'Mã hóa đơn:', payment.id);
    row++;
    labelValue(row, 'Người thuê:', payment.tenantName ?? 'Chưa xác định');
    row++;

    if (roomNumber != null) {
      labelValue(row, 'Phòng:', roomNumber);
      row++;
    }
    if (buildingName != null) {
      labelValue(row, 'Tòa nhà:', buildingName);
      row++;
    }
    if (tenantEmail != null && tenantEmail.isNotEmpty) {
      labelValue(row, 'Email:', tenantEmail);
      row++;
    }

    labelValue(row, 'Trạng thái:', payment.getStatusDisplayName());
    row++;
    labelValue(row, 'Hạn thanh toán:', df.format(payment.dueDate));
    row++;

    if (payment.paidAt != null) {
      labelValue(row, 'Ngày thanh toán:', df.format(payment.paidAt!));
      row++;
    }

    if (payment.status == PaymentStatus.partial) {
      labelValue(
        row,
        'Đã thanh toán:',
        '${nf.format(payment.paidAmount)} VND',
      );
      row++;
    }

    labelValue(row, 'Ngày xuất:', df.format(now));
    row += 2;

    // ── Line items table ─────────────────────────────────────────────────────

    sectionHeader(row, 'CHI TIẾT CÁC KHOẢN');
    row++;

    // Table column headers
    final headers = ['#', 'Loại khoản', 'Chi tiết / Ghi chú', '', '', 'Số tiền (VND)', ''];
    for (int col = 0; col < headers.length; col++) {
      final cell = r(row, col + 1);
      cell.setText(headers[col]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = cPrimary;
      cell.cellStyle.fontColor = cPrimaryFg;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.fontSize = 10;
    }
    row++;

    final lineItems = _parseLineItems(payment, df, nf);

    for (int i = 0; i < lineItems.length; i++) {
      final item = lineItems[i];
      final bg = (i % 2 == 0) ? cAlt : '#FFFFFF';

      // # column
      r(row, 1).setNumber((i + 1).toDouble());
      r(row, 1).cellStyle.hAlign = xlsio.HAlignType.center;
      r(row, 1).cellStyle.backColor = bg;

      // Type label
      r(row, 2).setText(item.typeLabel);
      r(row, 2).cellStyle.bold = true;
      r(row, 2).cellStyle.backColor = bg;

      // Detail (spans 3 columns)
      mergeSet(row, 3, row, 5,
          text: item.detail ?? '',
          bg: bg,
          wrap: true,
          fontSize: 9);

      // Amount (spans 2 columns)
      mergeSet(row, 6, row, 7,
          number: item.amount,
          bg: bg,
          hAlign: xlsio.HAlignType.right);
      sheet.getRangeByIndex(row, 6, row, 7).numberFormat = '#,##0 "₫"';

      row++;
    }

    row++;

    // ── Totals block ─────────────────────────────────────────────────────────

    void summaryRow(
      int ro,
      String label,
      double amount, {
      bool bold = false,
      double fontSize = 10,
      String? labelColor,
      String? bg,
    }) {
      mergeSet(ro, 1, ro, 5, text: label, bold: bold, fontSize: fontSize, fg: labelColor, bg: bg);
      mergeSet(ro, 6, ro, 7,
          number: amount,
          bold: bold,
          fontSize: fontSize,
          fg: labelColor,
          bg: bg,
          hAlign: xlsio.HAlignType.right);
      sheet.getRangeByIndex(ro, 6, ro, 7).numberFormat = '#,##0 "₫"';
    }

    summaryRow(row, 'Tổng các khoản:', payment.amount);
    row++;

    if (payment.lateFee != null && payment.lateFee! > 0) {
      summaryRow(row, 'Phí trễ hạn:', payment.lateFee!,
          labelColor: cLateFee);
      row++;
    }

    final subTotal = payment.amount + (payment.lateFee ?? 0);
    if ((payment.lateFee ?? 0) > 0) {
      summaryRow(row, 'Cộng:', subTotal, bold: false);
      row++;
    }

    if (payment.taxAmount != null && payment.taxAmount! > 0) {
      summaryRow(row, 'Tiền thuế:', payment.taxAmount!,
          labelColor: cTax);
      row++;
    }

    // Grand total — highlighted green
    summaryRow(
      row,
      'TỔNG THANH TOÁN:',
      payment.totalAmount,
      bold: true,
      fontSize: 13,
      bg: cTotal,
      labelColor: cTotalFg,
    );
    sheet.getRangeByIndex(row, 1, row, 7).cellStyle.fontColor = cTotalFg;
    row += 2;

    // ── Payment status note ─────────────────────────────────────────────────

    if (payment.status == PaymentStatus.partial) {
      final remaining = payment.totalAmount - payment.paidAmount;
      sectionHeader(row, 'TÌNH TRẠNG THANH TOÁN');
      row++;
      labelValue(row, 'Đã thanh toán:', '${nf.format(payment.paidAmount)} VND');
      row++;
      labelValue(row, 'Còn lại:', '${nf.format(remaining)} VND');
      row += 2;
    }

    // ── Notes ────────────────────────────────────────────────────────────────

    if (payment.notes != null && payment.notes!.isNotEmpty) {
      sectionHeader(row, 'GHI CHÚ');
      row++;
      mergeSet(row, 1, row, 7,
          text: payment.notes!,
          wrap: true,
          fontSize: 10);
      row++;
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    row++;
    mergeSet(row, 1, row, 7,
        text:
            'Xuất bởi hệ thống quản lý căn hộ • ${df.format(now)}',
        fontSize: 9,
        fg: '#9E9E9E',
        hAlign: xlsio.HAlignType.center);

    // ── Column widths ────────────────────────────────────────────────────────
    //  Col 1: # (narrow)
    //  Col 2: type label
    //  Col 3-5: detail (wide merged)
    //  Col 6-7: amount (merged)
    sheet.setColumnWidthInPixels(1, 28);
    sheet.setColumnWidthInPixels(2, 120);
    sheet.setColumnWidthInPixels(3, 100);
    sheet.setColumnWidthInPixels(4, 100);
    sheet.setColumnWidthInPixels(5, 100);
    sheet.setColumnWidthInPixels(6, 130);
    sheet.setColumnWidthInPixels(7, 10); // spacer

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parse payment into _XlsLineItem list — mirrors _parseLineItems in
  // view_edit_dialogs.dart but produces detail strings ready for Excel cells.
  // ─────────────────────────────────────────────────────────────────────────

  static List<_XlsLineItem> _parseLineItems(
    Payment payment,
    DateFormat df,
    NumberFormat nf,
  ) {
    // ── Case 1: single electricity with meter readings ──────────────────────
    if (payment.type == PaymentType.electricity &&
        payment.electricityStartReading != null) {
      return [_electricityItem(payment, df, nf)];
    }

    // ── Case 2: single water with meter readings ────────────────────────────
    if (payment.type == PaymentType.water &&
        payment.waterStartReading != null) {
      return [_waterItem(payment, df, nf)];
    }

    // ── Case 3: single rent with billing period ─────────────────────────────
    if (payment.type == PaymentType.rent &&
        payment.billingStartDate != null &&
        payment.billingEndDate != null) {
      return [
        _XlsLineItem(
          typeLabel: 'Tiền thuê',
          amount: payment.amount,
          detail:
              'Kỳ: ${df.format(payment.billingStartDate!)} – ${df.format(payment.billingEndDate!)}',
        )
      ];
    }

    // ── Case 4: multi-line description (combined invoice) ───────────────────
    final description = payment.description;
    if (description != null && description.contains('\n')) {
      final items = <_XlsLineItem>[];
      for (final line in description.split('\n')) {
        final match =
            RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$')
                .firstMatch(line.trim());
        if (match != null) {
          final typeLabel = match.group(1)?.trim() ?? '';
          final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
          final note = match.group(3);
          items.add(_XlsLineItem(
            typeLabel: typeLabel,
            amount: double.tryParse(amountStr) ?? 0,
            detail: note,
          ));
        }
      }
      if (items.isNotEmpty) return items;
    }

    // ── Case 5: fallback single item ────────────────────────────────────────
    return [
      _XlsLineItem(
        typeLabel: _label(payment.type),
        amount: payment.amount,
        detail: description,
      )
    ];
  }

  static _XlsLineItem _electricityItem(
      Payment p, DateFormat df, NumberFormat nf) {
    final start = p.electricityStartReading ?? 0;
    final end = p.electricityEndReading ?? 0;
    final usage = end - start;
    final buf = StringBuffer();
    buf.write('Chỉ số: $start → $end kWh (${usage.toStringAsFixed(1)} kWh)');
    if (p.electricityPricePerUnit != null) {
      buf.write(' × ${nf.format(p.electricityPricePerUnit)} đ/kWh');
    }
    if (p.electricityStartDate != null && p.electricityEndDate != null) {
      buf.write(
          '\nKỳ: ${df.format(p.electricityStartDate!)} – ${df.format(p.electricityEndDate!)}');
    }
    return _XlsLineItem(
        typeLabel: 'Tiền điện', amount: p.amount, detail: buf.toString());
  }

  static _XlsLineItem _waterItem(
      Payment p, DateFormat df, NumberFormat nf) {
    final start = p.waterStartReading ?? 0;
    final end = p.waterEndReading ?? 0;
    final usage = end - start;
    final buf = StringBuffer();
    buf.write('Chỉ số: $start → $end m³ (${usage.toStringAsFixed(1)} m³)');
    if (p.waterPricePerUnit != null) {
      buf.write(' × ${nf.format(p.waterPricePerUnit)} đ/m³');
    }
    if (p.waterStartDate != null && p.waterEndDate != null) {
      buf.write(
          '\nKỳ: ${df.format(p.waterStartDate!)} – ${df.format(p.waterEndDate!)}');
    }
    return _XlsLineItem(
        typeLabel: 'Tiền nước', amount: p.amount, detail: buf.toString());
  }
}