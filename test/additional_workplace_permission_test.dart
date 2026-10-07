import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/roles_screen.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
 setUpAll(() async {
  await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
 });
 for(final locale in ['en','vi']) {
  for(final size in [const Size(360,800),const Size(800,360),const Size(1440,900)]) {
   for(final scale in [1.0,1.3,2.0]) {
    testWidgets('retired workplace permission absent $locale ${size.width} $scale',(t) async {
     final editor=RoleEditor(organizationId:'org',service:TeamService(transport:(_,__) async => {}),actor:TeamAccess(role:'owner',status:'active',allBuildings:true),role:{'id':'administrator','canEdit':true,'name':'Riverside — Điều phối nhân sự','grants':TeamPolicy.encode(TeamPolicy.templates['administrator']!)},startFrom:const [],usedNames:const {},onCancel:(){},onSaved:(){},onAccessDenied:(){},onChangedElsewhere:(){});
     await fixtures.mount(t,Scaffold(body:editor),size:size,locale:locale,scale:scale);
     await t.pumpAndSettle();
     final label=find.text(locale=='en'?'Assign staff to another workplace':'Phân công nhân viên sang tổ chức khác');
     expect(label,findsNothing);
     expect(find.byKey(const ValueKey('role-assignAdditionalWorkplace-all')),findsNothing);
     expect(find.byKey(const ValueKey('role-assignAdditionalWorkplace-off')),findsNothing);
     expect(t.takeException(),isNull);
    });
   }
  }
 }
}
