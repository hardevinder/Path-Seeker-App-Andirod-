import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'api_service.dart';

class SchoolChatService {
  IO.Socket? socket;
  Future<String?> _token() async => (await SharedPreferences.getInstance()).getString('authToken');
  String get baseUrl => ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<void> connect({
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(Map<String, dynamic>) onThreadUpdated,
    required void Function(Map<String, dynamic>) onTyping,
    required void Function(Map<String, dynamic>) onSeen,
    void Function(Map<String, dynamic>)? onPresence,
  }) async {
    final token = await _token();
    socket?.dispose();
    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'auth': {'token': token},
    });
    socket!
      ..on('schoolchat:message', (d) => onMessage(_map(d)))
      ..on('schoolchat:thread-updated', (d) => onThreadUpdated(_map(d)))
      ..on('schoolchat:typing', (d) => onTyping(_map(d)))
      ..on('schoolchat:seen', (d) => onSeen(_map(d)))
      ..on('schoolchat:delivered', (d) => onSeen(_map(d)))
      ..on('schoolchat:presence-changed', (d) => onPresence?.call(_map(d)))
      ..connect();
  }

  Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    return {'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<List<Map<String, dynamic>>> threads() async {
    final r = await http.get(Uri.parse('$baseUrl/api/school-chat/threads'), headers: await _headers());
    final j = jsonDecode(r.body); if (r.statusCode >= 300) throw Exception(j['message'] ?? 'Failed to load chats');
    return (j['threads'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> recipients() async {
    final r = await http.get(Uri.parse('$baseUrl/api/school-chat/recipients'), headers: await _headers());
    final j = jsonDecode(r.body); if (r.statusCode >= 300) throw Exception(j['message'] ?? 'Failed to load recipients');
    return (j['recipients'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> start(Map<String, dynamic> recipient) async {
    final h = await _headers(); h['Content-Type'] = 'application/json';
    final r = await http.post(Uri.parse('$baseUrl/api/school-chat/threads'), headers: h, body: jsonEncode({'kind': recipient['kind'], 'id': recipient['id']}));
    final j = jsonDecode(r.body); if (r.statusCode >= 300) throw Exception(j['message'] ?? 'Unable to start chat');
    return Map<String, dynamic>.from(j['thread']);
  }

  Future<List<Map<String, dynamic>>> messages(int threadId) async {
    final r = await http.get(Uri.parse('$baseUrl/api/school-chat/threads/$threadId/messages?limit=80'), headers: await _headers());
    final j = jsonDecode(r.body); if (r.statusCode >= 300) throw Exception(j['message'] ?? 'Unable to load messages');
    return (j['messages'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void join(int threadId, {int? uptoMessageId}) => socket?.emit('schoolchat:join', {'threadId': threadId, if (uptoMessageId != null) 'uptoMessageId': uptoMessageId});
  void leave(int threadId) => socket?.emit('schoolchat:leave', {'threadId': threadId});
  void typing(int threadId, bool value) => socket?.emit('schoolchat:typing', {'threadId': threadId, 'isTyping': value});
  void seen(int threadId, int messageId) => socket?.emit('schoolchat:seen', {'threadId': threadId, 'messageId': messageId});

  Future<Map<String, dynamic>> send(int threadId, String body) async {
    final c = Completer<Map<String, dynamic>>();
    socket?.emitWithAck('schoolchat:send', {'threadId': threadId, 'body': body, 'clientNonce': '${DateTime.now().microsecondsSinceEpoch}'}, ack: (d) {
      final m = _map(d); if (m['ok'] == true) c.complete(Map<String, dynamic>.from(m['message'])); else c.completeError(Exception(m['message'] ?? 'Send failed'));
    });
    return c.future.timeout(const Duration(seconds: 15));
  }

  Future<void> sendFiles(int threadId, List<XFile> files, {String body = ''}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/school-chat/threads/$threadId/attachment-message'));
    req.headers.addAll(await _headers()); req.fields['body'] = body;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes('files', bytes, filename: f.name));
    }
    final r = await http.Response.fromStream(await req.send());
    if (r.statusCode >= 300) { final j = jsonDecode(r.body); throw Exception(j['message'] ?? 'Attachment send failed'); }
  }

  Future<void> openAttachment(Map<String, dynamic> attachment) async {
    final url = '$baseUrl${attachment['downloadUrl']}';
    final r = await http.get(Uri.parse(url), headers: await _headers());
    if (r.statusCode >= 300) throw Exception('Unable to download attachment');
    final dir = await getTemporaryDirectory();
    final safe = '${attachment['name'] ?? 'attachment'}'.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final file = File('${dir.path}/$safe'); await file.writeAsBytes(Uint8List.fromList(r.bodyBytes), flush: true); await OpenFilex.open(file.path);
  }

  void dispose() { socket?.dispose(); socket = null; }
}
