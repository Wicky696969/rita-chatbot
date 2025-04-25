import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:animated_background/animated_background.dart';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ChatbotPage(),
    );
  }
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  _ChatbotPageState createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    {
      "sender": "bot",
      "message": "Hello! I'm the RIT Chennai FAQ Bot. Ask me anything about RIT Chennai!"
    }
  ];
  final ScrollController _scrollController = ScrollController();
  bool _isBotTyping = false;

  void _sendMessage() async {
    if (_controller.text.isEmpty) return;

    String userMessage = _controller.text.trim().toLowerCase();
    setState(() {
      _messages.add({"sender": "user", "message": userMessage});
      _isBotTyping = true;
      _controller.clear();
    });

    // Store message in Firestore
    await FirebaseFirestore.instance.collection('messages').add({
      'sender': 'user',
      'message': userMessage,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Get response from Gemini API
    String botResponse = await getGeminiResponse(userMessage);

    // Simulate bot response with delay
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _isBotTyping = false;
        _messages.add({"sender": "bot", "message": botResponse});
      });

      // Scroll to the bottom after bot response
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    });
  }

  Future<String> getGeminiResponse(String userMessage) async {
    final response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=AIzaSyAA0m24JK9M3boO1K_2KqGbfawUk2peuug'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': userMessage}
            ]
          }
        ]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] ?? "Sorry, I couldn't process that.";
    } else {
      return "Sorry, I couldn't get a response. Status: ${response.statusCode}";
    }
  }

  Widget _buildMessage(String message, String sender) {
    return SlideInLeft(
      duration: const Duration(milliseconds: 300),
      child: ZoomIn(
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: sender == "bot" ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: sender == "bot"
                    ? [Colors.blueAccent, Colors.blue]
                    : [Colors.greenAccent, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: sender == "bot"
                ? AnimatedTextKit(
              animatedTexts: [
                TypewriterAnimatedText(
                  message,
                  textStyle: const TextStyle(color: Colors.white, fontSize: 16),
                  speed: const Duration(milliseconds: 20),
                ),
              ],
              totalRepeatCount: 1,
              pause: const Duration(milliseconds: 1000),
            )
                : Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RIT Chennai FAQ Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length + (_isBotTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isBotTyping) {
                  return const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(),
                  );
                }
                final message = _messages[index];
                return _buildMessage(message['message']!, message['sender']!);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}