import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';
import 'dart:io';

import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:country_flags/country_flags.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

enum ExportLanguage { vi, en, bilingual }

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

  // ========================================
  // LOCALIZATION HELPERS
  // ========================================
  static String _l(String key, ExportLanguage? lang) {
    final bilingual=lang == null || lang == ExportLanguage.bilingual;
    final t=AppTranslations(Locale(lang == ExportLanguage.en ? 'en' : 'vi'));
    return t['invoice_excel_${key}${bilingual ? '_bilingual' : ''}'];
  }

  static String _lStatus(PaymentStatus status, ExportLanguage lang) {
    final Map<PaymentStatus, Map<String, String>> statusMap = {
      PaymentStatus.pending: {'vi': 'Chưa thanh toán', 'en': 'Unpaid', 'bilingual': 'Chưa thanh toán / Unpaid'},
      PaymentStatus.paid: {'vi': 'Đã thanh toán', 'en': 'Paid', 'bilingual': 'Đã thanh toán / Paid'},
      PaymentStatus.partial: {'vi': 'Thanh toán một phần', 'en': 'Partially Paid', 'bilingual': 'Một phần / Partial'},
      PaymentStatus.overdue: {'vi': 'Quá hạn', 'en': 'Overdue', 'bilingual': 'Quá hạn / Overdue'},
    };
    return statusMap[status]?[lang.name] ?? statusMap[status]?['bilingual'] ?? status.name;
  }

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

            return AppAlertDialog(
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
                      color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
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
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t['export_lang_dialog_title'],
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
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
    final lang = await _showLanguageDialog(context);
    if (lang == null || !context.mounted) return;

    bool spinnerOpen = true;
    // Show spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(_l('loading', lang)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final bytes = _buildWorkbook(
        language: lang,
        payment: payment,
        organization: organization,
        roomNumber: roomNumber,
        buildingName: buildingName,
        tenantEmail: tenantEmail,
      );

      if (context.mounted) Navigator.of(context).pop(); // close spinner
      spinnerOpen = false;

      final suggestedName =
          'hoa_don_${payment.id}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final location = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
          ],
        );
        if (location == null) return;

        await File(location.path).writeAsBytes(bytes, flush: true);

        // Open containing folder so user can see the file
        if (Platform.isWindows) await Process.run(
          'explorer',
          ['/select,', location.path],
          runInShell: true,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_l('save_success', lang)} ${p.basename(location.path)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (!context.mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          fileNameOverrides: [suggestedName],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      }
    } catch (e) {
      if (spinnerOpen && context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_l('error_msg', lang)} $e'),
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
    required ExportLanguage language,
    required Payment payment,
    required Organization organization,
    String? roomNumber,
    String? buildingName,
    String? tenantEmail,
  }) {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = switch (language) {
      ExportLanguage.vi        => 'Hoa Don',
      ExportLanguage.en        => 'Invoice',
      ExportLanguage.bilingual => 'Invoice - Hoa Don',
    };
    sheet.showGridlines = false;

    final df = DateFormat(language == ExportLanguage.en ? 'MM/dd/yyyy' : 'dd/MM/yyyy');
    final nf = AppMoney.numberFormat(payment.currency);
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

    void setBorder(int ro, int co, [int? re, int? ce]) {
      final range = (re != null && ce != null)
          ? sheet.getRangeByIndex(ro, co, re, ce)
          : sheet.getRangeByIndex(ro, co);
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      range.cellStyle.borders.all.color = '#BDBDBD'; // light grey border
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
      setBorder(ro, 1);                    // border on label cell
      mergeSet(ro, 2, ro, 7, text: value, fontSize: 10);
      setBorder(ro, 2, ro, 7);             // border on value cell
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
        text: _l('invoice_title', language),
        bold: true,
        fontSize: 13,
        bg: cPrimary,
        fg: cPrimaryFg,
        hAlign: xlsio.HAlignType.center);
    row += 2;

    // ── Invoice metadata ─────────────────────────────────────────────────────

    sectionHeader(row, _l('info_section', language));
    row++;
    labelValue(row, _l('inv_id', language), payment.id);
    row++;
    labelValue(row, _l('tenant', language), payment.tenantName ?? 'N/A');
    row++;

    if (roomNumber != null) { labelValue(row, _l('room', language), roomNumber); row++; }
    if (buildingName != null) { labelValue(row, _l('building', language), buildingName); row++; }

    if (tenantEmail != null && tenantEmail.isNotEmpty) { labelValue(row, _l('email', language), tenantEmail); row++; }

    labelValue(row, _l('status', language), _lStatus(payment.status, language));
    row++;
    labelValue(row, _l('due_date', language), df.format(payment.dueDate));
    row++;

    if (payment.paidAt != null) { labelValue(row, _l('paid_date', language), df.format(payment.paidAt!)); row++; }

    if (payment.status == PaymentStatus.partial) {
      labelValue(
        row,
        _l('paid_amount', language), // Use the localized key
        '${nf.format(payment.paidAmount)} ${payment.currency}',
      );
      row++;
    }

    labelValue(row, _l('export_date', language), df.format(now));
    row += 2;

    // ── Line items table ─────────────────────────────────────────────────────

    sectionHeader(row, _l('detail_section', language));
    row++;

    // Table column headers
    r(row, 1).setText('#');
    r(row, 1).cellStyle.bold = true;
    r(row, 1).cellStyle.backColor = cPrimary;
    r(row, 1).cellStyle.fontColor = cPrimaryFg;
    r(row, 1).cellStyle.hAlign = xlsio.HAlignType.center;

    r(row, 2).setText(_l('col_type', language));
    r(row, 2).cellStyle.bold = true;
    r(row, 2).cellStyle.backColor = cPrimary;
    r(row, 2).cellStyle.fontColor = cPrimaryFg;
    r(row, 2).cellStyle.hAlign = xlsio.HAlignType.center;

    // Merge cols 3-5 for the notes header
    mergeSet(row, 3, row, 5,
        text: _l('col_note', language),
        bold: true,
        bg: cPrimary,
        fg: cPrimaryFg,
        hAlign: xlsio.HAlignType.center);

    // Merge cols 6-7 for the amount header
    mergeSet(row, 6, row, 7,
        text: '${_l('col_price', language).replaceAll(' ({{currency}})', '')} (${payment.currency})',
        bold: true,
        bg: cPrimary,
        fg: cPrimaryFg,
        hAlign: xlsio.HAlignType.center);

    setBorder(row, 1);
    setBorder(row, 2);
    setBorder(row, 3, row, 5);
    setBorder(row, 6, row, 7);
    row++;

    final lineItems = _parseLineItems(payment, df, nf, language);

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
      sheet.getRangeByIndex(row, 6, row, 7).numberFormat = AppMoney.excelFormat(payment.currency);

      setBorder(row, 1);
      setBorder(row, 2);
      setBorder(row, 3, row, 5);
      setBorder(row, 6, row, 7);
      row++;
    }

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
      setBorder(ro, 1, ro, 5);
      mergeSet(ro, 6, ro, 7,
          number: amount,
          bold: bold,
          fontSize: fontSize,
          fg: labelColor,
          bg: bg,
          hAlign: xlsio.HAlignType.right);
      setBorder(ro, 6, ro, 7);
      sheet.getRangeByIndex(ro, 6, ro, 7).numberFormat = AppMoney.excelFormat(payment.currency);
    }

    summaryRow(row, _l('total_items', language), payment.amount);
    row++;

    if (payment.lateFee != null && payment.lateFee! > 0) {
      summaryRow(row, _l('late_fee', language), payment.lateFee!, labelColor: cLateFee);
      row++;
    }

    final subTotal = payment.amount + (payment.lateFee ?? 0);
    if ((payment.lateFee ?? 0) > 0) {
      summaryRow(row, _l('plus', language), subTotal);
      row++;
    }

    if (payment.taxAmount != null && payment.taxAmount! > 0) {
      summaryRow(row, _l('tax', language), payment.taxAmount!, labelColor: cTax);
      row++;
    }

    // Grand total — highlighted green
    summaryRow(row, _l('grand_total', language), payment.totalAmount, bold: true, fontSize: 13, bg: cTotal, labelColor: cTotalFg);
    sheet.getRangeByIndex(row, 1, row, 7).cellStyle.fontColor = cTotalFg;

    final totalRange = sheet.getRangeByIndex(row, 1, row, 7);
    totalRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.medium;
    totalRange.cellStyle.borders.all.color = '#1B5E20';

    row += 2;
    // ── Payment status note ─────────────────────────────────────────────────

    if (payment.status == PaymentStatus.partial) {
      sectionHeader(row, _l('payment_status_section', language));
      row++;
      labelValue(row, _l('paid_amount', language), '${nf.format(payment.paidAmount)} ${payment.currency}');
      row++;
      labelValue(row, _l('remaining', language), '${nf.format(payment.totalAmount - payment.paidAmount)} ${payment.currency}');
      row += 2;
    }

    // ── Notes ────────────────────────────────────────────────────────────────

    if (payment.notes != null && payment.notes!.isNotEmpty) {
      sectionHeader(row, _l('remark_section', language));
      row++;
      mergeSet(row, 1, row, 7, text: payment.notes!, wrap: true);
      row++;
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    row++;
    mergeSet(row, 1, row, 7, text: '${_l('footer_msg', language)} • ${df.format(now)}', fontSize: 9, fg: '#9E9E9E', hAlign: xlsio.HAlignType.center);

    // ── Column widths ────────────────────────────────────────────────────────
    // Collect all label strings and pick the longest
    final labelStrings = [
      _l('inv_id', language),
      _l('tenant', language),
      if (roomNumber != null) _l('room', language),
      if (buildingName != null) _l('building', language),
      if (tenantEmail != null && tenantEmail.isNotEmpty) _l('email', language),
      _l('status', language),
      _l('due_date', language),
      if (payment.paidAt != null) _l('paid_date', language),
      if (payment.status == PaymentStatus.partial) _l('paid_amount', language),
      _l('export_date', language),
    ];

    // ~7px per character is a good approximation for fontSize 10
    final longestLabel = labelStrings.map((s) => s.length).reduce((a, b) => a > b ? a : b);
    final col1Width = (longestLabel * 7.0).clamp(80.0, 200.0);
    sheet.setColumnWidthInPixels(1, col1Width.toInt());
    sheet.setColumnWidthInPixels(2, 160);
    sheet.setColumnWidthInPixels(3, 110);
    sheet.setColumnWidthInPixels(4, 110);
    sheet.setColumnWidthInPixels(5, 110);
    sheet.setColumnWidthInPixels(6, 140);
    sheet.setColumnWidthInPixels(7, 10); // spacer

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parse payment into _XlsLineItem list — mirrors _parseLineItems in
  // view_edit_dialogs.dart but produces detail strings ready for Excel cells.
  // ─────────────────────────────────────────────────────────────────────────

  static List<_XlsLineItem> _parseLineItems(Payment payment, DateFormat df, NumberFormat nf, ExportLanguage lang) {
    if (payment.type == PaymentType.electricity && payment.electricityStartReading != null) {
      return [_electricityItem(payment, df, nf, lang)];
    }
    if (payment.type == PaymentType.water && payment.waterStartReading != null) {
      return [_waterItem(payment, df, nf, lang)];
    }
    if (payment.type == PaymentType.rent && payment.hasRentUnitPricing) {
      return [_rentItem(payment, df, nf, lang)];
    }

    // Default mapping for single types
    return [_XlsLineItem(
      typeLabel: _l(payment.type.name, lang),
      amount: payment.amount,
      detail: payment.description,
    )];
  }

  static _XlsLineItem _electricityItem(Payment p, DateFormat df, NumberFormat nf, ExportLanguage lang) {
    final start = p.electricityStartReading ?? 0;
    final end = p.electricityEndReading ?? 0;
    final usage = end - start;
    final detail = '${_l('meter_reading', lang)} $start → $end kWh (${usage.toStringAsFixed(1)} kWh)\n${_l('billing_cycle', lang)} ${df.format(p.electricityStartDate!)} – ${df.format(p.electricityEndDate!)}';
    return _XlsLineItem(typeLabel: _l('electricity', lang), amount: p.amount, detail: detail);
  }

  static _XlsLineItem _waterItem(Payment p, DateFormat df, NumberFormat nf, ExportLanguage lang) {
    final start = p.waterStartReading ?? 0;
    final end = p.waterEndReading ?? 0;
    final usage = end - start;
    final detail = '${_l('meter_reading', lang)} $start → $end m³ (${usage.toStringAsFixed(1)} m³)\n${_l('billing_cycle', lang)} ${df.format(p.waterStartDate!)} – ${df.format(p.waterEndDate!)}';
    return _XlsLineItem(typeLabel: _l('water', lang), amount: p.amount, detail: detail);
  }

  static String _rentUnitLabel(RentPriceMode mode, ExportLanguage lang) {
    switch (mode) {
      case RentPriceMode.daily:
        return _l('unit_day', lang);
      case RentPriceMode.monthly:
        return _l('unit_month', lang);
      case RentPriceMode.yearly:
        return _l('unit_year', lang);
      case RentPriceMode.direct:
        return '';
    }
  }

  static _XlsLineItem _rentItem(Payment p, DateFormat df, NumberFormat nf, ExportLanguage lang) {
    final mode = p.rentPriceMode!;
    final unitLabel = _rentUnitLabel(mode, lang);
    final qty = p.rentUnitQuantity!;
    final qtyText = mode == RentPriceMode.daily ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
    var detail = '$qtyText $unitLabel × ${nf.format(p.rentUnitPrice)} ${p.currency}/$unitLabel';
    if (p.billingStartDate != null && p.billingEndDate != null) {
      detail += '\n${_l('billing_cycle', lang)} ${df.format(p.billingStartDate!)} – ${df.format(p.billingEndDate!)}';
    }
    return _XlsLineItem(typeLabel: _l('rent', lang), amount: p.amount, detail: detail);
  }
}
