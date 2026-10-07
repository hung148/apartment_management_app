import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../services/sheet_import_files.dart';
import '../../services/team_service.dart';
import 'service_fee_text.dart' show FeeText;
import 'ws_ui.dart';

/// A picked file: its name and bytes.
typedef PickedSheet = ({String name, Uint8List bytes});

/// Settings → "Nhập từ file" (2026-10-05, Tom). The owner uploads the .xlsx
/// exported from the old app; the app reads it on this device and sends only
/// the columns the import uses (never the password column). The server shows
/// what it would create and what to look at, creates it all after "Nhập", and
/// can save a new Google Sheet with the imported data to the connected Drive.
/// Running the same file again creates nothing twice.
class SheetImportScreen extends StatefulWidget {
  final String organizationId;
  final TeamService service;

  /// Tests replace the file chooser and the link opener.
  final Future<PickedSheet?> Function()? pickFile;
  final Future<bool> Function(Uri url)? openUrl;
  const SheetImportScreen({
    super.key,
    required this.organizationId,
    required this.service,
    this.pickFile,
    this.openUrl,
  });

  @override
  State<SheetImportScreen> createState() => _SheetImportScreenState();
}

class _SheetImportScreenState extends State<SheetImportScreen> {
  String? _fileName, _error, _sheetUrl;
  Map<String, dynamic>? _sheets, _preview, _result;
  bool _busy = false, _confirm = false, _saving = false;
  String _operationId = const Uuid().v4();

  static const _keys = [
    'import_owner_only',
    'import_invalid_file',
    'import_missing_tab',
    'import_missing_column',
    'import_secret_column',
    'import_conflict',
    'import_overlap',
    'import_too_large',
    'request_too_large',
    'request_rate_limited',
    'drive_not_connected',
    'drive_reconnect_needed',
    'drive_unavailable',
  ];

  String _message(FeeText x, Object e) {
    if (e is SheetFileError) {
      return e.reason == 'not_xlsx'
          ? x.tr(
              'This is not an Excel (.xlsx) file.',
              'Đây không phải file Excel (.xlsx).',
            )
          : x.tr(
              'This file has none of the old app\'s tabs ("Phòng", "Đặt phòng").',
              'File này không có tab nào của ứng dụng cũ ("Phòng", "Đặt phòng").',
            );
    }
    final details = e is FirebaseFunctionsException && e.details is Map
        ? e.details as Map
        : const {};
    switch (serverReason(e, _keys)) {
      case 'import_owner_only':
        return x.tr(
          'Only the owner can import data.',
          'Chỉ chủ sở hữu mới nhập được dữ liệu.',
        );
      case 'import_missing_tab':
        return x.tr(
          'The file has no "${details['tab'] ?? ''}" tab.',
          'File không có tab "${details['tab'] ?? ''}".',
        );
      case 'import_missing_column':
        final cols = (details['columns'] as List? ?? const []).join(', ');
        return x.tr(
          'The "${details['tab'] ?? ''}" tab is missing columns: $cols.',
          'Tab "${details['tab'] ?? ''}" thiếu cột: $cols.',
        );
      case 'import_invalid_file':
      case 'import_secret_column':
        return x.tr(
          'The file could not be read. Export it again from the old app.',
          'Không đọc được file. Hãy xuất lại file từ ứng dụng cũ.',
        );
      case 'import_conflict':
        return x.tr(
          'Some records from this file belong to another organization.',
          'Một số dữ liệu trong file thuộc tổ chức khác.',
        );
      case 'import_overlap':
        return x.tr('Stays overlap in the same room. Correct their dates before importing. No records were changed.',
          'Lượt thuê trùng giờ trong cùng phòng. Hãy sửa ngày giờ trước khi nhập. Chưa thay đổi dữ liệu.');
      case 'import_too_large':
      case 'request_too_large':
        return x.tr(
          'The file is too large to import at once.',
          'File quá lớn để nhập một lần.',
        );
      case 'request_rate_limited':
        return x.tr(
          'Too many tries. Wait a minute, then try again.',
          'Thử quá nhiều lần. Chờ một phút rồi thử lại.',
        );
      case 'drive_not_connected':
        return x.tr(
          'Google Drive is not connected. Connect it on the home screen (Google Drive button).',
          'Chưa kết nối Google Drive. Hãy kết nối ở màn hình chính (nút Google Drive).',
        );
      case 'drive_reconnect_needed':
        return x.tr(
          'Google Drive needs to be connected again (home screen, Google Drive button).',
          'Cần kết nối lại Google Drive (màn hình chính, nút Google Drive).',
        );
      case 'drive_unavailable':
        return x.tr(
          'Google Drive did not answer. Try again in a moment.',
          'Google Drive chưa phản hồi. Thử lại sau ít phút.',
        );
    }
    return x.error(e);
  }

