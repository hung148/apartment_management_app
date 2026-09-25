import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/ai_chat/ai_import_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/ai_agent_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';

class UserFake implements User {
  @override
  String get uid => 'user';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class AuthFake implements AuthService {
  @override
  User get currentUser => UserFake();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class OrgFake implements OrganizationService {
  @override
  Future<List<Organization>> getUserOrganizations(String id) async => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class AIFake extends AIAgentService {
  int commits = 0;
  List<Map<String, dynamic>>? saved;
  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> input) async => {
    'draftId': 'draft',
    'warnings': [],
    'records': [
      {
        'key': 'org',
        'type': 'organization',
        'fields': {'name': 'Extracted organization', 'address': 'Address'},
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> commit(
    String id,
    List<Map<String, dynamic>> records,
  ) async {
    commits++;
    saved = records;
    return {
      'created': [
        {'id': 'org'},
      ],
    };
  }
}

void main() {
  for (final lang in ['en', 'vi'])
    testWidgets('AI import requires review before saving in $lang', (
      tester,
    ) async {
      await getIt.reset();
      addTearDown(getIt.reset);
      final ai = AIFake();
      getIt.registerSingleton<AIAgentService>(ai);
      getIt.registerSingleton<AuthService>(AuthFake());
      getIt.registerSingleton<OrganizationService>(OrgFake());
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final t = AppTranslations(Locale(lang));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<int>(
                  context: context,
                  builder: (_) => const AIImportDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'Create my organization from this text',
      );
      await tester.tap(find.text(t['ai_extract']));
      await tester.pumpAndSettle();
      expect(ai.commits, 0);
      expect(find.text('Extracted organization'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            w.controller?.text == 'Extracted organization',
      );
      await tester.enterText(field, 'Reviewed organization');
      await tester.tap(find.text(t['ai_save_records']));
      await tester.pumpAndSettle();
      expect(ai.commits, 1);
      expect(ai.saved!.single['fields']['name'], 'Reviewed organization');
      expect(find.byType(AIImportDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
}
