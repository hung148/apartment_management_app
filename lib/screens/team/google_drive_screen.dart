import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../services/drive_connect.dart';
import '../../services/local_emulators.dart';
import '../../services/team_service.dart';
import 'service_fee_text.dart' show FeeText;
import 'ws_ui.dart';

/// B7b: Google Drive. The owner connects one Google account; photos of
/// technical problems and meters, and the import's Google Sheet, are saved in
/// its Drive ("CanHo360" folder). The app only sees files it created (Google's
/// drive.file permission).
///
/// 2026-10-06 (Tom): opened from the home screen without an organization —
/// connected once for every organization the owner owns. With an
/// organizationId it shows (and, for an older connection, manages) that
/// organization's Drive.
class GoogleDriveScreen extends StatefulWidget {
  final String? organizationId;
  final TeamService service;

  /// Opens Google's pop-up; tests and the local emulator replace it.
  final Future<String> Function(String clientId)? requestCode;
  const GoogleDriveScreen({
    super.key,
    this.organizationId,
    required this.service,
    this.requestCode,
  });
  @override
  State<GoogleDriveScreen> createState() => _GoogleDriveScreenState();
}

class _GoogleDriveScreenState extends State<GoogleDriveScreen> {
  Map<String, dynamic>? _data;
  String? _error, _actionError;
  bool _busy = true, _working = false, _confirmDisconnect = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.requestCode == null && !localEmulators)
      prepareDriveConnect().catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant GoogleDriveScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service)
      _load();
  }

  String get _state => '${_data?['state'] ?? 'none'}';
  bool get _canConnect => _data?['canConnect'] == true;

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.googleDrive({
        'action': 'status',
        if (widget.organizationId != null)
          'organizationId': widget.organizationId,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = _message(FeeText(context), e);
      });
    }
  }

  static const _keys = [
    'drive_scope_missing',
    'drive_no_offline_access',
    'drive_connect_failed',
    'drive_not_configured',
    'drive_access_denied',
    'drive_unavailable',
  ];

  String _message(FeeText x, Object e) {
    if (e is DriveConnectError) {
      return switch (e.reason) {
        'popup_failed_to_open' => x.tr(
          'The browser blocked the Google window. Allow pop-ups for this site, then try again.',
          'Trình duyệt đã chặn cửa sổ Google. Hãy cho phép cửa sổ bật lên cho trang này rồi thử lại.',
        ),
        'script' => x.tr(
          'Could not reach Google. Check the internet connection, then try again.',
          'Không kết nối được tới Google. Kiểm tra mạng rồi thử lại.',
        ),
        'unsupported' => x.tr(
          'Connect Google Drive from the web app on a computer.',
          'Hãy kết nối Google Drive từ ứng dụng web trên máy tính.',
        ),
        _ => x.tr(
          'Google Drive was not connected.',
          'Chưa kết nối Google Drive.',
        ),
      };
    }
    switch (serverReason(e, _keys)) {
      case 'drive_scope_missing':
        return x.tr(
          'Tick the Google Drive permission in the Google window, then try again.',
          'Hãy đánh dấu quyền Google Drive trong cửa sổ của Google rồi thử lại.',
        );
      case 'drive_no_offline_access':
        return x.tr(
          'Google did not give lasting access. Open myaccount.google.com/permissions, remove CanHo360, then connect again.',
          'Google chưa cấp quyền lâu dài. Vào myaccount.google.com/permissions, gỡ CanHo360, rồi kết nối lại.',
        );
      case 'drive_connect_failed':
        return x.tr(
          'Connecting did not work. Try again.',
          'Kết nối không thành công. Hãy thử lại.',
        );
      case 'drive_not_configured':
        // The server's short reason, so a setup problem can be fixed without
        // the function log (2026-10-05).
        final details = e is FirebaseFunctionsException ? e.details : null;
        final why = details is Map ? '${details['why'] ?? ''}'.trim() : '';
        return x.tr(
              'Google Drive is not set up for this server yet.',
              'Máy chủ này chưa được cài đặt Google Drive.',
            ) +
            (why.isEmpty ? '' : ' ($why)');
      case 'drive_access_denied':
        return x.tr(
          'Only someone with the "Connect Google Drive" permission can do this.',
          'Chỉ người có quyền "Kết nối Google Drive" mới làm được việc này.',
        );
      case 'drive_unavailable':
        return x.tr(
          'Google Drive did not answer. Try again in a moment.',
          'Google Drive chưa phản hồi. Thử lại sau ít phút.',
        );
    }
    return x.error(e);
  }

  Future<void> _connect() async {
    final x = FeeText(context);
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final clientId = '${_data?['clientId'] ?? ''}';
      if (clientId.isEmpty) throw const DriveConnectError('not_configured');
      final request =
          widget.requestCode ??
          (localEmulators
              ? (String _) async => 'local-owner@canho.test'
              : requestDriveCode);
      final code = await request(clientId);
      final data = await widget.service.googleDrive({
        'action': 'connect',
        if (widget.organizationId != null)
          'organizationId': widget.organizationId,
        'code': code,
      });
      if (!mounted) return;
      setState(() {
        _data = data;
        _working = false;
      });
    } catch (e) {
      if (!mounted) return;
      final closed =
          e is DriveConnectError &&
          ['popup_closed', 'access_denied'].contains(e.reason);
      setState(() {
        _working = false;
        _actionError = closed
            ? null
            : e is DriveConnectError && e.reason == 'not_configured'
            ? x.tr(
                'Google Drive is not set up for this server yet. (app: no client id)',
                'Máy chủ này chưa được cài đặt Google Drive. (app: no client id)',
              )
            : _message(x, e);
      });
    }
  }

  Future<void> _disconnect() async {
    final x = FeeText(context);
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final data = await widget.service.googleDrive({
        'action': 'disconnect',
        if (widget.organizationId != null)
          'organizationId': widget.organizationId,
      });
      if (!mounted) return;
      setState(() {
        _data = data;
        _working = false;
        _confirmDisconnect = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _actionError = _message(x, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context);
    final small = Theme.of(context).textTheme.bodySmall;
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          title: 'Google Drive',
          help: widget.organizationId == null
              ? x.tr(
                  'Connect once for every organization you own. Problem and meter photos and the import\'s Google Sheet are saved in your Google Drive, in the "CanHo360" folder.',
                  'Kết nối một lần cho mọi tổ chức bạn sở hữu. Ảnh sự cố, ảnh đồng hồ điện nước và Google Sheet khi nhập dữ liệu được lưu vào Google Drive của bạn, trong thư mục "CanHo360".',
                )
              : x.tr(
                  'Photos of technical problems are saved in your Google Drive, in the "CanHo360" folder.',
                  'Ảnh sự cố kỹ thuật được lưu vào Google Drive của bạn, trong thư mục "CanHo360".',
                ),
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
        if (_data != null)
          WsSection(
            title: x.tr('Connection', 'Kết nối'),
            children: [
              if (_state == 'connected') ...[
                WsInfo(
                  x.tr('Status', 'Trạng thái'),
                  x.tr('Connected', 'Đã kết nối'),
                ),
                WsInfo(
                  x.tr('Google account', 'Tài khoản Google'),
                  '${_data?['email'] ?? ''}',
                ),
                if ('${_data?['connectedByName'] ?? ''}'.isNotEmpty)
                  WsInfo(
                    x.tr('Connected by', 'Người kết nối'),
                    '${_data?['connectedByName']}',
                  ),
              ] else if (_state == 'needsReconnect') ...[
                WsNotice(
                  x.tr(
                    'Google stopped the access (for example it was removed in the Google account). Connect again to add and view photos.',
                    'Google đã dừng quyền truy cập (ví dụ đã gỡ trong tài khoản Google). Hãy kết nối lại để thêm và xem ảnh.',
                  ),
                  key: const ValueKey('drive-reconnect-notice'),
                  tone: WsTone.warning,
                ),
                if ('${_data?['email'] ?? ''}'.isNotEmpty)
                  WsInfo(
                    x.tr('Google account', 'Tài khoản Google'),
                    '${_data?['email']}',
                  ),
              ] else ...[
                WsInfo(
                  x.tr('Status', 'Trạng thái'),
                  x.tr('Not connected', 'Chưa kết nối'),
                ),
                Text(
                  x.tr(
                    'The app only sees the files it creates in your Drive, nothing else.',
                    'Ứng dụng chỉ thấy các tệp do nó tạo trong Drive của bạn, không thấy gì khác.',
                  ),
                  style: small,
                ),
              ],
              if (!_canConnect)
                Padding(
                  padding: const EdgeInsets.only(top: WsSpace.sm),
                  child: Text(
                    x.tr(
                      'The owner connects Google Drive on the home screen (Google Drive button).',
                      'Chủ sở hữu kết nối Google Drive ở màn hình chính (nút Google Drive).',
                    ),
                    style: small,
                  ),
                ),
              if (_confirmDisconnect)
                WsNotice(
                  x.tr(
                    'Photos already saved stay in your Drive, but the app cannot show them until you connect the same Google account again. New photos cannot be added.',
                    'Ảnh đã lưu vẫn còn trong Drive của bạn, nhưng ứng dụng không hiện được cho đến khi kết nối lại cùng tài khoản Google. Không thêm được ảnh mới.',
                  ),
                  key: const ValueKey('drive-disconnect-warning'),
                  tone: WsTone.warning,
                ),
            ],
          ),
        if (_actionError != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(_actionError!, key: const ValueKey('drive-error')),
          ),
        if (_data != null && _canConnect)
          WsActions(
            children: [
              if (_state == 'connected' && !_confirmDisconnect)
                OutlinedButton(
                  key: const ValueKey('drive-disconnect'),
                  onPressed: _working
                      ? null
                      : () => setState(() => _confirmDisconnect = true),
                  child: Text(x.tr('Disconnect', 'Ngắt kết nối')),
                ),
              if (_confirmDisconnect) ...[
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() => _confirmDisconnect = false),
                  child: Text(x.tr('Cancel', 'Hủy')),
                ),
                FilledButton(
                  key: const ValueKey('drive-disconnect-confirm'),
                  onPressed: _working ? null : _disconnect,
                  child: Text(x.tr('Disconnect', 'Ngắt kết nối')),
                ),
              ],
              if (_state != 'connected')
                FilledButton.icon(
                  key: const ValueKey('drive-connect'),
                  onPressed: _working ? null : _connect,
                  icon: const Icon(Icons.add_to_drive),
                  label: Text(
                    _state == 'needsReconnect'
                        ? x.tr('Connect again', 'Kết nối lại')
                        : x.tr('Connect', 'Kết nối'),
                  ),
                ),
            ],
          ),
        if (_working) const LinearProgressIndicator(),
      ],
    );
  }
}
