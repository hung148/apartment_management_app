import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/account_entry_gate.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/services/account_entry_service.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final role in ['owner', 'receptionist']) {
    testWidgets('$role enters its one workspace without opening a dashboard route', (t) async {
      var opened = 0, settings = 0;
      await fixtures.mount(t, AccountEntryGate(
        load: () async => AccountEntry(mode: role == 'owner' ? 'owner' : 'staff', canCreate: false, workplaces: [fixtures.org('a')]),
        ownerBuilder: (_) => const Text('Organization list'),
        workspaceBuilder: (_, org) => Scaffold(appBar: AppBar(actions: [IconButton(onPressed: () => settings++, icon: const Icon(Icons.person_outline))]), body: Text('Direct ${org.name}')),
        openWorkplace: (_) async => opened++, onSettings: () {},
      ));
      await t.pumpAndSettle();
      expect(find.text('Organization list'), findsNothing);
      expect(find.textContaining('Direct Riverside'), findsOneWidget);
      await t.tap(find.byIcon(Icons.person_outline)); expect(settings, 1); expect(opened, 0);
    });
  }
  testWidgets('unresolved accounts cannot enter even a supplied workspace', (t) async {
    var entered = 0;
    await fixtures.mount(t, AccountEntryGate(
      load: () async => AccountEntry(mode: 'conflict', canCreate: false, workplaces: [fixtures.org('a')]),
      ownerBuilder: (_) => const Text('Organization list'),
      workspaceBuilder: (_, __) { entered++; return const Text('Data'); },
      openWorkplace: (_) async {}, onSettings: () {},
    ));
    await t.pumpAndSettle();expect(entered, 0);expect(find.text('Data'), findsNothing);expect(find.text('Organization list'), findsNothing);
  });
  for(final state in ['closed','suspended','waiting','deleting','review']) {
    testWidgets('$state entry cannot open a workspace', (t) async {
      var entered=0;
      await fixtures.mount(t,AccountEntryGate(load:()async=>AccountEntry(mode:'staff',state:state,canCreate:false,workplaces:[fixtures.org('a')]),ownerBuilder:(_)=>const Text('Owner entry'),workspaceBuilder:(_,__){entered++;return const Text('Data');},openWorkplace:(_)async{},onSettings:(){}));
      await t.pumpAndSettle();expect(entered,0);expect(find.text('Data'),findsNothing);expect(find.byIcon(Icons.settings).hitTestable(),findsOneWidget);
    });
  }
  for(final locale in ['en','vi']) for(final size in [const Size(360,800),const Size(800,360),const Size(1440,900)]) for(final scale in [1.0,1.3,2.0]) {
    testWidgets('populated direct workspace $locale $size $scale keeps account actions reachable', (t) async {
      final store=TeamPreviewStore()..addOperationalSamples();var account=0,organization=0;
      await fixtures.mount(t,Scaffold(body:RoleWorkspace(organizationId:'preview',title:'Riverside — Khu căn hộ và khách sạn phía Đông',service:store.service,onAccountSettings:()=>account++,onOrganizationSettings:()=>organization++)),locale:locale,size:size,scale:scale);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.person_outline).first);expect(account,1);
      await t.tap(find.byIcon(Icons.business_outlined).first);expect(organization,1);await t.pumpAndSettle();
      expect(find.byIcon(Icons.handshake_outlined),findsNothing);expect(t.takeException(),isNull);
      for(final label in find.descendant(of:find.byType(NavigationBar),matching:find.byType(Text)).evaluate()){
        expect(t.getRect(find.byWidget(label.widget)).bottom,lessThanOrEqualTo(size.height),reason:'Navigation label must stay inside the viewport');
      }
      if((locale=='vi'&&size.width==360&&scale==2)||(locale=='en'&&size.width==1440&&scale==1)) {
        await t.runAsync(() async {
          final boundary=t.element(find.byKey(fixtures.captureKey)).renderObject! as RenderRepaintBoundary;
          final image=await boundary.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
          await Directory('.dart_tool/single-organization-screenshots').create(recursive:true);
          await File('.dart_tool/single-organization-screenshots/$locale-${size.width.toInt()}-$scale.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
        });
      }
    });
  }
}