  Future<PickedSheet?> _pick() async {
    if (widget.pickFile != null) return widget.pickFile!();
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Excel',
          extensions: ['xlsx'],
          mimeTypes: [
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ],
          uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
        ),
      ],
    );
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  }

  Future<void> _choose() async {
    final x = FeeText(context);
    final picked = await _pick();
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _fileName = picked.name;
      _sheets = null;
      _preview = null;
      _result = null;
      _sheetUrl = null;
      _confirm = false;
      _operationId = const Uuid().v4();
    });
    try {
      final sheets = readOldAppSheet(picked.bytes);
      final preview = await widget.service.importSheet({
        'action': 'preview',
        'organizationId': widget.organizationId,
        'sheets': sheets,
      });
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
        _preview = preview;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(x, e);
      });
    }
  }

  Future<void> _apply() async {
    final x = FeeText(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.importSheet({
        'action': 'apply',
        'organizationId': widget.organizationId,
        'sheets': _sheets,
        'operationId': _operationId,
      });
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
        _confirm = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(x, e);
      });
    }
  }

  Future<void> _saveSheet() async {
    final x = FeeText(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = buildImportSheet(_result?['sheet'] as List? ?? const []);
      final day = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final saved = await widget.service.importSheet({
        'action': 'saveSheet',
        'organizationId': widget.organizationId,
        'name':
            'CanHo360 - dữ liệu nhập ${day.year}-${two(day.month)}-${two(day.day)}',
        'fileBase64': base64Encode(bytes),
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _sheetUrl = '${saved['url'] ?? ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _message(x, e);
      });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (widget.openUrl != null) {
      await widget.openUrl!(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _problemText(FeeText x, String code) => switch (code) {
    'duplicate_id' => x.tr(
      'Same ID twice: the second row is skipped',
      'Mã bị trùng: bỏ qua dòng sau',
    ),
    'building_no_name' => x.tr(
      'Building without a name: skipped',
      'Tòa nhà không có tên: bỏ qua',
    ),
    'duplicate_building' => x.tr(
      'Building listed twice: the second is skipped',
      'Tòa nhà bị lặp: bỏ qua dòng sau',
    ),
    'bad_rooms' => x.tr(
      'Room list could not be read',
      'Không đọc được danh sách phòng',
    ),
    'room_no_code' => x.tr(
      'Room without a number: skipped',
      'Phòng không có mã: bỏ qua',
    ),
    'duplicate_room' => x.tr(
      'Room listed twice: the second is skipped',
      'Phòng bị lặp: bỏ qua',
    ),
    'building_added' => x.tr(
      'Building not in the Phòng tab: added',
      'Tòa nhà không có trong tab Phòng: đã thêm',
    ),
    'room_added' => x.tr(
      'Room not in the Phòng tab: added',
      'Phòng không có trong tab Phòng: đã thêm',
    ),
    'stay_no_room' => x.tr(
      'Stay without a building or room: skipped',
      'Lượt thuê thiếu tòa nhà hoặc phòng: bỏ qua',
    ),
    'bad_dates' => x.tr(
      'Dates unreadable or check-out before check-in: skipped',
      'Ngày giờ không đọc được hoặc trả phòng trước nhận phòng: bỏ qua',
    ),
    'bad_amount' => x.tr(
      'Amount unreadable: skipped',
      'Số tiền không đọc được: bỏ qua',
    ),
    'bad_payment' => x.tr(
      'A payment could not be read: that payment is skipped',
      'Có khoản thanh toán không đọc được: bỏ khoản đó',
    ),
    'overpaid' => x.tr(
      'Paid more than the total',
      'Đã trả nhiều hơn tổng tiền',
    ),
    'no_name' => x.tr(
      'No guest name: saved as "Khách không tên"',
      'Không có tên khách: ghi "Khách không tên"',
    ),
    'staff_unknown' => x.tr(
      'Staff not in the Nhân viên tab: left empty',
      'Nhân viên không có trong tab Nhân viên: để trống',
    ),
    'staff_no_name' => x.tr(
      'Staff without a name: skipped',
      'Nhân viên không có tên: bỏ qua',
    ),
    'long_term_no_lease' => x.tr(
      'Room marked "Thuê dài hạn" but the file has no running lease for it',
      'Phòng ghi "Thuê dài hạn" nhưng file không có hợp đồng đang chạy',
    ),
    'expense_no_building' => x.tr(
      'Expense without a known building: skipped',
      'Chi phí không thuộc tòa nhà nào: bỏ qua',
    ),
    _ => code,
  };

  String _ref(Map p) => [
    '${p['tab'] ?? ''}',
    if (p['id'] != null) '${p['id']}',
    if ('${p['guest'] ?? ''}'.isNotEmpty) '${p['guest']}',
    if (p['building'] != null || p['room'] != null)
      [p['building'], p['room']].whereType<Object>().join(' · '),
    if (p['staff'] != null) '${p['staff']}',
  ].where((s) => s.isNotEmpty).join(' — ');

  Widget _counts(FeeText x, Map<String, dynamic> data) {
    final counts = Map<String, dynamic>.from(data['counts'] as Map? ?? {});
    final existing = Map<String, dynamic>.from(data['existing'] as Map? ?? {});
    final created = data['created'] is Map
        ? Map<String, dynamic>.from(data['created'] as Map)
        : null;
    String there(String kind) {
      final e = existing[kind];
      final n = e is Map ? (e['there'] as num? ?? 0).toInt() : 0;
      return n > 0 ? x.tr(' (already there: $n)', ' (đã có: $n)') : '';
    }

    final rows = <(String, String, String)>[
      ('buildings', 'buildings', x.tr('Buildings', 'Tòa nhà')),
      ('rooms', 'rooms', x.tr('Rooms', 'Phòng')),
      ('bookings', 'bookings', x.tr('Short stays', 'Đặt phòng ngắn ngày')),
      ('leases', 'tenants', x.tr('Leases', 'Hợp đồng thuê')),
      ('payments', 'payments', x.tr('Payments', 'Thanh toán')),
      ('staff', 'staffProfiles', x.tr('Staff', 'Nhân viên')),
      ('expenses', 'payments', x.tr('Expenses', 'Chi phí')),
    ];
    return WsSection(
      title: created == null
          ? x.tr('In this file', 'Trong file này')
          : x.tr('Imported', 'Đã nhập'),
      children: [
        for (final (key, kind, label) in rows)
          WsInfo(
            label,
            '${counts[key] ?? 0}${key == 'expenses' || key == 'payments' ? '' : there(kind)}',
          ),
        if (created != null)
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: Text(
              x.tr(
                'New records: ${created.values.fold<num>(0, (a, v) => a + (v as num))}. Records already imported were left as they are.',
                'Bản ghi mới: ${created.values.fold<num>(0, (a, v) => a + (v as num))}. Dữ liệu đã nhập trước đó được giữ nguyên.',
              ),
              key: const ValueKey('import-created'),
            ),
          ),
      ],
    );
  }

  Widget _notes(FeeText x, Map<String, dynamic> data) {
    final counts = Map<String, dynamic>.from(data['counts'] as Map? ?? {});
    final small = Theme.of(context).textTheme.bodySmall;
    final lines = [
      x.tr(
        'Rooms are created without an area: fill it in under each room.',
        'Phòng được tạo chưa có diện tích: nhập trong thông tin từng phòng.',
      ),
      if ((counts['staff'] ?? 0) > 0)
        x.tr(
          'Staff get a profile only. Invite each by email in Nhân sự (no passwords are imported).',
          'Nhân viên chỉ được tạo hồ sơ. Mời từng người qua email trong Nhân sự (không nhập mật khẩu).',
        ),
      if ((counts['buildingRents'] ?? 0) > 0)
        x.tr(
          'Building rents: enter the landlord, start date and due day in each building\'s "Hợp đồng thuê".',
          'Tiền thuê tòa nhà: nhập bên cho thuê, ngày bắt đầu và ngày trả trong "Hợp đồng thuê" của từng tòa nhà.',
        ),
      x.tr(
        'Payment methods are not in the old file: imported payments show "Other".',
        'File cũ không có hình thức thanh toán: các khoản đã nhập ghi "Khác".',
      ),
    ];
    return WsSection(
      title: x.tr('Good to know', 'Lưu ý'),
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: WsSpace.xs),
            child: Text('• $l', style: small),
          ),
      ],
    );
  }

  Widget _problems(FeeText x, Map<String, dynamic> data) {
    final list = (data['problems'] as List? ?? const [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final overlaps = (data['overlaps'] as List? ?? const [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final total = (data['problemCount'] as num?)?.toInt() ?? list.length;
    final overlapTotal =
        (data['overlapCount'] as num?)?.toInt() ?? overlaps.length;
    if (total == 0 && overlapTotal == 0) {
      return WsNotice(
        x.tr('Nothing to look at.', 'Không có gì cần xem lại.'),
        tone: WsTone.good,
      );
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in list) {
      groups.putIfAbsent('${p['code']}', () => []).add(p);
    }
    String stay(Map s) =>
        '${s['guest'] ?? ''} (${s['start'] ?? ''} – ${s['end'] ?? ''})';
    return WsSection(
      title: x.tr('To look at', 'Cần xem lại'),
      children: [
        for (final MapEntry(key: code, value: items) in groups.entries)
          ExpansionTile(
            key: ValueKey('import-problem-$code'),
            tilePadding: EdgeInsets.zero,
            title: Text('${_problemText(x, code)} (${items.length})'),
            children: [
              for (final p in items)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: WsSpace.xs),
                    child: Text(
                      _ref(p),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        if (overlapTotal > 0)
          ExpansionTile(
            key: const ValueKey('import-overlaps'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              x.tr(
                'Stays that overlap in one room ($overlapTotal): correct the file before importing',
                'Lượt thuê trùng giờ trong một phòng ($overlapTotal): sửa file trước khi nhập',
              ),
            ),
            children: [
              for (final o in overlaps)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: WsSpace.xs),
                    child: Text(
                      '${o['building']} · ${o['room']}: ${stay(o['a'] as Map)} ↔ ${stay(o['b'] as Map)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        if (total > list.length || overlapTotal > overlaps.length)
          Text(
            x.tr(
              'Only the first ones are listed.',
              'Chỉ liệt kê những dòng đầu.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context);
    final data = _result ?? _preview;
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          title: x.tr('Import from file', 'Nhập từ file'),
          help: x.tr(
            'Choose the .xlsx exported from the old app. You see everything before anything is created; importing the same file again adds nothing twice.',
            'Chọn file .xlsx xuất từ ứng dụng cũ. Bạn xem trước mọi thứ rồi mới tạo; nhập lại cùng file không tạo trùng.',
          ),
        ),
        if (_fileName != null) WsInfo(x.tr('File', 'File'), _fileName!),
        if (_busy || _saving) const LinearProgressIndicator(),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(_error!, key: const ValueKey('import-error')),
          ),
        if (data != null) ...[
          _counts(x, data),
          _problems(x, data),
          if (_result == null) _notes(x, data),
        ],
        if (_confirm && _result == null)
          WsNotice(
            x.tr(
              'Create these records now? Records already imported from this file are not changed.',
              'Tạo các dữ liệu này ngay? Dữ liệu đã nhập trước đó từ file này không bị thay đổi.',
            ),
            key: const ValueKey('import-confirm'),
            tone: WsTone.warning,
          ),
        if (_result != null && _sheetUrl == null)
          WsSection(
            title: 'Google Sheet',
            children: [
              Text(
                x.tr(
                  'Save the imported data as a new Google Sheet in your Drive (CanHo360 folder).',
                  'Lưu dữ liệu vừa nhập thành Google Sheet mới trong Drive của bạn (thư mục CanHo360).',
                ),
              ),
            ],
          ),
        if (_sheetUrl != null)
          WsNotice(
            x.tr(
              'Saved to Google Drive (CanHo360 folder).',
              'Đã lưu vào Google Drive (thư mục CanHo360).',
            ),
            key: const ValueKey('import-sheet-saved'),
            tone: WsTone.good,
          ),
        WsActions(
          children: [
            if (_result == null && !_confirm)
              OutlinedButton(
                key: const ValueKey('import-choose'),
                onPressed: _busy ? null : _choose,
                child: Text(
                  _fileName == null
                      ? x.tr('Choose file', 'Chọn file')
                      : x.tr('Other file', 'Chọn file khác'),
                ),
              ),
            if (_preview != null && _result == null && !_confirm)
              FilledButton(
                key: const ValueKey('import-start'),
                onPressed: _busy || (_preview?['overlapCount'] as num? ?? 0) > 0 ? null : () => setState(() => _confirm = true),
                child: Text(x.tr('Import', 'Nhập')),
              ),
            if (_confirm && _result == null) ...[
              TextButton(
                onPressed: _busy ? null : () => setState(() => _confirm = false),
                child: Text(x.tr('Cancel', 'Hủy')),
              ),
              FilledButton(
                key: const ValueKey('import-apply'),
                onPressed: _busy ? null : _apply,
                child: Text(x.tr('Import', 'Nhập')),
              ),
            ],
            if (_result != null && _sheetUrl == null)
              FilledButton(
                key: const ValueKey('import-save-sheet'),
                onPressed: _saving ? null : _saveSheet,
                child: Text(x.tr('Save Google Sheet', 'Lưu Google Sheet')),
              ),
            if (_sheetUrl != null && _sheetUrl!.isNotEmpty)
              OutlinedButton(
                key: const ValueKey('import-open-sheet'),
                onPressed: () => _open(_sheetUrl!),
                child: Text(x.tr('Open Sheet', 'Mở Sheet')),
              ),
          ],
        ),
      ],
    );
  }
}
