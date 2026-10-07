import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/ownership_agreements_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;
void main() {
 for(final locale in ['en','vi']) for(final size in [const Size(360,800),const Size(800,360),const Size(1440,900)]) for(final scale in [1.0,1.3,2.0]) {
  testWidgets('retired ownership destination $locale $size $scale exposes no agreement controls',(t) async {
   var calls=0;
   await fixtures.mount(t,OwnershipAgreementsScreen(organizationId:'org',service:TeamService(transport:(_,__) async {calls++;return {};})),locale:locale,size:size,scale:scale);
   await t.pumpAndSettle();expect(calls,0);expect(find.byType(FilledButton),findsNothing);expect(find.byType(TextField),findsNothing);expect(t.takeException(),isNull);
   expect(find.text(locale=='en'?'Co-ownership and organization sharing are no longer available.':'Đồng sở hữu và chia sẻ giữa các tổ chức không còn được hỗ trợ.'),findsOneWidget);
  });
 }
}
