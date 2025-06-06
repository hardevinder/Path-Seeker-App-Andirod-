import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ContactListScreen extends StatefulWidget {
  const ContactListScreen({super.key});

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  String? currentUserId;
  String? currentUserName;
  bool loading = true;
  String searchTerm = '';
  Map<String, List<Map<String, dynamic>>> groupedContacts = {};

  @override
  void initState() {
    super.initState();
    loadUserInfo();
  }

  Future<void> loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    currentUserId = prefs.getString('currentUserId');
    currentUserName = prefs.getString('username');
    await fetchContacts();
  }

  String getChatId(String contactId) {
    final ids = [currentUserId!, contactId]..sort();
    return ids.join('-');
  }

  Future<void> fetchContacts() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      final allUsers = {for (var doc in snapshot.docs) doc.id: doc.data()};
      final chatSnapshot = await FirebaseFirestore.instance.collection('chats').get();
      final chatMap = {for (var doc in chatSnapshot.docs) doc.id: doc.data()};

      final List<Map<String, dynamic>> allContacts = [];

      for (var entry in allUsers.entries) {
        final userId = entry.key;
        final data = entry.value;

        if (userId == currentUserId || data['role'] != 'teacher') continue;

        final chatId = getChatId(userId);
        final chatData = chatMap[chatId];

        allContacts.add({
          'id': userId,
          'name': data['name'] ?? data['username'] ?? 'Unknown',
          'chatId': chatId,
          'class': data['class'] ?? 'General',
          'lastMessage': chatData?['lastMessage'] ?? '',
          'lastMessageTimestamp': chatData?['lastMessageTimestamp'],
          'unreadCount': chatData?['unreadCounts']?[currentUserId] ?? 0,
          'isGroup': false,
        });
      }

      allContacts.sort((a, b) {
        final aUnread = a['unreadCount'];
        final bUnread = b['unreadCount'];
        if (aUnread > 0 && bUnread == 0) return -1;
        if (aUnread == 0 && bUnread > 0) return 1;
        final aTime = a['lastMessageTimestamp'] ?? Timestamp(0, 0);
        final bTime = b['lastMessageTimestamp'] ?? Timestamp(0, 0);
        return (bTime as Timestamp).compareTo(aTime as Timestamp);
      });

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var contact in allContacts) {
        final className = contact['class'];
        grouped.putIfAbsent(className, () => []);
        grouped[className]!.add(contact);
      }

      setState(() {
        groupedContacts = grouped;
        loading = false;
      });
    } catch (e) {
      print("\u274c Error: $e");
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/dashboard');
          },
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    onChanged: (value) => setState(() => searchTerm = value),
                    decoration: const InputDecoration(
                      labelText: 'Search contacts...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: groupedContacts.isEmpty
                      ? const Center(child: Text("No contacts found."))
                      : ListView(
                          children: groupedContacts.entries.map((entry) {
                            final className = entry.key;
                            final contacts = entry.value
                                .where((c) =>
                                    c['isGroup'] != true &&
                                    c['name'].toString().toLowerCase().contains(searchTerm.toLowerCase()))
                                .toList();

                            if (contacts.isEmpty) return const SizedBox.shrink();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    className,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...contacts.map((contact) {
                                  final hasUnread = contact['unreadCount'] > 0;

                                  return Container(
                                    color: hasUnread ? Colors.red[50] : null,
                                    child: ListTile(
                                      leading: const Icon(Icons.person),
                                      title: Text(
                                        contact['name'],
                                        style: TextStyle(
                                          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: contact['lastMessage'].isNotEmpty
                                          ? Text(
                                              contact['lastMessage'],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                          : null,
                                      trailing: hasUnread
                                          ? CircleAvatar(
                                              backgroundColor: Colors.red,
                                              radius: 12,
                                              child: Text(
                                                contact['unreadCount'].toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : null,
                                      onTap: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/chat',
                                          arguments: {
                                            'currentUserId': currentUserId!,
                                            'currentUserName': currentUserName ?? '',
                                            'contactId': contact['id'],
                                            'contactName': contact['name'],
                                            'isGroup': false,
                                          },
                                        );
                                      },
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }
}
