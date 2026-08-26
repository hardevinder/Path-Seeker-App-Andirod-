import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/support_center_api.dart';

String _pretty(dynamic value) {
  final s = (value ?? '').toString().replaceAll('_', ' ').trim();
  if (s.isEmpty) return '';
  return s.split(' ').where((p) => p.isNotEmpty).map((p) => '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

Color _priorityColor(String value) {
  switch (value) { case 'urgent': return Colors.red.shade700; case 'high': return Colors.deepOrange.shade700; case 'low': return Colors.green.shade700; default: return Colors.amber.shade800; }
}
Color _statusColor(String value) {
  switch (value) { case 'resolved': return Colors.green.shade700; case 'closed': return Colors.blueGrey; case 'waiting_for_user': return Colors.amber.shade900; case 'in_progress': case 'assigned': return Colors.deepPurple; default: return Colors.blue.shade700; }
}

class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key});
  @override State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _status = '';
  String? _error;
  Timer? _timer;

  @override void initState() { super.initState(); _load(); _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true)); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await SupportCenterApi.tickets(status: _status);
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) { if (mounted && !silent) setState(() => _error = e.toString()); }
    finally { if (mounted && !silent) setState(() => _loading = false); }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SupportCreateTicketScreen()));
    if (created == true) _load();
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportTicketDetailScreen(ticketNo: row['ticket_no']?.toString() ?? '')));
    _load();
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Raise Ticket')),
      body: Column(children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
          child: DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: '', child: Text('All tickets')),
              DropdownMenuItem(value: 'open', child: Text('Open')),
              DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
              DropdownMenuItem(value: 'waiting_for_user', child: Text('Waiting for User')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'closed', child: Text('Closed')),
            ],
            onChanged: (v) { setState(() => _status = v ?? ''); _load(); },
          ),
        ),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _ErrorView(message: _error!, retry: () => _load()) : RefreshIndicator(
          onRefresh: _load,
          child: _rows.isEmpty ? ListView(children: const [SizedBox(height: 150), Center(child: Text('No support tickets yet.'))]) : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), itemCount: _rows.length, separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (_, i) {
              final t = _rows[i]; final status = t['status']?.toString() ?? 'open'; final priority = t['priority']?.toString() ?? 'medium';
              return Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)), child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => _open(t), child: Padding(
                padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(t['ticket_no']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary))), _Badge(text: _pretty(priority), color: _priorityColor(priority))]),
                  const SizedBox(height: 7), Text(t['subject']?.toString() ?? 'Support ticket', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 9), Row(children: [_Badge(text: _pretty(status), color: _statusColor(status)), const SizedBox(width: 8), Expanded(child: Text(t['assignee'] is Map && t['assignee']['name'] != null ? 'Assigned to ${t['assignee']['name']}' : 'Awaiting assignment', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)))]),
                ]),
              )));
            },
          ),
        )),
      ]),
    );
  }
}

class SupportCreateTicketScreen extends StatefulWidget {
  const SupportCreateTicketScreen({super.key});
  @override State<SupportCreateTicketScreen> createState() => _SupportCreateTicketScreenState();
}

