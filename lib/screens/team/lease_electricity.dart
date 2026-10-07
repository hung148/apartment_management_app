import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import '../calendar/room_calendar.dart' show CalendarPageDialog;
import 'problem_photos.dart'
    show PickedPhoto, photoType, pickProblemPhotos, maxPhotoBytes;
import 'property_contract_screen.dart' show contractDate;
import 'room_rates_screen.dart' show parseRoomRate;
import 'utility_readings_screen.dart' show UtilityReadingsScreen, meterMilli;
import 'ws_ui.dart';

/// Electricity on a long-stay lease (2026-10-04): the price per kWh, the last
/// meter reading, and "Ghi chỉ số" — the meter number, the day and a photo of
/// the meter. The app subtracts the previous reading and prices the kWh.
String leaseElectricityText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'title': ['Electricity', 'Tiền điện'],
    'price': ['Price', 'Giá điện'],
    'priceInput': ['Price per kWh', 'Giá mỗi kWh'],
    'noPrice': ['No price yet', 'Chưa có giá'],
    'last': ['Last reading', 'Chỉ số gần nhất'],
    'none': [
      'No reading yet. The first reading is the starting point.',
      'Chưa ghi chỉ số. Chỉ số đầu tiên là mốc bắt đầu.',
    ],
    'record': ['Record reading', 'Ghi chỉ số'],
    'setPrice': ['Change price', 'Đổi giá'],
    'history': ['History', 'Lịch sử'],
    'reading': ['Meter reading (kWh)', 'Chỉ số công tơ (kWh)'],
    'date': ['Date (YYYY-MM-DD)', 'Ngày ghi (YYYY-MM-DD)'],
    'from': ['From (YYYY-MM-DD)', 'Áp dụng từ (YYYY-MM-DD)'],
    'photo': ['Add photo', 'Thêm ảnh'],
    'photoChange': ['Change photo', 'Đổi ảnh'],
    'photos': ['Photos', 'Ảnh'],
    'save': ['Save', 'Lưu'],
    'cancel': ['Cancel', 'Hủy'],
    'close': ['Close', 'Đóng'],
    'retry': ['Retry', 'Thử lại'],
    'invalidReading': [
      'Enter a reading (up to 3 decimals).',
      'Nhập chỉ số (tối đa 3 số lẻ).',
    ],
    'lower': ['Lower than the last reading.', 'Thấp hơn chỉ số trước.'],
    'invalidDate': ['Enter a valid date.', 'Nhập ngày hợp lệ.'],
    'beforeLast': [
      'Must be after the last reading.',
      'Phải sau ngày ghi trước.',
    ],
    'future': ['Cannot be in the future.', 'Không được sau hôm nay.'],
    'invalidPrice': ['Enter a price above 0.', 'Nhập giá lớn hơn 0.'],
    'estimate': [
      '{kwh} kWh × {price} = {total}',
      '{kwh} kWh × {price} = {total}',
    ],
    'baseline': ['Starting point, no charge.', 'Mốc bắt đầu, chưa tính tiền.'],
    // Billed or not (2026-10-04): usage goes on the next period invoice.
    'invoiced': ['On an invoice', 'Đã lập hóa đơn'],
    'notInvoiced': ['Not on an invoice yet', 'Chưa lập hóa đơn'],
    'needPrice': ['Set the price first.', 'Hãy đặt giá điện trước.'],
    'reason': ['Electricity reading', 'Ghi chỉ số điện'],
    'priceReason': ['Electricity price', 'Đổi giá điện'],
    'photoTooBig': ['The photo is larger than 2 MB.', 'Ảnh lớn hơn 2 MB.'],
    'photoFailed': [
      'Reading saved, but the photo did not upload. Try again.',
      'Đã lưu chỉ số nhưng chưa tải được ảnh. Hãy thử lại.',
    ],
    'saveFailed': [
      'Could not save. Reload and try again.',
      'Không lưu được. Tải lại rồi thử lại.',
    ],
    'loadFailed': ['Could not load electricity.', 'Không tải được tiền điện.'],
    'noDrive': [
      'Connect Google Drive to keep photos.',
      'Kết nối Google Drive để lưu ảnh.',
    ],
  };
  final pair = labels[key];
  return pair == null ? key : pair[vi ? 1 : 0];
}

