import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:oktoast/oktoast.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';


class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String contactId;
  final String currentUserName;
  final String contactName;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.contactId,
    required this.currentUserName,
    required this.contactName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String chatId;
  File? _attachment;
  final picker = ImagePicker();
  final String apiUrl = "https://erp.sirhindpublicschool.com:3000/upload/";
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _editingMessageId;
  String? _replyToText;
  String? _replyToSender;
  Map<String, Map<String, String?>> _messageReactions = {};

  @override
  void initState() {
    super.initState();
    chatId = [widget.currentUserId, widget.contactId].sorted().join('-');
    _audioRecorder.openRecorder();

    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.contactId)
        .where('status', isNotEqualTo: 'read')
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.update({'status': 'read'});
      }
    });
    markChatAsRead(); // ✅ Reset the unread count for this user

  }

  @override
  void dispose() {
    _audioRecorder.closeRecorder();
    super.dispose();
  }

 Future<String?> uploadAttachment(File file) async {
  var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
  request.files.add(await http.MultipartFile.fromPath('file', file.path));
  final response = await request.send();

  if (response.statusCode == 200) {
    final resStr = await response.stream.bytesToString();
    final jsonData = json.decode(resStr);

    String fileUrl = jsonData['fileUrl'];
    if (!fileUrl.startsWith("http")) {
      fileUrl = "https://erp.sirhindpublicschool.com" + fileUrl;
    }

    return fileUrl;
  } else {
    return null;
  }
}



  void sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty && _attachment == null) return;

    String? uploadedUrl;
    String? fileName;
    String? fileType;

    if (_attachment != null) {
      uploadedUrl = await uploadAttachment(_attachment!);
      fileName = _attachment!.path.split('/').last;
      fileType = lookupMimeType(_attachment!.path) ?? 'application/pdf';
    }

    final message = {
      'senderId': widget.currentUserId,
      'senderName': widget.currentUserName,
      'receiverId': widget.contactId, // ✅ Add this line
      'text': messageText,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      if (_replyToText != null) ...{
        'replyToText': _replyToText,
        'replyToSender': _replyToSender,
      },
      if (uploadedUrl != null) ...{
        'fileUrl': uploadedUrl,
        'fileName': fileName,
        'attachmentType': fileType,
      }
    };

    if (_editingMessageId != null) {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(_editingMessageId)
          .update(message);
      _editingMessageId = null;
    } else {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(message);
          sendPushNotification(widget.contactId, widget.currentUserName, messageText);

    }

    _messageController.clear();
    _attachment = null;
    _replyToText = null;
    _replyToSender = null;
    setState(() {});
    _scrollToBottom();
  }

  void markChatAsRead() async {
  await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
    'unreadCounts.${widget.currentUserId}': 0,
  });
}

  void toggleReaction(String messageId, String emoji) async {
    final current = _messageReactions[messageId]?[widget.currentUserId];
    final newReaction = current == emoji ? null : emoji;
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    await ref.set({
      'reactions.${widget.currentUserId}': newReaction
    }, SetOptions(merge: true));
  }

  Future pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _attachment = File(pickedFile.path);
      setState(() {});
    }
  }

  Future pickDocument() async {
    final params = OpenFileDialogParams(
      dialogType: OpenFileDialogType.document,
    );

    final path = await FlutterFileDialog.pickFile(params: params);
    if (path != null) {
      _attachment = File(path);
      setState(() {});
    }
  }

  Future startRecording() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) return;

    final path = '${Directory.systemTemp.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _audioRecorder.startRecorder(toFile: path);
    setState(() {
      _isRecording = true;
    });
  }

  Future stopRecording() async {
    final path = await _audioRecorder.stopRecorder();
    setState(() {
      _isRecording = false;
      if (path != null) {
        _attachment = File(path);
      }
    });
  }

  void startEditing(String messageId, String text) {
    setState(() {
      _editingMessageId = messageId;
      _messageController.text = text;
    });
  }

  void startReply(String text, String sender) {
    setState(() {
      _replyToText = text;
      _replyToSender = sender;
    });
  }

  void cancelReply() {
    setState(() {
      _replyToText = null;
      _replyToSender = null;
    });
  }

  Future<void> deleteMessage(String messageId) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
    showToast("Message deleted");
  }