class _SupportCreateTicketScreenState extends State<SupportCreateTicketScreen> {
  final _key = GlobalKey<FormState>(); final _subject = TextEditingController(); final _module = TextEditingController(); final _description = TextEditingController();
  String _category = 'app_technical'; String _priority = 'medium'; bool _sendPriority = true; bool _busy = false; List<XFile> _files = [];
  @override void initState() { super.initState(); _loadRole(); }
  Future<void> _loadRole() async { final p = await SharedPreferences.getInstance(); final role = (p.getString('activeRole') ?? p.getString('role') ?? '').toLowerCase(); if (mounted) setState(() => _sendPriority = role != 'student' && role != 'parent'); }
  @override void dispose() { _subject.dispose(); _module.dispose(); _description.dispose(); super.dispose(); }
  Future<void> _pick() async { final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: 'Support files', extensions: ['jpg','jpeg','png','webp','pdf','txt','docx'])]); if (mounted) setState(() => _files = files.take(5).toList()); }
  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return; setState(() => _busy = true);
    try { await SupportCenterApi.create(subject: _subject.text.trim(), description: _description.text.trim(), category: _category, module: _module.text.trim(), priority: _priority, sendPriority: _sendPriority, filePaths: _files.map((f) => f.path).toList()); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support ticket created.'))); Navigator.pop(context, true); } }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Raise Support Ticket')),
    body: Form(key: _key, child: ListView(padding: const EdgeInsets.all(16), children: [
      TextFormField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Subject is required' : null), const SizedBox(height: 14),
      DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()), items: const [DropdownMenuItem(value:'app_technical',child:Text('ERP / App Technical Problem')),DropdownMenuItem(value:'login',child:Text('Login / Account')),DropdownMenuItem(value:'fee_payment',child:Text('Fee / Payment')),DropdownMenuItem(value:'examination',child:Text('Examination / Marks')),DropdownMenuItem(value:'attendance',child:Text('Attendance')),DropdownMenuItem(value:'academic',child:Text('Academic')),DropdownMenuItem(value:'transport',child:Text('Transport')),DropdownMenuItem(value:'reports',child:Text('Reports')),DropdownMenuItem(value:'other',child:Text('Other'))], onChanged:(v)=>setState(()=>_category=v??'other')), const SizedBox(height:14),
      TextFormField(controller: _module, decoration: const InputDecoration(labelText: 'Module (optional)', hintText:'Examination, Fees, Attendance…', border: OutlineInputBorder())), const SizedBox(height:14),
      if (_sendPriority) ...[DropdownButtonFormField<String>(value:_priority, decoration: const InputDecoration(labelText:'Priority',border:OutlineInputBorder()), items: const [DropdownMenuItem(value:'low',child:Text('Low')),DropdownMenuItem(value:'medium',child:Text('Medium')),DropdownMenuItem(value:'high',child:Text('High')),DropdownMenuItem(value:'urgent',child:Text('Urgent'))], onChanged:(v)=>setState(()=>_priority=v??'medium')), const SizedBox(height:14)],
      TextFormField(controller:_description,minLines:5,maxLines:10,decoration:const InputDecoration(labelText:'Description',hintText:'What happened and what were you trying to do?',border:OutlineInputBorder()),validator:(v)=>v==null||v.trim().isEmpty?'Description is required':null), const SizedBox(height:14),
      OutlinedButton.icon(onPressed:_busy?null:_pick,icon:const Icon(Icons.attach_file_rounded),label:Text(_files.isEmpty?'Add screenshots / files':'${_files.length} file(s) selected')), if(_files.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),child:Text(_files.map((f)=>f.name).join(', '),style:TextStyle(fontSize:12,color:Colors.grey.shade700))), const SizedBox(height:20),
      FilledButton.icon(onPressed:_busy?null:_submit,icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.send_rounded),label:Text(_busy?'Submitting…':'Submit Ticket')),
    ])),
  );
}

