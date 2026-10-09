import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'back_steps.dart';
import 'problem_photos.dart';
import 'service_fee_text.dart' show FeeText, parseMinor, feeDate;
import 'workspace_page_scope.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

/// B7a technical problems (sự cố kỹ thuật) of one property: list, report,
/// details, edit, mark fixed (who, when, cost, optional paid expense in
/// "Thu chi") and reopen. "Room unavailable while open" stops new bookings,
/// new leases and moves into the room (server rule); existing bookings and
/// leases are only listed as a warning. B7b: photos in the owner's Google
/// Drive (problem_photos.dart).
class TechnicalProblemsScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;

  /// Chooses photos on the device; tests replace it.
  final Future<List<PickedPhoto>> Function(int max)? pickPhotos;

  /// From the calendar (C): open the report form for this room once loaded.
  final String? reportRoomId;

  /// From the calendar's "Báo sự cố" button (2026-10-05): open the report
  /// form once loaded; the room is chosen there.
  final bool startReport;

  /// Over the calendar: "Done" after saving closes the dialog.
  final VoidCallback? onClose;

  /// One room only (2026-10-04, from a booking or a lease): its problems, and
  /// reports go to that room.
  final String? onlyRoomId;
  const TechnicalProblemsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    this.pickPhotos,
    this.reportRoomId,
    this.startReport = false,
    this.onClose,
    this.onlyRoomId,
  });
  @override
  State<TechnicalProblemsScreen> createState() =>
      _TechnicalProblemsScreenState();
}

enum _View { list, report, detail, edit, fix, reopen, done }

class _TechnicalProblemsScreenState extends State<TechnicalProblemsScreen> {
  final _title = TextEditingController(),
      _description = TextEditingController();
  final _fixedBy = TextEditingController(),
      _fixedDate = TextEditingController();
  final _cost = TextEditingController(), _note = TextEditingController();
  Map<String, dynamic>? _data, _pending, _result;
  String _filter = 'open';
  String? _error, _problemId, _room, _method, _account, _formError;
  bool _busy = true, _saving = false, _block = false, _expense = false;
  _View _view = _View.list;
  int _generation = 0;
  bool _reportOpened = false;

