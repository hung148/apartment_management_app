import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

/// Sheet import (2026-10-05, Tom; design in IMPORT_SHEET.md).
///
/// The tabs and columns of the old app's export that the import uses. Only
/// these leave the device: the password column ("Mật khẩu"), the change log
/// and every other column stay in the file.
const oldAppColumns = <String, List<String>>{
  'Phòng': ['ID', 'Tên cơ sở', 'Giá thuê cơ sở', 'Mã phòng Json', 'Ghi chú'],
  'Đặt phòng': [
    'ID',
    'Tên cơ sở',
    'Mã phòng',
    'Ngày tạo',
    'Tên khách hàng',
    'Số điện thoại',
    'Nguồn',
    'Nhân viên',
    'Hình thức phòng',
    'Ngày giờ checkin',
    'Ngày giờ checkout',
    'Đơn giá',
    'Phụ phí',
    'Tổng doanh thu',
    'Ghi chú',
    'Thanh toán Json',
    'Số tiền còn lại',
  ],
  'Nhân viên': [
    'ID',
    'Tên nhân viên',
    'Tên đăng nhập',
    'Quyền',
    'Quản lý cơ sở',
    'Màu',
    'Tỷ lệ hoa hồng',
  ],
  'Chi phí': [
    'ID',
    'Ngày chi',
    'Cơ sở',
    'Nhóm chi phí',
    'Nội dung chi',
    'Số tiền',
    'Ghi chú',
  ],
};

