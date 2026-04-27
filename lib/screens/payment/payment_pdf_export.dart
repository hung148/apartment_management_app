import 'dart:io';
import 'dart:math';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart'; // Import Room Model
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';

enum ExportLanguage { vi, en, bilingual }

class PaymentPDFExporter {

  // ========================================
  // LOCALIZATION HELPERS
  // ========================================
  static String _l(String key, ExportLanguage? lang) {
    
    final langCode = lang?.name ?? 'bilingual';

    const labels = {
      'receipt_title': {
        'vi': 'THU PHÍ CHỦ CĂN HỘ',
        'en': 'APARTMENT OWNER FEE RECEIPT',
        'bilingual': 'THU PHÍ CHỦ CĂN HỘ / APARTMENT OWNER FEE RECEIPT'
      },
      'currency_unit': {'vi': 'Đơn vị tính: VND', 'en': 'Currency: VND', 'bilingual': 'Đơn vị tính / Currency: VND'},
      'apt_code': {'vi': 'MÃ CĂN', 'en': 'APT CODE', 'bilingual': 'MÃ CĂN / APARTMENT CODE'},
      'apt_type': {'vi': 'LOẠI CĂN HỘ', 'en': 'APT TYPE', 'bilingual': 'LOẠI CĂN HỘ / APARTMENT TYPE'},
      'full_name': {'vi': 'HỌ VÀ TÊN', 'en': 'FULL NAME', 'bilingual': 'HỌ VÀ TÊN / FULL NAME'},
      'handover_date': {'vi': 'NGÀY BÀN GIAO', 'en': 'HANDOVER DATE', 'bilingual': 'NGÀY BÀN GIAO / HANDOVER DATE'},
      'until_date': {'vi': 'ĐẾN NGÀY', 'en': 'UNTIL DATE', 'bilingual': 'ĐẾN NGÀY / UNTIL DATE'},
      'days_used': {'vi': 'SỐ NGÀY SỬ DỤNG', 'en': 'DAYS USED', 'bilingual': 'SỐ NGÀY SỬ DỤNG / DAYS USED'},
      'months_used': {'vi': 'SỐ THÁNG', 'en': 'MONTHS USED', 'bilingual': 'SỐ THÁNG / MONTHS USED'},
      'management_fee': {'vi': 'PHÍ QUẢN LÝ', 'en': 'MANAGEMENT FEE', 'bilingual': 'PHÍ QUẢN LÝ / MANAGEMENT FEE'},
      'area': {'vi': 'DIỆN TÍCH', 'en': 'AREA', 'bilingual': 'DIỆN TÍCH / AREA'},
      'unit_price': {'vi': 'ĐƠN GIÁ', 'en': 'UNIT PRICE', 'bilingual': 'ĐƠN GIÁ / UNIT PRICE'},
      'electricity': {'vi': 'PHÍ ĐIỆN', 'en': 'ELECTRICITY', 'bilingual': 'PHÍ ĐIỆN / ELECTRICITY'},
      'water': {'vi': 'PHÍ NƯỚC', 'en': 'WATER', 'bilingual': 'PHÍ NƯỚC / WATER'},
      'usage': {'vi': 'Số sử dụng', 'en': 'Usage', 'bilingual': 'Số sử dụng / Usage'},
      'internet': {'vi': 'PHÍ INTERNET', 'en': 'INTERNET FEE', 'bilingual': 'PHÍ INTERNET / INTERNET FEE'},
      'cable_tv': {'vi': 'PHÍ TRUYỀN HÌNH CÁP', 'en': 'CABLE TV FEE', 'bilingual': 'PHÍ TRUYỀN HÌNH CÁP / CABLE TV FEE'},
      'hot_water': {'vi': 'PHÍ NƯỚC NÓNG', 'en': 'HOT WATER FEE', 'bilingual': 'PHÍ NƯỚC NÓNG / HOT WATER FEE'},
      'subtotal': {'vi': 'TỔNG CHƯA THUẾ', 'en': 'SUBTOTAL', 'bilingual': 'TỔNG CHƯA THUẾ / SUBTOTAL'},
      'tax': {'vi': 'THUẾ (10%)', 'en': 'VAT (10%)', 'bilingual': 'THUẾ (10%) / VAT'},
      'total': {'vi': 'TỔNG THANH TOÁN', 'en': 'TOTAL PAYMENT', 'bilingual': 'TỔNG THANH TOÁN / TOTAL PAYMENT'},
      'transfer_info': {'vi': 'THÔNG TIN CHUYỂN KHOẢN', 'en': 'TRANSFER INFO', 'bilingual': 'THÔNG TIN CHUYỂN KHOẢN / TRANSFER INFO'},
      'remark': {'vi': 'GHI CHÚ', 'en': 'REMARK', 'bilingual': 'GHI CHÚ / REMARK'},
      'days': {'vi': 'ngày', 'en': 'days', 'bilingual': 'ngày/days'},
      'bank_acc_owner': {'vi': 'Chủ TK: ', 'en': 'Owner: ', 'bilingual': 'Chủ TK/Owner: '},
      'bank_acc_num': {'vi': 'Số TK: ', 'en': 'Acc No: ', 'bilingual': 'Số TK/Acc No: '},
      'bank_name': {'vi': 'Ngân hàng: ', 'en': 'Bank: ', 'bilingual': 'Ngân hàng/Bank: '},
    };
    
    final entry = labels[key];
    if (entry == null) return key;
    return entry[langCode] ?? entry['bilingual'] ?? key;
  }

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
    required ExportLanguage language,
    required Payment payment,
    required Organization organization,
    Tenant? tenant, 
    Room? room, 
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
      String tenantEmail = '';
      if (email != null && email.isNotEmpty) {
        tenantEmail = email;
      } else if (tenant?.email != null && tenant!.email!.isNotEmpty) {
        tenantEmail = tenant.email!;
      }