  /// Photos chosen on the report form; uploaded once the problem is saved
  /// (2026-10-05, Tom: add photos while reporting).
  List<PickedPhoto> _draftPhotos = [], _uploadPhotos = [];
  bool _photosBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TechnicalProblemsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _view = _View.list;
      _pending = null;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _fixedBy,
      _fixedDate,
      _cost,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map> get _records => ((_data?['records'] as List?) ?? const [])
      .cast<Map>()
      .where(
        (r) => widget.onlyRoomId == null || r['roomId'] == widget.onlyRoomId,
      )
      .toList();
  List<Map> get _rooms => ((_data?['rooms'] as List?) ?? const [])
      .cast<Map>()
      .where((r) => widget.onlyRoomId == null || r['id'] == widget.onlyRoomId)
      .toList();
  List<Map> get _accounts =>
      ((_data?['accounts'] as List?) ?? const []).cast<Map>();
  late final MoneyForm _money = MoneyForm(OrganizationMoney.shared.forOrganization(widget.organizationId));
  String get _inputCurrency => _money.currency(_currency);
  String get _currency => '${_data?['currency'] ?? 'VND'}';
  bool get _canReport => _data?['canReport'] == true;
  bool get _canManage => _data?['canManage'] == true;
  bool get _canExpense => _data?['canExpense'] == true;
  String get _driveState => '${(_data?['drive'] as Map?)?['state'] ?? 'none'}';
  String get _uid => '${_data?['uid'] ?? ''}';
  Map? get _problem => _records.where((r) => r['id'] == _problemId).firstOrNull;
  bool get _locked => _saving || _pending != null;

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.technicalProblems({
        'action': 'list',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _busy = false;
        if (_problemId != null && _problem == null && _view != _View.done)
          _view = _View.list;
      });
      final room = widget.reportRoomId;
      if (!_reportOpened &&
          room != null &&
          _canReport &&
          _rooms.any((r) => r['id'] == room)) {
        _reportOpened = true;
        _open(_View.report);
        setState(() => _room = room);
      } else if (!_reportOpened && widget.startReport && _canReport) {
        _reportOpened = true;
        _open(_View.report);
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = _message(FeeText(context), e);
      });
    }
  }

  static const _keys = [
    'problem_currency_changed',
    'problem_block_needs_manager',
    'problem_changed',
    'problem_not_open',
    'problem_not_fixed',
    'problem_fixed_in_future',
    'problem_fixed_before_report',
    'problem_expense_needs_cost',
    'problem_expense_needs_method',
    'problem_expense_needs_permission',
    'problem_reopen_needs_reason',
    'problem_room_not_found',
    'problem_not_found',
    'problem_invalid_text',
    'problem_invalid_cost',
  ];

  String _message(FeeText x, Object e, {bool uncertain = false}) {
    switch (serverReason(e, _keys)) {
      case 'problem_currency_changed':
        return x.tr(
          'The currency changed. Close and reopen this form before entering the cost again.',
          'Tiền tệ đã thay đổi. Đóng và mở lại biểu mẫu trước khi nhập lại chi phí.',
        );
      case 'problem_block_needs_manager':
        return x.tr(
          'Only a property manager can stop renting the room.',
          'Chỉ quản lý tòa nhà mới được tạm ngừng cho thuê phòng.',
        );
      case 'problem_changed':
        return x.tr(
          'Someone else just changed this problem. Reload, then try again.',
          'Có người vừa thay đổi sự cố này. Tải lại rồi thử lại.',
        );
      case 'problem_not_open':
        return x.tr(
          'This problem is already marked fixed.',
          'Sự cố này đã được đánh dấu đã sửa.',
        );
      case 'problem_not_fixed':
        return x.tr('This problem is still open.', 'Sự cố này vẫn đang mở.');
      case 'problem_fixed_in_future':
        return x.tr(
          'The fix date cannot be after today.',
          'Ngày sửa không được sau hôm nay.',
        );
      case 'problem_fixed_before_report':
        return x.tr(
          'The fix date cannot be before the day it was reported.',
          'Ngày sửa không được trước ngày báo sự cố.',
        );
      case 'problem_expense_needs_cost':
        return x.tr(
          'Enter the cost to record it as an expense.',
          'Nhập chi phí để ghi vào Thu chi.',
        );
      case 'problem_expense_needs_method':
        return x.tr(
          'Choose how the cost was paid.',
          'Chọn cách đã trả chi phí.',
        );
      case 'problem_expense_needs_permission':
        return x.tr(
          'Recording an expense needs permission to collect payments.',
          'Ghi vào Thu chi cần quyền thu tiền.',
        );
      case 'problem_reopen_needs_reason':
        return x.tr('Write why it is reopened.', 'Ghi lý do mở lại.');
      case 'problem_room_not_found':
      case 'problem_not_found':
        return x.tr(
          'This room or problem no longer exists. Reload.',
          'Phòng hoặc sự cố này không còn. Hãy tải lại.',
        );
      case 'problem_invalid_text':
        return x.tr(
          'Enter a short title (up to 120 characters).',
          'Nhập tiêu đề ngắn (tối đa 120 ký tự).',
        );
      case 'problem_invalid_cost':
        return x.tr('Check the cost.', 'Kiểm tra lại chi phí.');
    }
    return x.error(e, uncertain: uncertain);
  }

  void _open(_View view, {String? problemId}) {
    setState(() {
      _view = view;
      _uploadPhotos = [];
      _formError = null;
      _result = null;
      if (problemId != null) _problemId = problemId;
      final p = _problem;
      if (view == _View.report) {
        _room = widget.onlyRoomId;
        _draftPhotos = [];
        _title.clear();
        _description.clear();
        _block = false;
      } else if (view == _View.edit && p != null) {
        _title.text = '${p['title']}';
        _description.text = '${p['description'] ?? ''}';
        _block = p['blocksRoom'] == true;
      } else if (view == _View.fix) {
        _fixedBy.clear();
        _fixedDate.text = '${_data?['today'] ?? ''}';
        _cost.clear();
        _note.clear();
        _expense = false;
        _method = null;
        _account = null;
      } else if (view == _View.reopen) {
        _note.clear();
      }
    });
  }

  void _back() {
    if (_locked) return;
    setState(() {
      _formError = null;
      _uploadPhotos = [];
      _view =
          _view == _View.detail || _view == _View.report || _view == _View.done
          ? _View.list
          : _View.detail;
    });
  }

  /// Checks the form; returns the command, or null after setting [_formError].
  Map<String, dynamic>? _command(FeeText x) {
    final base = {
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'operationId': const Uuid().v4(),
    };
    final p = _problem;
    String? problem;
    Map<String, dynamic>? command;
    switch (_view) {
      case _View.report:
      case _View.edit:
        if (_view == _View.report && _room == null) {
          problem = x.tr('Choose the room.', 'Chọn phòng.');
        } else if (_title.text.trim().isEmpty) {
          problem = x.tr('Enter what is broken.', 'Nhập hỏng gì.');
        } else {
          command = {
            ...base,
            'action': _view == _View.report ? 'report' : 'update',
            if (_view == _View.report) 'roomId': _room,
            if (_view == _View.edit) 'problemId': p!['id'],
            if (_view == _View.edit) 'revision': p!['revision'],
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'blocksRoom': _canManage && _block,
          };
        }
      case _View.fix:
        final costText = _cost.text.trim();
        final cost = costText.isEmpty ? null : appParseMoney(_cost.text, _inputCurrency);
        if (_fixedBy.text.trim().isEmpty) {
          problem = x.tr('Enter who fixed it.', 'Nhập ai đã sửa.');
        } else if (!feeDate(_fixedDate.text.trim())) {
          problem = x.tr(
            'Enter the date as YYYY-MM-DD.',
            'Nhập ngày theo dạng YYYY-MM-DD.',
          );
        } else if (costText.isNotEmpty && cost == null) {
          problem = x.tr('Check the cost.', 'Kiểm tra lại chi phí.');
        } else if (_expense && !(cost != null && cost > 0)) {
          problem = x.tr(
            'Enter the cost to record it as an expense.',
            'Nhập chi phí để ghi vào Thu chi.',
          );
        } else if (_expense && _method == null) {
          problem = x.tr(
            'Choose how the cost was paid.',
            'Chọn cách đã trả chi phí.',
          );
        } else {
          command = {
            ...base,
            'action': 'fix',
            'problemId': p!['id'],
            'revision': p['revision'],
            'fixedByName': _fixedBy.text.trim(),
            'fixedDate': _fixedDate.text.trim(),
            'costMinor': cost,
            'inputCurrency': _inputCurrency,
            'recordExpense': _expense,
            'paymentMethod': _expense ? _method : null,
            'accountId': _expense && _method == 'bankTransfer'
                ? _account
                : null,
            'note': _note.text.trim(),
          };
        }
      case _View.reopen:
        if (_note.text.trim().isEmpty) {
          problem = x.tr('Write why it is reopened.', 'Ghi lý do mở lại.');
        } else {
          command = {
            ...base,
            'action': 'reopen',
            'problemId': p!['id'],
            'revision': p['revision'],
            'note': _note.text.trim(),
          };
        }
      default:
        break;
    }
    if (problem != null) setState(() => _formError = problem);
    return command;
  }

  Future<void> _save() async {
    final x = FeeText(context);
    final payload = _pending ?? _command(x);
    if (payload == null) return;
    setState(() {
      _saving = true;
      _formError = null;
      _pending = payload;
    });
    try {
      final result = await widget.service.technicalProblems(payload);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _pending = null;
        _result = result;
        _problemId = '${result['problemId']}';
        // Photos chosen on the report form go up now (shown on "Saved").
        if (payload['action'] == 'report') {
          _uploadPhotos = _draftPhotos;
          _draftPhotos = [];
        }
        _view = _View.done;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      final uncertain = FeeText.uncertain(e);
      setState(() {
        _saving = false;
        if (!uncertain) _pending = null;
        _formError = _message(x, e, uncertain: uncertain);
      });
    }
  }

  String _date(Object? v) => v == null ? '' : '$v';

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context);
    final page = switch (_view) {
      _View.list => _list(x),
      _View.report || _View.edit => _textForm(x),
      _View.detail => _detail(x),
      _View.fix => _fixForm(x),
      _View.reopen => _reopenForm(x),
      _View.done => _done(x),
    };
    return _view == _View.list ? page : BackStep(onBack: _back, child: page);
  }

  Widget _list(FeeText x) {
    final open = _records.where((r) => r['status'] == 'open').length;
    final shown = _records
        .where((r) => _filter == 'all' || r['status'] == _filter)
        .toList();
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          // In a dialog its title names the room's problems.
          title: DialogPageScope.contains(context)
              ? ''
              : x.tr('Technical problems', 'Sự cố kỹ thuật'),
          help: x.tr(
            'Report something broken in a room. A manager can stop renting the room until it is fixed.',
            'Báo hỏng hóc trong phòng. Quản lý có thể tạm ngừng cho thuê phòng đến khi sửa xong.',
          ),
          actions: [
            if (_canReport)
              FilledButton.icon(
                key: const ValueKey('problems-report'),
                onPressed: _busy ? null : () => _open(_View.report),
                icon: const Icon(Icons.add),
                label: Text(x.tr('Report', 'Báo sự cố')),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          WsNotice(
            _error!,
            action: TextButton(
              onPressed: _load,
              child: Text(x.tr('Reload', 'Tải lại')),
            ),
          ),
        if (_data != null) ...[
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              for (final f in const ['open', 'fixed', 'all'])
                ChoiceChip(
                  key: ValueKey('problem-filter-$f'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  label: Text(switch (f) {
                    'open' => '${x.tr('Open', 'Đang mở')} ($open)',
                    'fixed' => x.tr('Fixed', 'Đã sửa'),
                    _ => x.tr('All', 'Tất cả'),
                  }),
                ),
            ],
          ),
          const SizedBox(height: WsSpace.md),
          if (shown.isEmpty)
            WsEmpty(
              icon: Icons.build_outlined,
              message: _filter == 'open'
                  ? x.tr('No open problems.', 'Không có sự cố đang mở.')
                  : x.tr('Nothing here yet.', 'Chưa có sự cố nào.'),
            ),
          for (final r in shown)
            WsRecord(
              tapKey: ValueKey('problem-${r['id']}'),
              title: '${r['roomNumber']} · ${r['title']}',
              pill: r['status'] == 'open'
                  ? WsPill(x.tr('Open', 'Đang mở'), tone: WsTone.warning)
                  : WsPill(x.tr('Fixed', 'Đã sửa'), tone: WsTone.good),
              tone: r['status'] == 'open' && r['blocksRoom'] == true
                  ? WsTone.bad
                  : null,
              details: [
                if (r['status'] == 'open' && r['blocksRoom'] == true)
                  x.tr(
                    'Room not rented until fixed',
                    'Phòng tạm ngừng cho thuê',
                  ),
                '${x.tr('Reported', 'Báo')}: ${r['reportedByName']} · ${_date(r['reportedLocalDate'])}'
                    '${((r['photos'] as List?) ?? const []).isEmpty ? '' : ' · ${(r['photos'] as List).length} ${x.tr('photos', 'ảnh')}'}',
                if (r['status'] == 'fixed')
                  '${x.tr('Fixed', 'Sửa')}: ${r['fixedByName']} · ${_date(r['fixedLocalDate'])}${r['costMinor'] == null ? '' : ' · ${x.money(r['costMinor'] as num, '${r['currency']}')}'}',
              ],
              onTap: () => _open(_View.detail, problemId: '${r['id']}'),
            ),
        ],
      ],
    );
  }

  Widget _header(FeeText x, String title) => WsHeader(
    back: WsBack(
      label: x.tr('Technical problems', 'Sự cố kỹ thuật'),
      onPressed: _locked ? null : _back,
    ),
    title: title,
  );

  Widget _formEnd(FeeText x, String saveLabel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_formError != null)
        Semantics(liveRegion: true, child: WsNotice(_formError!)),
      WsActions(
        children: [
          TextButton(
            onPressed: _locked ? null : _back,
            child: Text(x.tr('Cancel', 'Hủy')),
          ),
          FilledButton(
            key: const ValueKey('problem-save'),
            onPressed: _saving ? null : _save,
            child: Text(
              _pending != null && !_saving
                  ? x.tr('Retry', 'Thử lại')
                  : saveLabel,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _textForm(FeeText x) {
    final report = _view == _View.report;
    final p = _problem;
    return WsPage(
      maxWidth: 760,
      children: [
        _header(
          x,
          report
              ? x.tr('Report a problem', 'Báo sự cố')
              : x.tr('Edit problem', 'Sửa thông tin sự cố'),
        ),
        WsSection(
          title: x.tr('Room', 'Phòng'),
          children: [
            if (report)
              Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                children: [
                  for (final r in _rooms)
                    ChoiceChip(
                      key: ValueKey('problem-room-${r['id']}'),
                      selected: _room == r['id'],
                      onSelected: _locked
                          ? null
                          : (_) => setState(() => _room = '${r['id']}'),
                      label: Text('${r['roomNumber']}'),
                    ),
                ],
              )
            else
              Text('${p?['roomNumber'] ?? ''}'),
            if (report && _rooms.any((r) => r['blocked'] == true))
              Padding(
                padding: const EdgeInsets.only(top: WsSpace.sm),
                child: Text(
                  '${x.tr('Not rented now (open problem)', 'Đang tạm ngừng cho thuê')}: ${_rooms.where((r) => r['blocked'] == true).map((r) => r['roomNumber']).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        WsSection(
          title: x.tr('Problem', 'Sự cố'),
          children: [
            TextFormField(
              key: const ValueKey('problem-title'),
              controller: _title,
              enabled: !_locked,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: x.tr('What is broken', 'Hỏng gì'),
                hintText: x.tr(
                  'e.g. Air conditioner leaks',
                  'VD: Máy lạnh chảy nước',
                ),
              ),
            ),
            const SizedBox(height: WsSpace.sm),
            TextFormField(
              key: const ValueKey('problem-description'),
              controller: _description,
              enabled: !_locked,
              maxLength: 2000,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: x.tr(
                  'Details (optional)',
                  'Mô tả thêm (không bắt buộc)',
                ),
                alignLabelWithHint: true,
              ),
            ),
            if (_canManage)
              CheckboxListTile(
                key: const ValueKey('problem-block'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _block,
                onChanged: _locked
                    ? null
                    : (v) => setState(() => _block = v ?? false),
                title: Text(
                  x.tr(
                    'Do not rent the room until fixed',
                    'Tạm ngừng cho thuê phòng đến khi sửa xong',
                  ),
                ),
                subtitle: Text(
                  x.tr(
                    'No new booking or lease can start in this room. Existing ones are kept and listed.',
                    'Không nhận đặt phòng hay hợp đồng mới cho phòng này. Đặt phòng đang có vẫn giữ và được liệt kê.',
                  ),
                ),
              ),
          ],
        ),
        if (report && _driveState == 'connected') _draftPhotoSection(x),
        _formEnd(x, report ? x.tr('Send', 'Gửi') : x.tr('Save', 'Lưu')),
      ],
    );
  }

  /// Photos for a new report, kept on the device until it is sent.
  Widget _draftPhotoSection(FeeText x) => WsSection(
    title:
        '${x.tr('Photos', 'Ảnh')} (${_draftPhotos.length}/$maxProblemPhotos)',
    children: [
      Wrap(
        spacing: WsSpace.sm,
        runSpacing: WsSpace.sm,
        children: [
          for (var i = 0; i < _draftPhotos.length; i++)
            Stack(
              key: ValueKey('problem-draft-photo-$i'),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _draftPhotos[i].bytes,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 96,
                      height: 96,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: x.tr('Remove', 'Bỏ ảnh'),
                    onPressed: _locked
                        ? null
                        : () => setState(
                            () => _draftPhotos = [..._draftPhotos]..removeAt(i),
                          ),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
        ],
      ),
      if (_draftPhotos.length < maxProblemPhotos)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton.icon(
            key: const ValueKey('problem-draft-add-photos'),
            onPressed: _locked ? null : _pickDraftPhotos,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(x.tr('Add photos', 'Thêm ảnh')),
          ),
        ),
    ],
  );

  Future<void> _pickDraftPhotos() async {
    final pick = widget.pickPhotos ?? pickProblemPhotos;
    try {
      final picked = await pick(maxProblemPhotos - _draftPhotos.length);
      if (!mounted || picked.isEmpty) return;
      setState(
        () => _draftPhotos = [
          ..._draftPhotos,
          ...picked,
        ].take(maxProblemPhotos).toList(),
      );
    } catch (_) {
      if (!mounted) return;
      final x = FeeText(context);
      setState(
        () => _formError = x.tr(
          'Could not open the photos.',
          'Không mở được ảnh.',
        ),
      );
    }
  }

  Widget _detail(FeeText x) {
    final p = _problem;
    if (p == null) {
      return WsPage(
        maxWidth: 760,
        children: [
          _header(x, x.tr('Problem', 'Sự cố')),
          if (_busy) const LinearProgressIndicator(),
        ],
      );
    }
    final open = p['status'] == 'open';
    final occupant = p['occupant'] as Map?;
    final blocked = p['blocksRoom'] == true;
    return WsPage(
      maxWidth: 760,
      children: [
        _header(x, '${p['roomNumber']} · ${p['title']}'),
        WsSection(
          title: x.tr('Details', 'Thông tin'),
          children: [
            WsInfo(
              x.tr('Status', 'Trạng thái'),
              open ? x.tr('Open', 'Đang mở') : x.tr('Fixed', 'Đã sửa'),
            ),
            if ('${p['description'] ?? ''}'.isNotEmpty)
              WsInfo(x.tr('Details', 'Mô tả'), '${p['description']}'),
            WsInfo(
              x.tr('Reported by', 'Người báo'),
              '${p['reportedByName']} · ${_date(p['reportedLocalDate'])}',
            ),
            if (occupant != null)
              WsInfo(
                occupant['kind'] == 'lease'
                    ? x.tr('Tenant then', 'Người thuê lúc báo')
                    : x.tr('Guest then', 'Khách lúc báo'),
                '${occupant['name']}',
              ),
            WsInfo(
              x.tr('Room not rented', 'Tạm ngừng cho thuê'),
              !blocked
                  ? x.tr('No', 'Không')
                  : open
                  ? x.tr('Yes, until fixed', 'Có, đến khi sửa xong')
                  : x.tr('No longer', 'Đã cho thuê lại'),
            ),
            if (!open) ...[
              WsInfo(
                x.tr('Fixed by', 'Người sửa'),
                '${p['fixedByName']} · ${_date(p['fixedLocalDate'])}',
              ),
              WsInfo(
                x.tr('Cost', 'Chi phí'),
                p['costMinor'] == null
                    ? '—'
                    : x.money(p['costMinor'] as num, '${p['currency']}'),
              ),
            ],
            if (p['expenseId'] != null)
              WsInfo(
                x.tr('Expense', 'Thu chi'),
                x.tr(
                  'Recorded as a paid expense',
                  'Đã ghi là khoản chi đã trả',
                ),
              ),
            if ('${p['note'] ?? ''}'.isNotEmpty)
              WsInfo(x.tr('Note', 'Ghi chú'), '${p['note']}'),
          ],
        ),
        ProblemPhotos(
          key: ValueKey('photos-${p['id']}'),
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          problemId: '${p['id']}',
          photos: ((p['photos'] as List?) ?? const []).cast<Map>(),
          driveState: _driveState,
          canAdd: _canManage || (_canReport && open),
          canRemove: (photo) =>
              _canManage || (open && photo['addedBy'] == _uid),
          service: widget.service,
          pick: widget.pickPhotos ?? pickProblemPhotos,
          onChanged: _load,
        ),
        if (_canManage)
          WsActions(
            children: [
              if (open) ...[
                OutlinedButton(
                  key: const ValueKey('problem-edit'),
                  onPressed: () => _open(_View.edit),
                  child: Text(x.tr('Edit', 'Sửa thông tin')),
                ),
                FilledButton(
                  key: const ValueKey('problem-fix'),
                  onPressed: () => _open(_View.fix),
                  child: Text(x.tr('Mark fixed', 'Đã sửa xong')),
                ),
              ] else
                OutlinedButton(
                  key: const ValueKey('problem-reopen'),
                  onPressed: () => _open(_View.reopen),
                  child: Text(x.tr('Reopen', 'Mở lại')),
                ),
            ],
          ),
      ],
    );
  }

  Widget _fixForm(FeeText x) {
    final p = _problem;
    final small = Theme.of(context).textTheme.bodySmall;
    return WsPage(
      maxWidth: 760,
      children: [
        _header(x, x.tr('Mark fixed', 'Đã sửa xong')),
        WsSection(
          title: '${p?['roomNumber'] ?? ''} · ${p?['title'] ?? ''}',
          children: [
            TextFormField(
              key: const ValueKey('problem-fixed-by'),
              controller: _fixedBy,
              enabled: !_locked,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: x.tr(
                  'Fixed by (person or company)',
                  'Người sửa (người hoặc công ty)',
                ),
              ),
            ),
            const SizedBox(height: WsSpace.sm),
            TextFormField(
              key: const ValueKey('problem-fixed-date'),
              controller: _fixedDate,
              enabled: !_locked,
              decoration: InputDecoration(
                labelText: x.tr(
                  'Fixed on (YYYY-MM-DD)',
                  'Ngày sửa (YYYY-MM-DD)',
                ),
              ),
            ),
            const SizedBox(height: WsSpace.sm),
            TextFormField(
              key: const ValueKey('problem-cost'),
              controller: _cost,
              enabled: !_locked,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _inputCurrency == 'USD',
              ),
              inputFormatters: appMoneyInput(_inputCurrency),
              decoration: InputDecoration(
                labelText:
                    '${x.tr('Cost (optional)', 'Chi phí (không bắt buộc)')} ($_inputCurrency)',
              ),
            ),
            if (_canExpense) ...[
              CheckboxListTile(
                key: const ValueKey('problem-expense'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _expense,
                onChanged: _locked
                    ? null
                    : (v) => setState(() => _expense = v ?? false),
                title: Text(
                  x.tr(
                    'Record as a paid expense',
                    'Ghi vào Thu chi là khoản chi đã trả',
                  ),
                ),
                subtitle: Text(
                  x.tr(
                    "Shown with the property's invoices and expenses.",
                    'Hiện cùng hóa đơn và chi phí của tòa nhà.',
                  ),
                ),
              ),
              if (_expense) ...[
                Wrap(
                  spacing: WsSpace.sm,
                  runSpacing: WsSpace.sm,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('problem-method-cash'),
                      selected: _method == 'cash',
                      onSelected: _locked
                          ? null
                          : (_) => setState(() => _method = 'cash'),
                      label: Text(x.tr('Cash', 'Tiền mặt')),
                    ),
                    ChoiceChip(
                      key: const ValueKey('problem-method-bank'),
                      selected: _method == 'bankTransfer',
                      onSelected: _locked
                          ? null
                          : (_) => setState(() => _method = 'bankTransfer'),
                      label: Text(x.tr('Bank transfer', 'Chuyển khoản')),
                    ),
                  ],
                ),
                if (_method == 'bankTransfer' && _accounts.isNotEmpty) ...[
                  const SizedBox(height: WsSpace.sm),
                  Wrap(
                    spacing: WsSpace.sm,
                    runSpacing: WsSpace.sm,
                    children: [
                      for (final a in _accounts)
                        ChoiceChip(
                          key: ValueKey('problem-account-${a['id']}'),
                          selected: _account == a['id'],
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _account = '${a['id']}'),
                          label: Text('${a['label']}'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: WsSpace.sm),
              ],
            ],
            const SizedBox(height: WsSpace.md),
            TextFormField(
              key: const ValueKey('problem-note'),
              controller: _note,
              enabled: !_locked,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: x.tr('Note (optional)', 'Ghi chú (không bắt buộc)'),
                alignLabelWithHint: true,
              ),
            ),
            if (p?['blocksRoom'] == true)
              Text(
                x.tr(
                  'The room can be rented again once this is saved.',
                  'Lưu xong, phòng được cho thuê lại.',
                ),
                style: small,
              ),
          ],
        ),
        _formEnd(x, x.tr('Save', 'Lưu')),
      ],
    );
  }

  Widget _reopenForm(FeeText x) {
    final p = _problem;
    final small = Theme.of(context).textTheme.bodySmall;
    return WsPage(
      maxWidth: 760,
      children: [
        _header(x, x.tr('Reopen', 'Mở lại sự cố')),
        WsSection(
          title: '${p?['roomNumber'] ?? ''} · ${p?['title'] ?? ''}',
          children: [
            TextFormField(
              key: const ValueKey('problem-note'),
              controller: _note,
              enabled: !_locked,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: x.tr('Why is it reopened', 'Lý do mở lại'),
                alignLabelWithHint: true,
              ),
            ),
            if (p?['blocksRoom'] == true)
              Text(
                x.tr(
                  'The room stops taking new bookings and leases again.',
                  'Phòng lại tạm ngừng nhận đặt phòng và hợp đồng mới.',
                ),
                style: small,
              ),
            if (p?['expenseId'] != null)
              Text(
                x.tr(
                  'The recorded expense stays in Thu chi.',
                  'Khoản chi đã ghi vẫn giữ trong Thu chi.',
                ),
                style: small,
              ),
          ],
        ),
        _formEnd(x, x.tr('Reopen', 'Mở lại')),
      ],
    );
  }

  Widget _done(FeeText x) {
    final warnings = ((_result?['warnings'] as List?) ?? const []).cast<Map>();
    return WsPage(
      maxWidth: 760,
      children: [
        _header(x, x.tr('Technical problems', 'Sự cố kỹ thuật')),
        WsNotice(
          _result?['expenseId'] != null
              ? x.tr(
                  'Saved. The cost is recorded in Thu chi.',
                  'Đã lưu. Chi phí đã ghi vào Thu chi.',
                )
              : x.tr('Saved.', 'Đã lưu.'),
          key: const ValueKey('problem-done'),
          tone: WsTone.good,
        ),
        if (warnings.isNotEmpty)
          WsNotice(
            [
              x.tr(
                'The room is not rented until fixed. These stay as they are; contact them if needed:',
                'Phòng tạm ngừng cho thuê đến khi sửa xong. Các khách sau vẫn giữ nguyên, hãy liên hệ nếu cần:',
              ),
              for (final w in warnings)
                '• ${w['kind'] == 'lease' ? x.tr('Lease', 'Hợp đồng') : x.tr('Booking', 'Đặt phòng')} ${w['name']}: ${w['start'] ?? ''}${w['end'] == null ? '' : ' – ${w['end']}'}',
            ].join('\n'),
            key: const ValueKey('problem-warnings'),
            tone: WsTone.warning,
          ),
        // The photos chosen while reporting, uploading now.
        if (_uploadPhotos.isNotEmpty && _problemId != null)
          ProblemPhotos(
            key: ValueKey('photos-done-$_problemId'),
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            problemId: _problemId!,
            photos: ((_problem?['photos'] as List?) ?? const []).cast<Map>(),
            driveState: _driveState,
            canAdd: false,
            canRemove: (_) => false,
            service: widget.service,
            pick: widget.pickPhotos ?? pickProblemPhotos,
            initial: _uploadPhotos,
            onBusy: (busy) {
              if (mounted) setState(() => _photosBusy = busy);
            },
            onChanged: _load,
          ),
        WsActions(
          children: [
            OutlinedButton(
              // Wait for the photos still going up (2026-10-05).
              onPressed: _photosBusy ? null : () => _open(_View.detail),
              child: Text(x.tr('Open the problem', 'Xem sự cố')),
            ),
            FilledButton(
              key: const ValueKey('problem-finish'),
              onPressed: _photosBusy
                  ? null
                  : widget.onClose ?? () => setState(() => _view = _View.list),
              child: Text(x.tr('Done', 'Xong')),
            ),
          ],
        ),
      ],
    );
  }
}
