import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/utility_readings_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/utility_tariff_form.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/utility_invoice_form.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

void main(){
 setUpAll(()async{await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();});
 test('readings parse exactly to thousandths without floating point',(){
  expect(meterMilli('12.345'),12345);expect(meterMilli('1,200.5'),1200500);expect(meterMilli('0,5'),isNull);expect(meterMilli('0'),0);
  for(final value in ['-1','NaN','1.2345','1e5','1000000001']){expect(meterMilli(value),isNull);}
 });
 test('dates reject normalized invalid days and accept leap days',(){
  expect(utilityDate('2024-02-29'),isTrue);
  for(final value in ['2026-02-29','2026-02-30','2026-13-01','26-01-01','']){expect(utilityDate(value),isFalse);}
 });
 testWidgets('tariff editor sends exact tiers and a dated property default',(t)async{
  Map<String,dynamic>? saved;
  await fixtures.mount(t,Scaffold(body:SingleChildScrollView(child:UtilityTariffForm(currency:'USD',locked:false,onSave:(d)async{saved=d;}))));
  await t.tap(find.widgetWithText(ChoiceChip,'Property'));await t.pumpAndSettle();
  await t.enterText(find.byType(TextFormField).at(0),'2026-10-02');
  await t.tap(find.widgetWithText(OutlinedButton,'Add tier'));await t.pumpAndSettle();
  await t.enterText(find.byType(TextFormField).at(1),'100');
  await t.enterText(find.byType(TextFormField).at(2),'0.12');
  await t.enterText(find.byType(TextFormField).at(3),'0.25');
  await t.enterText(find.byType(TextFormField).at(4),'New tariff');
  final save=find.widgetWithText(FilledButton,'Save price');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect(saved,{'tariffScope':'property','effectiveDate':'2026-10-02','reason':'New tariff','tariff':{'currency':'USD','bands':[{'throughMilli':100000,'priceMinor':12},{'throughMilli':null,'priceMinor':25}]}});
  expect(t.takeException(),isNull);
 });
 testWidgets('invoice review uses a reading and retries an identical creation after response loss',(t)async{
  final requests=<Map<String,dynamic>>[];var done=false;
  final service=TeamService(transport:(_,d)async{
   if(d['action']=='tenants')return {'records':[{'id':'t','fullName':'Nguyễn Văn An — long tenant name'}],'today':'2026-10-02'};
   if(d['action']=='quote'){expect(d['readingId'],'x');expect(d.containsKey('unitPriceMinor'),isFalse);return {'record':{'totalMinor':35000,'currency':'VND','quoteRevision':'q'}};}
   requests.add(Map<String,dynamic>.from(d));if(requests.length==1)throw Exception('Lost response');return {'invoiceId':'i'};
  });
  await fixtures.mount(t,Scaffold(body:UtilityInvoiceForm(service:service,scope:{'organizationId':'o','buildingId':'b','roomId':'r','kind':'electricity'},reading:{'id':'x','startDate':'2026-09-01','date':'2026-10-01'},onDone:()=>done=true,onCancel:(){})));
  await t.pumpAndSettle();await t.tap(find.byType(CheckboxListTile));await t.enterText(find.byType(TextFormField).at(1),'Meter bill');
  await t.ensureVisible(find.widgetWithText(FilledButton,'Review'));await t.tap(find.widgetWithText(FilledButton,'Review'));await t.pumpAndSettle();
  await t.ensureVisible(find.widgetWithText(FilledButton,'Create'));await t.tap(find.widgetWithText(FilledButton,'Create'));await t.pumpAndSettle();expect(done,isFalse);
  await t.ensureVisible(find.widgetWithText(FilledButton,'Retry'));await t.tap(find.widgetWithText(FilledButton,'Retry'));await t.pumpAndSettle();expect(done,isTrue);expect(requests.length,2);expect(requests[1],requests[0]);
 });
 testWidgets('latest reading correction requires a reason and preserves the reading identity',(t)async{
  Map<String,dynamic>? request;
  final service=TeamService(transport:(_,d)async{
   if(d['action']=='reverse'){request=Map<String,dynamic>.from(d);return {'revision':4};}
   return {'record':{'roomNumber':'101','revision':3,'propertyRevision':0,'currency':'VND','lastDate':'2026-10-01','lastReadingMilli':120000,'lastReadingId':'last','canPrice':true},'records':[{'id':'last','date':'2026-10-01','readingMilli':120000,'reason':'Original reading'}]};
  });
  await fixtures.mount(t,Scaffold(body:UtilityReadingsScreen(organizationId:'o',buildingId:'b',roomId:'r',service:service,onBack:(){})));await t.pumpAndSettle();
  final correct=find.widgetWithText(TextButton,'Correct');await t.ensureVisible(correct);await t.tap(correct);await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton,'Confirm'));await t.pumpAndSettle();expect(request,isNull);
  await t.enterText(find.descendant(of:find.byType(AlertDialog),matching:find.byType(TextFormField)),'Transposed meter digits');
  await t.tap(find.widgetWithText(FilledButton,'Confirm'));await t.pumpAndSettle();expect(request?['readingId'],'last');expect(request?['revision'],3);expect(request?['reason'],'Transposed meter digits');
 });
 testWidgets('a refused correction explains the invoice recovery next to that reading, without a useless retry',(t)async{
  // The invoice was made elsewhere after this page loaded, so the page still
  // lets the person try; the server refuses.
  final service=TeamService(transport:(_,d)async{
   if(d['action']=='reverse')throw FirebaseFunctionsException(code:'failed-precondition',message:'[firebase_functions/failed-precondition] utility_void_invoice_first');
   return {'record':{'roomNumber':'101','revision':3,'propertyRevision':0,'currency':'VND','lastDate':'2026-10-01','lastReadingMilli':120000,'lastReadingId':'last','canPrice':true},'records':[{'id':'last','date':'2026-10-01','readingMilli':120000,'reason':'Original reading'}]};
  });
  await fixtures.mount(t,Scaffold(body:UtilityReadingsScreen(organizationId:'o',buildingId:'b',roomId:'r',service:service,onBack:(){})));await t.pumpAndSettle();
  final correct=find.widgetWithText(TextButton,'Correct');await t.ensureVisible(correct);await t.tap(correct);await t.pumpAndSettle();
  await t.enterText(find.descendant(of:find.byType(AlertDialog),matching:find.byType(TextFormField)),'Correction');await t.tap(find.widgetWithText(FilledButton,'Confirm'));await t.pumpAndSettle();
  final message=find.text('Refund payments and void the linked invoice before correcting this reading.');
  expect(message,findsOneWidget);
  expect(find.descendant(of:find.byType(Card),matching:message),findsOneWidget);
  expect(find.text('Retry'),findsNothing);
  // Visible where the person tapped: below the reading, not above the form.
  expect(t.getTopLeft(message).dy,greaterThan(t.getTopLeft(find.text('Reading history')).dy));
 });
 testWidgets('an invoiced reading explains how to correct it and sends nothing',(t)async{
  var reverses=0;
  final service=TeamService(transport:(_,d)async{
   if(d['action']=='reverse'){reverses++;return {'revision':4};}
   return {'record':{'roomNumber':'101','revision':3,'propertyRevision':0,'currency':'VND','lastDate':'2026-10-01','lastReadingMilli':120000,'lastReadingId':'last','canPrice':true},'records':[{'id':'last','date':'2026-10-01','readingMilli':120000,'invoiceId':'invoice','reason':'Original reading'}]};
  });
  await fixtures.mount(t,Scaffold(body:UtilityReadingsScreen(organizationId:'o',buildingId:'b',roomId:'r',service:service,onBack:(){})));await t.pumpAndSettle();
  final correct=find.widgetWithText(TextButton,'Correct');await t.ensureVisible(correct);await t.tap(correct);await t.pumpAndSettle();
  expect(find.text('This reading is on an invoice. Refund payments and void that invoice first, then correct the reading.'),findsOneWidget);
  expect(find.descendant(of:find.byType(AlertDialog),matching:find.byType(TextFormField)),findsNothing);
  expect(find.text('Confirm'),findsNothing);
  await t.tap(find.widgetWithText(FilledButton,'Close'));await t.pumpAndSettle();
  expect(find.byType(AlertDialog),findsNothing);expect(reverses,0);
 });
 for(final locale in ['en','vi'])for(final size in [const Size(360,800),const Size(800,360),const Size(1440,900)])for(final scale in [1.0,1.3,2.0]){
  testWidgets('utility form $locale ${size.width} $scale',(t)async{
   final service=TeamService(transport:(_,d)async=>{'record':{'roomNumber':'Riverside — Phòng gia đình hướng biển 1201','revision':2,'currency':'VND','lastDate':'2026-09-01','lastReadingMilli':100000,'tariff':{'currency':'VND'}},'records':[{'date':'2026-09-01','readingMilli':100000,'reason':'Chỉ số bàn giao đồng hồ điện cho khách thuê dài hạn','calculation':{'usageMilli':12500,'amountMinor':43750,'currency':'VND'}}]});
   await fixtures.mount(t,Scaffold(body:UtilityReadingsScreen(organizationId:'o',buildingId:'b',roomId:'r',service:service,onBack:(){})),locale:locale,size:size,scale:scale);await t.pumpAndSettle();
   final reset=find.byType(CheckboxListTile);await t.ensureVisible(reset);await t.tap(reset);await t.pumpAndSettle();
   final save=find.widgetWithText(FilledButton,locale=='en'?'Save':'Lưu');await t.ensureVisible(save);expect(save.hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
   await fixtures.mount(t,Scaffold(body:SingleChildScrollView(padding:const EdgeInsets.all(16),child:UtilityTariffForm(currency:'VND',locked:false,onSave:(_)async{}))),locale:locale,size:size,scale:scale);
   await t.pumpAndSettle();
   final add=find.widgetWithText(OutlinedButton,locale=='en'?'Add tier':'Thêm bậc');await t.ensureVisible(add);await t.tap(add);await t.pumpAndSettle();
   await t.enterText(find.byType(TextFormField).at(0),'2026-10-02');await t.enterText(find.byType(TextFormField).at(1),'100');await t.enterText(find.byType(TextFormField).at(2),'3500');await t.enterText(find.byType(TextFormField).at(3),'4000');await t.enterText(find.byType(TextFormField).at(4),'Giá điện theo thỏa thuận của chủ nhà và khách thuê');
   final priceSave=find.widgetWithText(FilledButton,locale=='en'?'Save price':'Lưu giá');await t.ensureVisible(priceSave);await t.pumpAndSettle();expect(priceSave.hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
   if((locale=='vi'&&size.width==360&&scale==2)||(locale=='en'&&size.width==1440&&scale==1))await t.runAsync(()async{final boundary=t.element(find.byKey(fixtures.captureKey)).renderObject! as RenderRepaintBoundary;final image=await boundary.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('.dart_tool/utility-screenshots').create(recursive:true);await File('.dart_tool/utility-screenshots/tariff-$locale-${size.width.toInt()}-$scale.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
   final invoiceService=TeamService(transport:(_,d)async=>{'records':[{'id':'t','fullName':'Nguyễn Văn An — Khách thuê căn hộ gia đình hướng biển'}],'today':'2026-10-02'});
   await fixtures.mount(t,Scaffold(body:UtilityInvoiceForm(service:invoiceService,scope:{'organizationId':'o','buildingId':'b','roomId':'r','kind':'electricity'},reading:{'id':'x','startDate':'2026-09-01','date':'2026-10-01'},onDone:(){},onCancel:(){})),locale:locale,size:size,scale:scale);await t.pumpAndSettle();
   final review=find.widgetWithText(FilledButton,locale=='en'?'Review':'Xem lại');await t.ensureVisible(review);expect(review.hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
  });
 }
}
