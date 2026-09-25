import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/searchable_select_field.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/suggested_text_field.dart';

Future<void> pumpFields(
  WidgetTester tester,
  Widget child, {
  String language = 'en',
  double scale = 1,
  Size size = const Size(1000, 900),
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'free text saves immediately, survives parent rebuild and allows presets',
    (tester) async {
      String value = 'Standard';
      late StateSetter update;
      await pumpFields(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SuggestedTextField(
              value: value,
              label: 'Apartment type',
              options: const ['Standard', 'Deluxe'],
              onChanged: (v) => value = v,
            );
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'Phòng Gia Đình');
      expect(value, 'Phòng Gia Đình');
      final selection = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .selection;
      update(() {});
      await tester.pumpAndSettle();
      expect(find.text('Phòng Gia Đình'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.selection,
        selection,
      );
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deluxe'));
      await tester.pumpAndSettle();
      expect(value, 'Deluxe');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search selects IDs, cancellation and unmatched text preserve selection',
    (tester) async {
      String? selected = 'first';
      const labels = {'first': 'Nguyễn Thị Mai', 'second': 'Trần Minh Anh'};
      await pumpFields(
        tester,
        StatefulBuilder(
          builder: (context, update) => SearchableSelectField<String>(
            label: 'Tenant',
            options: labels.keys.toList(),
            labelOf: (id) => labels[id]!,
            selected: selected,
            allowClear: true,
            onChanged: (id) => update(() => selected = id),
          ),
        ),
      );
      await tester.tap(find.byType(SearchableSelectField<String>));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-search')),
        'does not exist',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(selected, 'first');
      await tester.tap(find.byType(SearchableSelectField<String>));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-search')),
        'MINH',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.text('Trần Minh Anh'));
      await tester.pumpAndSettle();
      expect(selected, 'second');
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    },
  );

  for (final language in ['en', 'vi']) {
    testWidgets(
      'typed dates validate ranges, clearing and rebuilds in $language',
      (tester) async {
        final form = GlobalKey<FormState>();
        DateTime? value = DateTime(2026, 9, 8);
        await pumpFields(
          tester,
          StatefulBuilder(
            builder: (context, update) => Form(
              key: form,
              child: LocalizedDatePicker(
                labelText: 'Date',
                initialDate: value,
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2026, 12, 31),
                onDateChanged: (v) => update(() => value = v),
              ),
            ),
          ),
          language: language,
        );
        final field = find.byType(TextField);
        await tester.enterText(field, '1/');
        await tester.pumpAndSettle();
        expect(find.text('1/'), findsOneWidget);
        expect(form.currentState!.validate(), isFalse);
        await tester.enterText(
          field,
          language == 'vi' ? '25/09/2026' : '09/25/2026',
        );
        await tester.pumpAndSettle();
        expect(value, DateTime(2026, 9, 25));
        expect(form.currentState!.validate(), isTrue);
        await tester.enterText(
          field,
          language == 'vi' ? '25/09/2027' : '09/25/2027',
        );
        await tester.pumpAndSettle();
        expect(form.currentState!.validate(), isFalse);
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(value, isNull);
        expect(form.currentState!.validate(), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'populated editable controls and search results adapt to locale size and theme',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        final t = AppTranslations(Locale(language));
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 900),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              await pumpFields(
                tester,
                Column(
                  children: [
                    SuggestedTextField(
                      value: 'Phòng Gia Đình Có Ban Công Rộng',
                      label: t['tenant_field_apt_type'],
                      options: const ['Standard', 'Deluxe'],
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 16),
                    SuggestedTextField(
                      value: 'Chuyển công tác đến thành phố khác',
                      label: t['tenant_moveout_reason_label'],
                      options: const ['Other'],
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 16),
                    LocalizedDatePicker(
                      labelText: t['tenant_field_move_in_date'],
                      initialDate: DateTime(2026, 9, 25),
                    ),
                    const SizedBox(height: 16),
                    SearchableSelectField<String>(
                      label: t['tenant_move_room_building'],
                      selected:
                          'Tòa nhà Nguyễn Văn Linh — Khu căn hộ phía Đông',
                      options: const [
                        'Tòa nhà Nguyễn Văn Linh — Khu căn hộ phía Đông',
                        'Riverside Apartments',
                      ],
                      labelOf: (v) => v,
                      onChanged: (_) {},
                    ),
                  ],
                ),
                language: language,
                scale: scale,
                size: size,
                brightness: brightness,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('EDITABLE_GOLDENS') &&
                  brightness == Brightness.light) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/fields-$language-${size.width.toInt()}-$scale.png',
                  ),
                );
              }
              await tester.ensureVisible(
                find.byType(SearchableSelectField<String>),
              );
              await tester.tap(find.byType(SearchableSelectField<String>));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('record-search')),
                'Tòa',
              );
              await tester.pumpAndSettle();
              expect(find.byType(ListTile), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('EDITABLE_GOLDENS') &&
                  brightness == Brightness.light) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/search-$language-${size.width.toInt()}-$scale.png',
                  ),
                );
              }
              await tester.ensureVisible(find.byType(ListTile));
              await tester.tap(find.byType(ListTile));
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('record-search')), findsNothing);
            }
          }
        }
      }
    },
  );
}
