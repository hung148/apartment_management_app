import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

class OwnershipTransferScreen extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final VoidCallback onChanged;
  const OwnershipTransferScreen({super.key,required this.organizationId,required this.service,required this.onChanged});
  @override
  State<OwnershipTransferScreen> createState()=>_OwnershipTransferScreenState();
}
class _OwnershipTransferScreenState extends State<OwnershipTransferScreen>{
  Map<String,dynamic>? _data,_intent;
  String? _recipient,_error;
  bool _busy=false;
  String _message(Object e){
    final key=e is FirebaseFunctionsException?e.message:null;
    return const {'org_transfer_changed','org_transfer_pending','org_transfer_owner_only','org_single_organization_review','account_deletion_in_progress'}.contains(key)?key!:'org_transfer_error';
  }
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    setState((){_busy=true;_error=null;});
    try{final data=await widget.service.transferOrganization({'action':'read','organizationId':widget.organizationId});if(mounted)setState(()=>_data=data);}
    catch(e){if(mounted)setState(()=>_error=_message(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _act(String action,String proposal) async {
    if(_busy)return;
    _intent??={'action':action,'organizationId':widget.organizationId,'proposalId':proposal,if(action=='propose')'recipientId':_recipient};
    setState((){_busy=true;_error=null;});
    try{await widget.service.transferOrganization(_intent!);_intent=null;widget.onChanged();if(mounted)await _load();}
    catch(e){if(mounted)setState(()=>_error=_message(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context){
    final t=AppTranslations.of(context),p=_data?['proposal'] as Map?;
    return WsPage(children:[
      Text(t['org_transfer_title'],style:Theme.of(context).textTheme.titleLarge),
      Text(t['org_transfer_explanation']),
      if(_busy)const LinearProgressIndicator(),
      if(_error!=null)WsNotice(t[_error??'org_transfer_error'],tone:WsTone.neutral),
      if(_data?['owner']==true&&p==null)...[
        if((_data!['candidates'] as List).isEmpty)Text(t['org_transfer_no_staff'])
        else DropdownButtonFormField<String>(isExpanded:true,initialValue:_recipient,
          decoration:InputDecoration(labelText:t['org_transfer_recipient']),
          items:[for(final c in _data!['candidates'] as List)DropdownMenuItem(value:(c as Map)['id'] as String,child:Text(c['name'] as String))],
          onChanged:_busy||_intent!=null?null:(value)=>setState(()=>_recipient=value)),
        FilledButton(onPressed:_busy||_recipient==null?null:()=>_act('propose',const Uuid().v4()),child:Text(t['org_transfer_propose'])),
      ],
      if(p!=null)...[
        Text('${t['org_transfer_pending']}: ${p['recipientName']}'),
        if(p['canAccept']==true)FilledButton(onPressed:_busy?null:()=>_act('accept',p['id'] as String),child:Text(t['org_transfer_accept'])),
        if(_data?['owner']==true)OutlinedButton(onPressed:_busy?null:()=>_act('cancel',p['id'] as String),child:Text(t['org_transfer_cancel'])),
      ],
      if(_data?['owner']!=true&&p==null)Text(t['org_transfer_no_offer']),
      OutlinedButton(onPressed:_busy||_intent!=null?null:_load,child:Text(t['staff_refresh'])),
    ]);
  }
}
