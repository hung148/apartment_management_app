import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/building/building_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/constants.dart';

Future<void> openBuilding(WidgetTester tester, {bool uniform = false,
  Size size = const Size(1440, 1200), String language = 'en', double scale = 1,
  String type = 'standard', ValueChanged<dynamic>? onSave}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('vi')],
    theme: ThemeData(fontFamily: 'Roboto'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
    ),
    localizationsDelegates: const [AppTranslationsDelegate(),
      ...GlobalMaterialLocalizations.delegates],
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      child: const Text('Open'), onPressed: () async {
        final result = await showDialog<dynamic>(context: context,
          builder: (_) => BuildingDialog(isEditMode: true,
            initialName: 'Riverside Apartments', initialAddress: '123 Main Street',
            initialFloors: 2, initialUniformRooms: uniform,
            initialRoomsPerFloor: 10, initialRoomType: type, initialRoomArea: 50,
            initialFloorDetails: [
              {'count': 10, 'type': type, 'area': 50},
              {'count': 8, 'type': 'suite', 'area': 60},
            ]));
        onSave?.call(result);
      })),),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder fieldWithText(String text) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.controller?.text == text);
Finder typeField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

void main() {
  test('custom names retain capitalization and accents', () {
    expect(normalizeAptType('  Phòng Gia Đình  '), 'Phòng Gia Đình');
    expect(normalizeAptType('Tiêu chuẩn'), 'standard');
  });

  testWidgets('floor room type accepts text and saves immediately', (tester) async {
    dynamic result;
    await openBuilding(tester, onSave: (value) => result = value);
    final field = fieldWithText('Standard');
    expect(tester.widget<TextField>(field).readOnly, isFalse);
    await tester.ensureVisible(field);
    await tester.enterText(field, '  Phòng Gia Đình  ');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(result['floorDetails'][0]['type'], 'Phòng Gia Đình');
    expect(result['floorDetails'][1]['type'], 'suite');
    expect(tester.takeException(), isNull);
  });

  testWidgets('uniform custom name survives reopening and preset selection', (tester) async {
    dynamic result;
    await openBuilding(tester, uniform: true, onSave: (v) => result = v);
    final field = typeField('uniform-room-type');
    await tester.ensureVisible(field);
    await tester.enterText(field, '  Phòng Gia Đình  ');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(result['roomType'], 'Phòng Gia Đình');
    await openBuilding(tester, uniform: true, type: result['roomType'], onSave: (v) => result = v);
    expect(fieldWithText('Phòng Gia Đình'), findsOneWidget);
    await tester.ensureVisible(field);
    await tester.tap(find.descendant(of: field, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deluxe').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(result['roomType'], 'deluxe');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk applies custom text and blank type leaves floors unchanged', (tester) async {
    for (final bulkType in ['Phòng Gia Đình', '   ']) {
      dynamic result;
      await openBuilding(tester, type: 'Family Studio', onSave: (v) => result = v);
      await tester.ensureVisible(find.text('Bulk edit'));
      await tester.tap(find.text('Bulk edit'));
      await tester.pumpAndSettle();
      for (final entry in {'From floor': '1', 'To floor': '2'}.entries) {
        final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      final field = typeField('bulk-room-type');
      await tester.ensureVisible(field);
      await tester.enterText(field, bulkType);
      await tester.ensureVisible(find.text('Apply to all'));
      await tester.tap(find.text('Apply to all'));
      await tester.pumpAndSettle();
      expect(fieldWithText(bulkType.trim().isEmpty ? 'Family Studio' : bulkType),
        bulkType.trim().isEmpty ? findsOneWidget : findsNWidgets(2));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(result['floorDetails'][0]['type'], bulkType.trim().isEmpty ? 'Family Studio' : bulkType);
      expect(result['floorDetails'][1]['type'], bulkType.trim().isEmpty ? 'suite' : bulkType);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('populated room types fit phone desktop landscape and text scales', (tester) async {
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final size in [const Size(320, 740), const Size(812, 375), const Size(1440, 1000)]) {
      for (final language in ['en', 'vi']) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final mode in ['uniform', 'floor', 'bulk']) {
            final uniform = mode == 'uniform';
            await openBuilding(tester, size: size, language: language, scale: scale,
              uniform: uniform, type: 'Phòng Gia Đình Có Ban Công Rộng');
            final t = AppTranslations(Locale(language));
            if (mode == 'bulk') {
              await tester.ensureVisible(find.text(t['building_bulk_edit']));
              await tester.tap(find.text(t['building_bulk_edit']));
              await tester.pumpAndSettle();
            }
            final field = typeField(uniform ? 'uniform-room-type' : mode == 'bulk' ? 'bulk-room-type' : 'floor-1-room-type');
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size $language $scale $mode');
            expect(field.hitTestable(), findsOneWidget);
            await tester.tap(field);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(field);
            await tester.enterText(field, 'Phòng Gia Đình Có Ban Công Rộng VIP');
            await tester.pumpAndSettle();
            // Caret visibility may scroll the form; typing must not resize
            // the control or move it horizontally.
            expect(tester.getRect(field).size, bounds.size);
            expect(tester.getRect(field).left, bounds.left);
            expect(field.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('ROOM_TYPE_GOLDENS')) {
              await expectLater(find.byKey(const ValueKey('capture')), matchesGoldenFile(
                '../.dart_tool/room-type-$language-${size.width.toInt()}-$scale-$mode.png'));
            }
          }
        }
      }
    }
  });
}
