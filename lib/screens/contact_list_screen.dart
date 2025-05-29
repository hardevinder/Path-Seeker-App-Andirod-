import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactListScreen extends StatefulWidget {
  const ContactListScreen({super.key});

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  String? currentUserId;
  String? currentUserName;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
  }

  Future<void> loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserId = prefs.getString('currentUserId');
      currentUserName = prefs.getString('username');
    });
  }

  String getChatId(String contactId) {
    final ids = [currentUserId!, contactId];
    ids.sort();
    return ids.join('-');
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Contact'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/dashboard');
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final List<Map<String, dynamic>> contactList = [];

          for (var doc in docs) {
            if (doc.id == currentUserId || doc['role'] == 'student') continue;

            final contactId = doc.id;
            final contactName = doc['name'] ?? doc['username'] ?? 'Unknown';
            final chatId = getChatId(contactId);

            contactList.add({
              'id': contactId,
              'name': contactName,
              'chatId': chatId,
            });
          }

          return ListView.builder(
            itemCount: contactList.length,
            itemBuilder: (context, index) {
              final contact = contactList[index];

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(contact['chatId'])
                    .snapshots(),
                builder: (context, chatSnap) {
                  int unreadCount = 0;
                  String latestMsg = '';

                  if (chatSnap.hasData && chatSnap.data!.exists) {
                    final data = chatSnap.data!.data() as Map<String, dynamic>;
                    latestMsg = data['lastMessage'] ?? '';
                    unreadCount =
                        (data['unreadCounts'] ?? {})[currentUserId] ?? 0;
                  }

                  return ListTile(
                    tileColor: unreadCount > 0 ? Colors.red[50] : null,
                    title: Text(contact['name'],
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: latestMsg.isNotEmpty
                        ? Text(latestMsg,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: unreadCount > 0
                        ? CircleAvatar(
                            backgroundColor: Colors.red,
                            radius: 12,
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/chat',
                        arguments: {
                          'currentUserId': currentUserId!,
                          'contactId': contact['id'],
                          'currentUserName': currentUserName ?? '',
                          'contactName': contact['name'],
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