Widget _buildAttachmentWidget(String? url, String? type, String? name) {
  if (url == null || name == null) return const SizedBox();

  if (!url.startsWith("http")) {
    url = "https://erp.sirhindpublicschool.com" + url;
  }

  if (type?.startsWith('image/') == true) {
    return Image.network(url, height: 150, width: 150, fit: BoxFit.cover);
  } else {
    return GestureDetector(
      onTap: () async {
        print("Trying to open file: $url");

        try {
          showToast("Downloading file...");
          final response = await http.get(Uri.parse(url!)); // ✅ FIXED HERE

          if (response.statusCode != 200) {
            showToast("Failed to download file");
            return;
          }

          final bytes = response.bodyBytes;
          final fileName = name;
          final filePath = '${Directory.systemTemp.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(bytes);

          // final result = await OpenFile.open(file.path);
          // if (result.type != ResultType.done) {
          //   showToast("File open failed: ${result.message}");
          // }
          // final uri = Uri.file(file.path);
          //   if (!await launchUrl(uri)) {
          //     print('Could not open file');
          //   }
          final result = await OpenFilex.open(file.path);
            if (result.type != ResultType.done) {
              showToast("❌ Could not open file: ${result.message}");
            }


        } catch (e) {
          showToast("Error opening file: $e");
        }
      },
      child: Text(
        '📄 $name',
        style: const TextStyle(
          decoration: TextDecoration.underline,
          color: Colors.blue,
        ),
      ),
    );
  }
}

Future<void> sendPushNotification(String receiverId, String senderName, String message) async {
  final doc = await FirebaseFirestore.instance.collection('users').doc(receiverId).get();
  final fcmToken = doc.data()?['fcmToken'];

  if (fcmToken == null) {
    print("🚫 No FCM token for user $receiverId");
    return;
  }

  final serverKey = 'AIzaSyD6h5jlZ1DJbGulpsxFY9JDLOfsBsl8XJU'; // 🔒 Replace with environment-safe storage in production

  try {
    final response = await http.post(
  Uri.parse('https://fcm.googleapis.com/fcm/send'),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'key=$serverKey',
  },
  body: jsonEncode({
    "to": fcmToken,
    "notification": {
      "title": "Message from $senderName",
      "body": message,
      "sound": "default",
    },
    "data": {
      "click_action": "FLUTTER_NOTIFICATION_CLICK",
    }
  }),
);

print("📤 FCM PUSH SENT → Status: ${response.statusCode}");
print("📩 FCM Response → Body: ${response.body}");

  } catch (e) {
    print("❌ Push error: $e");
  }
}


  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('Chat with ${widget.contactName}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.contacts),
              tooltip: 'Contacts',
              onPressed: () {
                Navigator.pushNamed(context, '/contacts');
              },
            ),
          ],
        ),

      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            if (_replyToText != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: Colors.grey[200],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('Replying to $_replyToSender: $_replyToText')),
                    IconButton(
                      icon: Icon(Icons.close, size: 16),
                      onPressed: cancelReply,
                    )
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatId)
                    .collection('messages')
                    .orderBy('timestamp')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  final messages = snapshot.data?.docs ?? [];
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                  _messageReactions.clear();
                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final data = msg.data() as Map<String, dynamic>;
                      final replyText = data['replyToText'];
                      final replySender = data['replyToSender'];
                      if (data.containsKey('reactions')) {
                        _messageReactions[msg.id] = Map<String, String?>.from(data['reactions']);
                      }
                      final isMe = data['senderId'] == widget.currentUserId;
                      return Container(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (replyText != null)
                              Text('↪️ $replySender: $replyText',
                                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                            _buildAttachmentWidget(data['fileUrl'], data['attachmentType'], data['fileName']),
                            Container(
                              margin: EdgeInsets.only(top: 5),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.blue[100] : Colors.grey[200],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['text'] ?? '', style: TextStyle(fontSize: 16)),
                                  if (_messageReactions[msg.id]?.isNotEmpty ?? false)
                                    Wrap(
                                      children: _messageReactions[msg.id]!.entries
                                          .where((entry) => entry.value != null)
                                          .map((entry) => Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Text('${entry.value!}'),
                                              ))
                                          .toList(),
                                    ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.reply, size: 16),
                                        onPressed: () => startReply(data['text'], data['senderName']),
                                      ),
                                      if (isMe) ...[
                                        IconButton(
                                          icon: Icon(Icons.edit, size: 16),
                                          onPressed: () => startEditing(msg.id, data['text']),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, size: 16),
                                          onPressed: () => deleteMessage(msg.id),
                                        ),
                                      ],
                                      Text(
                                        data['status'] == 'read' ? '✔✔' : '✔',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(data['senderName'] ?? '',
                                style: TextStyle(fontSize: 10, color: Colors.grey[700]))
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_attachment != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(child: Text('Attachment: ${_attachment!.path.split('/').last}')),
                    IconButton(
                      icon: Icon(Icons.cancel, color: Colors.red),
                      onPressed: () {
                        _attachment = null;
                        setState(() {});
                      },
                    )
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.attach_file), onPressed: pickImage),
                  IconButton(icon: Icon(Icons.description), onPressed: pickDocument),
                  IconButton(
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic,
                        color: _isRecording ? Colors.red : Colors.grey[700]),
                    onPressed: _isRecording ? stopRecording : startRecording,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(hintText: 'Type your message...'),
                    ),
                  ),
                  IconButton(icon: Icon(Icons.send, color: Colors.blue), onPressed: sendMessage),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

extension SortStringList on List<String> {
  List<String> sorted() {
    final copy = List<String>.from(this);
    copy.sort();
    return copy;
  }
}