class SupportTicketDetailScreen extends StatefulWidget {
  final String ticketNo; const SupportTicketDetailScreen({super.key, required this.ticketNo});
  @override State<SupportTicketDetailScreen> createState() => _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<SupportTicketDetailScreen> {
  Map<String,dynamic>? _ticket; bool _loading=true; bool _busy=false; String? _error; final _reply=TextEditingController(); List<XFile> _files=[];
  @override void initState(){super.initState();_load();} @override void dispose(){_reply.dispose();super.dispose();}
  Future<void> _load() async { setState((){_loading=true;_error=null;}); try{final t=await SupportCenterApi.ticket(widget.ticketNo);if(mounted)setState(()=>_ticket=t);}catch(e){if(mounted)setState(()=>_error=e.toString());}finally{if(mounted)setState(()=>_loading=false);} }
  Future<void> _pick() async {final f=await openFiles(acceptedTypeGroups:const [XTypeGroup(label:'Support files',extensions:['jpg','jpeg','png','webp','pdf','txt','docx'])]);if(mounted)setState(()=>_files=f.take(5).toList());}
  Future<void> _send() async {if(_reply.text.trim().isEmpty&&_files.isEmpty)return;setState(()=>_busy=true);try{final t=await SupportCenterApi.reply(widget.ticketNo,message:_reply.text.trim(),filePaths:_files.map((e)=>e.path).toList());if(mounted)setState((){_ticket=t;_reply.clear();_files=[];});}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> _reopen() async {setState(()=>_busy=true);try{final t=await SupportCenterApi.reopen(widget.ticketNo);if(mounted)setState(()=>_ticket=t);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context){final t=_ticket;return Scaffold(appBar:AppBar(title:Text(widget.ticketNo),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh_rounded))]),body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?_ErrorView(message:_error!,retry:_load):t==null?const Center(child:Text('Ticket not found.')):Column(children:[
    Container(width:double.infinity,padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:.45)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t['subject']?.toString()??'',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)),const SizedBox(height:9),Wrap(spacing:8,runSpacing:8,children:[_Badge(text:_pretty(t['priority']),color:_priorityColor(t['priority']?.toString()??'medium')),_Badge(text:_pretty(t['status']),color:_statusColor(t['status']?.toString()??'open')),_Badge(text:_pretty(t['category']),color:Colors.blueGrey)]),if(['resolved','closed'].contains(t['status']))... [const SizedBox(height:10),OutlinedButton.icon(onPressed:_busy?null:_reopen,icon:const Icon(Icons.replay_rounded),label:const Text('Reopen Ticket'))]])),
    Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[...(t['messages'] is List?(t['messages'] as List):const []).whereType<Map>().map((raw){final m=Map<String,dynamic>.from(raw);final support=m['sender_type']=='support_user';return Align(alignment:support?Alignment.centerLeft:Alignment.centerRight,child:Container(constraints:const BoxConstraints(maxWidth:520),margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:support?Colors.white:Theme.of(context).colorScheme.primaryContainer.withValues(alpha:.55),border:Border.all(color:Colors.grey.shade200),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(m['sender_name']?.toString()??(support?'Edubridge Support':'You'),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800)),const SizedBox(height:5),Text(m['message']?.toString()??''),if(m['attachments'] is List&&(m['attachments'] as List).isNotEmpty)...[const SizedBox(height:7),Text('${(m['attachments'] as List).length} attachment(s)',style:TextStyle(fontSize:12,color:Colors.grey.shade700))]])));})]),),
    SafeArea(top:false,child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Theme.of(context).scaffoldBackgroundColor,border:Border(top:BorderSide(color:Colors.grey.shade200))),child:Column(children:[TextField(controller:_reply,minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'Reply to Edubridge Support…',border:OutlineInputBorder())),const SizedBox(height:7),Row(children:[IconButton(onPressed:_busy?null:_pick,tooltip:'Attach file',icon:Badge(isLabelVisible:_files.isNotEmpty,label:Text('${_files.length}'),child:const Icon(Icons.attach_file_rounded))),const Spacer(),FilledButton.icon(onPressed:_busy?null:_send,icon:const Icon(Icons.send_rounded),label:Text(_busy?'Sending…':'Send'))])]))),
  ]));}
}

class _Badge extends StatelessWidget { final String text; final Color color; const _Badge({required this.text,required this.color}); @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:color.withValues(alpha:.11),borderRadius:BorderRadius.circular(999)),child:Text(text,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w800))); }
class _ErrorView extends StatelessWidget { final String message; final VoidCallback retry; const _ErrorView({required this.message, required this.retry}); @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.error_outline_rounded,size:42,color:Colors.redAccent),const SizedBox(height:10),Text(message,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:retry,child:const Text('Try Again'))]))); }
