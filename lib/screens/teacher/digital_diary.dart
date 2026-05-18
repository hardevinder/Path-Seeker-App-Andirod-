// File: lib/screens/teacher/digital_diary.dart
// Updated digital diary screen with acknowledgement and download-history viewers for teachers.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int PAGE_SIZE = 20;
final Dio dio = Dio(BaseOptions(receiveDataWhenStatusError: true));

Future<Map<String, String>> getAuthHeaders() async {
  final sp = await SharedPreferences.getInstance();
  final token = sp.getString('token') ??
      sp.getString('jwt') ??
      sp.getString('accessToken') ??
      sp.getString('authToken');
  if (token == null || token.isEmpty) return {};
  return {'Authorization': 'Bearer $token'};
}

class RoleFlags {
  final List<String> roles;
  final bool isAdmin;
  final bool isSuperadmin;
  final bool isHR;
  final bool isCoordinator;
  final bool isTeacher;
  final bool isStudent;

  RoleFlags({
    required this.roles,
    required this.isAdmin,
    required this.isSuperadmin,
    required this.isHR,
    required this.isCoordinator,
    required this.isTeacher,
    required this.isStudent,
  });
}

Future<RoleFlags> getRoleFlags() async {
  final sp = await SharedPreferences.getInstance();
  final single = sp.getString('userRole');
  final multiRaw = sp.getString('roles');

  List<String> multi = [];
  try {
    if (multiRaw != null) {
      final decoded = jsonDecode(multiRaw);
      if (decoded is List) {
        multi = decoded.map((e) => e.toString()).toList();
      }
    }
  } catch (_) {}

  final roles = multi.isNotEmpty ? multi : (single != null ? [single] : []);
  final lc = roles.map((r) => r.toLowerCase()).toList();

  return RoleFlags(
    roles: roles,
    isAdmin: lc.contains('admin'),
    isSuperadmin: lc.contains('superadmin'),
    isHR: lc.contains('hr'),
    isCoordinator: lc.contains('academic_coordinator'),
    isTeacher: lc.contains('teacher'),
    isStudent: lc.contains('student'),
  );
}

List<String> buildDiaryCandidates() {
  return ['/diaries', 'diaries'];
}

Future<Response> diaryRequest({
  String method = 'get',
  String suffix = '',
  Map<String, dynamic>? params,
  dynamic data,
  Map<String, String> headers = const {},
}) async {
  final sp = await SharedPreferences.getInstance();
  final cached = sp.getString('diary_base_selected');
  final candidates = buildDiaryCandidates();
  final tried = cached != null
      ? [cached, ...candidates.where((p) => p != cached)]
      : candidates;

  dynamic lastErr;

  String joinBase(String base, String suf) {
    if (suf.isEmpty) return base;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final s = suf.startsWith('/') ? suf : '/$suf';
    return '$b$s';
  }

  for (final base in tried) {
    final url = joinBase(base, suffix);
    try {
      final auth = await getAuthHeaders();
      final opt = Options(headers: {...auth, ...headers});
      late Response res;
      final m = method.toLowerCase();

      if (m == 'get') {
        res = await dio.get(url, queryParameters: params, options: opt);
      } else if (m == 'post') {
        res = await dio.post(url, data: data, queryParameters: params, options: opt);
      } else if (m == 'put') {
        res = await dio.put(url, data: data, queryParameters: params, options: opt);
      } else if (m == 'delete') {
        res = await dio.delete(url, data: data, queryParameters: params, options: opt);
      } else {
        throw Exception('Unsupported method $method');
      }

      if (cached != base) {
        await sp.setString('diary_base_selected', base);
      }
      return res;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) rethrow;
      lastErr = e;
    }
  }

  throw lastErr ?? Exception('Diary request failed');
}

Future<Response> diaryGet(String s, [Map<String, dynamic>? p]) =>
    diaryRequest(method: 'get', suffix: s, params: p);
Future<Response> diaryPost(String s, [dynamic d, Map<String, String> h = const {}]) =>
    diaryRequest(method: 'post', suffix: s, data: d, headers: h);
Future<Response> diaryPut(String s, [dynamic d, Map<String, String> h = const {}]) =>
    diaryRequest(method: 'put', suffix: s, data: d, headers: h);
Future<Response> diaryDelete(String s, [Map<String, dynamic>? p]) =>
    diaryRequest(method: 'delete', suffix: s, params: p);

String safeStr(dynamic value) => value == null ? '' : value.toString();

String formatDiaryDate(String value) {
  if (value.isEmpty) return '';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd MMM yyyy').format(parsed);
}

String formatDiaryDateTime(String value) {
  if (value.isEmpty) return '';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
}

Color diaryTypeColor(String type) {
  switch (type.toUpperCase()) {
    case 'HOMEWORK':
      return Colors.indigo;
    case 'REMARK':
      return Colors.orange;
    case 'ANNOUNCEMENT':
      return Colors.green;
    default:
      return Colors.blueGrey;
  }
}

IconData diaryTypeIcon(String type) {
  switch (type.toUpperCase()) {
    case 'HOMEWORK':
      return Icons.menu_book_rounded;
    case 'REMARK':
      return Icons.warning_amber_rounded;
    case 'ANNOUNCEMENT':
      return Icons.campaign_rounded;
    default:
      return Icons.sticky_note_2_rounded;
  }
}

class DiaryDownloadEntry {
  final int id;
  final int? studentId;
  final String admissionNumber;
  final String studentName;
  final String downloadedAt;

  DiaryDownloadEntry({
    required this.id,
    this.studentId,
    required this.admissionNumber,
    required this.studentName,
    required this.downloadedAt,
  });

