import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/organization_settings_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

String _text(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'title': ['Receiving accounts', 'Tài khoản nhận tiền'],
    'help': [
      'Bank or e-wallet accounts that deposits and payments can be received into. Cash is always available. Old payments keep the name they were saved with.',
      'Tài khoản ngân hàng hoặc ví điện tử dùng để nhận cọc và tiền phòng. Luôn có sẵn tiền mặt. Khoản thu cũ giữ tên đã lưu lúc đó.',
    ],
    'label': [
      'Account (e.g. Vietcombank 0123 – Nguyen Van A)',
      'Tài khoản (vd. Vietcombank 0123 – Nguyễn Văn A)',
    ],
    'add': ['Add account', 'Thêm tài khoản'],
    'list': ['Accounts', 'Danh sách tài khoản'],
    'remove': ['Remove', 'Xóa'],
    'save': ['Save', 'Lưu'],
    'saved': ['Saved.', 'Đã lưu.'],
    'empty': [
      'No accounts yet. Payments can still be received in cash.',
      'Chưa có tài khoản. Vẫn có thể nhận tiền mặt.',
    ],
    'readOnly': [
      'Only people with "Organization settings" can change this list.',
      'Chỉ người có quyền "Cài đặt tổ chức" mới sửa được danh sách này.',
    ],
    'error': [
      'Could not load or save. Try again.',
      'Không tải hoặc lưu được. Hãy thử lại.',
    ],
    'uncertain': [
      'The connection dropped. Press Save again to finish the same change.',
      'Mất kết nối. Bấm Lưu lần nữa để hoàn tất đúng thay đổi này.',
    ],
    'required': [
      'Enter a name for every account, or remove the empty line.',
      'Nhập tên cho từng tài khoản, hoặc xóa dòng trống.',
    ],
  };
  return labels[key]?[vi ? 1 : 0] ?? key;
}

/// Page name in the Settings section.
String paymentAccountsTitle(BuildContext context) => _text(context, 'title');

class _Row {
  final String id;
  final TextEditingController label;
  _Row(this.id, String text) : label = TextEditingController(text: text);
}

/// B8-lite: the organization's list of receiving accounts (Cài đặt).
class PaymentAccountsScreen extends StatefulWidget {
  final String organizationId;
  final OrganizationSettingsService? settings;
  const PaymentAccountsScreen({
    super.key,
    required this.organizationId,
    this.settings,
  });
  @override
  State<PaymentAccountsScreen> createState() => _PaymentAccountsScreenState();
}

class _PaymentAccountsScreenState extends State<PaymentAccountsScreen> {
  late final OrganizationSettingsService _service =
      widget.settings ?? OrganizationSettingsService();
  final _rows = <_Row>[];
  final _retired = <_Row>[];
  bool _busy = true, _canManage = false;
  String? _message;
  // Kept while a save is unconfirmed, so pressing Save again repeats it.
  String? _operation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in [..._rows, ..._retired]) {
      r.label.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final s = await _service.read(widget.organizationId);
      if (!mounted) return;
      setState(() {
        _retired.addAll(_rows);
        _rows
          ..clear()
          ..addAll(s.paymentAccounts.map((a) => _Row(a.id, a.label)));
        _canManage = s.canManage;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'error';
        });
      }
    }
  }

  Future<void> _save() async {
    final accounts = [
      for (final r in _rows) PaymentAccount(r.id, r.label.text.trim()),
    ];
    if (accounts.any((a) => a.label.isEmpty)) {
      setState(() => _message = 'required');
      return;
    }
    _operation ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.saveAccounts(
        widget.organizationId,
        accounts,
        operationId: _operation!,
      );
      _operation = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'saved';
      });
    } catch (e) {
      final transient =
          e is! FirebaseFunctionsException ||
          const {
            'unavailable',
            'internal',
            'deadline-exceeded',
            'unknown',
          }.contains(e.code);
      if (!transient) _operation = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _message = transient ? 'uncertain' : 'error';
        });
      }
    }
  }

  void _changed() {
    // Editing means a new change: a retry would now send different content.
    _operation = null;
    if (_message == 'saved') setState(() => _message = null);
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => _text(context, k);
    final theme = Theme.of(context);
    final editable = _canManage && !_busy;
    return WsPage(
      maxWidth: 720,
      children: [
        WsHeader(title: t('title'), help: t('help')),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          WsNotice(
            t(_message!),
            tone: _message == 'saved' ? WsTone.good : WsTone.warning,
          ),
        if (!_busy && !_canManage && _message == null) WsNotice(t('readOnly')),
        WsSection(
          title: t('list'),
          icon: Icons.account_balance_outlined,
          children: [
            if (_rows.isEmpty)
              Text(
                t('empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (final (i, r) in _rows.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : WsSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('account-${r.id}'),
                        controller: r.label,
                        enabled: editable,
                        maxLength: 80,
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(
                          labelText: t('label'),
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: t('remove'),
                      icon: const Icon(Icons.close),
                      onPressed: editable
                          ? () => setState(() {
                              _retired.add(_rows.removeAt(i));
                              _changed();
                            })
                          : null,
                    ),
                  ],
                ),
              ),
            if (_canManage && _rows.length < 20)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('account-add'),
                  onPressed: editable
                      ? () => setState(() {
                          _rows.add(
                            _Row(
                              const Uuid()
                                  .v4()
                                  .replaceAll('-', '')
                                  .substring(0, 16),
                              '',
                            ),
                          );
                          _changed();
                        })
                      : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t('add')),
                ),
              ),
          ],
        ),
        if (_canManage)
          WsActions(
            children: [
              FilledButton(
                key: const ValueKey('account-save'),
                onPressed: _busy ? null : _save,
                child: Text(t('save')),
              ),
            ],
          ),
      ],
    );
  }
}
