import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:animated_background/animated_background.dart';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;

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
  final FocusNode _focusNode = FocusNode();
  final List<Map<String, dynamic>> _messages = [
    {
      "sender": "bot",
      "message": "Hello! I'm RITA, your guide to Rajalakshmi Institute of Technology (RIT Chennai). Ask about courses, campus, fees, or placements! Try: 'What are the courses available?'",
      "timestamp": DateTime.now(),
    }
  ];
  final ScrollController _scrollController = ScrollController();
  bool _isBotTyping = false;
  List<Map<String, String>> _faqData = [];
  Map<String, String> _responseCache = {};
  Map<String, String> _normalizedQueryCache = {};
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  bool _isVoiceOutputEnabled = true;
  String _lastWords = '';
  late AnimationController _micAnimationController;
  late Animation<double> _micScaleAnimation;
  bool _speechInitialized = false;
  bool _isVoiceInput = false;
  bool isStudent = false;
  double _soundLevel = 0.0;
  static const double _minSoundLevel = -10.0;
  static const int _maxSilenceSeconds = 5;
  bool _isDarkMode = false;
  final Uuid _uuid = Uuid();
  final Map<String, int> _responseRatings = {};

  @override
  void initState() {
    super.initState();
    _loadFaqData();
    _loadCachedResponses();
    _loadVoiceOutputPreference();
    _loadThemePreference();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initSpeech();
    _initTts();
    _micAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _micScaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );
    _determineUserRole();
  }

  Future<void> _determineUserRole() async {
    setState(() {
      isStudent = false;
    });
  }

  Future<void> _loadVoiceOutputPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isVoiceOutputEnabled = prefs.getBool('voice_output_enabled') ?? true;
    });
  }

  Future<void> _saveVoiceOutputPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_output_enabled', value);
    setState(() {
      _isVoiceOutputEnabled = value;
    });
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    });
  }

  Future<void> _saveThemePreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', value);
    setState(() {
      _isDarkMode = value;
    });
  }

  @override
  void dispose() {
    _micAnimationController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize TTS')),
      );
    }
  }

  Future<void> _speak(String text) async {
    if (_isVoiceOutputEnabled && _isVoiceInput) {
      try {
        await _flutterTts.stop();
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.speak(text);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to speak response')),
        );
      }
    }
  }

  Future<void> _loadFaqData() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final String response = await rootBundle.loadString(
          'assets/college_faq.json',
        );
        final List<dynamic> data = jsonDecode(response);
        setState(() {
          _faqData = data
              .map(
                (item) => {
              "uuid": _uuid.v5(
                Uuid.NAMESPACE_OID,
                item["instruction"]?.toString() ?? "",
              ),
              "instruction": item["instruction"]?.toString() ?? "",
              "output": item["output"]?.toString() ?? "",
              "keywords": item["keywords"]?.toString().toLowerCase() ?? "",
              "related_questions": item["related_questions"]?.toString() ?? "",
              "category": item["category"]?.toString() ?? "general",
              "access_level": item["access_level"]?.toString() ?? "public",
            },
          )
              .toList();
        });
        for (var faq in _faqData) {
          if (faq["output"] != null && faq["uuid"] != null) {
            _responseCache[faq["uuid"]!] = faq["output"]!;
          }
        }
        await _saveCachedResponses();
        return;
      } catch (e) {
        if (attempt == 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load FAQs after $attempt attempts'),
            ),
          );
          setState(() {
            _faqData = [];
          });
        }
      }
    }
  }

  Future<void> _loadCachedResponses() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('response_cache');
    if (cached != null) {
      try {
        setState(() {
          _responseCache = Map<String, String>.from(jsonDecode(cached));
          if (_responseCache.length > 1000) {
            _responseCache.remove(_responseCache.keys.first);
          }
        });
      } catch (e) {}
    }
  }

  Future<void> _saveCachedResponses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('response_cache', jsonEncode(_responseCache));
  }

  Future<void> _saveCachedResponse(String uuid, String? response) async {
    if (response != null) {
      _responseCache[uuid] = response;
      if (_responseCache.length > 1000) {
        _responseCache.remove(_responseCache.keys.first);
      }
      await _saveCachedResponses();
    }
  }

  Future<void> _initSpeech() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        _speechInitialized = await _speech.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              setState(() {
                _isListening = false;
                _micAnimationController.stop();
              });
            }
          },
          onError: (error) {
            setState(() {
              _isListening = false;
              _isVoiceInput = false;
              _micAnimationController.stop();
            });
            _showSpeechErrorDialog(error.errorMsg);
          },
          debugLogging: true,
        );
        if (_speechInitialized) {
          return;
        }
      } catch (e) {}
      if (attempt == 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize speech recognition'),
          ),
        );
      }
    }
  }

  void _showSpeechErrorDialog(String errorMsg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent, Colors.blue[700]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                child: Icon(Icons.mic_off, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 10),
              Text(
                'Speech Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Speech recognition failed: $errorMsg. Please try again or use text input.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _listen();
                    },
                    child: Text(
                      'Try Again',
                      style: TextStyle(
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _controller.clear();
                      _focusNode.requestFocus();
                    },
                    child: Text(
                      'Use Text',
                      style: TextStyle(
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _listen() async {
    if (!_speechInitialized) {
      await _initSpeech();
      if (!_speechInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not initialized')),
        );
        return;
      }
    }

    if (_isListening) {
      setState(() {
        _isListening = false;
        _micAnimationController.stop();
      });
      await _speech.stop();
      return;
    }

    setState(() {
      _isListening = true;
      _isVoiceInput = true;
      _lastWords = '';
      _soundLevel = 0.0;
      _micAnimationController.repeat(reverse: true);
    });

    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords ?? '';
            _controller.text = _lastWords;
          });

          if (result.finalResult && _lastWords.isNotEmpty) {
            setState(() {
              _isListening = false;
              _micAnimationController.stop();
            });
            _sendMessage();
          }
        },
        onSoundLevelChange: (level) {
          setState(() {
            _soundLevel = level;
          });
          if (_isListening &&
              _lastWords.isEmpty &&
              _soundLevel < _minSoundLevel) {
            Future.delayed(Duration(seconds: _maxSilenceSeconds), () {
              if (_isListening &&
                  _lastWords.isEmpty &&
                  _soundLevel < _minSoundLevel) {
                _speech.stop();
                setState(() {
                  _isListening = false;
                  _isVoiceInput = false;
                  _controller.clear();
                  _micAnimationController.stop();
                });
              }
            });
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        sampleRate: 16000,
        partialResults: true,
        cancelOnError: false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start speech recognition: $e')),
      );
      setState(() {
        _isListening = false;
        _isVoiceInput = false;
        _controller.clear();
        _micAnimationController.stop();
      });
    }
  }

  void _sendMessage() async {
    String userMessage = _controller.text.trim();
    if (userMessage.isEmpty) {
      setState(() {
        _controller.clear();
        _isVoiceInput = false;
      });
      return;
    }

    setState(() {
      _messages.add({
        "sender": "user",
        "message": userMessage,
        "timestamp": DateTime.now(),
      });
      _isBotTyping = true;
      _controller.clear();
      if (_messages.length > 100) {
        _messages.removeAt(0);
      }
    });

    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'sender': 'user',
        'message': userMessage,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save message')),
      );
    }

    String botResponse = await _getBotResponse(userMessage);

    String responseId = _uuid.v4();
    setState(() {
      _isBotTyping = false;
      _messages.add({
        "sender": "bot",
        "message": botResponse,
        "timestamp": DateTime.now(),
        "responseId": responseId,
      });
    });

    await _speak(botResponse);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<String> _getBotResponse(String userMessage) async {
    if (userMessage.isEmpty) {
      return "Please provide a valid question about RIT Chennai.";
    }

    String normalizedMessage = _normalizeQuery(userMessage);
    String queryUuid = _uuid.v5(Uuid.NAMESPACE_OID, normalizedMessage);

    if (_responseCache.containsKey(queryUuid)) {
      return _responseCache[queryUuid]!;
    }

    final casualResponses = {
      'hi': 'Hello! How can I assist you with RIT Chennai today?',
      'hello': 'Hi there! Ready to answer your questions about RIT Chennai!',
      'ok': 'Alright! Anything specific about RIT Chennai you want to know?',
      'bye': 'Goodbye! Feel free to come back with more questions about RIT Chennai!',
      'thanks': 'You\'re welcome! Any more questions about RIT Chennai?',
      'thank you': 'My pleasure! What\'s next on your mind about RIT Chennai?',
    };

    if (casualResponses.containsKey(normalizedMessage)) {
      await _saveCachedResponse(queryUuid, casualResponses[normalizedMessage]);
      return casualResponses[normalizedMessage]!;
    }

    List<String> responses = [];
    final keyTerms = {
      'rit',
      'chennai',
      'campus',
      'fee',
      'placement',
      'courses',
      'hostel',
      'admission',
      'scholarship',
      'faculty',
      'library',
      'transport',
      'club',
      'event',
      'undergraduate',
      'postgraduate',
      'water',
      'facilities',
    };

    for (var faq in _faqData) {
      String instruction = _normalizeQuery(faq["instruction"]!);
      String faqUuid = faq["uuid"]!;
      List<String> keywords =
      faq["keywords"]!.split(', ').map((k) => k.trim()).toList();
      List<String> relatedQuestions =
      faq["related_questions"]!
          .split(', ')
          .map((q) => _normalizeQuery(q.trim()))
          .toList();

      double instructionScore = _calculateSimilarity(normalizedMessage, instruction);
      double keywordScore = _calculateKeywordScore(normalizedMessage, keywords);
      double relatedScore = relatedQuestions
          .map((q) => _calculateSimilarity(normalizedMessage, q))
          .fold(0.0, (max, score) => score > max ? score : max);

      int keyTermMatches =
          keyTerms.where((term) => normalizedMessage.contains(term)).length;
      double keyTermBoost = keyTermMatches * 0.3;

      double totalScore =
      (0.5 * instructionScore + 0.3 * keywordScore + 0.2 * relatedScore + keyTermBoost);
      if (totalScore >= 0.7) {
        responses.add(faq["output"]!);
      }
    }

    if (responses.isNotEmpty) {
      String botResponse = responses.join("\n\n");
      await _saveCachedResponse(queryUuid, botResponse);
      return botResponse;
    }

    if (!isStudent &&
        (normalizedMessage.contains("attendance") ||
            normalizedMessage.contains("student portal"))) {
      String response =
          "This information is restricted to RIT Chennai students. Please log in as a student.";
      await _saveCachedResponse(queryUuid, response);
      return response;
    }

    // Check pre-provided web context for water facilities or related topics
    if (normalizedMessage.contains("water") || normalizedMessage.contains("facilities")) {
      String waterResponse = _getWaterFacilitiesResponse(normalizedMessage);
      if (waterResponse.isNotEmpty) {
        await _saveCachedResponse(queryUuid, waterResponse);
        return waterResponse;
      }
    }

    // Fallback to Gemini with global search tied to RIT Chennai
    String geminiResponse = await getGeminiResponse(userMessage);
    await _saveCachedResponse(queryUuid, geminiResponse);
    return geminiResponse;
  }

  // Helper method to check web context for water facilities
  String _getWaterFacilitiesResponse(String normalizedMessage) {
    if (normalizedMessage.contains("water") && normalizedMessage.contains("facilities")) {
      return "RIT Chennai provides uninterrupted water supply in its hostels, including RO water facilities, as part of its modern amenities.";
    } else if (normalizedMessage.contains("water supply")) {
      return "RIT Chennai ensures an uninterrupted water supply in its hostels and campus facilities.";
    }
    return ""; // Return empty if no match
  }

  Future<String> getGeminiResponse(String userMessage) async {
    final apiKey = 'YOUR API KEY ';
    if (apiKey.isEmpty) {
      return "API key not configured. Please try again later.";
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                  'You are RITA, a chatbot for Rajalakshmi Institute of Technology (RIT Chennai). Search your global knowledge base to answer the question, but relate the answer specifically to RIT Chennai where possible (e.g., courses, campus, facilities, water, etc.). If no relevant connection to RIT Chennai can be made, respond with: "Sorry, I can\'t find the answer for that response." Question: $userMessage',
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String responseText =
            data['candidates'][0]['content']['parts'][0]['text']?.trim() ??
                "Sorry, I can't find the answer for that response";
        if (responseText.contains("Sorry, I can't answer that")) {
          return "Sorry, I can't find the answer for that response";
        }
        return responseText;
      }
      return "Sorry, I can't find the answer for that response";
    } catch (e) {
      return "Sorry, I can't find the answer for that response";
    }
  }

  String _normalizeQuery(String query) {
    if (_normalizedQueryCache.containsKey(query)) {
      return _normalizedQueryCache[query]!;
    }

    List<String> words = query.toLowerCase().trim().split(' ');
    List<String> correctedWords = [];

    final typoMap = {
      'hostle': 'hostel',
      'fees': 'fee',
      'placment': 'placement',
      'sholarship': 'scholarship',
      'admmision': 'admission',
      'courcess': 'courses',
      'campuss': 'campus',
      'libary': 'library',
      'transpot': 'transport',
      'facilty': 'facility',
      'course': 'courses',
      'programme': 'program',
      'undergraduate': 'ug',
      'postgraduate': 'pg',
      'ritchennai': 'rit chennai',
      'admsn': 'admission',
      'inmcorrect': 'incorrect',
      'midstakes': 'mistakes',
      'havbe': 'have',
      'alos': 'also',
      'shuld': 'should',
      'wht': 'what',
      'abt': 'about',
    };

    final synonymMap = {
      'courses': ['program', 'degree', 'class', 'curriculum', 'subjects', 'programmes'],
      'fee': ['cost', 'price', 'charge', 'expense', 'tuition', 'fees'],
      'hostel': ['dorm', 'residence', 'accommodation', 'hall'],
      'placement': ['job', 'career', 'recruitment', 'jobs'],
      'campus': ['grounds', 'site', 'premises', 'college'],
      'library': ['books', 'resources', 'study room'],
      'transport': ['bus', 'shuttle', 'transportation'],
      'faculty': ['teacher', 'professor', 'staff', 'lecturer'],
      'event': ['festival', 'celebration', 'activity'],
      'club': ['group', 'society', 'organization'],
    };

    for (String word in words) {
      if (word.isEmpty) continue;
      String corrected = word;

      if (typoMap.containsKey(word)) {
        corrected = typoMap[word]!;
      } else {
        for (var entry in typoMap.entries) {
          if (_approximateMatch(corrected, entry.key, 2)) {
            corrected = entry.value;
            break;
          }
        }
      }

      correctedWords.add(corrected);
    }

    String normalized = correctedWords.join(' ');

    words = normalized.split(' ');
    for (int i = 0; i < words.length; i++) {
      synonymMap.forEach((key, synonyms) {
        if (synonyms.contains(words[i])) {
          words[i] = key;
        }
      });
    }
    normalized = words.join(' ').replaceAll(RegExp(r'[^\w\s]'), '');

    _normalizedQueryCache[query] = normalized;
    if (_normalizedQueryCache.length > 1000) {
      _normalizedQueryCache.remove(_normalizedQueryCache.keys.first);
    }
    return normalized;
  }

  bool _approximateMatch(String a, String b, int maxDistance) {
    int m = a.length;
    int n = b.length;

    List<List<int>> matrix = List.generate(m + 1, (i) => List<int>.filled(n + 1, 0));

    for (int i = 0; i <= m; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        int cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }

    return matrix[m][n] <= maxDistance;
  }

  double _calculateKeywordScore(String query, List<String> keywords) {
    if (keywords.isEmpty) return 0.0;
    double score = 0.0;
    List<String> queryWords = query.split(' ');
    for (var keyword in keywords) {
      if (queryWords.contains(keyword)) {
        score += 1.0;
      } else {
        for (var word in queryWords) {
          if (_approximateMatch(word, keyword, 2)) {
            score += 0.6;
            break;
          }
        }
      }
    }
    return (score / keywords.length).clamp(0.0, 1.0);
  }

  double _calculateSimilarity(String query, String instruction) {
    final queryWords = query.toLowerCase().split(' ').toSet();
    final instructionWords = instruction.toLowerCase().split(' ').toSet();
    final keyTerms = {
      'rit',
      'chennai',
      'campus',
      'fee',
      'placement',
      'courses',
      'hostel',
      'admission',
      'scholarship',
      'faculty',
      'library',
      'transport',
      'club',
      'event',
      'undergraduate',
      'postgraduate',
    };

    final intersection = queryWords.intersection(instructionWords);
    final union = queryWords.union(instructionWords);
    double jaccardSimilarity = intersection.length / union.length;

    int keyTermMatches =
        intersection.where((word) => keyTerms.contains(word)).length;
    double keyTermBoost = keyTermMatches * 0.3;

    double lengthPenalty =
    (instructionWords.length < 3 || queryWords.length < 3) ? 0.05 : 0.0;

    return (jaccardSimilarity + keyTermBoost - lengthPenalty).clamp(0.0, 1.0);
  }

  void _rateResponse(String responseId, int rating) {
    setState(() {
      _responseRatings[responseId] = rating;
    });
    FirebaseFirestore.instance.collection('response_ratings').add({
      'responseId': responseId,
      'rating': rating,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isBot = message['sender'] == 'bot';
    final timestamp = (message['timestamp'] as DateTime).toString().substring(11, 16);
    final responseId = message['responseId'] as String?;
    return SlideInLeft(
      duration: const Duration(milliseconds: 300),
      child: ZoomIn(
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Column(
            crossAxisAlignment: isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBot)
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                        'R',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (isBot) const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isBot
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
                      child: isBot
                          ? AnimatedTextKit(
                        animatedTexts: [
                          TypewriterAnimatedText(
                            message['message']!,
                            textStyle: const TextStyle(color: Colors.white, fontSize: 16),
                            speed: const Duration(milliseconds: 20),
                          ),
                        ],
                        totalRepeatCount: 1,
                        pause: const Duration(milliseconds: 1000),
                      )
                          : Text(
                        message['message']!,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                  if (!isBot) const SizedBox(width: 8),
                  if (!isBot)
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.green,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                ],
              ),
              if (isBot && responseId != null)
                Row(
                  mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.thumb_up,
                        color: _responseRatings[responseId] == 1 ? Colors.blue : Colors.grey,
                      ),
                      onPressed: () => _rateResponse(responseId, 1),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.thumb_down,
                        color: _responseRatings[responseId] == -1 ? Colors.red : Colors.grey,
                      ),
                      onPressed: () => _rateResponse(responseId, -1),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String label, String query) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            color: _isDarkMode ? Colors.white : Colors.white,
          ),
        ),
        backgroundColor: Colors.blueAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () {
          _controller.text = query;
          _isVoiceInput = false;
          _sendMessage();
        },
      ),
    );
  }

  Widget _buildVoiceDetectorAnimation() {
    return GestureDetector(
      onTap: _listen,
      child: AnimatedBuilder(
        animation: _micAnimationController,
        builder: (context, child) {
          return Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _isListening
                      ? Colors.blueAccent.withOpacity(0.6)
                      : Colors.blueAccent.withOpacity(0.3),
                  _isDarkMode
                      ? Colors.black.withOpacity(0.2)
                      : Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
                stops: [0.0, 0.5, 1.0],
                radius: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isListening
                      ? Colors.blueAccent.withOpacity(0.5)
                      : Colors.blueAccent.withOpacity(0.3),
                  blurRadius: _isListening ? 15.0 : 5.0,
                  spreadRadius: _isListening ? 5.0 : 2.0,
                ),
              ],
            ),
            child: ScaleTransition(
              scale: _isListening
                  ? _micScaleAnimation
                  : AlwaysStoppedAnimation(1.0),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: _isDarkMode ? Colors.grey[800] : Colors.white,
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.blueAccent,
                  size: 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Map<String, String>> _getDynamicSuggestions() {
    return [
      {
        'label': 'Courses Available',
        'query': 'What are the courses available at RIT Chennai?',
      },
      {
        'label': 'UG Courses',
        'query': 'What are the undergraduate courses at RIT Chennai?',
      },
      {
        'label': 'PG Courses',
        'query': 'What are the postgraduate courses at RIT Chennai?',
      },
      {
        'label': 'Hostel Fees',
        'query': 'What is the hostel fee at RIT Chennai?',
      },
      {
        'label': 'Placements',
        'query': 'What are the placement statistics for RIT Chennai?',
      },
      {
        'label': 'Admission',
        'query': 'What is the admission process for RIT Chennai?',
      },
      {
        'label': 'Scholarships',
        'query': 'Does RIT Chennai offer scholarships?',
      },
      {
        'label': 'Library',
        'query': 'What are the library facilities at RIT Chennai?',
      },
      {
        'label': 'Cultural Festival',
        'query': 'Does RIT Chennai have a cultural festival?',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/rit_building.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                _isDarkMode
                    ? Colors.black.withOpacity(0.5)
                    : Colors.black.withOpacity(0.3),
                BlendMode.dstATop,
              ),
            ),
          ),
          child: Column(
            children: [
              AppBar(
                title: const Text('RITA - RIT Chennai Chatbot'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isDarkMode
                          ? [Colors.blueGrey[900]!, Colors.blueGrey[700]!]
                          : [Colors.blueAccent, Colors.blue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      _isVoiceOutputEnabled
                          ? Icons.volume_up
                          : Icons.volume_off,
                    ),
                    onPressed: () {
                      _saveVoiceOutputPreference(!_isVoiceOutputEnabled);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.brightness_4),
                    onPressed: () {
                      _saveThemePreference(!_isDarkMode);
                    },
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _messages.length + (_isBotTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isBotTyping) {
                      return Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blueAccent,
                              child: Text(
                                'R',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blueAccent, Colors.blue],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return _buildMessage(_messages[index]);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                color: _isDarkMode ? Colors.grey[900] : Colors.white,
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _getDynamicSuggestions()
                            .map((s) => _buildSuggestionChip(s['label']!, s['query']!))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ask about RIT Chennai...',
                              hintStyle: TextStyle(
                                color: _isDarkMode ? Colors.grey[400] : Colors.grey,
                              ),
                              filled: true,
                              fillColor: _isDarkMode ? Colors.grey[800] : Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildVoiceDetectorAnimation(),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blueAccent,
                          child: IconButton(
                            icon: Icon(Icons.send, color: Colors.white),
                            onPressed: () {
                              _isVoiceInput = false;
                              _sendMessage();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
