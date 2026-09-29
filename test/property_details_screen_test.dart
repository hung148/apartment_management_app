import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

Widget page(TeamService service, {String building = 'riverside'}) =>
    PropertyDetailsScreen(
      organizationId: 'preview',
      buildingId: building,
      service: service,
      onBack: () {},
    );
Future<void> enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await reveal(tester, field);
  await tester.enterText(field, value);
}

void main() {
  testWidgets('large text shows the whole address without an inner scroll area', (
    tester,
  ) async {
    final store = TeamPreviewStore();
    store.buildings.first['address'] =
        'Tầng 12, số 123 đường Nguyễn Văn Thoại, phường Mỹ An, quận Ngũ Hành Sơn, thành phố Đà Nẵng';
    await mountReview(
      tester,
      page(store.service),
      language: 'vi',
      size: const Size(320, 740),
      scale: 2,
    );
    final editable = tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byKey(const ValueKey('property-address')),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    expect((editable.offset as ScrollPosition).maxScrollExtent, 0);
  });
  testWidgets(
    'manager edits from workspace and sees updated name; receptionist has no editor',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await press(tester, 'Property details');
      await enter(tester, 'property-name', '');
      await press(tester, 'Save property details');
      expect(find.text('Enter a value.'), findsOneWidget);
      await enter(tester, 'property-name', 'Riverside updated');
      await enter(tester, 'property-address', '25 Nguyễn Văn Thoại, Đà Nẵng');
      await press(tester, 'Save property details');
      expect(store.buildings.first['name'], 'Riverside updated');
      expect(find.text('Property details saved.'), findsOneWidget);
      await press(
        tester,
        AppTranslations(const Locale('en'))['workspace_title'],
      );
      expect(find.text('Riverside updated'), findsWidgets);
      store.workspaceRole = 'receptionist';
      await mountReview(
        tester,
        RoleWorkspace(
          key: UniqueKey(),
          organizationId: 'preview',
          service: store.service,
        ),
      );
      expect(find.text('Property details'), findsNothing);
    },
  );
  testWidgets(
    'lost reply retries same intent, conflicts require reload, denial clears fields',
    (tester) async {
      final store = TeamPreviewStore();
      final sent = <Map<String, dynamic>>[];
      String? error;
      final service = TeamService(
        transport: (name, data) async {
          if (error != null) {
            throw FirebaseFunctionsException(code: error, message: 'test');
          }
          if (data['action'] == 'update') {
            sent.add(Map.of(data));
            final result = await store.call(name, data);
            if (sent.length == 1) throw StateError('lost reply');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await enter(tester, 'property-name', 'Updated');
      await press(tester, 'Save property details');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('property-name')))
            .enabled,
        isFalse,
      );
      await press(tester, 'Retry the same change');
      expect(sent[0], sent[1]);
      error = 'aborted';
      await press(tester, 'Save property details');
      expect(find.textContaining('Copy any edits'), findsOneWidget);
      expect(find.text('Save property details'), findsNothing);
      error = null;
      await press(tester, 'Reload property details');
      error = 'permission-denied';
      await press(tester, 'Save property details');
      expect(find.byKey(const ValueKey('property-name')), findsNothing);
      expect(find.text('Updated'), findsNothing);
    },
  );
  testWidgets(
    'late save cannot lock or overwrite a different property; failed reads recover',
    (tester) async {
      final store = TeamPreviewStore();
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (name, data) async => data['action'] == 'update'
            ? pending.future
            : store.call(name, data),
      );
      await mountReview(tester, page(service));
      await reveal(tester, find.text('Save property details'));
      await tester.tap(find.text('Save property details'));
      await tester.pump();
      await mountReview(tester, page(service, building: 'garden'));
      expect(find.text('Garden Homestay'), findsOneWidget);
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('Garden Homestay'), findsOneWidget);
      expect(find.text('Property details saved.'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save property details'),
            )
            .onPressed,
        isNotNull,
      );
      await mountReview(tester, page(service, building: 'missing'));
      expect(find.textContaining('Check your access'), findsOneWidget);
      await mountReview(tester, page(service));
      expect(find.byKey(const ValueKey('property-name')), findsOneWidget);
    },
  );
  testWidgets('populated property form fits both languages sizes scales and themes', (
    tester,
  ) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final language in ['en', 'vi']) {
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final brightness in Brightness.values) {
            final store = TeamPreviewStore();
            store.buildings.first['name'] =
                'Riverside — Khu căn hộ và khách sạn phía Đông thành phố Đà Nẵng';
            store.buildings.first['address'] =
                'Tầng 12, số 123 đường Nguyễn Văn Thoại, phường Mỹ An, quận Ngũ Hành Sơn, thành phố Đà Nẵng';
            final t = AppTranslations(Locale(language));
            await mountReview(
              tester,
              page(store.service),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            await reveal(tester, find.text(t['property_save']));
            expect(find.text(t['property_save']).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('PROPERTY_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/property-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
          }
        }
      }
    }
  });
}
