import 'dart:io';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

// Helper class for invoice line items
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;

  InvoiceLineItem({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
  });
}

// Parse line items from payment description
List<InvoiceLineItem> _parseLineItemsForPDF(Payment payment) {
  final description = payment.description;
  if (description == null || description.isEmpty) {
    return [
      InvoiceLineItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: payment.type,
        amount: payment.amount,
        description: null,
      ),
    ];
  }

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
  
  if (items.isEmpty) {
    return [
      InvoiceLineItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: payment.type,
        amount: payment.amount,
        description: description,
      ),
    ];
  }
  
  return items;
}

// Get payment type label in Vietnamese
String _getPaymentTypeLabel(PaymentType type) {
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
  return labels[type.toString().split('.')[1]] ?? type.toString();
}

// Get payment status label in Vietnamese
String _getPaymentStatusLabel(PaymentStatus status) {
  const labels = {
    'pending': 'Chờ thanh toán',
    'paid': 'Đã thanh toán',
    'overdue': 'Quá hạn',
    'cancelled': 'Đã hủy',
    'refunded': 'Đã hoàn tiền',
    'partial': 'Thanh toán 1 phần',
  };
  return labels[status.toString().split('.')[1]] ?? status.toString();
}

// PDF Export Service
class PaymentPDFExporter {
  static Future<pw.Font> _loadVietnameseFont() async {
    try {
      // Try to load a font that supports Vietnamese characters
      // You may need to add a .ttf font file to your assets
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      // Fallback to default font if custom font not available
      return pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    }
  }

  // Generate PDF for a single payment
  static Future<pw.Document> generatePaymentPDF({
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
  }) async {
    final pdf = pw.Document();
    final lineItems = _parseLineItemsForPDF(payment);
    
    // Try to load Vietnamese font, fallback to default if not available
    pw.Font? vietnameseFont;
    try {
      vietnameseFont = await _loadVietnameseFont();
    } catch (e) {
      // Will use default font
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        organization.name,
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          font: vietnameseFont,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      if (organization.address != null && organization.address!.isNotEmpty)
                        pw.Text(
                          organization.address!,
                          style: pw.TextStyle(fontSize: 10, font: vietnameseFont),
                        ),
                      if (organization.phone != null && organization.phone!.isNotEmpty)
                        pw.Text(
                          'Tel: ${organization.phone!}',
                          style: pw.TextStyle(fontSize: 10, font: vietnameseFont),
                        ),
                      if (organization.email != null && organization.email!.isNotEmpty)
                        pw.Text(
                          'Email: ${organization.email!}',
                          style: pw.TextStyle(fontSize: 9, font: vietnameseFont),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'HÓA ĐƠN',
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          font: vietnameseFont,
                        ),
                      ),
                      pw.Text(
                        'Invoice #${payment.id.substring(0, 8)}',
                        style: pw.TextStyle(fontSize: 10, font: vietnameseFont),
                      ),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 30),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),
              
              // Payment Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'THÔNG TIN KHÁCH HÀNG',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          font: vietnameseFont,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Người thuê: ${payment.tenantName ?? "Chưa xác định"}',
                        style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                      ),
                      if (buildingName != null)
                        pw.Text(
                          'Tòa nhà: $buildingName',
                          style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                        ),
                      if (roomNumber != null)
                        pw.Text(
                          'Phòng: $roomNumber',
                          style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'THÔNG TIN HÓA ĐƠN',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          font: vietnameseFont,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Ngày tạo: ${DateFormat('dd/MM/yyyy').format(payment.createdAt)}',
                        style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                      ),
                      pw.Text(
                        'Hạn thanh toán: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}',
                        style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                      ),
                      pw.Text(
                        'Trạng thái: ${_getPaymentStatusLabel(payment.status)}',
                        style: pw.TextStyle(fontSize: 11, font: vietnameseFont),
                      ),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 30),
              
              // Line Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  // Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'SỐ THỨ TỰ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: vietnameseFont,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'KHOẢN MỤC',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: vietnameseFont,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'MÔ TẢ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: vietnameseFont,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'SỐ TIỀN',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: vietnameseFont,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  // Line Item Rows
                  ...List.generate(lineItems.length, (index) {
                    final item = lineItems[index];
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            '${index + 1}',
                            style: pw.TextStyle(font: vietnameseFont),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            _getPaymentTypeLabel(item.type),
                            style: pw.TextStyle(font: vietnameseFont),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            item.description ?? '-',
                            style: pw.TextStyle(fontSize: 9, font: vietnameseFont),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            '${NumberFormat('#,###').format(item.amount)} d',
                            style: pw.TextStyle(font: vietnameseFont),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    );
                  }),
                  // Total Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(''),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'TỔNG CỘNG',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: vietnameseFont,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(''),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '${NumberFormat('#,###').format(payment.amount)} VND',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                            font: vietnameseFont,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 30),
              
              // Notes
              if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                pw.Text(
                  'GHI CHÚ',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    font: vietnameseFont,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    payment.notes!,
                    style: pw.TextStyle(fontSize: 10, font: vietnameseFont),
                  ),
                ),
                pw.SizedBox(height: 20),
              ],
              
              pw.Spacer(),
              
              // Footer
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Cảm ơn quý khách!',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      font: vietnameseFont,
                    ),
                  ),
                  pw.Text(
                    'In lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 8, font: vietnameseFont),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Show PDF preview and allow save/print
  static Future<void> showPDFPreview({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
  }) async {
    try {
      final pdf = await generatePaymentPDF(
        payment: payment,
        organization: organization,
        roomNumber: roomNumber,
        buildingName: buildingName,
      );

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text('Xem Trước Hóa Đơn'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Tải xuống PDF',
                    onPressed: () => _savePDF(context, pdf, payment),
                  ),
                ],
              ),
              body: PdfPreview(
                build: (format) => pdf.save(),
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tạo PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save PDF to file
  static Future<void> _savePDF(
    BuildContext context,
    pw.Document pdf,
    Payment payment,
  ) async {
    try {
      final fileName = 'hoa_don_${payment.id.substring(0, 8)}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      
      // For desktop platforms
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // ── Modern / recommended way ────────────────────────────────
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'PDF',
              extensions: ['pdf'],
            ),
          ],
        );

        if (saveLocation == null) {
          // User cancelled
          return;
        }

        final bytes = await pdf.save();
        final file = XFile.fromData(
          bytes,
          name: p.basename(saveLocation.path),  // or just fileName
          mimeType: 'application/pdf',
        );

        await file.saveTo(saveLocation.path);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã lưu PDF: ${p.basename(saveLocation.path)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Mobile: share (unchanged)
        final bytes = await pdf.save();
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lưu PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Quick export without preview
  static Future<void> quickExportPDF({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
  }) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final pdf = await generatePaymentPDF(
        payment: payment,
        organization: organization,
        roomNumber: roomNumber,
        buildingName: buildingName,
      );

      // Close loading
      if (context.mounted) {
        Navigator.pop(context);
      }

      await _savePDF(context, pdf, payment);
    } catch (e) {
      // Close loading if still open
      if (context.mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