  factory DiaryDownloadEntry.fromMap(Map m) {
    final student = m['student'];
    return DiaryDownloadEntry(
      id: m['id'] is int ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      studentId: m['studentId'] is int ? m['studentId'] : int.tryParse('${m['studentId']}'),
      admissionNumber: safeStr(
        m['admissionNumber'] ??
            m['admission_number'] ??
            (student is Map ? student['admission_number'] : null),
      ),
      studentName: safeStr(
        m['studentName'] ??
            m['name'] ??
            (student is Map ? student['name'] : null),
      ),
      downloadedAt: safeStr(m['downloadedAt'] ?? m['createdAt']),
    );
  }
}


class DiaryAcknowledgementEntry {
  final int id;
  final int? studentId;
  final String admissionNumber;
  final String studentName;
  final String rollNumber;
  final String note;
  final String acknowledgedAt;

  DiaryAcknowledgementEntry({
    required this.id,
    this.studentId,
    required this.admissionNumber,
    required this.studentName,
    required this.rollNumber,
    required this.note,
    required this.acknowledgedAt,
  });

  factory DiaryAcknowledgementEntry.fromMap(Map m) {
    final student = m['student'];
    return DiaryAcknowledgementEntry(
      id: m['id'] is int ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      studentId: m['studentId'] is int ? m['studentId'] : int.tryParse('${m['studentId']}'),
      admissionNumber: safeStr(
        m['admissionNumber'] ??
            m['admission_number'] ??
            (student is Map ? student['admission_number'] : null),
      ),
      studentName: safeStr(
        m['studentName'] ??
            m['name'] ??
            (student is Map ? student['name'] : null),
      ),
      rollNumber: safeStr(
        m['rollNumber'] ??
            m['roll_number'] ??
            (student is Map ? student['roll_number'] : null),
      ),
      note: safeStr(m['note']),
      acknowledgedAt: safeStr(m['acknowledgedAt'] ?? m['createdAt']),
    );
  }
}

class Diary {
  int id;
  String date;
  String type;
  String title;
  String content;
  dynamic classObj;
  dynamic sectionObj;
  dynamic subject;
  List<dynamic> attachments;
  List<dynamic> targets;
  List<DiaryAcknowledgementEntry> acknowledgements;
  List<dynamic> views;
  List<DiaryDownloadEntry> downloads;
  List<int>? sourceIds;

  Diary({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    required this.content,
    this.classObj,
    this.sectionObj,
    this.subject,
    this.attachments = const [],
    this.targets = const [],
    this.acknowledgements = const [],
    this.views = const [],
    this.downloads = const [],
    this.sourceIds,
  });

  factory Diary.fromMap(Map m) {
    return Diary(
      id: (m['id'] is int) ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      date: safeStr(m['date']),
      type: safeStr(m['type']).isEmpty ? 'ANNOUNCEMENT' : safeStr(m['type']),
      title: safeStr(m['title']),
      content: safeStr(m['content']),
      classObj: m['class'] ?? m['Class'],
      sectionObj: m['section'] ?? m['Section'],
      subject: m['subject'],
      attachments: (m['attachments'] is List) ? List.from(m['attachments']) : [],
      targets: (m['targets'] is List) ? List.from(m['targets']) : [],
      acknowledgements: (m['acknowledgements'] is List)
          ? List.from(m['acknowledgements'])
              .whereType<Map>()
              .map((e) => DiaryAcknowledgementEntry.fromMap(e))
              .toList()
          : [],
      views: (m['views'] is List) ? List.from(m['views']) : [],
      downloads: (m['downloads'] is List)
          ? List.from(m['downloads'])
              .whereType<Map>()
              .map((e) => DiaryDownloadEntry.fromMap(e))
              .toList()
          : [],
      sourceIds: (m['_sourceIds'] is List)
          ? List.from(m['_sourceIds'])
              .map((e) => int.tryParse('$e') ?? 0)
              .where((e) => e > 0)
              .toList()
          : null,
    );
  }
}


class AcknowledgementSummary {
  final String key;
  final int? studentId;
  final String admissionNumber;
  final String studentName;
  final String rollNumber;
  final String latestAcknowledgedAt;
  final String note;
  final int count;

  AcknowledgementSummary({
    required this.key,
    this.studentId,
    required this.admissionNumber,
    required this.studentName,
    required this.rollNumber,
    required this.latestAcknowledgedAt,
    required this.note,
    required this.count,
  });
}

List<AcknowledgementSummary> summarizeAcknowledgements(
  List<DiaryAcknowledgementEntry> acknowledgements,
) {
  final Map<String, List<DiaryAcknowledgementEntry>> grouped = {};

  for (final entry in acknowledgements) {
    final key = entry.studentId != null
        ? 'student:${entry.studentId}'
        : 'adm:${entry.admissionNumber.isEmpty ? entry.id.toString() : entry.admissionNumber}';
    grouped.putIfAbsent(key, () => []).add(entry);
  }

  final summaries = grouped.entries.map((entry) {
    final items = List<DiaryAcknowledgementEntry>.from(entry.value);
    items.sort(
      (a, b) => safeStr(b.acknowledgedAt).compareTo(safeStr(a.acknowledgedAt)),
    );
    final latest = items.first;
    return AcknowledgementSummary(
      key: entry.key,
      studentId: latest.studentId,
      admissionNumber: latest.admissionNumber,
      studentName: latest.studentName,
      rollNumber: latest.rollNumber,
      latestAcknowledgedAt: latest.acknowledgedAt,
      note: latest.note,
      count: items.length,
    );
  }).toList();

  summaries.sort(
    (a, b) => safeStr(b.latestAcknowledgedAt).compareTo(safeStr(a.latestAcknowledgedAt)),
  );
  return summaries;
}

Future<List<DiaryAcknowledgementEntry>> fetchDiaryAcknowledgements(int diaryId) async {
  try {
    final res = await diaryGet('/$diaryId/acknowledgements');
    final raw = res.data;
    final list = raw is List
        ? raw
        : raw is Map
            ? (raw['acknowledgements'] ?? raw['data'] ?? raw['items'] ?? [])
            : [];
    if (list is List) {
      return List.from(list)
          .whereType<Map>()
          .map((e) => DiaryAcknowledgementEntry.fromMap(e))
          .toList();
    }
  } catch (_) {
    // Fallback to full diary detail if dedicated route is not available
    final diary = await fetchDiaryDetailsForDownloads(diaryId);
    return diary.acknowledgements;
  }
  return [];
}

