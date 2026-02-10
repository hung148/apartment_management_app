import 'dart:io';
import 'dart:math';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart'; // Import Room Model
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

class PaymentPDFExporter {
  // ========================================
  // FONT LOADING
  // ========================================
  static Future<pw.Font> _loadVietnameseFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
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

  static String formatCurrency(double amount) => NumberFormat('#,###', 'vi_VN').format(amount);
  static String formatDate(DateTime? date) => date != null ? DateFormat('dd/MM/yyyy').format(date) : 'N/A';
  static String formatDateTime(DateTime dateTime) => DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  static int calculateDaysBetween(DateTime start, DateTime end) => end.difference(start).inDays + 1;
  
  static int calculateMonthsBetween(DateTime start, DateTime end) {
    int months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day >= start.day) months++;
    return max(1, months.abs()); // Tối thiểu là 1 tháng để tính đơn giá
  }

  // ========================================
  // MAIN PDF GENERATION
  // ========================================
  
  static Future<pw.Document> generateOwnerFeeReceipt({
    required Payment payment,
    required Organization organization,
    Tenant? tenant, 
    Room? room, // NEW: Thêm Room để lấy Type và Area
    String? roomNumber,
    String? buildingName,
    String? apartmentTypeOverride,
    double? areaOverride,
    String? tenantNameOverride,
    DateTime? handoverDateOverride,
    double? internetFeeOverride,
    double? cableTVFeeOverride,
    double? hotWaterFeeOverride,
    double? hotWaterPercentOverride,
    String? email,
    String? remark,
  }) async {
    final pdf = pw.Document();
    
    try {
      final regularFont = await _loadVietnameseFont();
      final boldFont = await _loadVietneseBoldFont();

      // --- LOGIC TRÍCH XUẤT DỮ LIỆU ---

      // 1. Tên khách thuê
      String tenantName = 'N/A';
      if (tenant?.fullName.isNotEmpty ?? false) {
        tenantName = tenant!.fullName;
      } else if (tenantNameOverride?.isNotEmpty ?? false) {
        tenantName = tenantNameOverride!;
      } else {
        tenantName = payment.tenantName!;
      }

      // 2. Loại căn hộ (Override > Tenant > Room)
      String apartmentType = apartmentTypeOverride ?? 
                             tenant?.apartmentType ?? 
                             room?.roomType ?? 
                             'Tiêu chuẩn';

      // 3. Diện tích (Override > Tenant > Room)
      double area = areaOverride ?? 
                    tenant?.apartmentArea ?? 
                    (room?.area.toDouble() ?? 0.0);

      // 5. Email liên hệ
      String contactEmail = email ?? tenant?.email ?? organization.email ?? '';

      // 6. Xử lý ngày tháng hóa đơn
      DateTime? billingEnd = payment.billingEndDate ?? payment.electricityEndDate ?? payment.waterEndDate ?? payment.dueDate;
      DateTime? billingStart = payment.billingStartDate ?? payment.electricityStartDate ?? payment.waterStartDate;
      
      // 4. Ngày bàn giao
      // Thứ tự ưu tiên: Ghi đè > Ngày dời vào của khách > Ngày bắt đầu hóa đơn > Ngày tạo hóa đơn
      DateTime? handoverDate = handoverDateOverride ?? 
                               tenant?.moveInDate ?? 
                               billingStart ?? 
                               payment.createdAt;

      final daysUsed = calculateDaysBetween(handoverDate, billingEnd); 
      final monthsUsed = calculateMonthsBetween(handoverDate, billingEnd);

      // --- TÍNH TOÁN CHI PHÍ ---
      double managementFee = 0;
      double electricityFee = 0;
      double waterFee = 0;
      double actualInternetFee = payment.internetFee ?? internetFeeOverride ?? 0;
      double actualCableTVFee = payment.cableTVFee ?? cableTVFeeOverride ?? 0;
      double actualHotWaterFee = payment.hotWaterFee ?? hotWaterFeeOverride ?? 0;
      double actualHotWaterPercent = payment.hotWaterPercent ?? hotWaterPercentOverride ?? 0;

      // Phân bổ phí dựa trên loại payment chính
      switch (payment.type) {
        case PaymentType.rent: managementFee = payment.amount; break;
        case PaymentType.electricity: electricityFee = payment.amount; break;
        case PaymentType.water: waterFee = payment.amount; break;
        case PaymentType.internet: actualInternetFee = payment.amount; break;
        case PaymentType.parking: actualCableTVFee = payment.amount; break;
        default: managementFee = payment.amount;
      }

      final subtotal = managementFee + electricityFee + waterFee + actualInternetFee + actualCableTVFee + actualHotWaterFee;
      final taxAmount = payment.taxAmount ?? (subtotal * 0.10);
      final grandTotal = subtotal + taxAmount;

      final billingPeriodStr = '${formatDate(handoverDate)} - ${formatDate(billingEnd)}';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // HEADER
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          organization.name.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 14, 
                            fontWeight: pw.FontWeight.bold, 
                            font: boldFont, 
                            color: PdfColors.blue900
                          )
                        ),
                        // ADDED: Tax Code in header
                        if (organization.taxCode != null && organization.taxCode!.isNotEmpty)
                          pw.SizedBox(height: 4),
                        if (organization.taxCode != null && organization.taxCode!.isNotEmpty)
                          pw.Text(
                            'Mã số thuế / Tax Code: ${organization.taxCode}',
                            style: pw.TextStyle(
                              fontSize: 9, 
                              font: regularFont,
                              color: PdfColors.grey800
                            )
                          ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                
                // TITLE
                pw.Center(
                  child: pw.Column(children: [
                    pw.Text('THU PHÍ CHỦ CĂN HỘ / APARTMENT OWNER FEE RECEIPT ${roomNumber ?? room?.roomNumber ?? ""}',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, font: boldFont)),
                    if (billingPeriodStr.isNotEmpty)
                      pw.Text('($billingPeriodStr)', style: pw.TextStyle(fontSize: 9, font: regularFont, fontStyle: pw.FontStyle.italic)),
                    pw.Text('Đơn vị tính/Currency: VND', style: pw.TextStyle(fontSize: 8, font: regularFont)),
                  ]),
                ),
                pw.SizedBox(height: 20),
                
                // THÔNG TIN CƠ BẢN
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow('MÃ CĂN / APARTMENT CODE', roomNumber ?? room?.roomNumber ?? 'N/A', regularFont, boldFont),
                    _buildInfoRow('LOẠI CĂN HỘ / APARTMENT TYPE', apartmentType, regularFont, boldFont),
                    _buildInfoRow('HỌ VÀ TÊN / FULL NAME', tenantName, regularFont, boldFont),
                    _buildInfoRow('NGÀY BÀN GIAO / HANDOVER DATE', formatDate(handoverDate), regularFont, boldFont),
                    _buildInfoRow('ĐẾN NGÀY / UNTIL DATE', formatDate(billingEnd), regularFont, boldFont),
                    _buildInfoRow('SỐ NGÀY SỬ DỤNG / DAYS USED', '$daysUsed ngày', regularFont, boldFont),
                    _buildInfoRow('SỐ THÁNG / MONTHS USED', monthsUsed.toString(), regularFont, boldFont),
                    _buildInfoRow('PHÍ QUẢN LÝ / MANAGEMENT FEE', formatCurrency(managementFee), regularFont, boldFont),
                    _buildInfoRow('DIỆN TÍCH / AREA', '${area.toStringAsFixed(2)} m²', regularFont, boldFont),
                    _buildInfoRow('ĐƠN GIÁ / UNIT PRICE', (area > 0 && monthsUsed > 0) ? formatCurrency(managementFee / area / monthsUsed) : '0', regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                // ĐIỆN & NƯỚC
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow('PHÍ ĐIỆN / ELECTRICITY', formatCurrency(electricityFee), regularFont, boldFont),
                    _buildInfoRow('Số sử dụng / Usage', '${payment.electricityUsage?.toStringAsFixed(1) ?? "0"} kWh', regularFont, boldFont),
                    _buildInfoRow('PHÍ NƯỚC / WATER', formatCurrency(waterFee), regularFont, boldFont),
                    _buildInfoRow('Số sử dụng / Usage', '${payment.waterUsage?.toStringAsFixed(1) ?? "0"} m³', regularFont, boldFont),
                  ],
                ),

                pw.SizedBox(height: 10),

                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('PHÍ INTERNET / INTERNET FEE', formatCurrency(actualInternetFee), regularFont, boldFont),
                    _buildInfoRow('PHÍ TRUYỀN HÌNH CÁP / CABLE TV FEE', formatCurrency(actualCableTVFee), regularFont, boldFont),
                    
                    // SỬ DỤNG BIẾN actualHotWaterPercent Ở ĐÂY:
                    _buildInfoRow(
                      'PHÍ NƯỚC NÓNG (${actualHotWaterPercent.toStringAsFixed(0)}%) / HOT WATER FEE (${actualHotWaterPercent.toStringAsFixed(0)}%)', 
                      formatCurrency(actualHotWaterFee), 
                      regularFont, 
                      boldFont
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                
                // TỔNG CỘNG
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildTotalRow('TỔNG CHƯA THUẾ / SUBTOTAL', formatCurrency(subtotal), regularFont, boldFont, false),
                    _buildTotalRow('THUẾ (10%) / VAT', formatCurrency(taxAmount), regularFont, boldFont, false),
                    _buildTotalRow('TỔNG THANH TOÁN / TOTAL PAYMENT', formatCurrency(grandTotal), regularFont, boldFont, true),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildInfoRow('Email', contactEmail, regularFont, boldFont, isLink: true),
                    _buildInfoRow('GHI CHÚ/ REMARK', remark ?? payment.notes ?? '', regularFont, boldFont, isMultiline: true),
                  ],
                ),
                pw.Spacer(),
                
                // BANK INFO
                if (organization.hasBankInfo)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5), color: PdfColors.grey100),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('THÔNG TIN CHUYỂN KHOẢN / TRANSFER INFO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: boldFont)),
                        pw.SizedBox(height: 4),
                        _buildBankInfoRow('Chủ TK: ', organization.bankAccountName ?? '', regularFont, boldFont),
                        _buildBankInfoRow('Số TK: ', organization.bankAccountNumber ?? '', regularFont, boldFont),
                        _buildBankInfoRow('Ngân hàng: ', organization.bankName ?? '', regularFont, boldFont),
                      ],
                    ),
                  ),
                
                pw.SizedBox(height: 10),
                pw.Divider(color: PdfColors.grey400),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Generated: ${formatDateTime(DateTime.now())}', style: pw.TextStyle(fontSize: 7, font: regularFont)),
                    pw.Text('Receipt ID: ${payment.id.substring(0, min(8, payment.id.length)).toUpperCase()}', style: pw.TextStyle(fontSize: 7, font: regularFont)),
                  ],
                ),
              ],
            );
          },
        ),
      );

      return pdf;
    } catch (e) {
      rethrow;
    }
  }

  // --- HELPER ROWS ---
  static pw.TableRow _buildInfoRow(String label, String value, pw.Font reg, pw.Font bold, {bool isLink = false, bool isMultiline = false}) {
    return pw.TableRow(children: [
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(label, style: pw.TextStyle(fontSize: 8, font: reg))),
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, font: bold, color: isLink ? PdfColors.blue700 : PdfColors.black, decoration: isLink ? pw.TextDecoration.underline : null))),
    ]);
  }
  
  static pw.TableRow _buildTotalRow(String label, String value, pw.Font reg, pw.Font bold, bool isGrand) {
    return pw.TableRow(
      decoration: isGrand ? const pw.BoxDecoration(color: PdfColors.blue50) : null,
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label, style: pw.TextStyle(fontSize: isGrand ? 10 : 9, font: bold))),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: isGrand ? 10 : 9, font: bold))),
      ],
    );
  }

  static pw.Widget _buildBankInfoRow(String label, String value, pw.Font reg, pw.Font bold) {
    return pw.Row(children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 8, font: reg)),
      pw.Text(value, style: pw.TextStyle(fontSize: 8, font: bold)),
    ]);
  }

  // ========================================
  // WRAPPERS (PREVIEW & EXPORT)
  // ========================================
  
  static Future<void> showPDFPreview({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    Tenant? tenant,
    Room? room, // NEW
    String? roomNumber,
    String? buildingName,
    String? apartmentTypeOverride,
    double? areaOverride,
    String? email,
    String? remark,
  }) async {
    try {
      final pdf = await generateOwnerFeeReceipt(
        payment: payment,
        organization: organization,
        tenant: tenant,
        room: room, // Pass room
        roomNumber: roomNumber,
        buildingName: buildingName,
        apartmentTypeOverride: apartmentTypeOverride,
        areaOverride: areaOverride,
        email: email,
        remark: remark,
      );

      if (context.mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Xem Trước Hóa Đơn')),
            body: PdfPreview(build: (format) => pdf.save(), allowPrinting: true, allowSharing: true),
          ),
        ));
      }
    } catch (e) {
      print('PDF Error: $e');
    }
  }

  static Future<void> quickExportPDF({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    Tenant? tenant,
    Room? room, // NEW
    String? roomNumber,
    String? buildingName,
    double? areaOverride,
    String? remark,
  }) async {
    try {
      final pdf = await generateOwnerFeeReceipt(
        payment: payment,
        organization: organization,
        tenant: tenant,
        room: room, // Pass room
        roomNumber: roomNumber,
        buildingName: buildingName,
        areaOverride: areaOverride,
        remark: remark,
      );
      await _savePDF(context, pdf, payment);
    } catch (e) {
       print('PDF Export Error: $e');
    }
  }

  static Future<void> _savePDF(BuildContext context, pw.Document pdf, Payment payment) async {
    final fileName = 'receipt_${payment.id.substring(0, min(8, payment.id.length))}.pdf';
    final bytes = await pdf.save();
    
    if (Platform.isWindows || Platform.isMacOS) {
      final saveLocation = await getSaveLocation(suggestedName: fileName, acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])]);
      if (saveLocation != null) {
        final file = XFile.fromData(bytes, name: p.basename(saveLocation.path), mimeType: 'application/pdf');
        await file.saveTo(saveLocation.path);
      }
    } else {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }
}