import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
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
      "message":
      "Hello! I'm RITA, your guide to Rajalakshmi Institute of Technology (RIT Chennai). Ask me about campus, fees, placements, or courses! Try: 'What is the full name of RIT Chennai?'"
    }
  ];
  final ScrollController _scrollController = ScrollController();
  bool _isBotTyping = false;
  List<Map<String, String>> _faqData = [];
  Map<String, String> _responseCache = {};

  @override
  void initState() {
    super.initState();
    _loadFaqData();
    _loadCachedResponses();
  }

  Future<void> _loadFaqData() async {
    try {
      final String response = await rootBundle.loadString('assets/college_faq.json');
      final List<dynamic> data = jsonDecode(response);
      setState(() {
        _faqData = data.map((item) => {
          "instruction": item["instruction"].toString(),
          "output": item["output"].toString(),
        }).toList();
        print("FAQ Data Loaded: ${_faqData.length} entries");
      });
    } catch (e) {
      print("Error loading FAQ data: $e");
      setState(() {
        _faqData = [];
      });
    }
  }

  Future<void> _loadCachedResponses() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('response_cache');
    if (cached != null) {
      setState(() {
        _responseCache = Map<String, String>.from(jsonDecode(cached));
      });
    }
  }

  Future<void> _saveCachedResponse(String query, String response) async {
    _responseCache[query] = response;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('response_cache', jsonEncode(_responseCache));
  }

  void _sendMessage() async {
    if (_controller.text.isEmpty) return;

    String userMessage = _controller.text.trim();
    setState(() {
      _messages.add({"sender": "user", "message": userMessage});
      _isBotTyping = true;
      _controller.clear();
    });

    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'sender': 'user',
        'message': userMessage,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Firestore error: $e");
    }

    String botResponse = await _getBotResponse(userMessage);

    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _isBotTyping = false;
        _messages.add({"sender": "bot", "message": botResponse});
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    });
  }

  Future<String> _getBotResponse(String userMessage) async {
    String normalizedMessage = _normalizeQuery(userMessage);
    if (_responseCache.containsKey(normalizedMessage)) {
      print("Cache hit for: $normalizedMessage");
      return _responseCache[normalizedMessage]!;
    }

    final Map<String, List<String>> synonyms = {
      'size': ['area', 'large', 'big', 'space', 'dimension'],
      'fee': ['cost', 'price', 'charge', 'expense'],
      'hostel': ['dorm', 'residence', 'accommodation', 'housing'],
      'campus': ['grounds', 'site', 'premises', 'facility'],
      'placement': ['job', 'career', 'recruitment', 'employment'],
      'course': ['program', 'degree', 'study', 'class'],
      'full name': ['name', 'title', 'official name'],
      'established': ['founded', 'started', 'created'],
    };

    List<String> queryWords = normalizedMessage.split(' ').toList();
    for (var word in normalizedMessage.split(' ')) {
      synonyms.forEach((key, value) {
        if (value.contains(word) || key == word) {
          queryWords.add(key);
        }
      });
    }

    String? bestMatch;
    double bestScore = 0.0;
    for (var faq in _faqData) {
      String instruction = faq["instruction"]!.toLowerCase().trim();
      double score = _calculateSimilarity(queryWords, instruction);
      if (score > bestScore && score >= 0.4) {
        bestScore = score;
        bestMatch = faq["output"];
        print("Matched FAQ: $instruction (Score: $score)");
      }
    }

    if (bestMatch != null) {
      await _saveCachedResponse(normalizedMessage, bestMatch);
      return bestMatch;
    }

    print("No FAQ match for: $normalizedMessage, using Gemini API");
    String response = await getGeminiResponse(userMessage);
    await _saveCachedResponse(normalizedMessage, response);
    return response;
  }

  String _normalizeQuery(String query) {
    final typoMap = {
      'hostle': 'hostel',
      'fees': 'fee',
      'chennai': 'chennai',
      'rit': 'rit',
    };
    String normalized = query.toLowerCase().trim();
    typoMap.forEach((wrong, correct) {
      normalized = normalized.replaceAll(wrong, correct);
    });
    return normalized;
  }

  double _calculateSimilarity(List<String> queryWords, String instruction) {
    final instructionWords = instruction.toLowerCase().split(' ').toSet();
    final querySet = queryWords.toSet();

    final keyTerms = {
      'rit',
      'chennai',
      'campus',
      'fee',
      'placement',
      'course',
      'hostel',
      'department',
      'admission'
    };
    int keyTermMatches = 0;
    int totalMatches = 0;

    for (var word in querySet) {
      if (instructionWords.contains(word)) {
        totalMatches++;
        if (keyTerms.contains(word)) {
          keyTermMatches++;
        }
      }
    }

    double overlap = totalMatches / (instructionWords.length + querySet.length - totalMatches);
    double keyTermBoost = keyTermMatches * 0.2;
    return (overlap + keyTermBoost).clamp(0.0, 1.0);
  }

  Future<String> getGeminiResponse(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=AIzaSyAA0m24JK9M3boO1K_2KqGbfawUk2peuug'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                  'You are RITA, a chatbot for Rajalakshmi Institute of Technology (RIT Chennai). Provide accurate, concise answers about RIT Chennai (e.g., campus, fees, placements, courses). If you don\'t know the answer, say: "I don\'t have specific information on that. Please ask another question about RIT Chennai." Question: $userMessage'
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] ??
            "Sorry, I couldn't process that.";
      } else {
        return "Sorry, I couldn't get a response. Try asking something specific about RIT Chennai!";
      }
    } catch (e) {
      print("Gemini API error: $e");
      return "Sorry, I couldn't connect to the server. Try again later!";
    }
  }

  Widget _buildMessage(String message, String sender) {
    return Align(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'RITA',
          style: TextStyle(fontSize: 24), // Add fontFamily: 'Cinzel' after adding font
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 4,
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
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Campus Size'),
                      onPressed: () {
                        _controller.text = "What is the size of the RIT Chennai campus?";
                        _sendMessage();
                      },
                    ),
                    ActionChip(
                      label: const Text('Hostel Fees'),
                      onPressed: () {
                        _controller.text = "What is the hostel fee at RIT Chennai?";
                        _sendMessage();
                      },
                    ),
                    ActionChip(
                      label: const Text('Placements'),
                      onPressed: () {
                        _controller.text = "What are the placement statistics at RIT Chennai?";
                        _sendMessage();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Ask about RIT Chennai (e.g., fees, campus)...',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[200],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}