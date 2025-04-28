import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart'; // For fuzzy matching

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
      "message":
      "Hello! I'm RITA, your guide to Rajalakshmi Institute of Technology (RIT Chennai). Ask about campus, courses, placements, or anything else! Try: 'What is RIT Chennai?'",
      "timestamp": DateTime.now(),
      "message_id": const Uuid().v4(),
    },
  ];
  final ScrollController _scrollController = ScrollController();
  bool _isBotTyping = false;
  List<Map<String, String>> _faqData = [];
  Map<String, String> _responseCache = {};
  Map<String, String> _contextCache = {};
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
  static const int _maxSilenceSeconds = 3;
  bool _isDarkMode = false;
  String _lastCategory = "general";
  List<String> _recentQueries = [];

  // Gemini API Key (Replace with a valid key from Google AI Studio)
  static const String _geminiApiKey = 'AIzaSyDbbo4pQxT4Wy9Tn_H1nNf1zfvp9vG0os0';

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
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _micScaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );
    _determineUserRole();
  }

  Future<void> _determineUserRole() async {
    setState(() {
      isStudent = false; // Replace with actual authentication logic
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
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (_isVoiceOutputEnabled && _isVoiceInput) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  Future<void> _loadFaqData() async {
    final String faqJson = '''
    [
      {
        "instruction": "What are the facilities for data analytics students at RIT Chennai?",
        "output": "Data Analytics students at RIT Chennai have access to labs with data visualization tools, statistical software, and big data platforms like Hadoop.",
        "keywords": "data analytics, facilities, labs, rit chennai",
        "related_questions": "What facilities are there for data analytics students at RIT Chennai?, Does RIT have good data analytics labs?, What resources are available for data analytics at RIT?",
        "category": "academics",
        "access_level": "public"
      },
      {
        "instruction": "What courses are offered at RIT Chennai?",
        "output": "RIT Chennai offers courses in Computer Science, Electronics, Mechanical Engineering, and more.",
        "keywords": "courses, offered, rit chennai, programs",
        "related_questions": "What are the courses at RIT Chennai?, Which courses are available at RIT?, What programs does RIT offer?",
        "category": "academics",
        "access_level": "public"
      },
      {
        "instruction": "Does RIT Chennai have a tennis club?",
        "output": "Yes, RIT Chennai has a tennis club that organizes tournaments and training sessions for students.",
        "keywords": "tennis, club, tournaments, rit chennai",
        "related_questions": "Is there a tennis club at RIT Chennai?, Does RIT have tennis activities?, Can I join the tennis club at RIT?",
        "category": "campus",
        "access_level": "public"
      }
      // ... (Insert the remaining 997 entries here as per the JSON structure)
    ]
    ''';

    try {
      final List<dynamic> data = jsonDecode(faqJson);
      setState(() {
        _faqData = data.map((item) => {
          "instruction": item["instruction"]?.toString() ?? "",
          "output": item["output"]?.toString() ?? "",
          "keywords": item["keywords"]?.toString() ?? "",
          "related_questions": item["related_questions"]?.toString() ?? "",
          "category": item["category"]?.toString() ?? "general",
          "access_level": item["access_level"]?.toString() ?? "public",
        }).toList();
      });
      print("FAQ Data Loaded: ${_faqData.length} entries");
    } catch (e) {
      print("Error loading FAQ data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load FAQs')),
      );
      setState(() {
        _faqData = [];
      });
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
      } catch (e) {
        print("Error loading cached responses: $e");
      }
    }
  }

  Future<void> _saveCachedResponse(String query, String? response) async {
    if (response != null) {
      _responseCache[query] = response;
      if (_responseCache.length > 1000) {
        _responseCache.remove(_responseCache.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('response_cache', jsonEncode(_responseCache));
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
              if (_lastWords.isEmpty && _soundLevel < _minSoundLevel) {
                _showVoiceNotDetectedDialog();
              }
            }
          },
          onError: (error) {
            setState(() {
              _isListening = false;
              _micAnimationController.stop();
            });
            if (error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout') {
              _showVoiceNotDetectedDialog();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Speech recognition error: ${error.errorMsg}'),
                  action: SnackBarAction(
                    label: 'Use Text',
                    onPressed: () {
                      _focusNode.requestFocus();
                    },
                  ),
                ),
              );
            }
          },
          debugLogging: true,
        );
        if (_speechInitialized) {
          print('Speech recognition initialized successfully');
          return;
        }
        print('Speech recognition not available (attempt $attempt)');
      } catch (e) {
        print('Speech initialization failed (attempt $attempt): $e');
      }
      if (attempt == 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize speech recognition')),
        );
      }
    }
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
          if (_isListening && level < _minSoundLevel && _lastWords.isEmpty) {
            Future.delayed(Duration(seconds: _maxSilenceSeconds), () {
              if (_isListening && _lastWords.isEmpty && _soundLevel < _minSoundLevel) {
                _speech.stop();
                setState(() {
                  _isListening = false;
                  _micAnimationController.stop();
                });
                _showVoiceNotDetectedDialog();
              }
            });
          }
        },
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        sampleRate: 44100,
        partialResults: true,
        cancelOnError: false,
        localeId: "en_US",
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start speech recognition: $e')),
      );
      setState(() {
        _isListening = false;
        _isVoiceInput = false;
        _micAnimationController.stop();
      });
      _showVoiceNotDetectedDialog();
    }
  }

  void _showVoiceNotDetectedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
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
                'Voice Not Detected',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'No speech was detected. Please speak clearly or try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _listen();
                    },
                    child: Text(
                      'Try Again',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.blueAccent),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _focusNode.requestFocus();
                    },
                    child: Text(
                      'Use Text',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.blueAccent),
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

  void _sendMessage() async {
    if (_controller.text.isEmpty) return;

    String userMessage = _controller.text.trim();
    setState(() {
      _messages.add({
        "sender": "user",
        "message": userMessage,
        "timestamp": DateTime.now(),
        "message_id": const Uuid().v4(),
      });
      _isBotTyping = true;
      _controller.clear();
      _recentQueries.add(userMessage);
      if (_recentQueries.length > 5) _recentQueries.removeAt(0);
    });

    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'sender': 'user',
        'message': userMessage,
        'timestamp': FieldValue.serverTimestamp(),
        'message_id': const Uuid().v4(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save message')),
      );
    }

    String botResponse = await _getBotResponse(userMessage);

    setState(() {
      _isBotTyping = false;
      _messages.add({
        "sender": "bot",
        "message": botResponse,
        "timestamp": DateTime.now(),
        "message_id": const Uuid().v4(),
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
    String normalizedMessage = userMessage.toLowerCase().trim();

    if (_responseCache.containsKey(normalizedMessage)) {
      return _responseCache[normalizedMessage]!;
    }

    String? generalResponse = await _handleGeneralQueries(normalizedMessage);
    if (generalResponse != null) {
      await _saveCachedResponse(normalizedMessage, generalResponse);
      return generalResponse;
    }

    String? faqResponse = await _getFaqResponseWithGemini(normalizedMessage);
    if (faqResponse != null) {
      await _saveCachedResponse(normalizedMessage, faqResponse);
      return faqResponse;
    }

    return "Sorry, I can't find the answer for that response.";
  }

  Future<String?> _handleGeneralQueries(String normalizedMessage) async {
    final casualResponses = {
      'hi': 'Hello! How can I assist you today?',
      'hello': 'Hi there! Ready to answer your questions!',
      'hey': 'Hey! What do you want to know about RIT Chennai?',
      'ok': 'Alright! Anything specific you want to know?',
      'bye': 'Goodbye! Feel free to come back with more questions!',
      'goodbye': 'See you later! Have a great day!',
      'thanks': 'You\'re welcome! Any more questions?',
      'thank you': 'My pleasure! What\'s next on your mind?',
    };

    if (casualResponses.containsKey(normalizedMessage)) {
      return casualResponses[normalizedMessage];
    }

    if (normalizedMessage.contains('time') || normalizedMessage.contains('what time is it')) {
      final now = DateTime.now();
      return "The current time is ${now.hour}:${now.minute.toString().padLeft(2, '0')} on ${now.day}/${now.month}/${now.year}.";
    }

    if (normalizedMessage.contains('weather') || normalizedMessage.contains('what is the weather')) {
      return "I can't access real-time weather data, but here's a mock response: It's sunny in Chennai with a temperature of 32°C. Would you like to know something else?";
    }

    return null;
  }

  Future<String?> _getFaqResponseWithGemini(String userMessage) async {
    if (_faqData.isEmpty) return null;

    // Simulate Gemini API response to extract keywords and match with FAQ
    // In a real application, uncomment the HTTP request below and process the response
    List<String> extractedKeywords = await _extractKeywordsFromGemini(userMessage);

    String bestMatch = "";
    double bestScore = 0.0;

    for (var faq in _faqData) {
      String accessLevel = faq["access_level"] ?? "public";
      if (accessLevel == "students_only" && !isStudent) continue;

      String instruction = _normalizeQuery(faq["instruction"]!).toLowerCase();
      List<String> keywords = faq["keywords"]!.split(',').map((k) => k.trim().toLowerCase()).toList();
      List<String> relatedQuestions = faq["related_questions"]!
          .split(',')
          .map((q) => _normalizeQuery(q.trim()).toLowerCase())
          .toList();

      // Check keyword overlap with extracted keywords
      double keywordMatchScore = _calculateKeywordMatchScore(extractedKeywords, keywords);
      double instructionScore = extractedKeywords.any((kw) => instruction.contains(kw))
          ? ratio(userMessage, instruction) / 100.0
          : 0.0;
      double relatedQuestionScore = relatedQuestions.isNotEmpty
          ? relatedQuestions
          .map((q) => extractedKeywords.any((kw) => q.contains(kw))
          ? ratio(userMessage, q) / 100.0
          : 0.0)
          .reduce((a, b) => a > b ? a : b)
          : 0.0;

      double categoryBoost = (faq["category"] == _lastCategory) ? 0.2 : 0.0;
      double combinedScore = (0.3 * instructionScore) +
          (0.5 * keywordMatchScore) +
          (0.2 * relatedQuestionScore) +
          categoryBoost;

      if (combinedScore > bestScore && combinedScore >= 0.3) {
        bestScore = combinedScore;
        bestMatch = faq["output"] ?? "";
        setState(() {
          _lastCategory = faq["category"]!;
        });
      }
    }

    return bestScore > 0 ? bestMatch : null;
  }

  Future<List<String>> _extractKeywordsFromGemini(String userMessage) async {
    // Simulated keyword extraction (in a real scenario, Gemini API would process this)
    // Uncomment and implement the real API call below in a non-restricted environment
    /*
    if (_geminiApiKey.isEmpty) {
      print("API key is empty. Returning default keywords.");
      return [userMessage.split(' ').first];
    }

    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text':
                      'Extract the key terms or keywords from the following query related to Rajalakshmi Institute of Technology (RIT Chennai). Return them as a JSON array of strings. Query: $userMessage'
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final content = data['candidates'][0]['content'];
          if (content != null && content['parts'] != null && content['parts'].isNotEmpty) {
            String jsonString = content['parts'][0]['text']?.trim() ?? '[]';
            return (jsonDecode(jsonString) as List<dynamic>).map((e) => e.toString()).toList();
          }
        }
        print("Invalid Gemini keyword response structure: $data");
        return [userMessage.split(' ').first];
      } else {
        print("Gemini API error: ${response.statusCode}, Body: ${response.body}");
        return [userMessage.split(' ').first];
      }
    } catch (e) {
      print("Gemini keyword extraction error: $e");
      return [userMessage.split(' ').first];
    }
    */

    // Simulated keyword extraction based on query splitting
    return userMessage.split(' ').where((word) => word.length > 2).toList();
  }

  double _calculateKeywordMatchScore(List<String> queryKeywords, List<String> faqKeywords) {
    if (queryKeywords.isEmpty || faqKeywords.isEmpty) return 0.0;
    int matches = queryKeywords.where((qk) => faqKeywords.contains(qk)).length;
    return (matches / queryKeywords.length).clamp(0.0, 1.0);
  }

  String _normalizeQuery(String query) {
    if (_contextCache.containsKey(query)) return _contextCache[query]!;

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
      'collage': 'college',
      'univercity': 'university',
      'engeneering': 'engineering',
      'scholorship': 'scholarship',
      'rit': 'rit chennai',
      'courses available': 'what courses are offered at rit chennai',
      'available courses': 'what courses are offered at rit chennai',
      'what courses': 'what courses are offered at rit chennai',
      'which courses': 'what courses are offered at rit chennai',
    };

    final synonymMap = {
      'fee': ['cost', 'price', 'charge', 'expense', 'tuition'],
      'hostel': ['dorm', 'residence', 'accommodation', 'housing'],
      'placement': ['job', 'career', 'recruitment', 'employment'],
      'course': ['program', 'degree', 'class', 'subject', 'courses'],
      'campus': ['grounds', 'site', 'premises', 'college'],
      'library': ['books', 'resources', 'study'],
      'transport': ['bus', 'shuttle', 'commute'],
      'faculty': ['teacher', 'professor', 'staff', 'instructor'],
      'event': ['festival', 'celebration', 'activity'],
      'club': ['group', 'society', 'organization'],
      'admission': ['entry', 'enrollment', 'application'],
      'scholarship': ['financial aid', 'grant', 'bursary'],
      'college': ['institute', 'university', 'school'],
    };

    String normalized = query.toLowerCase().trim().replaceAll(RegExp(r'[^\w\s]'), '');

    typoMap.forEach((wrong, correct) {
      if (normalized.contains(wrong)) {
        normalized = normalized.replaceAll(wrong, correct);
      }
    });

    List<String> words = normalized.split(' ');
    for (int i = 0; i < words.length; i++) {
      synonymMap.forEach((key, synonyms) {
        if (synonyms.contains(words[i])) {
          words[i] = key;
        }
      });
    }
    normalized = words.join(' ');

    _contextCache[query] = normalized;
    return normalized;
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isBot = message['sender'] == 'bot';
    final timestamp = (message['timestamp'] as DateTime).toString().substring(11, 16);
    return Padding(
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
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              if (isBot) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isBot
                        ? (_isDarkMode ? Colors.blue[800]!.withOpacity(0.9) : Colors.blue[50]!.withOpacity(0.9))
                        : (_isDarkMode ? Colors.green[800]!.withOpacity(0.9) : Colors.green[100]!.withOpacity(0.9)),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _isDarkMode ? Colors.black54 : Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isBot
                      ? AnimatedTextKit(
                    animatedTexts: [
                      TypewriterAnimatedText(
                        message['message']!,
                        textStyle: TextStyle(
                          color: _isDarkMode ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontFamily: 'Poppins',
                        ),
                        speed: const Duration(milliseconds: 20),
                      ),
                    ],
                    totalRepeatCount: 1,
                  )
                      : Text(
                    message['message']!,
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                    ),
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
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              timestamp,
              style: TextStyle(
                fontSize: 12,
                color: _isDarkMode ? Colors.white70 : Colors.white70,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
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
            fontFamily: 'Poppins',
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
                  _isDarkMode ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.2),
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
              scale: _isListening ? _micScaleAnimation : AlwaysStoppedAnimation(1.0),
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
    final categorySuggestions = {
      'general': [
        {'label': 'Full Name', 'query': 'What is the full name of RIT Chennai?'},
        {'label': 'Website', 'query': 'What is the official website of RIT Chennai?'},
        {'label': 'Contact', 'query': 'What is the contact number for RIT Chennai?'},
        {'label': 'Address', 'query': 'What is the address of RIT Chennai?'},
      ],
      'academics': [
        {'label': 'Courses', 'query': 'What courses are offered at RIT Chennai?'},
        {'label': 'B.Tech Duration', 'query': 'What is the duration of B.E./B.Tech programs?'},
        {'label': 'Specializations', 'query': 'What specializations are available in B.Tech at RIT Chennai?'},
        {'label': 'Ph.D. Programs', 'query': 'Are there any Ph.D. programs at RIT Chennai?'},
      ],
      'admissions': [
        {'label': 'Admission Process', 'query': 'How can I apply for admission to RIT Chennai?'},
        {'label': 'Eligibility', 'query': 'What is the eligibility criteria for B.E./B.Tech programs?'},
        {'label': 'TNEA', 'query': 'What is TNEA and how does it relate to RIT Chennai admissions?'},
        {'label': 'Scholarships', 'query': 'Does RIT Chennai offer scholarships?'},
      ],
      'placements': [
        {'label': 'Placement Stats', 'query': 'What are the placement statistics for RIT Chennai?'},
        {'label': 'Top Recruiters', 'query': 'Who are some of the top recruiters at RIT Chennai?'},
        {'label': 'Highest Package', 'query': 'What is the highest salary package offered at RIT Chennai?'},
        {'label': 'Internships', 'query': 'Are there internship opportunities at RIT Chennai?'},
      ],
      'campus': [
        {'label': 'Campus Size', 'query': 'What is the size of the RIT Chennai campus?'},
        {'label': 'Hostel Fees', 'query': 'What is the hostel fee at RIT Chennai?'},
        {'label': 'Clubs', 'query': 'What student clubs are there at RIT Chennai?'},
        {'label': 'Facilities', 'query': 'What facilities are available on campus?'},
      ],
      'financial': [
        {'label': 'B.Tech Fees', 'query': 'What is the fee structure for B.Tech at RIT Chennai?'},
        {'label': 'Scholarships', 'query': 'Does RIT Chennai offer scholarships?'},
        {'label': 'Hostel Fees', 'query': 'What is the hostel fee at RIT Chennai?'},
        {'label': 'Transport', 'query': 'Does RIT Chennai offer transportation facilities?'},
      ],
    };

    return categorySuggestions[_lastCategory] ?? categorySuggestions['general']!;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: const AssetImage('assets/rit_building.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                _isDarkMode ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.3),
                BlendMode.dstATop,
              ),
            ),
          ),
          child: Column(
            children: [
              AppBar(
                title: const Text(
                  'RITA - RIT Chennai Chatbot',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 20),
                ),
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
                    icon: Icon(_isVoiceOutputEnabled ? Icons.volume_up : Icons.volume_off),
                    onPressed: () {
                      _saveVoiceOutputPreference(!_isVoiceOutputEnabled);
                    },
                    tooltip: 'Toggle Voice Output',
                  ),
                  IconButton(
                    icon: const Icon(Icons.brightness_4),
                    onPressed: () {
                      _saveThemePreference(!_isDarkMode);
                    },
                    tooltip: 'Toggle Theme',
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
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isDarkMode
                                    ? Colors.blue[800]!.withOpacity(0.9)
                                    : Colors.blue[50]!.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const CircularProgressIndicator(strokeWidth: 2),
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
                    const SizedBox(height: 8),
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
                              fontFamily: 'Poppins',
                              color: _isDarkMode ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ask about RIT Chennai...',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                color: _isDarkMode ? Colors.grey[400] : Colors.grey,
                              ),
                              filled: true,
                              fillColor: _isDarkMode ? Colors.grey[800] : Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            onSubmitted: (_) {
                              _isVoiceInput = false;
                              _sendMessage();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildVoiceDetectorAnimation(),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blueAccent,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
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