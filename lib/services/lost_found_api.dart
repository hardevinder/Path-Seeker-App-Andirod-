import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class LostFoundApiException implements Exception { final String message; const LostFoundApiException(this.message); @override String toString()=>message; }
class LostFoundApi {
  static dynamic _decode(http.Response r){dynamic d;try{d=jsonDecode(r.body);}catch(_){d={'message':r.body};}if(r.statusCode<200||r.statusCode>=300){final m=d is Map?d['message']?.toString():null;throw LostFoundApiException((m??'Request failed (${r.statusCode})').trim());}return d;}
  static Future<String> _token() async {final p=await SharedPreferences.getInstance();final t=p.getString('authToken')??p.getString('token');if(t==null||t.trim().isEmpty)throw const LostFoundApiException('Your login session has expired.');return t.trim();}
  static Future<Map<String,dynamic>> capabilities() async {final r=await ApiService.rawGet('/lost-found/capabilities');final d=_decode(r);return d is Map?Map<String,dynamic>.from(d):{};}
  static Future<List<dynamic>> items({String entryType='found'}) async {final r=await ApiService.rawGet('/lost-found/items?entry_type=${Uri.encodeQueryComponent(entryType)}&limit=150');final d=_decode(r);return d is Map&&d['items'] is List?List<dynamic>.from(d['items']):[];}
  static Future<Map<String,dynamic>> createItem({required Map<String,String> fields,String? imagePath}) async {final req=http.MultipartRequest('POST',Uri.parse('${ApiService.baseUrl}/lost-found/items'));req.headers['Authorization']='Bearer ${await _token()}';req.headers['Accept']='application/json';req.fields.addAll(fields);if(imagePath!=null&&imagePath.trim().isNotEmpty)req.files.add(await http.MultipartFile.fromPath('image',imagePath));final streamed=await req.send().timeout(const Duration(seconds:90));final r=await http.Response.fromStream(streamed);final d=_decode(r);return d is Map?Map<String,dynamic>.from(d):{};}
  static Future<Uint8List?> imageBytes(int id) async {final r=await http.get(Uri.parse('${ApiService.baseUrl}/lost-found/items/$id/image'),headers:{'Authorization':'Bearer ${await _token()}','Accept':'image/*'}).timeout(const Duration(seconds:30));if(r.statusCode==404)return null;if(r.statusCode<200||r.statusCode>=300){_decode(r);return null;}return r.bodyBytes;}
  static Future<Map<String,dynamic>> claim(int itemId,{required int studentId,String note=''}) async {final r=await ApiService.rawPost('/lost-found/items/$itemId/claims',{'student_id':studentId,'claim_note':note});final d=_decode(r);return d is Map?Map<String,dynamic>.from(d):{};}
  static Future<List<dynamic>> myClaims() async {final r=await ApiService.rawGet('/lost-found/my-claims');final d=_decode(r);return d is Map&&d['claims'] is List?List<dynamic>.from(d['claims']):[];}
  static Future<List<dynamic>> matches(int itemId) async {final r=await ApiService.rawGet('/lost-found/matches?item_id=$itemId');final d=_decode(r);return d is Map&&d['matches'] is List?List<dynamic>.from(d['matches']):[];}
}
