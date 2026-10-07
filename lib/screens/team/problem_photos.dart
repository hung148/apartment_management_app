import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'service_fee_text.dart' show FeeText;
import 'ws_ui.dart';

/// One photo chosen on the device, before upload.
class PickedPhoto {
  final Uint8List bytes;
  final String name;
  const PickedPhoto(this.bytes, this.name);
}

const int maxProblemPhotos = 6, maxPhotoBytes = 2 * 1024 * 1024;

/// JPEG / PNG / WebP by their first bytes (the name or browser type can lie).
String? photoType(Uint8List b) {
  if (b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff)
    return 'image/jpeg';
  if (b.length > 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47)
    return 'image/png';
  if (b.length > 12 &&
      ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/// Phone/computer gallery, made smaller (long side 1600 px) before upload.
Future<List<PickedPhoto>> pickProblemPhotos(int max) async {
  final files = await ImagePicker().pickMultiImage(
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
    limit: max < 2 ? 2 : max,
  );
  return [
    for (final f in files.take(max)) PickedPhoto(await f.readAsBytes(), f.name),
  ];
}

/// Photos already loaded, kept while the app is open (they do not change).
final Map<String, Uint8List> _cache = {};

/// B7b: the photos section of a technical problem. Files live in the owner's
/// Google Drive; the server fetches them for anyone who can read the problem.
class ProblemPhotos extends StatefulWidget {
  final String organizationId, buildingId, problemId;
  final List<Map> photos;
  final String driveState; // connected | needsReconnect | none
  final bool canAdd;
  final bool Function(Map photo) canRemove;
  final TeamService service;
  final Future<List<PickedPhoto>> Function(int max) pick;
  final VoidCallback onChanged;

  /// Photos chosen on the report form before the problem existed: uploaded
  /// as soon as this shows, once (2026-10-05, Tom).
  final List<PickedPhoto> initial;

  /// Told when uploading starts and stops (the page can wait for it).
  final ValueChanged<bool>? onBusy;
  const ProblemPhotos({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.problemId,
    required this.photos,
    required this.driveState,
    required this.canAdd,
    required this.canRemove,
    required this.service,
    required this.onChanged,
    this.pick = pickProblemPhotos,
    this.initial = const [],
    this.onBusy,
  });
  @override
  State<ProblemPhotos> createState() => _ProblemPhotosState();
}

class _ProblemPhotosState extends State<ProblemPhotos> {
  final Map<String, String> _failed = {}; // photo id -> message
  final Set<String> _loading = {};
  // Uploads waiting for a retry keep their operation id: the server then
  // recognises a photo that did arrive and does not save it twice.
  List<Map<String, dynamic>> _queue = [];
  int _done = 0, _total = 0;
  bool _uploading = false;
  String? _error, _skipped;

  @override
  void initState() {
    super.initState();
    _later();
    if (widget.initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(widget.initial);
      });
    }
  }

  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _fetchAll();
  });

  @override
  void didUpdateWidget(covariant ProblemPhotos old) {
    super.didUpdateWidget(old);
    if (old.problemId != widget.problemId) {
      _queue = [];
      _error = null;
      _failed.clear();
    }
    _later();
  }

  void _fetchAll() {
    if (widget.driveState != 'connected') return;
    for (final p in widget.photos) {
      final id = '${p['id']}';
      if (_cache.containsKey(id) ||
          _loading.contains(id) ||
          _failed.containsKey(id))
        continue;
      _fetch(id);
    }
  }

  Future<void> _fetch(String id) async {
    setState(() {
      _loading.add(id);
      _failed.remove(id);
    });
    try {
      final r = await widget.service.technicalProblems({
        'action': 'photo',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'problemId': widget.problemId,
        'photoId': id,
      });
      _cache[id] = base64Decode('${r['dataBase64']}');
      if (!mounted) return;
      setState(() => _loading.remove(id));
    } catch (e) {
      if (!mounted) return;
      final x = FeeText(context);
      setState(() {
        _loading.remove(id);
        _failed[id] = _message(x, e);
      });
    }
  }

  static const _keys = [
    'problem_photo_missing',
    'problem_photo_limit',
    'problem_photo_invalid',
    'drive_not_connected',
    'drive_reconnect_needed',
    'drive_full',
    'drive_denied',
    'drive_unavailable',
    'problem_not_open',
    'problem_access_denied',
  ];

  String _message(FeeText x, Object e, {bool uncertain = false}) {
    switch (serverReason(e, _keys)) {
      case 'problem_photo_missing':
        return x.tr(
          'This photo was deleted from Google Drive.',
          'Ảnh này đã bị xóa khỏi Google Drive.',
        );
      case 'problem_photo_limit':
        return x.tr(
          'A problem can have at most $maxProblemPhotos photos.',
          'Mỗi sự cố có tối đa $maxProblemPhotos ảnh.',
        );
      case 'problem_photo_invalid':
        return x.tr(
          'Only JPG, PNG or WebP photos up to 2 MB.',
          'Chỉ nhận ảnh JPG, PNG hoặc WebP, tối đa 2 MB.',
        );
      case 'drive_not_connected':
        return x.tr(
          'Google Drive is not connected (home screen › Google Drive).',
          'Chưa kết nối Google Drive (Màn hình chính › Google Drive).',
        );
      case 'drive_reconnect_needed':
        return x.tr(
          'Google Drive needs to be connected again (home screen › Google Drive).',
          'Cần kết nối lại Google Drive (Màn hình chính › Google Drive).',
        );
      case 'drive_full':
        return x.tr('The Google Drive is full.', 'Google Drive đã đầy.');
      case 'drive_denied':
        return x.tr(
          'Google Drive refused the photo.',
          'Google Drive từ chối ảnh này.',
        );
      case 'drive_unavailable':
        return x.tr(
          'Google Drive did not answer. Try again in a moment.',
          'Google Drive chưa phản hồi. Thử lại sau ít phút.',
        );
      case 'problem_not_open':
        return x.tr(
          'This problem is fixed; only a manager can change its photos.',
          'Sự cố đã sửa xong; chỉ quản lý mới thay đổi được ảnh.',
        );
      case 'problem_access_denied':
        return x.tr(
          'You cannot change the photos of this problem.',
          'Bạn không thể thay đổi ảnh của sự cố này.',
        );
    }
    return x.error(e, uncertain: uncertain);
  }

  Future<void> _add() async {
    final x = FeeText(context);
    final room = maxProblemPhotos - widget.photos.length;
    setState(() {
      _error = null;
      _skipped = null;
    });
    final List<PickedPhoto> picked;
    try {
      picked = await widget.pick(room);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = x.tr('Could not open the photos.', 'Không mở được ảnh.'),
        );
      return;
    }
    if (!mounted || picked.isEmpty) return;
    await _send(picked);
  }

  /// Checks the photos and uploads them one by one.
  Future<void> _send(List<PickedPhoto> picked) async {
    final x = FeeText(context);
    final room = maxProblemPhotos - widget.photos.length;
    final queue = <Map<String, dynamic>>[];
    final skipped = <String>[];
    for (final p in picked.take(room)) {
      final type = photoType(p.bytes);
      if (type == null || p.bytes.length > maxPhotoBytes) {
        skipped.add(p.name);
        continue;
      }
      queue.add({
        'action': 'addPhoto',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'operationId': const Uuid().v4(),
        'problemId': widget.problemId,
        'mimeType': type,
        'dataBase64': base64Encode(p.bytes),
      });
    }
    if (skipped.isNotEmpty) {
      setState(
        () => _skipped =
            '${x.tr('Skipped (only JPG, PNG or WebP up to 2 MB)', 'Bỏ qua (chỉ nhận JPG, PNG hoặc WebP tối đa 2 MB)')}: ${skipped.join(', ')}',
      );
    }
    if (queue.isEmpty) return;
    _queue = queue;
    await _upload();
  }

  Future<void> _upload() async {
    final x = FeeText(context);
    setState(() {
      _uploading = true;
      _total = _queue.length;
      _done = 0;
    });
    widget.onBusy?.call(true);
    var added = false;
    while (_queue.isNotEmpty) {
      try {
        final r = await widget.service.technicalProblems(_queue.first);
        final photo = r['photo'] as Map?;
        final sent = _queue.first['dataBase64'] as String;
        if (photo != null) _cache['${photo['id']}'] = base64Decode(sent);
        added = true;
        if (!mounted) return;
        setState(() {
          _queue = _queue.sublist(1);
          _done++;
        });
      } catch (e) {
        if (!mounted) return;
        final uncertain = FeeText.uncertain(e);
        setState(() {
          _uploading = false;
          // A definite refusal will not change on retry: drop the rest.
          if (!uncertain) _queue = [];
          _error = _message(x, e, uncertain: uncertain);
        });
        widget.onBusy?.call(false);
        if (added) widget.onChanged();
        return;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    widget.onBusy?.call(false);
    widget.onChanged();
  }

  Future<void> _remove(Map photo) async {
    final x = FeeText(context);
    final id = '${photo['id']}';
    try {
      final r = await widget.service.technicalProblems({
        'action': 'removePhoto',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'operationId': const Uuid().v4(),
        'problemId': widget.problemId,
        'photoId': id,
      });
      if (!mounted) return;
      setState(
        () => _error = r['trashed'] == true
            ? null
            : x.tr(
                'Removed from the problem. The file is still in Google Drive.',
                'Đã gỡ khỏi sự cố. Tệp vẫn còn trong Google Drive.',
              ),
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = _message(x, e));
    }
  }

  Future<void> _view(Map photo) async {
    final x = FeeText(context);
    final id = '${photo['id']}';
    final bytes = _cache[id];
    if (bytes == null) {
      if (_failed.containsKey(id)) _fetch(id);
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (c) {
        var confirm = false;
        return StatefulBuilder(
          builder: (c, set) => Dialog(
            insetPadding: const EdgeInsets.all(WsSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(WsSpace.sm),
                  child: Text(
                    '${photo['addedByName'] ?? ''} · ${photo['addedLocalDate'] ?? ''}',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ),
                if (confirm)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: WsSpace.sm),
                    child: Text(
                      x.tr(
                        'The file goes to the Google Drive trash.',
                        'Tệp sẽ chuyển vào thùng rác của Google Drive.',
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(WsSpace.sm),
                  child: WsActions(
                    children: [
                      if (widget.canRemove(photo) && !confirm)
                        TextButton(
                          key: const ValueKey('photo-remove'),
                          onPressed: () => set(() => confirm = true),
                          child: Text(x.tr('Remove', 'Xóa ảnh')),
                        ),
                      if (confirm)
                        FilledButton(
                          key: const ValueKey('photo-remove-confirm'),
                          onPressed: () => Navigator.of(c).pop(true),
                          child: Text(x.tr('Remove', 'Xóa ảnh')),
                        ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(c).pop(false),
                        child: Text(x.tr('Close', 'Đóng')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (remove == true) _remove(photo);
  }

  Widget _tile(FeeText x, Map photo) {
    final id = '${photo['id']}';
    final bytes = _cache[id];
    final scheme = Theme.of(context).colorScheme;
    final failed = _failed[id];
    return Tooltip(
      message:
          failed ??
          '${photo['addedByName'] ?? ''} · ${photo['addedLocalDate'] ?? ''}',
      child: InkWell(
        key: ValueKey('photo-$id'),
        borderRadius: BorderRadius.circular(8),
        onTap: widget.driveState == 'connected' ? () => _view(photo) : null,
        child: Container(
          width: 96,
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
              : Center(
                  child: _loading.contains(id)
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          failed != null
                              ? Icons.broken_image_outlined
                              : Icons.image_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final count = widget.photos.length;
    final connected = widget.driveState == 'connected';
    final canPick =
        widget.canAdd && connected && count < maxProblemPhotos && !_uploading;
    return WsSection(
      title: '${x.tr('Photos', 'Ảnh')} ($count/$maxProblemPhotos)',
      children: [
        if (count > 0)
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [for (final p in widget.photos) _tile(x, p)],
          ),
        if (count == 0 && connected)
          Text(x.tr('No photos yet.', 'Chưa có ảnh.'), style: small),
        if (!connected)
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: Text(
              widget.driveState == 'needsReconnect'
                  ? x.tr(
                      'Google Drive needs to be connected again (home screen › Google Drive) to add and view photos.',
                      'Cần kết nối lại Google Drive (Màn hình chính › Google Drive) để thêm và xem ảnh.',
                    )
                  : x.tr(
                      'Photos are saved in the owner\'s Google Drive. It is not connected yet (home screen › Google Drive).',
                      'Ảnh được lưu vào Google Drive của chủ nhà. Chưa kết nối (Màn hình chính › Google Drive).',
                    ),
              key: const ValueKey('photos-drive-note'),
              style: small,
            ),
          ),
        if (_uploading)
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: Text(
              '${x.tr('Uploading photo', 'Đang tải ảnh')} ${_done + 1}/$_total…',
              style: small,
            ),
          ),
        if (_skipped != null)
          WsNotice(
            _skipped!,
            key: const ValueKey('photos-skipped'),
            tone: WsTone.warning,
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(_error!, key: const ValueKey('photos-error')),
          ),
        if (widget.canAdd &&
            connected &&
            (count < maxProblemPhotos || _queue.isNotEmpty))
          WsActions(
            children: [
              if (_queue.isNotEmpty && !_uploading)
                FilledButton(
                  key: const ValueKey('photos-retry'),
                  onPressed: _upload,
                  child: Text(x.tr('Retry', 'Thử lại')),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('photos-add'),
                  onPressed: canPick ? _add : null,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(x.tr('Add photos', 'Thêm ảnh')),
                ),
            ],
          ),
      ],
    );
  }
}
