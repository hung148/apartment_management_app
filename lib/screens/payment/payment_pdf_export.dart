import 'dart:io';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// Payment PDF Exporter - Fully Integrated with Tenant Model
/// Creates Wyndham-style professional receipts with complete tenant integration
class PaymentPDFExporter {
  // ========================================
  // FONT LOADING
  // ========================================
  static Future<pw.Font> _loadVietnameseFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      print('Error loading Vietnamese font: $e');
      throw Exception('Vietnamese font not found. Please add Roboto-Regular.ttf to assets/fonts/');
    }
  }

  static Future<pw.Font> _loadVietneseBoldFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      return _loadVietnameseFont();
    }
  }

  // ========================================
  // FORMATTING HELPERS
  // ========================================
  
  static String formatCurrency(double amount) {
    return NumberFormat('#,###', 'vi_VN').format(amount);
  }

  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatDateTime(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  }

  static int calculateDaysBetween(DateTime start, DateTime end) {
    return end.difference(start).inDays + 1;
  }

  static int calculateMonthsBetween(DateTime start, DateTime end) {
    int months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day >= start.day) months++;
    return months.abs();
  }

  static String getPaymentTypeLabel(PaymentType type) {
    const labels = {
      'rent': 'PHÍ QUẢN LÝ',
      'electricity': 'PHÍ ĐIỆN SINH HOẠT',
      'water': 'PHÍ NƯỚC SINH HOẠT',
      'internet': 'PHÍ INTERNET',
      'parking': 'PHÍ GỬI XE',
      'maintenance': 'PHÍ BẢO TRÌ',
      'deposit': 'TIỀN CỌC',
      'penalty': 'TIỀN PHẠT',
      'other': 'KHÁC',
    };
    return labels[type.name] ?? type.name.toUpperCase();
  }

  // ========================================
  // MAIN PDF GENERATION WITH TENANT INTEGRATION
  // ========================================
  
  static Future<pw.Document> generateOwnerFeeReceipt({
    required Payment payment,
    required Organization organization,
    Tenant? tenant, // Direct tenant integration
    String? roomNumber,
    String? buildingName,
    
    // Optional overrides (if not using tenant/payment data)
    String? apartmentTypeOverride,
    double? areaOverride,
    String? tenantNameOverride,
    DateTime? handoverDateOverride,
    
    // Optional fee overrides (use payment fields if available)
    double? internetFeeOverride,
    double? cableTVFeeOverride,
    double? hotWaterFeeOverride,
    double? hotWaterPercentOverride,
    
    // Additional info
    String? email,
    String? remark,
  }) async {
    final pdf = pw.Document();
    
    try {
      final regularFont = await _loadVietnameseFont();
      final boldFont = await _loadVietneseBoldFont();

      // Extract data from tenant or use overrides
      final tenantName = tenant?.fullName ?? tenantNameOverride ?? 'N/A';
      final handoverDate = tenant?.moveInDate ?? handoverDateOverride;
      final contactEmail = tenant?.email ?? email ?? organization.email;
      final apartmentType = tenant?.apartmentType ?? apartmentTypeOverride;
      final area = tenant?.apartmentArea ?? areaOverride;
      
      // Calculate billing period details
      final billingStart = payment.billingStartDate;
      final billingEnd = payment.billingEndDate;
      final daysUsed = (billingStart != null && billingEnd != null) 
          ? calculateDaysBetween(billingStart, billingEnd) 
          : 0;
      final monthsUsed = (billingStart != null && billingEnd != null)
          ? calculateMonthsBetween(billingStart, billingEnd)
          : 0;

      // Determine fees - use payment fields first, then overrides
      double managementFee = 0;
      double electricityFee = 0;
      double waterFee = 0;
      double actualInternetFee = payment.internetFee ?? internetFeeOverride ?? 0;
      double actualCableTVFee = payment.cableTVFee ?? cableTVFeeOverride ?? 0;
      double actualHotWaterFee = payment.hotWaterFee ?? hotWaterFeeOverride ?? 0;
      double actualHotWaterPercent = payment.hotWaterPercent ?? hotWaterPercentOverride ?? 0;

      switch (payment.type) {
        case PaymentType.rent:
          managementFee = payment.amount;
          break;
        case PaymentType.electricity:
          electricityFee = payment.amount;
          break;
        case PaymentType.water:
          waterFee = payment.amount;
          break;
        case PaymentType.internet:
          actualInternetFee = payment.amount;
          break;
        case PaymentType.parking:
          actualCableTVFee = payment.amount;
          break;
        default:
          managementFee = payment.amount;
      }

      // Calculate subtotal and tax
      final subtotal = managementFee + electricityFee + waterFee + 
                      actualInternetFee + actualCableTVFee + actualHotWaterFee;
      // Use tax from payment model if available, otherwise calculate 10% of subtotal
      final taxAmount = payment.taxAmount ?? (subtotal * 0.10);
      final grandTotal = subtotal + taxAmount;

      // Billing period text
      final billingPeriod = billingStart != null && billingEnd != null
          ? '${formatDate(billingStart)} đến ${formatDate(billingEnd)} / From ${formatDate(billingStart)} to ${formatDate(billingEnd)}'
          : '';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ========================================
                // HEADER
                // ========================================
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          organization.name.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            font: boldFont,
                            color: PdfColors.blue900,
                          ),
                        ),
                        if (buildingName != null) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            buildingName,
                            style: pw.TextStyle(
                              fontSize: 11,
                              font: regularFont,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 20),
                
                // ========================================
                // TITLE
                // ========================================
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'THU PHÍ CHỦ CĂN HỘ / APARTMENT OWNER FEE RECEIPT ${roomNumber ?? ''}',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      if (billingPeriod.isNotEmpty)
                        pw.Text(
                          '($billingPeriod)',
                          style: pw.TextStyle(
                            fontSize: 9,
                            font: regularFont,
                            fontStyle: pw.FontStyle.italic,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Đơn vị tính/Currency unit: VND',
                        style: pw.TextStyle(
                          fontSize: 8,
                          font: regularFont,
                          fontStyle: pw.FontStyle.italic,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                pw.SizedBox(height: 20),
                
                // ========================================
                // BASIC INFORMATION TABLE
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('MÃ CĂN / APARTMENT CODE', roomNumber ?? 'N/A', regularFont, boldFont),
                    _buildInfoRow('LOẠI CĂN HỘ / APARTMENT TYPE', apartmentType ?? 'N/A', regularFont, boldFont),
                    _buildInfoRow('HỌ VÀ TÊN CHỦ CĂN HỘ / OWNER\'S FULL NAME', tenantName, regularFont, boldFont),
                    _buildInfoRow('NGÀY BÀN GIAO ĐƯA VÀO SỬ DỤNG / HANDOVER DATE', 
                        handoverDate != null ? formatDate(handoverDate) : 'N/A', regularFont, boldFont),
                    _buildInfoRow('ĐẾN NGÀY / UNTIL DATE', 
                        billingEnd != null ? formatDate(billingEnd) : 'N/A', regularFont, boldFont),
                    _buildInfoRow('SỐ NGÀY SỬ DỤNG / NUMBER OF DAYS USED', daysUsed.toString(), regularFont, boldFont),
                    _buildInfoRow('SỐ THÁNG SỬ DỤNG / NUMBER OF MONTHS USED', monthsUsed.toString(), regularFont, boldFont),
                    _buildInfoRow('PHÍ QUẢN LÝ / MANAGEMENT FEE', formatCurrency(managementFee), regularFont, boldFont),
                    _buildInfoRow('Diện tích / Area', area != null ? area.toStringAsFixed(2) : '0.00', regularFont, boldFont),
                    _buildInfoRow('Đơn giá / Unit price', 
                        area != null && area > 0 && monthsUsed > 0
                            ? formatCurrency(managementFee / area / monthsUsed)
                            : '0', regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ========================================
                // ELECTRICITY SECTION
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('PHÍ ĐIỆN SINH HOẠT / ELECTRICITY FEE', formatCurrency(electricityFee), regularFont, boldFont),
                    _buildInfoRow('KWH sử dụng / KWH used', 
                        payment.electricityUsage?.toStringAsFixed(2) ?? '0.00', regularFont, boldFont),
                    _buildInfoRow('Đơn giá / Unit price', 
                        payment.electricityPricePerUnit != null 
                            ? formatCurrency(payment.electricityPricePerUnit!)
                            : '0', regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ========================================
                // WATER SECTION
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('PHÍ NƯỚC SINH HOẠT / WATER FEE', formatCurrency(waterFee), regularFont, boldFont),
                    _buildInfoRow('Số sử dụng / Consumption', 
                        payment.waterUsage?.toStringAsFixed(2) ?? '0.00', regularFont, boldFont),
                    _buildInfoRow('Đơn giá / Unit price', 
                        payment.waterPricePerUnit != null 
                            ? formatCurrency(payment.waterPricePerUnit!)
                            : '0', regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ========================================
                // OTHER FEES
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('PHÍ INTERNET (300.000/1 THÁNG) / INTERNET FEE (VND 300,000 PER MONTH)', 
                        formatCurrency(actualInternetFee), regularFont, boldFont),
                    _buildInfoRow('PHÍ TRUYỀN HÌNH CẤP (100.000/1 TIVI) / CABLE TV FEE (VND 100,000 PER TV)', 
                        formatCurrency(actualCableTVFee), regularFont, boldFont),
                    _buildInfoRow('PHÍ NƯỚC NÓNG (% TÍNH PHÍ: ${actualHotWaterPercent.toStringAsFixed(2)}%) / HOT WATER FEE (% CHARGE APPLIED: ${actualHotWaterPercent.toStringAsFixed(2)}%)', 
                        formatCurrency(actualHotWaterFee), regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ========================================
                // TOTALS
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildTotalRow('TỔNG CỘNG / SUBTOTAL', formatCurrency(subtotal), regularFont, boldFont, false),
                    _buildTotalRow('TIỀN THUẾ / TAX AMOUNT', formatCurrency(taxAmount), regularFont, boldFont, false),
                    _buildTotalRow('TỔNG THANH TOÁN / TOTAL PAYMENT', formatCurrency(grandTotal), regularFont, boldFont, true),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ========================================
                // CONTACT INFO
                // ========================================
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('Email', contactEmail ?? '', regularFont, boldFont, isLink: true),
                    _buildInfoRow('GHI CHÚ/ REMARK', remark ?? payment.notes ?? '', regularFont, boldFont, isMultiline: true),
                  ],
                ),
                
                pw.Spacer(),
                
                // ========================================
                // BANK TRANSFER INFORMATION
                // ========================================
                if (organization.hasBankInfo)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'THÔNG TIN CHUYỂN KHOẢN / TRANSFER INFORMATION',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            font: boldFont,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        _buildBankInfoRow('● Account Name: ', organization.bankAccountName ?? 'N/A', regularFont, boldFont),
                        _buildBankInfoRow('● Account Number: ', organization.bankAccountNumber ?? 'N/A', regularFont, boldFont),
                        _buildBankInfoRow('● Bank Name: ', organization.bankName ?? 'N/A', regularFont, boldFont),
                      ],
                    ),
                  ),
                
                pw.SizedBox(height: 15),
                
                // ========================================
                // FOOTER
                // ========================================
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Generated: ${formatDateTime(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 8, font: regularFont, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Receipt ID: ${payment.id.substring(0, min(8, payment.id.length)).toUpperCase()}',
                      style: pw.TextStyle(fontSize: 8, font: regularFont, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      return pdf;
    } catch (e) {
      print('Error generating PDF: $e');
      rethrow;
    }
  }

  // ========================================
  // HELPER METHODS FOR TABLE ROWS
  // ========================================
  
  static pw.TableRow _buildInfoRow(
    String label, 
    String value, 
    pw.Font regularFont, 
    pw.Font boldFont, {
    bool isLink = false,
    bool isMultiline = false,
  }) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, font: regularFont),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9, 
              font: boldFont,
              color: isLink ? PdfColors.blue700 : PdfColors.black,
              decoration: isLink ? pw.TextDecoration.underline : null,
            ),
            textAlign: pw.TextAlign.right,
            maxLines: isMultiline ? 3 : 1,
          ),
        ),
      ],
    );
  }
  
  static pw.TableRow _buildTotalRow(
    String label, 
    String value, 
    pw.Font regularFont, 
    pw.Font boldFont,
    bool isGrandTotal,
  ) {
    return pw.TableRow(
      decoration: isGrandTotal 
          ? const pw.BoxDecoration(color: PdfColors.blue50)
          : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isGrandTotal ? 11 : 10, 
              font: boldFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: isGrandTotal ? 12 : 10, 
              font: boldFont,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }
  
  static pw.Widget _buildBankInfoRow(
    String label, 
    String value, 
    pw.Font regularFont, 
    pw.Font boldFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, font: regularFont),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 9, font: boldFont),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // PDF PREVIEW AND SAVE
  // ========================================
  
  /// Show PDF preview with tenant integration
  static Future<void> showPDFPreview({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    Tenant? tenant,
    String? roomNumber,
    String? buildingName,
    String? apartmentTypeOverride,
    double? areaOverride,
    double? internetFeeOverride,
    double? cableTVFeeOverride,
    double? hotWaterFeeOverride,
    double? hotWaterPercentOverride,
    String? email,
    String? remark,
  }) async {
    try {
      final pdf = await generateOwnerFeeReceipt(
        payment: payment,
        organization: organization,
        tenant: tenant,
        roomNumber: roomNumber,
        buildingName: buildingName,
        apartmentTypeOverride: apartmentTypeOverride,
        areaOverride: areaOverride,
        internetFeeOverride: internetFeeOverride,
        cableTVFeeOverride: cableTVFeeOverride,
        hotWaterFeeOverride: hotWaterFeeOverride,
        hotWaterPercentOverride: hotWaterPercentOverride,
        email: email,
        remark: remark,
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

  /// Save PDF to file
  static Future<void> _savePDF(
    BuildContext context,
    pw.Document pdf,
    Payment payment,
  ) async {
    try {
      final fileName = 'receipt_${payment.id.substring(0, min(8, payment.id.length))}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'PDF',
              extensions: ['pdf'],
            ),
          ],
        );

        if (saveLocation == null) return;

        final bytes = await pdf.save();
        final file = XFile.fromData(
          bytes,
          name: p.basename(saveLocation.path),
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

  /// Quick export without preview
  static Future<void> quickExportPDF({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    Tenant? tenant,
    String? roomNumber,
    String? buildingName,
    String? apartmentTypeOverride,
    double? areaOverride,
    double? internetFeeOverride,
    double? cableTVFeeOverride,
    double? hotWaterFeeOverride,
    double? hotWaterPercentOverride,
    String? email,
    String? remark,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final pdf = await generateOwnerFeeReceipt(
        payment: payment,
        organization: organization,
        tenant: tenant,
        roomNumber: roomNumber,
        buildingName: buildingName,
        apartmentTypeOverride: apartmentTypeOverride,
        areaOverride: areaOverride,
        internetFeeOverride: internetFeeOverride,
        cableTVFeeOverride: cableTVFeeOverride,
        hotWaterFeeOverride: hotWaterFeeOverride,
        hotWaterPercentOverride: hotWaterPercentOverride,
        email: email,
        remark: remark,
      );

      if (context.mounted) {
        Navigator.pop(context);
      }

      await _savePDF(context, pdf, payment);
    } catch (e) {
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

// Helper function for min
int min(int a, int b) => a < b ? a : b;