/// The price in force on [date]: the room's own price, else the property's.
Map? electricityTariffOn(Map record, String date) {
  Map? at(List rows) {
    Map? found;
    for (final r in rows) {
      if (r is Map && '${r['effectiveDate']}'.compareTo(date) <= 0) found = r;
    }
    return found?['tariff'] as Map?;
  }

  return at(record['roomTariffs'] as List? ?? const []) ??
      at(record['propertyTariffs'] as List? ?? const []);
}

/// Usage priced by the bands of [tariff], in minor units (same rule as the server).
int electricityCharge(int usageMilli, Map tariff) {
  var left = usageMilli, previous = 0, numerator = 0;
  for (final b in (tariff['bands'] as List).cast<Map>()) {
    final through = b['throughMilli'] as int?;
    final width = through == null ? left : (through - previous).clamp(0, left);
    numerator += width * (b['priceMinor'] as int);
    left -= width;
    if (through != null) previous = through;
    if (left <= 0) break;
  }
  return (numerator + 500) ~/ 1000;
}

class LeaseElectricitySection extends StatefulWidget {
  final String organizationId, buildingId, roomId, roomLabel;
  final TeamService service;
  final Future<List<PickedPhoto>> Function(int max) pick;
  const LeaseElectricitySection({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.roomLabel,
    required this.service,
    this.pick = pickProblemPhotos,
  });
  @override
  State<LeaseElectricitySection> createState() =>
      _LeaseElectricitySectionState();
}