Future<void> showDiaryAcknowledgementsSheet(BuildContext context, Diary seedDiary) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: FutureBuilder<List<DiaryAcknowledgementEntry>>(
              future: fetchDiaryAcknowledgements(seedDiary.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Icon(Icons.error_outline_rounded, size: 42, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text(
                          'Unable to load acknowledgements',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                final summary = summarizeAcknowledgements(snapshot.data ?? const []);

                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Acknowledgements',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  seedDiary.title.isEmpty ? 'Diary #${seedDiary.id}' : seedDiary.title,
                                  style: const TextStyle(color: Colors.black54),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${summary.length}',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  summary.length == 1 ? 'student' : 'students',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: summary.isEmpty
                          ? ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
                              children: const [
                                Icon(Icons.check_circle_outline_rounded, size: 56, color: Colors.blueGrey),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    'No acknowledgements yet.',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Center(
                                  child: Text(
                                    'Once students acknowledge this diary, their names will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                              itemCount: summary.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = summary[index];
                                final displayName = item.studentName.isNotEmpty
                                    ? item.studentName
                                    : (item.admissionNumber.isNotEmpty
                                        ? item.admissionNumber
                                        : 'Student');
                                final details = <String>[
                                  if (item.admissionNumber.isNotEmpty) 'Adm: ${item.admissionNumber}',
                                  if (item.rollNumber.isNotEmpty) 'Roll: ${item.rollNumber}',
                                ].join(' • ');

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: Colors.green.shade100,
                                        child: Text(
                                          displayName.isNotEmpty
                                              ? displayName.trim().substring(0, 1).toUpperCase()
                                              : 'S',
                                          style: TextStyle(
                                            color: Colors.green.shade900,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (details.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                details,
                                                style: const TextStyle(color: Colors.black54),
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Text(
                                              'Acknowledged: ${formatDiaryDateTime(item.latestAcknowledgedAt)}',
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                            if (item.note.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Note: ${item.note}',
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 12.5,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.green.shade100),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              '${item.count}',
                                              style: TextStyle(
                                                color: Colors.green.shade800,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.count == 1 ? 'time' : 'times',
                                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );
}

class DownloadSummary {
  final String key;
  final int? studentId;
  final String admissionNumber;
  final String studentName;
  final String latestDownloadedAt;
  final int count;

  DownloadSummary({
    required this.key,
    this.studentId,
    required this.admissionNumber,
    required this.studentName,
    required this.latestDownloadedAt,
    required this.count,
  });
}

List<DownloadSummary> summarizeDownloads(List<DiaryDownloadEntry> downloads) {
  final Map<String, List<DiaryDownloadEntry>> grouped = {};

  for (final entry in downloads) {
    final key = entry.studentId != null
        ? 'student:${entry.studentId}'
        : 'adm:${entry.admissionNumber.isEmpty ? entry.id.toString() : entry.admissionNumber}';
    grouped.putIfAbsent(key, () => []).add(entry);
  }

  final summaries = grouped.entries.map((entry) {
    final items = List<DiaryDownloadEntry>.from(entry.value);
    items.sort((a, b) => safeStr(b.downloadedAt).compareTo(safeStr(a.downloadedAt)));
    final latest = items.first;
    return DownloadSummary(
      key: entry.key,
      studentId: latest.studentId,
      admissionNumber: latest.admissionNumber,
      studentName: latest.studentName,
      latestDownloadedAt: latest.downloadedAt,
      count: items.length,
    );
  }).toList();

  summaries.sort((a, b) => safeStr(b.latestDownloadedAt).compareTo(safeStr(a.latestDownloadedAt)));
  return summaries;
}

Future<Diary> fetchDiaryDetailsForDownloads(int diaryId) async {
  final res = await diaryGet('/$diaryId');
  final raw = res.data is Map ? (res.data['diary'] ?? res.data) : res.data;
  if (raw is Map) {
    return Diary.fromMap(raw);
  }
  throw Exception('Invalid diary response');
}

Future<void> showDiaryDownloadsSheet(BuildContext context, Diary seedDiary) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: FutureBuilder<Diary>(
              future: fetchDiaryDetailsForDownloads(seedDiary.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Icon(Icons.error_outline_rounded, size: 42, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text(
                          'Unable to load download history',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                final diary = snapshot.data ?? seedDiary;
                final summary = summarizeDownloads(diary.downloads);

                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Download History',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  diary.title.isEmpty ? 'Diary #${diary.id}' : diary.title,
                                  style: const TextStyle(color: Colors.black54),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${summary.length}',
                                  style: TextStyle(
                                    color: Colors.indigo.shade800,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  summary.length == 1 ? 'student' : 'students',
                                  style: TextStyle(
                                    color: Colors.indigo.shade700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: summary.isEmpty
                          ? ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
                              children: const [
                                Icon(Icons.cloud_download_outlined, size: 56, color: Colors.blueGrey),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    'No download history yet.',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Center(
                                  child: Text(
                                    'Once students download attachments, their names and admission numbers will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                              itemCount: summary.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = summary[index];
                                final displayName = item.studentName.isNotEmpty
                                    ? item.studentName
                                    : (item.admissionNumber.isNotEmpty
                                        ? item.admissionNumber
                                        : 'Student');
                                final sub = item.admissionNumber.isNotEmpty
                                    ? 'Admission No: ${item.admissionNumber}'
                                    : 'Student record';

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: Colors.indigo.shade100,
                                        child: Text(
                                          displayName.isNotEmpty
                                              ? displayName.trim().substring(0, 1).toUpperCase()
                                              : 'S',
                                          style: TextStyle(
                                            color: Colors.indigo.shade900,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              sub,
                                              style: const TextStyle(color: Colors.black54),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Last download: ${formatDiaryDateTime(item.latestDownloadedAt)}',
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.indigo.shade100),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              '${item.count}',
                                              style: TextStyle(
                                                color: Colors.indigo.shade800,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.count == 1 ? 'time' : 'times',
                                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );
}

class DigitalDiaryPage extends StatefulWidget {
  const DigitalDiaryPage({Key? key}) : super(key: key);

  @override
  State<DigitalDiaryPage> createState() => _DigitalDiaryPageState();
}

class _DigitalDiaryPageState extends State<DigitalDiaryPage> {
  late Future<RoleFlags> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = getRoleFlags();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoleFlags>(
      future: _rolesFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final r = snap.data!;
        final showManage =
            r.isAdmin || r.isSuperadmin || r.isHR || r.isCoordinator || r.isTeacher;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (showManage) ...[
                const ManageDiariesWidget(),
                const SizedBox(height: 24),
                const Divider(thickness: 1.5),
                const SizedBox(height: 24),
              ],
              const DiaryFeedWidget(),
            ],
          ),
        );
      },
    );
  }
}

class DiaryCardWidget extends StatelessWidget {
  final Diary diary;
  final bool canAck;
  final bool showDownloadAction;
  final bool showAcknowledgementAction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewDownloads;
  final VoidCallback? onViewAcknowledgements;

  const DiaryCardWidget({
    Key? key,
    required this.diary,
    this.canAck = false,
    this.showDownloadAction = false,
    this.showAcknowledgementAction = false,
    this.onEdit,
    this.onDelete,
    this.onViewDownloads,
    this.onViewAcknowledgements,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = diaryTypeColor(diary.type);
    final seenCount = diary.views.length;
    final ackCount = diary.acknowledgements.length;
    final downloadCount = summarizeDownloads(diary.downloads).length;
    final attachments = (diary.attachments).map<Map<String, String?>>((a) {
      if (a is String) {
        return {'href': a, 'label': a.split('/').last};
      }
      if (a is Map) {
        final href = a['fileUrl']?.toString() ?? a['url']?.toString();
        final label = a['originalName']?.toString() ??
            a['name']?.toString() ??
            (href != null ? href.split('/').last : 'Attachment');
        return {'href': href, 'label': label};
      }
      return {'href': null, 'label': 'Attachment'};
    }).where((a) => a['href'] != null).toList();

    final className = safeStr(diary.classObj?['class_name'] ?? diary.classObj?['name']);
    final sectionName = safeStr(diary.sectionObj?['section_name'] ?? diary.sectionObj?['name']);
    final subjectName = safeStr(diary.subject?['name']);

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(diaryTypeIcon(diary.type), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diary.title.isEmpty ? 'Untitled Diary' : diary.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              diary.type,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (className.isNotEmpty || sectionName.isNotEmpty)
                            _MetaPill(
                              icon: Icons.groups_rounded,
                              text: [className, sectionName]
                                  .where((e) => e.isNotEmpty)
                                  .join(' • '),
                            ),
                          if (subjectName.isNotEmpty)
                            _MetaPill(
                              icon: Icons.book_rounded,
                              text: subjectName,
                            ),
                          if (diary.date.isNotEmpty)
                            _MetaPill(
                              icon: Icons.calendar_today_rounded,
                              text: formatDiaryDate(diary.date),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              diary.content,
              style: const TextStyle(
                fontSize: 14.2,
                height: 1.45,
                color: Colors.black87,
              ),
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: attachments.map((a) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file_rounded, size: 16),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            a['label'] ?? 'Attachment',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountBadge(icon: Icons.visibility_rounded, label: 'Views', count: seenCount),
                      _CountBadge(icon: Icons.check_circle_rounded, label: 'Ack', count: ackCount),
                      _CountBadge(icon: Icons.download_rounded, label: 'Downloads', count: downloadCount),
                    ],
                  ),
                ),
              ],
            ),
            if (onEdit != null || onDelete != null || showDownloadAction || showAcknowledgementAction) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (showAcknowledgementAction)
                    FilledButton.icon(
                      onPressed: onViewAcknowledgements,
                      icon: const Icon(Icons.checklist_rounded),
                      label: const Text('View Acknowledgements'),
                    ),
                  if (showDownloadAction)
                    FilledButton.tonalIcon(
                      onPressed: onViewDownloads,
                      icon: const Icon(Icons.download_for_offline_rounded),
                      label: const Text('View Downloads'),
                    ),
                  if (onEdit != null)
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  if (onDelete != null)
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12.2, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _CountBadge({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class ManageDiariesWidget extends StatefulWidget {
  const ManageDiariesWidget({Key? key}) : super(key: key);

  @override
  State<ManageDiariesWidget> createState() => _ManageDiariesWidgetState();
}

class _ManageDiariesWidgetState extends State<ManageDiariesWidget> {
  List<Diary> diaries = [];
  bool applyLoading = false;
  bool pageLoading = false;
  int page = 1;
  int total = 0;

  Map<String, dynamic> filters = {
    'from': '',
    'to': '',
    'classId': '',
    'sectionId': '',
    'subjectId': '',
    'type': '',
    'q': '',
  };

  List<dynamic> classes = [];
  List<dynamic> sections = [];
  List<dynamic> subjects = [];
  List<dynamic> sessions = [];

  Map<String, dynamic> form = {};
  bool multiMode = false;
  List<Map<String, dynamic>> targets = [];
  Map<String, dynamic> draftTarget = {'classId': '', 'sectionId': ''};
  bool saving = false;
  List<dynamic> studentsForPicker = [];
  bool studentsLoading = false;
  String studentSearch = '';
  List<int> selectedStudentIds = [];
  bool showModal = false;

  @override
  void initState() {
    super.initState();
    _initLists();
  }

  Future<void> _initLists() async {
    setState(() => applyLoading = true);

    try {
      final cl = await dio.get('/classes', options: Options(headers: await getAuthHeaders()));
      final sec = await dio.get('/sections', options: Options(headers: await getAuthHeaders()));
      setState(() {
        classes = (cl.data is List) ? cl.data : (cl.data['classes'] ?? []);
        sections = (sec.data is List) ? sec.data : (sec.data['sections'] ?? []);
      });
    } catch (_) {}

    try {
      final resp = await dio.get(
        '/class-subject-teachers/teacher/class-subjects',
        options: Options(headers: await getAuthHeaders()),
      );
      final arr = (resp.data?['assignments'] ?? [])
          .map((a) => a['subject'])
          .where((s) => s != null)
          .toList();
      final map = <dynamic, dynamic>{};
      for (final s in arr) {
        map[s['id']] = s;
      }
      setState(() => subjects = map.values.toList());
    } catch (_) {
      setState(() => subjects = []);
    }

    try {
      final r = await dio.get('/sessions', options: Options(headers: await getAuthHeaders()));
      final list = (r.data is List) ? r.data : (r.data['items'] ?? []);
      setState(() => sessions = list);
      if (list.isNotEmpty) {
        form['sessionId'] = (list.firstWhere(
          (s) => s['is_active'] == true,
          orElse: () => list.first,
        ))['id'];
      }
    } catch (_) {
      setState(() => sessions = []);
    }

    await loadDiaries(1);
    setState(() => applyLoading = false);
  }

  Future<void> loadDiaries(int p) async {
    setState(() {
      applyLoading = true;
      pageLoading = true;
    });

    try {
      final params = {
        'page': p,
        'pageSize': PAGE_SIZE,
        if ((filters['from'] ?? '').toString().isNotEmpty) 'dateFrom': filters['from'],
        if ((filters['to'] ?? '').toString().isNotEmpty) 'dateTo': filters['to'],
        if ((filters['classId'] ?? '').toString().isNotEmpty) 'classId': filters['classId'],
        if ((filters['sectionId'] ?? '').toString().isNotEmpty) 'sectionId': filters['sectionId'],
        if ((filters['subjectId'] ?? '').toString().isNotEmpty) 'subjectId': filters['subjectId'],
        if ((filters['type'] ?? '').toString().isNotEmpty) 'type': filters['type'],
        if ((filters['q'] ?? '').toString().isNotEmpty) 'q': filters['q'],
      };

      final res = await diaryGet('', params);
      final list = (res.data?['data'] is List) ? res.data['data'] : [];
      setState(() {
        diaries = List.from(list.map((m) => Diary.fromMap(m)));
        total = res.data?['pagination']?['total'] ?? 0;
        page = p;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load diaries: $e')),
      );
    } finally {
      setState(() {
        applyLoading = false;
        pageLoading = false;
      });
    }
  }

  void openCreate() {
    setState(() {
      form = {
        'id': null,
        'sessionId': sessions.isNotEmpty
            ? (sessions.firstWhere(
                (s) => s['is_active'] == true,
                orElse: () => sessions[0],
              ))['id']
            : null,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'type': 'ANNOUNCEMENT',
        'title': '',
        'content': '',
        'classId': '',
        'sectionId': '',
        'subjectId': '',
        'attachments': [],
        'selectedFiles': [],
        'replaceAttachments': false,
        'keepAttachmentIds': [],
      };
      multiMode = false;
      targets = [];
      draftTarget = {'classId': '', 'sectionId': ''};
      studentsForPicker = [];
      selectedStudentIds = [];
      showModal = true;
    });
  }

  void openEdit(Diary d) {
    final existing = (d.attachments).map((a) {
      return {
        'id': a is Map ? a['id'] : null,
        'name': a is Map
            ? (a['originalName'] ?? a['name'] ?? (a['fileUrl']?.toString().split('/').last ?? 'Attachment'))
            : (a is String ? a.split('/').last : 'Attachment'),
        'url': a is Map ? (a['fileUrl'] ?? a['url']) : (a is String ? a : null),
        'kind': a is Map ? (a['kind'] ?? '') : '',
        'mimeType': a is Map ? a['mimeType'] : null,
        'size': a is Map ? a['size'] : null,
      };
    }).toList();

    setState(() {
      form = {
        'id': d.id,
        'sessionId': d.subject?['sessionId'] ?? null,
        'date': d.date.split('T').first,
        'type': d.type,
        'title': d.title,
        'content': d.content,
        'classId': d.classObj?['id']?.toString() ?? '',
        'sectionId': d.sectionObj?['id']?.toString() ?? '',
        'subjectId': d.subject?['id']?.toString() ?? '',
        'attachments': existing,
        'selectedFiles': [],
        'replaceAttachments': false,
        'keepAttachmentIds': existing.where((a) => a['id'] != null).map((a) => a['id']).toList(),
      };
      multiMode = false;
      targets = [];
      draftTarget = {'classId': '', 'sectionId': ''};
      showModal = true;
    });
  }

  Future<void> save() async {
    if (form['sessionId'] == null ||
        safeStr(form['date']).isEmpty ||
        safeStr(form['type']).isEmpty ||
        safeStr(form['title']).isEmpty ||
        safeStr(form['content']).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill session, date, type, title and content.')),
      );
      return;
    }

    if (!multiMode && safeStr(form['classId']).isEmpty && form['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Class & Section.')),
      );
      return;
    }

    if (multiMode && targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one Class & Section in Targets.')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final hasFiles = ((form['selectedFiles'] ?? []) as List).isNotEmpty;
      final isUpdate = form['id'] != null;

      if (!hasFiles && !(isUpdate && form['replaceAttachments'] == true)) {
        final payload = {
          'sessionId': int.tryParse('${form['sessionId']}') ?? form['sessionId'],
          'date': form['date'],
          'type': form['type'],
          'title': form['title'],
          'content': form['content'],
          'subjectId': safeStr(form['subjectId']).isNotEmpty
              ? int.tryParse('${form['subjectId']}')
              : null,
          'attachments': ((form['attachments'] ?? []) as List).map((a) {
            final m = a is Map ? a : {};
            return {
              'fileUrl': m['url'] ?? m['fileUrl'] ?? '',
              'originalName': m['name'] ?? m['originalName'] ?? (m['url']?.toString().split('/').last ?? ''),
              'mimeType': m['mimeType'] ?? 'application/octet-stream',
              'size': m['size'] ?? 0,
            };
          }).toList(),
          if (isUpdate) 'replaceAttachments': form['replaceAttachments'] == true,
          if (multiMode && !isUpdate) 'targets': targets,
          if (!multiMode && !isUpdate) 'classId': int.tryParse('${form['classId']}') ?? form['classId'],
          if (!multiMode && !isUpdate) 'sectionId': int.tryParse('${form['sectionId']}') ?? form['sectionId'],
          if (!isUpdate && !multiMode && selectedStudentIds.isNotEmpty) 'studentIds': selectedStudentIds,
        };

        if (isUpdate) {
          await diaryPut('/${form['id']}', payload);
        } else {
          await diaryPost('', payload);
        }
      } else {
        final fd = FormData();
        fd.fields.addAll([
          MapEntry('sessionId', '${form['sessionId']}'),
          MapEntry('date', '${form['date']}'),
          MapEntry('type', '${form['type']}'),
          MapEntry('title', '${form['title']}'),
          MapEntry('content', '${form['content']}'),
        ]);

        fd.fields.add(
          MapEntry(
            'attachments',
            jsonEncode(((form['attachments'] ?? []) as List).map((a) {
              final m = a is Map ? a : {};
              return {
                'fileUrl': m['url'] ?? m['fileUrl'] ?? '',
                'originalName': m['name'] ?? m['originalName'] ?? '',
                'mimeType': m['mimeType'] ?? 'application/octet-stream',
                'size': m['size'] ?? 0,
              };
            }).toList()),
          ),
        );

        if (multiMode && form['id'] == null) {
          fd.fields.add(MapEntry('targets', jsonEncode(targets)));
          for (var i = 0; i < targets.length; i++) {
            fd.fields.add(MapEntry('targets[$i][classId]', '${targets[i]['classId']}'));
            fd.fields.add(MapEntry('targets[$i][sectionId]', '${targets[i]['sectionId']}'));
          }
        } else {
          fd.fields.add(MapEntry('classId', '${form['classId']}'));
          fd.fields.add(MapEntry('sectionId', '${form['sectionId']}'));
        }

        if (!isUpdate && !multiMode && selectedStudentIds.isNotEmpty) {
          fd.fields.add(MapEntry('studentIds', selectedStudentIds.join(',')));
        }

        if (isUpdate) {
          if (form['replaceAttachments'] == true) {
            fd.fields.add(const MapEntry('replaceAttachments', 'true'));
          } else {
            fd.fields.add(MapEntry('existingFiles', jsonEncode(form['keepAttachmentIds'] ?? [])));
          }
        }

        final selFiles = (form['selectedFiles'] ?? []) as List;
        for (final f in selFiles) {
          try {
            if (f is PlatformFile && f.path != null) {
              fd.files.add(
                MapEntry('files', MultipartFile.fromFileSync(f.path!, filename: f.name)),
              );
            } else if (f is File) {
              fd.files.add(
                MapEntry('files', MultipartFile.fromFileSync(f.path, filename: f.path.split('/').last)),
              );
            }
          } catch (_) {}
        }

        if (form['id'] != null) {
          await diaryPut('/${form['id']}', fd);
        } else {
          await diaryPost('', fd);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(form['id'] != null ? 'Diary updated' : 'Diary created')),
      );
      setState(() => showModal = false);
      await loadDiaries(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> del(dynamic idOrIds) async {
    final ids = idOrIds is List ? idOrIds : [idOrIds];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ids.length > 1 ? 'Delete this message from all classes?' : 'Delete this diary?'),
        content: Text(
          ids.length > 1
              ? 'This will remove all copies of this message across selected classes/sections.'
              : 'This will archive (hide) the note. You can hard-delete later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => applyLoading = true);
    try {
      for (final id in ids) {
        await diaryDelete('/$id');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      await loadDiaries(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    } finally {
      setState(() => applyLoading = false);
    }
  }

  void addTarget() {
    final c = int.tryParse('${draftTarget['classId']}') ?? 0;
    final s = int.tryParse('${draftTarget['sectionId']}') ?? 0;
    if (c == 0 || s == 0) return;

    final exists = targets.any((t) => t['classId'] == c && t['sectionId'] == s);
    if (exists) return;

    setState(() {
      targets.add({'classId': c, 'sectionId': s});
      draftTarget = {'classId': '', 'sectionId': ''};
    });
  }

  void removeTargetAt(int idx) {
    setState(() => targets.removeAt(idx));
  }

  Future<void> pickFilesForForm() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res != null) {
        setState(() {
          form['selectedFiles'] = res.files;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick failed: $e')),
      );
    }
  }

  Future<void> loadStudentsForPicker() async {
    if (safeStr(form['classId']).isEmpty || safeStr(form['sectionId']).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select class and section first.')),
      );
      return;
    }

    setState(() => studentsLoading = true);
    try {
      final res = await dio.get(
        '/students/searchByClassAndSection',
        queryParameters: {
          'class_id': form['classId'],
          'section_id': form['sectionId'],
          'q': studentSearch.length >= 2 ? studentSearch : null,
          'limit': 500,
        },
        options: Options(headers: await getAuthHeaders()),
      );

      final data = res.data;
      final list = data is List ? data : (data['data'] ?? data['items'] ?? []);
      setState(() {
        studentsForPicker = List.from(list);
        selectedStudentIds = selectedStudentIds
            .where((id) => studentsForPicker.any((s) => s['id'] == id))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load students.')),
      );
    } finally {
      setState(() => studentsLoading = false);
    }
  }

  Widget _buildAttachmentLinksEditor() {
    final attachmentsList = List.from((form['attachments'] ?? []) as List);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Attachments (Links)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (attachmentsList.isEmpty)
          const Text('No attachment links added.', style: TextStyle(color: Colors.black54)),
        ...attachmentsList.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(safeStr(item['name']).isEmpty ? 'Attachment' : safeStr(item['name'])),
            subtitle: Text(safeStr(item['url'])),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  attachmentsList.removeAt(i);
                  form['attachments'] = attachmentsList;
                });
              },
            ),
          );
        }),
        TextButton.icon(
          onPressed: () {
            final nameCtrl = TextEditingController();
            final urlCtrl = TextEditingController();
            showDialog(
              context: context,
              builder: (ctx) {
                return AlertDialog(
                  title: const Text('Add Attachment Link'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'File name'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlCtrl,
                        decoration: const InputDecoration(labelText: 'URL'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        final list = List.from((form['attachments'] ?? []) as List);
                        list.add({'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim()});
                        setState(() => form['attachments'] = list);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Add'),
                    ),
                  ],
                );
              },
            );
          },
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Add Link'),
        ),
      ],
    );
  }

  Widget _buildModal() {
    final selectedFiles = (form['selectedFiles'] ?? []) as List;
    final existingAttachments = (form['attachments'] ?? []) as List;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      form['id'] != null ? 'Edit Diary Entry' : 'Create New Diary Entry',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => showModal = false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField(
                      value: form['sessionId'],
                      items: sessions
                          .map<DropdownMenuItem>(
                            (s) => DropdownMenuItem(
                              value: s['id'],
                              child: Text(s['name'] ?? '${s['start_date']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => form['sessionId'] = v),
                      decoration: const InputDecoration(labelText: 'Session'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: safeStr(form['date']),
                      decoration: const InputDecoration(labelText: 'Date (yyyy-mm-dd)'),
                      onChanged: (v) => setState(() => form['date'] = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField(
                      value: form['type'],
                      items: const [
                        DropdownMenuItem(value: 'ANNOUNCEMENT', child: Text('Announcement')),
                        DropdownMenuItem(value: 'HOMEWORK', child: Text('Homework')),
                        DropdownMenuItem(value: 'REMARK', child: Text('Remark')),
                      ],
                      onChanged: (v) => setState(() => form['type'] = v),
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!multiMode && form['id'] == null)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: safeStr(form['classId']),
                        items: classes
                            .map<DropdownMenuItem<String>>(
                              (c) => DropdownMenuItem(
                                value: safeStr(c['id']),
                                child: Text(c['class_name'] ?? c['name'] ?? '${c['id']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => form['classId'] = v),
                        decoration: const InputDecoration(labelText: 'Class'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: safeStr(form['sectionId']),
                        items: sections
                            .map<DropdownMenuItem<String>>(
                              (s) => DropdownMenuItem(
                                value: safeStr(s['id']),
                                child: Text(s['section_name'] ?? s['name'] ?? '${s['id']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => form['sectionId'] = v),
                        decoration: const InputDecoration(labelText: 'Section'),
                      ),
                    ),
                  ],
                ),
              if (!multiMode && form['id'] == null) const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: safeStr(form['subjectId']),
                items: [
                  const DropdownMenuItem(value: '', child: Text('General')),
                  ...subjects.map<DropdownMenuItem<String>>(
                    (s) => DropdownMenuItem(
                      value: safeStr(s['id']),
                      child: Text(s['name'] ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => form['subjectId'] = v),
                decoration: const InputDecoration(labelText: 'Subject (Optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: safeStr(form['title']),
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (v) => setState(() => form['title'] = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: safeStr(form['content']),
                decoration: const InputDecoration(labelText: 'Content'),
                maxLines: 5,
                onChanged: (v) => setState(() => form['content'] = v),
              ),
              const SizedBox(height: 16),
              if (form['id'] == null && !multiMode) ...[
                const Text('Students (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(hintText: 'Search students (min 2 chars)'),
                        onChanged: (v) => setState(() => studentSearch = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: studentsLoading ? null : loadStudentsForPicker,
                      child: const Text('Load'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (studentsLoading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  )
                else if (studentsForPicker.isEmpty)
                  const Text('No students loaded.', style: TextStyle(color: Colors.black54)),
                if (studentsForPicker.isNotEmpty)
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: studentsForPicker.length,
                      itemBuilder: (c, i) {
                        final s = studentsForPicker[i];
                        return CheckboxListTile(
                          value: selectedStudentIds.contains(s['id']),
                          title: Text(
                            '${s['roll_number'] != null ? '${s['roll_number']}. ' : ''}${s['name'] ?? ''}${s['admission_number'] != null ? ' (${s['admission_number']})' : ''}',
                          ),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                selectedStudentIds.add(s['id']);
                              } else {
                                selectedStudentIds.remove(s['id']);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              _buildAttachmentLinksEditor(),
              const SizedBox(height: 16),
              const Text('Upload Files from Computer', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: pickFilesForForm,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Pick files'),
              ),
              const SizedBox(height: 8),
              if (selectedFiles.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedFiles.map<Widget>((f) {
                    final name = (f is PlatformFile)
                        ? (f.name)
                        : (f is File ? f.path.split('/').last : 'file');
                    return Chip(label: Text(name));
                  }).toList(),
                ),
              if (form['id'] != null) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: form['replaceAttachments'] == true,
                  onChanged: (v) => setState(() => form['replaceAttachments'] = v),
                  title: const Text('Replace all existing attachments with the ones above'),
                ),
                if (!(form['replaceAttachments'] == true) && existingAttachments.any((a) => a['id'] != null))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Keep / remove existing attachments:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: existingAttachments
                            .where((a) => a['id'] != null)
                            .map<Widget>((a) {
                          final id = a['id'];
                          final currentKeepIds = (form['keepAttachmentIds'] ?? []) as List;
                          return FilterChip(
                            label: Text(safeStr(a['name'])),
                            selected: currentKeepIds.contains(id),
                            onSelected: (sel) {
                              setState(() {
                                final keepIds = List.from(currentKeepIds);
                                if (sel) {
                                  if (!keepIds.contains(id)) keepIds.add(id);
                                } else {
                                  keepIds.remove(id);
                                }
                                form['keepAttachmentIds'] = keepIds;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Unchecked items will be removed on save.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => showModal = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(form['id'] != null ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = total == 0 ? 1 : (total / PAGE_SIZE).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Digital Diary Management',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Create, organize and monitor diary entries across classes. Teachers can also review attachment download history.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: openCreate,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Add Diary'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search by title or content',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => filters['q'] = v),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: applyLoading ? null : () => loadDiaries(1),
                  icon: applyLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.filter_alt_outlined),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (applyLoading && diaries.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          ))
        else if (diaries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.book_outlined, size: 48, color: Colors.blueGrey),
                SizedBox(height: 10),
                Text(
                  'No diaries found',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Create a new diary or adjust your search filters.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              ListView.separated(
                itemCount: diaries.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final d = diaries[idx];
                  return DiaryCardWidget(
                    diary: d,
                    canAck: false,
                    showAcknowledgementAction: true,
                    onViewAcknowledgements: () => showDiaryAcknowledgementsSheet(context, d),
                    showDownloadAction: true,
                    onViewDownloads: () => showDiaryDownloadsSheet(context, d),
                    onEdit: () => openEdit(d),
                    onDelete: () => del(d.sourceIds ?? [d.id]),
                  );
                },
              ),
              if (total > PAGE_SIZE) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: page <= 1 || pageLoading ? null : () => loadDiaries(page - 1),
                      child: const Text('Prev'),
                    ),
                    const SizedBox(width: 12),
                    Text('Page $page of $totalPages'),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: (page * PAGE_SIZE) >= total || pageLoading
                          ? null
                          : () => loadDiaries(page + 1),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        if (showModal) _buildModal(),
      ],
    );
  }
}

class DiaryFeedWidget extends StatefulWidget {
  const DiaryFeedWidget({Key? key}) : super(key: key);

  @override
  State<DiaryFeedWidget> createState() => _DiaryFeedWidgetState();
}

class _DiaryFeedWidgetState extends State<DiaryFeedWidget> {
  bool loading = true;
  List<Diary> diaries = [];
  List<dynamic> classes = [];
  List<dynamic> sections = [];
  Map<String, dynamic> sel = {'classId': '', 'sectionId': ''};
  late Future<RoleFlags> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = getRoleFlags();
    _initLists();
  }

  Future<void> _initLists() async {
    setState(() => loading = true);
    try {
      final cl = await dio.get('/classes', options: Options(headers: await getAuthHeaders()));
      final sec = await dio.get('/sections', options: Options(headers: await getAuthHeaders()));
      setState(() {
        classes = (cl.data is List) ? cl.data : (cl.data['classes'] ?? []);
        sections = (sec.data is List) ? sec.data : (sec.data['sections'] ?? []);
      });
    } catch (_) {}
    await load();
    setState(() => loading = false);
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await diaryGet('/student/feed/list', {
        if (safeStr(sel['classId']).isNotEmpty) 'classId': int.tryParse(sel['classId'].toString()),
        if (safeStr(sel['sectionId']).isNotEmpty) 'sectionId': int.tryParse(sel['sectionId'].toString()),
        'page': 1,
        'pageSize': PAGE_SIZE,
      });
      final raw = r.data?['data'] ?? [];
      setState(() => diaries = List.from(raw.map((m) => Diary.fromMap(m))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load diary feed: $e')),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoleFlags>(
      future: _rolesFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final roles = snap.data!;
        final isNonStudent = !roles.isStudent;
        final showDownloadAction = isNonStudent;
        final showAcknowledgementAction = isNonStudent;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNonStudent)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 1.5,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: safeStr(sel['classId']),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('Select Class')),
                                ...classes.map<DropdownMenuItem<String>>(
                                  (c) => DropdownMenuItem(
                                    value: safeStr(c['id']),
                                    child: Text(c['class_name'] ?? c['name'] ?? ''),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => sel['classId'] = v),
                              decoration: const InputDecoration(labelText: 'Class'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: safeStr(sel['sectionId']),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('Select Section')),
                                ...sections.map<DropdownMenuItem<String>>(
                                  (s) => DropdownMenuItem(
                                    value: safeStr(s['id']),
                                    child: Text(s['section_name'] ?? s['name'] ?? ''),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => sel['sectionId'] = v),
                              decoration: const InputDecoration(labelText: 'Section'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: loading ? null : load,
                            child: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Load Feed'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Choose a class and section to preview that group’s personalized diary feed.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Icon(Icons.menu_book_rounded, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Recent Diary Notes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ))
            else if (diaries.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 52, color: Colors.blueGrey),
                    SizedBox(height: 10),
                    Text(
                      'No Diary Notes Yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: diaries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final d = diaries[idx];
                  return DiaryCardWidget(
                    diary: d,
                    canAck: roles.isStudent,
                    showAcknowledgementAction: showAcknowledgementAction,
                    onViewAcknowledgements: showAcknowledgementAction ? () => showDiaryAcknowledgementsSheet(context, d) : null,
                    showDownloadAction: showDownloadAction,
                    onViewDownloads: showDownloadAction ? () => showDiaryDownloadsSheet(context, d) : null,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}