      String organizationEmail = organization.email ?? '';

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
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          // header: (context) => _buildHeader(organization, boldFont, regularFont), // Optional: keep header on every page
          build: (context) {
            return [
                // HEADER
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(organization.name.toUpperCase(),
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: boldFont, color: PdfColors.blue900)),
                        if (organization.taxCode?.isNotEmpty ?? false)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 4),
                            child: pw.Text('${language == ExportLanguage.en ? "Tax Code" : "MST"}: ${organization.taxCode}',
                              style: pw.TextStyle(fontSize: 9, font: regularFont, color: PdfColors.grey800)),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                
                // TITLE
                pw.Center(
                  child: pw.Column(children: [
                    pw.Text('${_l('receipt_title', language)} ${roomNumber ?? room?.roomNumber ?? ""}',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, font: boldFont)),
                    pw.Text('($billingPeriodStr)', style: pw.TextStyle(fontSize: 9, font: regularFont, fontStyle: pw.FontStyle.italic)),
                    pw.Text(_l('currency_unit', language), style: pw.TextStyle(fontSize: 8, font: regularFont)),
                  ]),
                ),
                pw.SizedBox(height: 20),
                
                // DATA TABLES
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow(_l('apt_code', language), roomNumber ?? room?.roomNumber ?? 'N/A', regularFont, boldFont),
                    _buildInfoRow(_l('apt_type', language), apartmentType, regularFont, boldFont),
                    _buildInfoRow(_l('full_name', language), tenantName, regularFont, boldFont),
                    _buildInfoRow(_l('handover_date', language), formatDate(handoverDate), regularFont, boldFont),
                    _buildInfoRow(_l('until_date', language), formatDate(billingEnd), regularFont, boldFont),
                    _buildInfoRow(_l('days_used', language), '$daysUsed ${_l('days', language)}', regularFont, boldFont),
                    _buildInfoRow(_l('months_used', language), monthsUsed.toString(), regularFont, boldFont),
                    _buildInfoRow(_l('management_fee', language), formatCurrency(managementFee), regularFont, boldFont),
                    _buildInfoRow(_l('area', language), '${area.toStringAsFixed(2)} m²', regularFont, boldFont),
                    _buildInfoRow(_l('unit_price', language), (area > 0 && monthsUsed > 0) ? formatCurrency(managementFee / area / monthsUsed) : '0', regularFont, boldFont),
                  ],
                ),
                
                pw.SizedBox(height: 10),
                
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow(_l('electricity', language), formatCurrency(electricityFee), regularFont, boldFont),
                    _buildInfoRow(_l('usage', language), '${payment.electricityUsage?.toStringAsFixed(1) ?? "0"} kWh', regularFont, boldFont),
                    _buildInfoRow(_l('water', language), formatCurrency(waterFee), regularFont, boldFont),
                    _buildInfoRow(_l('usage', language), '${payment.waterUsage?.toStringAsFixed(1) ?? "0"} m³', regularFont, boldFont),
                  ],
                ),

                pw.SizedBox(height: 10),

                // EXTRA FEES
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow(_l('internet', language), formatCurrency(actualInternetFee), regularFont, boldFont),
                    _buildInfoRow(_l('cable_tv', language), formatCurrency(actualCableTVFee), regularFont, boldFont),
                    _buildInfoRow('${_l('hot_water', language)} (${actualHotWaterPercent.toStringAsFixed(0)}%)', formatCurrency(actualHotWaterFee), regularFont, boldFont),
                  ],
                ),

                pw.SizedBox(height: 10),
                
                // TOTALS
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildTotalRow(_l('subtotal', language), formatCurrency(subtotal), regularFont, boldFont, false),
                    _buildTotalRow(_l('tax', language), formatCurrency(taxAmount), regularFont, boldFont, false),
                    _buildTotalRow(_l('total', language), formatCurrency(grandTotal), regularFont, boldFont, true),
                  ],
                ),
                
                pw.SizedBox(height: 10),

                // CONTACT & REMARK
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
                  children: [
                    _buildInfoRow('TENANT EMAIL', tenantEmail, regularFont, boldFont, isLink: tenantEmail.isNotEmpty),
                    _buildInfoRow('OFFICE EMAIL', organizationEmail, regularFont, boldFont, isLink: organizationEmail.isNotEmpty),
                    _buildInfoRow(_l('remark', language), remark ?? payment.notes ?? '', regularFont, boldFont),
                  ],
                ),

                pw.SizedBox(height: 20), // Replaced pw.Spacer() with fixed gap
                
                // BANK INFO
                if (organization.hasBankInfo)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5), color: PdfColors.grey100),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(_l('transfer_info', language), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: boldFont)),
                        pw.SizedBox(height: 4),
                        _buildBankInfoRow(_l('bank_acc_owner', language), organization.bankAccountName ?? '', regularFont, boldFont),
                        _buildBankInfoRow(_l('bank_acc_num', language), organization.bankAccountNumber ?? '', regularFont, boldFont),
                        _buildBankInfoRow(_l('bank_name', language), organization.bankName ?? '', regularFont, boldFont),
                      ],
                    ),
                  ),
                
                pw.SizedBox(height: 20),
                pw.Divider(color: PdfColors.grey400),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Generated: ${formatDateTime(DateTime.now())}', style: pw.TextStyle(fontSize: 7, font: regularFont)),
                    pw.Text('ID: ${payment.id.toUpperCase()}', style: pw.TextStyle(fontSize: 7, font: regularFont)),
                  ],
                ),
            ];
          },
        ),
      );

      return pdf;
    } catch (e) {
      rethrow;
    }
  }

  // --- HELPER ROWS ---
  static pw.TableRow _buildInfoRow(String label, String value, pw.Font reg, pw.Font bold, {bool isLink = false}) {
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
  static Future<ExportLanguage?> _showLanguageDialog(BuildContext context) async {
    ExportLanguage? selected = ExportLanguage.vi;
    final t = AppTranslations.of(context);

    return await showDialog<ExportLanguage>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            Widget buildOption({
              required ExportLanguage value,
              required Widget flag,
              required String title,
              required String subtitle,
            }) {
              final isSelected = selected == value;
              return GestureDetector(
                onTap: () => setState(() => selected = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(ctx).colorScheme.primary
                          : Colors.grey.shade300,
                      width: isSelected ? 2.0 : 0.5,
                    ),
                    color: isSelected
                        ? Theme.of(ctx).colorScheme.primary.withOpacity(0.07)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      flag,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Theme.of(ctx).colorScheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(ctx).colorScheme.primary
                                : Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 12, color: Colors.white)
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.translate_rounded,
                      color: Theme.of(ctx).colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['export_lang_dialog_subtitle'],
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t['export_lang_dialog_title'],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildOption(
                      value: ExportLanguage.vi,
                      flag: CountryFlag.fromCountryCode(
                        'VN',
                        theme: const ImageTheme(
                          width: 48,
                          height: 32,
                          shape: RoundedRectangle(6),
                        ),
                      ),
                      title: t['export_lang_vi_title'],
                      subtitle: t['export_lang_vi_subtitle'],
                    ),
                    const SizedBox(height: 8),
                    buildOption(
                      value: ExportLanguage.en,
                      flag: CountryFlag.fromCountryCode(
                        'US',
                        theme: const ImageTheme(
                          width: 48,
                          height: 32,
                          shape: RoundedRectangle(6),
                        ),
                      ),
                      title: t['export_lang_en_title'],
                      subtitle: t['export_lang_en_subtitle'],
                    ),
                    const SizedBox(height: 8),
                    buildOption(
                      value: ExportLanguage.bilingual,
                      flag: SizedBox(
                        width: 48,
                        height: 36,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              child: CountryFlag.fromCountryCode(
                                'VN',
                                theme: const ImageTheme(
                                  width: 36,
                                  height: 24,
                                  shape: RoundedRectangle(4),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CountryFlag.fromCountryCode(
                                'US',
                                theme: const ImageTheme(
                                  width: 36,
                                  height: 24,
                                  shape: RoundedRectangle(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      title: t['export_lang_bi_title'],
                      subtitle: t['export_lang_bi_subtitle'],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t['cancel']),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: Text(t['export_lang_btn_export']),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========================================
  // WRAPPERS (PREVIEW & EXPORT)
  // ========================================
  static Future<void> showPDFPreview({
    required BuildContext context,
    required Payment payment,
    required Organization organization,
    Tenant? tenant,
    Room? room,
    String? roomNumber,
    String? buildingName,
    String? apartmentTypeOverride,
    double? areaOverride,
    String? email,
    String? remark,
  }) async {

    // 1. Ask for language first
    final lang = await _showLanguageDialog(context);
    
    // 2. Check if user cancelled or if the widget is no longer in the tree
    if (lang == null || !context.mounted) return;

    try {
      // Show loading indicator

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = await generateOwnerFeeReceipt(
        language: lang,
        payment: payment,
        organization: organization,
        tenant: tenant,
        room: room,
        roomNumber: roomNumber,
        buildingName: buildingName,
        apartmentTypeOverride: apartmentTypeOverride,
        areaOverride: areaOverride,
        email: email,
        remark: remark,
      );

      final bytes = await pdf.save();

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog

        await Navigator.push(context, MaterialPageRoute(
          builder: (context) => _PDFPreviewScreen(
            bytes: bytes,
            payment: payment,
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất PDF: $e'), backgroundColor: Colors.red),
        );
      }
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
    String? email,
  }) async {
    // 1. Prompt for language (since generateOwnerFeeReceipt requires it)
    final lang = await _showLanguageDialog(context);
    if (lang == null || !context.mounted) return;

    try {
      final pdf = await generateOwnerFeeReceipt(
        language: lang,
        payment: payment,
        organization: organization,
        tenant: tenant,
        room: room, // Pass room
        roomNumber: roomNumber,
        buildingName: buildingName,
        areaOverride: areaOverride,
        remark: remark,
        email: email,
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

class _PDFPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final Payment payment;

  const _PDFPreviewScreen({required this.bytes, required this.payment});

  String get _fileName => 'receipt_${payment.id.substring(0, min(8, payment.id.length))}.pdf';

  Future<void> _printPDF(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi in: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sharePDF(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chia sẻ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _savePDF(BuildContext context) async {
    try {
      if (Platform.isWindows || Platform.isMacOS) {
        final saveLocation = await getSaveLocation(
          suggestedName: _fileName,
          acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
        );
        if (saveLocation != null) {
          final file = XFile.fromData(bytes, name: p.basename(saveLocation.path), mimeType: 'application/pdf');
          await file.saveTo(saveLocation.path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã lưu PDF thành công'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: _fileName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem Trước Hóa Đơn'),
        actions: [
          Tooltip(
            message: 'In hóa đơn ra máy in',
            child: IconButton(
              icon: const Icon(Icons.print),
              onPressed: () => _printPDF(context),
            ),
          ),
          if (!Platform.isWindows && !Platform.isMacOS)
            Tooltip(
              message: 'Chia sẻ PDF qua ứng dụng khác',
              child: IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _sharePDF(context),
              ),
            ),
          Tooltip(
            message: Platform.isWindows || Platform.isMacOS
                ? 'Lưu PDF vào máy tính'
                : 'Tải xuống PDF',
            child: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _savePDF(context),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false,    // We handle print ourselves above
        allowSharing: false,     // We handle share ourselves above
        canChangeOrientation: false,  // Remove useless orientation toggle
        canChangePageFormat: false,   // Remove useless Letter/A4 toggle
        canDebug: false,              // Remove debug toggle
        initialPageFormat: PdfPageFormat.a4,
      ),
    );
  }
}