class _LeaseElectricitySectionState extends State<LeaseElectricitySection> {
  Map<String, dynamic>? _record;
  List<Map<String, dynamic>> _rows = [];
  bool _busy = true, _hidden = false;
  String? _error;
  int _generation = 0;
  String lt(String k) => leaseElectricityText(context, k);
  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'roomId': widget.roomId,
    'kind': 'electricity',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeaseElectricitySection old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId ||
        old.buildingId != widget.buildingId ||
        old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.utilityReadings({
        'action': 'read',
        ..._scope,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(data['record'] as Map);
        _rows = [
          for (final r in (data['records'] as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
        _busy = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        // No access to meters (or not offered here): the section stays out of the way.
        if (![
          'unavailable',
          'deadline-exceeded',
          'internal',
          'unknown',
        ].contains(e.code)) {
          _hidden = true;
        } else {
          _error = lt('loadFailed');
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = lt('loadFailed');
      });
    }
  }

  String get _currency => '${_record?['currency'] ?? 'VND'}';
  // Money 5,000,000 VND; kWh without a thousands mark: 1200.5 (Tom, 2026-10-05).
  String _money(num minor) => appMoneyMinor(minor, _currency);

  String _kwh(num milli) => appQuantityMilli(milli);
  String get _today =>
      '${_record?['today'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())}';

  Future<void> _recordReading() async {
    final r = _record;
    if (r == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReadingDialog(
        scope: _scope,
        record: r,
        today: _today,
        service: widget.service,
        pick: widget.pick,
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _setPrice() async {
    final r = _record;
    if (r == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PriceDialog(
        scope: _scope,
        record: r,
        today: _today,
        service: widget.service,
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _history() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CalendarPageDialog(
        title: '${widget.roomLabel} · ${lt('title')}',
        build: (close) => UtilityReadingsScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: widget.roomId,
          service: widget.service,
          onBack: close,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _showPhoto(Map row, Map photo) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PhotoDialog(
        scope: _scope,
        readingId: '${row['id']}',
        photoId: '${photo['id']}',
        service: widget.service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final r = _record;
    final tariff = r == null ? null : electricityTariffOn(r, _today);
    final bands = (tariff?['bands'] as List?)?.cast<Map>() ?? const [];
    final price = bands.isEmpty
        ? lt('noPrice')
        : bands.length == 1
        ? '${_money(bands.first['priceMinor'] as num)} / kWh'
        : bands
              .map(
                (b) =>
                    '${_money(b['priceMinor'] as num)}${b['throughMilli'] == null ? '' : ' (≤ ${_kwh(b['throughMilli'] as num)})'}',
              )
              .join(' · ');
    final live = _rows.where((x) => x['reversedAt'] == null).toList();
    final recent = live.reversed.take(3).toList();
    return WsSection(
      key: const ValueKey('lease-electricity'),
      title: lt('title'),
      icon: Icons.bolt_outlined,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          WsNotice(_error!),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _busy ? null : _load,
              child: Text(lt('retry'), maxLines: 1),
            ),
          ),
        ],
        if (r != null) ...[
          WsInfo(lt('price'), price),
          WsInfo(
            lt('last'),
            r['lastDate'] == null
                ? ''
                : '${_kwh(r['lastReadingMilli'] as num)} kWh · ${r['lastDate']}',
          ),
          if (r['lastDate'] == null) Text(lt('none'), style: muted),
          for (final row in recent)
            Padding(
              padding: const EdgeInsets.only(top: WsSpace.xs),
              child: Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    [
                      '${row['date']}',
                      '${_kwh(row['readingMilli'] as num)} kWh',
                      if (row['calculation'] is Map) ...[
                        '+${_kwh((row['calculation'] as Map)['usageMilli'] as num)} kWh = ${_money((row['calculation'] as Map)['amountMinor'] as num)}',
                        if (((row['calculation'] as Map)['amountMinor']
                                as num) >
                            0)
                          lt(
                            row['invoiceId'] == null
                                ? 'notInvoiced'
                                : 'invoiced',
                          ),
                      ] else
                        lt('baseline'),
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                  for (final (i, p)
                      in ((row['photos'] as List?) ?? const [])
                          .cast<Map>()
                          .indexed)
                    ActionChip(
                      key: ValueKey('lease-electricity-photo-${row['id']}-$i'),
                      avatar: const Icon(Icons.photo_outlined, size: 16),
                      label: Text('${lt('photos')} ${i + 1}', maxLines: 1),
                      onPressed: () => _showPhoto(row, p),
                    ),
                ],
              ),
            ),
          const SizedBox(height: WsSpace.sm),
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('lease-electricity-record'),
                onPressed: _busy ? null : _recordReading,
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(lt('record'), maxLines: 1),
              ),
              if (r['canPrice'] == true)
                OutlinedButton(
                  key: const ValueKey('lease-electricity-price'),
                  onPressed: _busy ? null : _setPrice,
                  child: Text(lt('setPrice'), maxLines: 1),
                ),
              TextButton(
                key: const ValueKey('lease-electricity-history'),
                onPressed: _busy ? null : _history,
                child: Text(lt('history'), maxLines: 1),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "Ghi chỉ số": meter number, day and an optional photo of the meter.
class _ReadingDialog extends StatefulWidget {
  final Map<String, dynamic> scope;
  final Map<String, dynamic> record;
  final String today;
  final TeamService service;
  final Future<List<PickedPhoto>> Function(int max) pick;
  const _ReadingDialog({
    required this.scope,
    required this.record,
    required this.today,
    required this.service,
    required this.pick,
  });
  @override
  State<_ReadingDialog> createState() => _ReadingDialogState();
}

class _ReadingDialogState extends State<_ReadingDialog> {
  final _form = GlobalKey<FormState>();
  final _reading = TextEditingController();
  late final _date = TextEditingController(text: widget.today);
  PickedPhoto? _photo;
  Map<String, dynamic>? _pending; // the reading request, kept for a retry
  String? _readingId; // saved; only the photo is left
  String? _photoOperation;
  bool _saving = false;
  String? _error;
  String lt(String k) => leaseElectricityText(context, k);

  @override
  void dispose() {
    _reading.dispose();
    _date.dispose();
    super.dispose();
  }

  String get _currency => '${widget.record['currency'] ?? 'VND'}';
  String _money(num minor) => appMoneyMinor(minor, _currency);

  Future<void> _pickPhoto() async {
    final picked = await widget.pick(1);
    if (!mounted || picked.isEmpty) return;
    final p = picked.first;
    setState(() {
      if (p.bytes.length > maxPhotoBytes) {
        _error = lt('photoTooBig');
      } else {
        _photo = p;
        _error = null;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_readingId == null &&
        _pending == null &&
        !_form.currentState!.validate())
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_readingId == null) {
        _pending ??= {
          'action': 'record',
          ...widget.scope,
          'operationId': const Uuid().v4(),
          'revision': widget.record['revision'],
          'date': _date.text.trim(),
          'readingMilli': meterMilli(_reading.text),
          'reason': lt('reason'),
          'oldFinalMilli': null,
          'newStartMilli': null,
        };
        final r = await widget.service.utilityReadings(Map.of(_pending!));
        _readingId = '${r['readingId']}';
      }
      final photo = _photo;
      if (photo != null) {
        final type = photoType(photo.bytes);
        if (type != null) {
          _photoOperation ??= const Uuid().v4();
          try {
            await widget.service.utilityReadings({
              'action': 'addPhoto',
              ...widget.scope,
              'readingId': _readingId,
              'operationId': _photoOperation,
              'mimeType': type,
              'dataBase64': base64Encode(photo.bytes),
            });
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error =
                  e is FirebaseFunctionsException &&
                      e.message == 'drive_not_configured'
                  ? lt('noDrive')
                  : lt('photoFailed');
            });
            return;
          }
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // A refusal will not change on retry: let them fix the form.
        if ([
          'invalid-argument',
          'failed-precondition',
          'aborted',
          'permission-denied',
        ].contains(e.code))
          _pending = null;
        _error = switch (e.message) {
          'utility_tariff_required' => lt('needPrice'),
          'utility_reading_order' => lt('beforeLast'),
          'utility_future_reading' => lt('future'),
          _ => lt('saveFailed'),
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = lt('saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final last = r['lastReadingMilli'] as int?,
        lastDate = r['lastDate'] as String?;
    final milli = meterMilli(_reading.text);
    final date = _date.text.trim();
    String? estimate;
    if (last == null) {
      estimate = lt('baseline');
    } else if (milli != null && milli >= last && contractDate(date)) {
      final tariff = electricityTariffOn(r, lastDate!);
      if (tariff == null) {
        estimate = lt('needPrice');
      } else {
        final bands = (tariff['bands'] as List).cast<Map>();
        final unit = bands.length == 1
            ? '${_money(bands.first['priceMinor'] as num)}/kWh'
            : lt('price');
        estimate = lt('estimate')
            .replaceAll('{kwh}', appQuantityMilli(milli - last))
            .replaceAll('{price}', unit)
            .replaceAll(
              '{total}',
              _money(electricityCharge(milli - last, tariff)),
            );
      }
    }
    final locked = _saving || _pending != null || _readingId != null;
    return AlertDialog(
      scrollable: true,
      title: Text(lt('record')),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) WsNotice(_error!),
              if (last != null)
                Text(
                  '${leaseElectricityText(context, 'last')}: ${appQuantityMilli(last)} kWh · $lastDate',
                ),
              const SizedBox(height: WsSpace.sm),
              TextFormField(
                key: const ValueKey('lease-electricity-reading'),
                controller: _reading,
                enabled: !locked,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: lt('reading')),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final m = meterMilli(v ?? '');
                  if (m == null) return lt('invalidReading');
                  return last != null && m < last ? lt('lower') : null;
                },
              ),
              const SizedBox(height: WsSpace.sm),
              TextFormField(
                key: const ValueKey('lease-electricity-date'),
                controller: _date,
                enabled: !locked,
                decoration: InputDecoration(
                  labelText: lt('date'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    onPressed: locked
                        ? null
                        : () async {
                            final now =
                                DateTime.tryParse(widget.today) ??
                                DateTime.now();
                            final first = lastDate == null
                                ? DateTime(now.year - 1)
                                : DateTime.parse(
                                    lastDate,
                                  ).add(const Duration(days: 1));
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: now.isBefore(first) ? first : now,
                              firstDate: first.isAfter(now) ? now : first,
                              lastDate: now,
                            );
                            if (picked != null)
                              setState(
                                () => _date.text = DateFormat(
                                  'yyyy-MM-dd',
                                ).format(picked),
                              );
                          },
                  ),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final d = (v ?? '').trim();
                  if (!contractDate(d)) return lt('invalidDate');
                  if (lastDate != null && d.compareTo(lastDate) <= 0)
                    return lt('beforeLast');
                  return d.compareTo(widget.today) > 0 ? lt('future') : null;
                },
              ),
              const SizedBox(height: WsSpace.sm),
              if (estimate != null)
                Text(
                  estimate,
                  key: const ValueKey('lease-electricity-estimate'),
                ),
              const SizedBox(height: WsSpace.sm),
              // Wrap: on a phone the thumbnail goes under the button.
              Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('lease-electricity-photo'),
                    onPressed: _saving ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      lt(_photo == null ? 'photo' : 'photoChange'),
                      maxLines: 1,
                    ),
                  ),
                  if (_photo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        _photo!.bytes,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        // A file the phone cannot preview still uploads.
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.pop(context, _readingId != null),
          child: Text(lt(_readingId != null ? 'close' : 'cancel'), maxLines: 1),
        ),
        FilledButton(
          key: const ValueKey('lease-electricity-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            lt(_pending != null || _readingId != null ? 'retry' : 'save'),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

/// "Đổi giá": a single price per kWh from a day on.
class _PriceDialog extends StatefulWidget {
  final Map<String, dynamic> scope, record;
  final String today;
  final TeamService service;
  const _PriceDialog({
    required this.scope,
    required this.record,
    required this.today,
    required this.service,
  });
  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _form = GlobalKey<FormState>();
  final _price = TextEditingController();
  late final _from = TextEditingController(
    text:
        widget.record['lastDate'] != null &&
            '${widget.record['lastDate']}'.compareTo(widget.today) > 0
        ? '${widget.record['lastDate']}'
        : widget.today,
  );
  Map<String, dynamic>? _pending;
  bool _saving = false;
  String? _error;
  String lt(String k) => leaseElectricityText(context, k);
  String get _currency => '${widget.record['currency'] ?? 'VND'}';

  @override
  void dispose() {
    _price.dispose();
    _from.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || (_pending == null && !_form.currentState!.validate()))
      return;
    _pending ??= {
      'action': 'tariff',
      ...widget.scope,
      'operationId': const Uuid().v4(),
      'revision': widget.record['revision'],
      'propertyRevision': widget.record['propertyRevision'],
      'reason': lt('priceReason'),
      'tariffScope': 'room',
      'effectiveDate': _from.text.trim(),
      'tariff': {
        'currency': _currency,
        'bands': [
          {
            'throughMilli': null,
            'priceMinor': parseRoomRate(_price.text, _currency),
          },
        ],
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.utilityReadings(Map.of(_pending!));
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if ([
          'invalid-argument',
          'failed-precondition',
          'aborted',
          'permission-denied',
        ].contains(e.code))
          _pending = null;
        _error = e.message == 'utility_tariff_past_reading'
            ? lt('beforeLast')
            : lt('saveFailed');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = lt('saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastDate = widget.record['lastDate'] as String?;
    return AlertDialog(
      scrollable: true,
      title: Text(lt('setPrice')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) WsNotice(_error!),
              TextFormField(
                key: const ValueKey('lease-electricity-price-input'),
                controller: _price,
                enabled: !_saving && _pending == null,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: _currency == 'USD',
                ),
                inputFormatters: appMoneyInput(_currency),
                decoration: InputDecoration(
                  labelText: '${lt('priceInput')} ($_currency)',
                ),
                validator: (v) {
                  final m = parseRoomRate(v ?? '', _currency);
                  return m == null || m <= 0 ? lt('invalidPrice') : null;
                },
              ),
              const SizedBox(height: WsSpace.sm),
              TextFormField(
                key: const ValueKey('lease-electricity-price-from'),
                controller: _from,
                enabled: !_saving && _pending == null,
                decoration: InputDecoration(labelText: lt('from')),
                validator: (v) {
                  final d = (v ?? '').trim();
                  if (!contractDate(d)) return lt('invalidDate');
                  return lastDate != null && d.compareTo(lastDate) < 0
                      ? lt('beforeLast')
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(lt('cancel'), maxLines: 1),
        ),
        FilledButton(
          key: const ValueKey('lease-electricity-price-save'),
          onPressed: _saving ? null : _save,
          child: Text(lt(_pending != null ? 'retry' : 'save'), maxLines: 1),
        ),
      ],
    );
  }
}

/// One meter photo, fetched from the owner's Drive through the server.
class _PhotoDialog extends StatefulWidget {
  final Map<String, dynamic> scope;
  final String readingId, photoId;
  final TeamService service;
  const _PhotoDialog({
    required this.scope,
    required this.readingId,
    required this.photoId,
    required this.service,
  });
  @override
  State<_PhotoDialog> createState() => _PhotoDialogState();
}

final Map<String, Uint8List> _photoCache = {};

class _PhotoDialogState extends State<_PhotoDialog> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bytes = _photoCache[widget.photoId];
    if (_bytes == null) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _failed = false);
    try {
      final r = await widget.service.utilityReadings({
        'action': 'photo',
        ...widget.scope,
        'readingId': widget.readingId,
        'photoId': widget.photoId,
      });
      final bytes = base64Decode('${r['dataBase64']}');
      _photoCache[widget.photoId] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseElectricityText(context, k);
    // A plain Dialog: AlertDialog asks its content for an intrinsic size.
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(WsSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _bytes != null
                    ? InteractiveViewer(
                        child: Image.memory(
                          _bytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Text(lt('loadFailed')),
                        ),
                      )
                    : _failed
                    ? Text(lt('loadFailed'))
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
              ),
              const SizedBox(height: WsSpace.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: WsSpace.sm,
                children: [
                  if (_failed)
                    TextButton(
                      onPressed: _fetch,
                      child: Text(lt('retry'), maxLines: 1),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(lt('close'), maxLines: 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