/// Why a file could not be read: 'not_xlsx' (not an Excel file) or
/// 'not_old_app' (none of the old app's tabs).
class SheetFileError implements Exception {
  final String reason;
  const SheetFileError(this.reason);
  @override
  String toString() => 'SheetFileError($reason)';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Built-in Excel number formats that are dates or times.
const _dateFormatIds = {
  14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
  45, 46, 47, 50, 51, 52, 53, 54, 55, 56, 57, 58,
};

/// A custom number format that shows a date or time ("dd/mm/yyyy hh:mm"),
/// not money ("#,##0\ [\$đ-42A]").
bool _isDateFormat(String code) {
  final bare = code
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase();
  return RegExp('[dmyhs]').hasMatch(bare) && !bare.contains('general');
}

/// An Excel date number (days since 1899-12-30) as 'YYYY-MM-DD HH:mm:ss'.
String _serialStamp(double serial) {
  final d = DateTime.utc(1899, 12, 30).add(
    Duration(seconds: (serial * 86400).round()),
  );
  return '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// Column letters of a cell reference ("AB12") → 0-based index.
int _column(String ref) {
  var n = 0;
  for (final c in ref.toUpperCase().codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// Every tab of an .xlsx as rows of cells: text, numbers (whole numbers as
/// int), true/false, or dates as 'YYYY-MM-DD HH:mm:ss' (the wall clock written
/// in the file). Read directly from the file's XML, so files saved by Excel,
/// Google Sheets or other tools all work (2026-10-05: the excel package
/// refused some of them).
Map<String, List<List<Object?>>> readXlsx(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const SheetFileError('not_xlsx');
  }
  XmlDocument? xmlOf(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(f.content as List<int>));
    } catch (_) {
      throw const SheetFileError('not_xlsx');
    }
  }

  String? attr(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  final workbook = xmlOf('xl/workbook.xml');
  if (workbook == null) throw const SheetFileError('not_xlsx');
  final targets = <String, String>{};
  for (final r
      in xmlOf('xl/_rels/workbook.xml.rels')?.findAllElements(
            'Relationship',
          ) ??
          const <XmlElement>[]) {
    final id = r.getAttribute('Id'), target = r.getAttribute('Target');
    if (id == null || target == null) continue;
    targets[id] = target.startsWith('/')
        ? target.substring(1)
        : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
  }
  String text(XmlElement e) => e
      .findAllElements('t')
      .where((t) => t.parentElement?.name.local != 'rPh')
      .map((t) => t.innerText)
      .join();
  final shared = [
    for (final si
        in xmlOf('xl/sharedStrings.xml')?.findAllElements('si') ??
            const <XmlElement>[])
      text(si),
  ];
  // Which cell styles show dates.
  final styles = xmlOf('xl/styles.xml');
  final custom = <int, String>{
    for (final f in styles?.findAllElements('numFmt') ?? const <XmlElement>[])
      if (int.tryParse(f.getAttribute('numFmtId') ?? '') != null)
        int.parse(f.getAttribute('numFmtId')!): f.getAttribute('formatCode') ?? '',
  };
  final dateStyles = <bool>[];
  final xfs = styles?.findAllElements('cellXfs').firstOrNull;
  for (final xf in xfs?.findElements('xf') ?? const <XmlElement>[]) {
    final id = int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0;
    dateStyles.add(
      _dateFormatIds.contains(id) ||
          (custom.containsKey(id) && _isDateFormat(custom[id]!)),
    );
  }

  final out = <String, List<List<Object?>>>{};
  for (final sheet in workbook.findAllElements('sheet')) {
    final name = sheet.getAttribute('name');
    final path = targets[attr(sheet, 'id') ?? ''];
    if (name == null || path == null) continue;
    final doc = xmlOf(path);
    if (doc == null) continue;
    final rows = <List<Object?>>[];
    for (final row in doc.findAllElements('row')) {
      final index = (int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1) - 1;
      if (index < 0 || index > 200000) continue;
      while (rows.length < index) {
        rows.add(<Object?>[]);
      }
      final cells = <Object?>[];
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? next : _column(ref);
        if (col < 0 || col > 1000) continue;
        next = col + 1;
        final type = c.getAttribute('t') ?? 'n';
        final raw = c.findElements('v').firstOrNull?.innerText;
        Object? value;
        switch (type) {
          case 's':
            final i = int.tryParse(raw ?? '');
            value = i != null && i >= 0 && i < shared.length ? shared[i] : null;
          case 'inlineStr':
            final s = c.findElements('is').firstOrNull;
            value = s == null ? null : text(s);
          case 'str':
            value = raw;
          case 'b':
            value = raw == '1';
          case 'e':
            value = null;
          default:
            final n = double.tryParse(raw ?? '');
            final style = int.tryParse(c.getAttribute('s') ?? '0') ?? 0;
            if (n == null) {
              value = null;
            } else if (style < dateStyles.length && dateStyles[style]) {
              value = _serialStamp(n);
            } else if (n == n.truncateToDouble() && n.abs() < 9e15) {
              value = n.toInt();
            } else {
              value = n;
            }
        }
        if (value is String && value.isEmpty) value = null;
        while (cells.length < col) {
          cells.add(null);
        }
        cells.add(value);
      }
      if (rows.length == index) {
        rows.add(cells);
      } else {
        rows[index] = cells;
      }
    }
    out[name] = rows;
  }
  return out;
}

/// The old app's .xlsx → {tab: {headers, rows}} with the known columns only.
Map<String, dynamic> readOldAppSheet(List<int> bytes) {
  final book = readXlsx(bytes);
  final out = <String, dynamic>{};
  for (final MapEntry(key: name, value: rows) in book.entries) {
    final wanted = oldAppColumns[name.trim()];
    if (wanted == null || rows.isEmpty) continue;
    final header = [for (final c in rows.first) '${c ?? ''}'.trim()];
    final picked = [
      for (final column in wanted)
        if (header.contains(column)) (column, header.indexOf(column)),
    ];
    final kept = <List<Object?>>[];
    for (final row in rows.skip(1)) {
      final values = [
        for (final (_, i) in picked) i < row.length ? row[i] : null,
      ];
      if (values.every((v) => v == null || (v is String && v.trim().isEmpty))) {
        continue;
      }
      kept.add(values);
    }
    out[name.trim()] = {
      'headers': [for (final (c, _) in picked) c],
      'rows': kept,
    };
  }
  if (!out.containsKey('Phòng') && !out.containsKey('Đặt phòng')) {
    throw const SheetFileError('not_old_app');
  }
  return out;
}

/// The new sheet (tabs from the server) as an .xlsx, saved to Google Drive as
/// a Google Sheet.
Uint8List buildImportSheet(List tabs) {
  final book = xlsio.Workbook(tabs.isEmpty ? 1 : tabs.length);
  try {
    for (var t = 0; t < tabs.length; t++) {
      final tab = Map<String, dynamic>.from(tabs[t] as Map);
      final sheet = book.worksheets[t];
      sheet.name = '${tab['name']}';
      final headers = (tab['headers'] as List).map((h) => '$h').toList();
      for (var c = 0; c < headers.length; c++) {
        final cell = sheet.getRangeByIndex(1, c + 1);
        cell.setText(headers[c]);
        cell.cellStyle.bold = true;
      }
      final rows = tab['rows'] as List;
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r] as List;
        for (var c = 0; c < row.length; c++) {
          final v = row[c];
          final cell = sheet.getRangeByIndex(r + 2, c + 1);
          if (v is num) {
            cell.setNumber(v.toDouble());
            if (v is int || v == v.roundToDouble()) cell.numberFormat = '#,##0';
          } else if (v != null && '$v'.isNotEmpty) {
            cell.setText('$v');
          }
        }
      }
      if (headers.isNotEmpty) {
        sheet.getRangeByIndex(1, 1, rows.length + 1, headers.length).autoFitColumns();
      }
    }
    return Uint8List.fromList(book.saveAsStream());
  } finally {
    book.dispose();
  }
}
