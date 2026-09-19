import '../services/building_service.dart';
import '../services/room_service.dart';
import '../utils/currency_formatter.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:cloud_functions/cloud_functions.dart';
import '../main.dart';
import '../services/ai_agent_service.dart';
import '../services/organization_service.dart';
import '../services/auth_service.dart';
import '../utils/app_localizations.dart';
import '../widgets/app_dialog.dart';

class AIImportDialog extends StatefulWidget {
  const AIImportDialog({super.key});
  @override
  State<AIImportDialog> createState() => _AIImportDialogState();
}

class _AIImportDialogState extends State<AIImportDialog> {
  final _text = TextEditingController();
  final _ai = getIt<AIAgentService>();
  final _form = GlobalKey<FormState>();
  String? _organizationId, _filename, _draftId, _error;
  Map<String, dynamic>? _attachment;
  List<Map<String, dynamic>> _organizations = [],
      _records = [],
      _buildings = [],
      _rooms = [];
  List<String> _warnings = [];
  bool _busy = false, _loadingOrganizations = true;
  final _fields = <String, TextEditingController>{};
  static const fieldNames = {
    'organization': ['name', 'address'],
    'building': ['name', 'address', 'currency'],
    'room': [
      'roomNumber',
      'roomType',
      'area',
      'roomPrice',
      'currency',
      'rentalMode',
    ],
    'tenant': [
      'fullName',
      'phoneNumber',
      'email',
      'moveInDate',
      'moveOutDate',
      'monthlyRent',
      'deposit',
      'currency',
    ],
    'payment': [
      'tenantName',
      'type',
      'amount',
      'paidAmount',
      'currency',
      'dueDate',
      'status',
      'description',
    ],
  };
  static const requiredFields = {
    'organization': ['name'],
    'building': ['name', 'address'],
    'room': ['roomNumber', 'roomType', 'area'],
    'tenant': ['fullName', 'phoneNumber', 'moveInDate'],
    'payment': ['type', 'amount', 'dueDate', 'status'],
  };
  static const numeric = {
    'area',
    'roomPrice',
    'monthlyRent',
    'deposit',
    'amount',
    'paidAmount',
  };
  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  Future<void> _loadOrganizations() async {
    try {
      final user = getIt<AuthService>().currentUser;
      if (user == null) return;
      final orgs = await getIt<OrganizationService>().getUserOrganizations(
        user.uid,
      );
      if (mounted)
        setState(
          () => _organizations = orgs
              .map((o) => {'id': o.id, 'name': o.name})
              .toList(),
        );
    } catch (_) {
      if (mounted) setState(() => _error = 'ai_unavailable');
    } finally {
      if (mounted) setState(() => _loadingOrganizations = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    for (final c in _fields.values) c.dispose();
    super.dispose();
  }

  void _handle(Object error) {
    if (mounted)
      setState(
        () => _error =
            error is FirebaseFunctionsException &&
                error.message?.startsWith('ai_') == true
            ? error.message!
            : error is FirebaseFunctionsException &&
                  error.message == 'booking_conflict'
            ? 'booking_conflict'
            : 'ai_import_failed',
      );
  }

  Future<void> _pick() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Documents and images',
            extensions: [
              'png',
              'jpg',
              'jpeg',
              'webp',
              'pdf',
              'txt',
              'csv',
              'json',
              'xlsx',
            ],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        setState(() => _error = 'ai_file_large');
        return;
      }
      final bytes = await file.readAsBytes(),
          extension = file.name.split('.').last.toLowerCase();
      if (extension == 'xlsx') {
        final workbook = Excel.decodeBytes(bytes);
        final buffer = StringBuffer();
        int rows = 0;
        for (final sheet in workbook.tables.entries) {
          buffer.writeln(sheet.key);
          for (final row in sheet.value.rows) {
            if (++rows > 2000) throw const FormatException();
            buffer.writeln(
              row.map((c) => c?.value?.toString() ?? '').join(' | '),
            );
            if (buffer.length > 50000) throw const FormatException();
          }
        }
        _text.text = buffer.toString();
        _attachment = null;
      } else if (['txt', 'csv', 'json'].contains(extension)) {
        final value = utf8.decode(bytes);
        if (value.length > 50000) throw const FormatException();
        _text.text = value;
        _attachment = null;
      } else {
        _attachment = {
          'mimeType': {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'webp': 'image/webp',
            'pdf': 'application/pdf',
          }[extension],
          'data': base64Encode(bytes),
        };
      }
      if (mounted)
        setState(() {
          _filename = file.name;
          _error = null;
        });
    } catch (_) {
      if (mounted) setState(() => _error = 'ai_file_invalid');
    }
  }

  Future<void> _loadParents(String? orgId) async {
    _buildings = [];
    _rooms = [];
    if (orgId == null) return;
    final buildings = await getIt<BuildingService>().getOrganizationBuildings(
      orgId,
    );
    final rooms = await getIt<RoomService>().getOrganizationRooms(orgId);
    if (mounted)
      setState(() {
        _buildings = buildings
            .map((b) => {'id': b.id, 'name': b.name})
            .toList();
        _rooms = rooms
            .map(
              (r) => {
                'id': r.id,
                'name': r.roomNumber,
                'buildingId': r.buildingId,
              },
            )
            .toList();
      });
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _ai.preview({
        'text': _text.text,
        'language': AppTranslations.of(context).locale.languageCode,
        if (_organizationId != null) 'organizationId': _organizationId,
        if (_attachment != null) 'attachment': _attachment,
      });
      if (!mounted) return;
      _records = (result['records'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      for (final record in _records) {
        final values = Map<String, dynamic>.from(record['fields'] as Map);
        for (final field in fieldNames[record['type']]!) {
          _fields['${record['key']}:$field'] = TextEditingController(
            text: values[field] is num
                ? CurrencyParser.format(values[field])
                : values[field]?.toString() ?? '',
          );
        }
      }
      setState(() {
        _draftId = result['draftId'];
        _warnings = List<String>.from(result['warnings']);
        _attachment = null;
      });
    } catch (error) {
      _handle(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = _records.map((record) {
        final fields = <String, dynamic>{};
        for (final name in fieldNames[record['type']]!) {
          final value = _fields['${record['key']}:$name']!.text.trim();
          if (value.isNotEmpty)
            fields[name] = numeric.contains(name)
                ? CurrencyParser.parse(value)
                : value;
        }
        return {
          ...record,
          'fields': fields,
          'dateOffsets': {
            for (final name in ['moveInDate', 'moveOutDate', 'dueDate'])
              if (fields[name] != null)
                name: DateTime.parse(
                  fields[name] as String,
                ).timeZoneOffset.inMinutes,
          },
        };
      }).toList();
      final result = await _ai.commit(_draftId!, records);
      if (mounted) Navigator.pop(context, (result['created'] as List).length);
    } catch (error) {
      if (error is FirebaseFunctionsException &&
          [
            'invalid-argument',
            'permission-denied',
            'already-exists',
            'failed-precondition',
            'not-found',
          ].contains(error.code)) {
        _handle(error);
      } else if (mounted) {
        setState(() => _error = 'ai_save_uncertain');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _reference(Map<String, dynamic> record, String field, String type) {
    final t = AppTranslations.of(context);
    final options = _records
        .where((r) => r['type'] == type && r['key'] != record['key'])
        .map(
          (r) => DropdownMenuItem<String>(
            value: r['key'],
            child: Text(
              '${t['ai_type_$type']} ${r['key']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
    final existing = record[field] as String?;
    if (existing != null && !options.any((o) => o.value == existing))
      options.add(
        DropdownMenuItem(
          value: existing,
          child: Text(existing, overflow: TextOverflow.ellipsis),
        ),
      );
    if (type == 'organization')
      for (final org in _organizations) {
        if (!options.any((o) => o.value == org['id']))
          options.add(
            DropdownMenuItem(
              value: org['id'],
              child: Text(org['name'], overflow: TextOverflow.ellipsis),
            ),
          );
      }
    final parents = type == 'building'
        ? _buildings
        : type == 'room'
        ? _rooms.where((r) => r['buildingId'] == record['buildingRef']).toList()
        : <Map<String, dynamic>>[];
    for (final parent in parents) {
      if (!options.any((o) => o.value == parent['id']))
        options.add(
          DropdownMenuItem(
            value: parent['id'],
            child: Text(parent['name'], overflow: TextOverflow.ellipsis),
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${record['key']}:$field:$existing'),
        initialValue: existing,
        isExpanded: true,
        decoration: InputDecoration(labelText: t['ai_type_$type']),
        items: options,
        onChanged: _busy
            ? null
            : (v) async {
                setState(() {
                  record[field] = v;
                  if (field == 'buildingRef') record.remove('roomRef');
                });
                if (field == 'organizationRef') await _loadParents(v);
              },
        validator: (v) => v == null ? t['ai_import_missing'] : null,
      ),
    );
  }

  Widget _field(Map<String, dynamic> record, String name) {
    final t = AppTranslations.of(context),
        controller = _fields['${record['key']}:$name']!;
    final choices = switch (name) {
      'currency' => ['USD', 'VND'],
      'rentalMode' => ['monthly', 'hourly', 'both'],
      'status' => ['pending', 'paid', 'partial', 'overdue'],
      'type' => [
        'rent',
        'electricity',
        'water',
        'internet',
        'parking',
        'maintenance',
        'deposit',
        'penalty',
        'buildingRent',
        'hourlyRent',
        'other',
      ],
      _ => null,
    };
    if (choices != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: choices.contains(controller.text)
              ? controller.text
              : null,
          decoration: InputDecoration(labelText: t['ai_field_$name']),
          items: choices
              .map(
                (v) =>
                    DropdownMenuItem(value: v, child: Text(t['ai_option_$v'])),
              )
              .toList(),
          onChanged: _busy ? null : (v) => controller.text = v ?? '',
          validator: (v) =>
              requiredFields[record['type']]!.contains(name) && v == null
              ? t['ai_import_missing']
              : null,
        ),
      );
    }
    final date = ['moveInDate', 'moveOutDate', 'dueDate'].contains(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('${record['key']}:$name'),
        controller: controller,
        enabled: !_busy,
        readOnly: date,
        keyboardType: numeric.contains(name)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: numeric.contains(name)
            ? [CurrencyInputFormatter(decimalDigits: 2)]
            : null,
        onTap: date
            ? () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(controller.text) ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2200),
                );
                if (selected != null)
                  controller.text =
                      '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
              }
            : null,
        decoration: InputDecoration(
          labelText: t['ai_field_$name'],
          suffixIcon: date ? const Icon(Icons.calendar_month) : null,
        ),
        validator: (v) {
          if (requiredFields[record['type']]!.contains(name) &&
              (v == null || v.trim().isEmpty))
            return t['ai_import_missing'];
          if (numeric.contains(name) &&
              v!.isNotEmpty &&
              (CurrencyParser.tryParse(v) == null ||
                  CurrencyParser.parse(v) < 0))
            return t['ai_import_invalid'];
          return null;
        },
      ),
    );
  }

  Widget _record(Map<String, dynamic> record) {
    final t = AppTranslations.of(context), type = record['type'] as String;
    record['organizationRef'] ??= _organizationId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t['ai_type_$type']} · ${record['key']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: t['delete'],
                  onPressed: _busy
                      ? null
                      : () => setState(() => _records.remove(record)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (type != 'organization')
              _reference(record, 'organizationRef', 'organization'),
            if (['room', 'tenant', 'payment'].contains(type))
              _reference(record, 'buildingRef', 'building'),
            if (['tenant', 'payment'].contains(type))
              _reference(record, 'roomRef', 'room'),
            ...fieldNames[type]!.map((name) => _field(record, name)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return AppDialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t['ai_import_title'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: t['close'],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_draftId == null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F6F4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(t['ai_upload_privacy']),
                        ),
                        const SizedBox(height: 16),
                        if (_loadingOrganizations)
                          const LinearProgressIndicator()
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _organizationId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t['ai_target_org'],
                            ),
                            items: [
                              DropdownMenuItem(
                                value: null,
                                child: Text(t['ai_new_org']),
                              ),
                              ..._organizations.map(
                                (o) => DropdownMenuItem<String>(
                                  value: o['id'],
                                  child: Text(
                                    o['name'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) async {
                                    setState(() => _organizationId = v);
                                    await _loadParents(v);
                                  },
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _text,
                          minLines: 4,
                          maxLines: 10,
                          maxLength: 50000,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: t['ai_paste_data'],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pick,
                          icon: const Icon(Icons.attach_file),
                          label: Text(_filename ?? t['ai_choose_file']),
                        ),
                        Text(t['ai_file_types']),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F6F4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(t['ai_review_notice']),
                        ),
                        ..._warnings.map(
                          (w) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(w),
                          ),
                        ),
                        ..._records.map(_record),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            t[_error!],
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _busy
                  ? const LinearProgressIndicator()
                  : Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t['cancel']),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _draftId == null
                              ? _preview
                              : _records.isEmpty
                              ? null
                              : _save,
                          child: Text(
                            t[_draftId == null
                                ? 'ai_extract'
                                : 'ai_save_records'],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

