import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      "Hello! I'm RITA, your guide to Rajalakshmi Institute of Technology (RIT Chennai). Tap the mic to ask about campus, fees, placements, or courses! Try: 'What is the full name of RIT Chennai?'",
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
  static const double _minSoundLevel = -10.0; // Threshold for detecting voice
  static const int _maxSilenceSeconds = 5; // Timeout for no voice detected

  // Casual message responses
  final Map<String, String> _casualResponses = {
    "hi": "Hey there! How can I help you with RIT Chennai today?",
    "hello": "Hello! Ready to explore RIT Chennai? Ask me anything!",
    "bye": "Goodbye! Feel free to come back with more questions about RIT Chennai!",
    "ok": "Alright! What's next? Ask about campus, fees, or anything else!",
    "thanks": "You're welcome! Anything else about RIT Chennai I can help with?",
    "thank you": "My pleasure! Got more questions about RIT Chennai?",
  };

  @override
  void initState() {
    super.initState();
    _loadFaqData();
    _loadCachedResponses();
    _loadVoiceOutputPreference();
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
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final String response = await rootBundle.loadString('assets/college_faq.json');
        final List<dynamic> data = jsonDecode(response);
        setState(() {
          _faqData = data.map((item) => {
            "instruction": item["instruction"]?.toString() ?? "",
            "output": item["output"]?.toString() ?? "",
            "keywords": item["keywords"]?.toString() ?? item["instruction"]?.toString().toLowerCase() ?? "",
            "category": item["category"]?.toString() ?? "general",
            "related_questions": item["related_questions"]?.toString() ?? item["instruction"]?.toString() ?? "",
            "access_level": item["access_level"]?.toString() ?? "public",
          }).toList();
        });
        print("FAQ Data Loaded: ${_faqData.length} entries");
        return;
      } catch (e) {
        print("Error loading FAQ data (attempt $attempt): $e");
        if (attempt == 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load FAQs after $attempt attempts')),
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

  Future<void> _saveLearnedResponse(String query, String response) async {
    try {
      final normalizedQuery = _normalizeQuery(query);
      final collection = FirebaseFirestore.instance.collection('learned_responses');
      final querySnapshot = await collection
          .where('normalized_query', isEqualTo: normalizedQuery)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        await collection.add({
          'normalized_query': normalizedQuery,
          'original_query': query,
          'response': response,
          'timestamp': FieldValue.serverTimestamp(),
        });
        print("Saved learned response for query: $query");
      }
      // Limit Firestore collection size
      final allDocs = await collection.orderBy('timestamp').get();
      if (allDocs.docs.length > 1000) {
        await allDocs.docs.first.reference.delete();
      }
    } catch (e) {
      print("Error saving learned response: $e");
    }
  }

  Future<String?> _getLearnedResponse(String query) async {
    try {
      final normalizedQuery = _normalizeQuery(query);
      final querySnapshot = await FirebaseFirestore.instance
          .collection('learned_responses')
          .where('normalized_query', isEqualTo: normalizedQuery)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data()['response'] as String?;
      }
    } catch (e) {
      print("Error fetching learned response: $e");
    }
    return null;
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
                child: Icon(
                  Icons.mic_off,
                  color: Colors.white,
                  size: 50,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Oops, No Voice Detected!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Please speak clearly or tap "Try Again" to retry.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _listen();
                },
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
      });
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
    String normalizedMessage = _normalizeQuery(userMessage);

    // Check for casual messages
    if (_casualResponses.containsKey(normalizedMessage)) {
      final response = _casualResponses[normalizedMessage]!;
      await _saveCachedResponse(normalizedMessage, response);
      return response;
    }

    // Check local cache
    if (_responseCache.containsKey(normalizedMessage)) {
      return _responseCache[normalizedMessage]!;
    }

    // Check learned responses in Firestore
    final learnedResponse = await _getLearnedResponse(userMessage);
    if (learnedResponse != null) {
      await _saveCachedResponse(normalizedMessage, learnedResponse);
      return learnedResponse;
    }

    // Check FAQ data
    for (var faq in _faqData) {
      String faqInstruction = _normalizeQuery(faq["instruction"]!);
      String accessLevel = faq["access_level"] ?? "public";
      if (accessLevel == "students_only" && !isStudent) {
        continue;
      }
      if (normalizedMessage == faqInstruction) {
        await _saveCachedResponse(normalizedMessage, faq["output"]);
        return faq["output"] ?? "No response available";
      }
    }

    String? bestMatch;
    double bestScore = 0.0;
    for (var faq in _faqData) {
      String accessLevel = faq["access_level"] ?? "public";
      if (accessLevel == "students_only" && !isStudent) {
        continue;
      }

      String instruction = _normalizeQuery(faq["instruction"]!);
      List<String> keywords = faq["keywords"]!.split(',').map((k) => k.trim().toLowerCase()).toList();
      List<String> relatedQuestions = faq["related_questions"]!.split(',').map((q) => _normalizeQuery(q.trim())).toList();

      double instructionScore = _calculateSimilarity(normalizedMessage.split(' ').toList(), instruction);
      double keywordScore = _calculateKeywordScore(normalizedMessage, keywords);
      double relatedQuestionScore = relatedQuestions.isNotEmpty
          ? relatedQuestions
          .map((q) => _calculateSimilarity(normalizedMessage.split(' ').toList(), q))
          .reduce((a, b) => a > b ? a : b)
          : 0.0;

      double combinedScore = (0.5 * instructionScore) + (0.3 * keywordScore) + (0.2 * relatedQuestionScore);

      if (combinedScore > bestScore && combinedScore >= 0.3) {
        bestScore = combinedScore;
        bestMatch = faq["output"];
      }
    }

    if (bestMatch != null) {
      await _saveCachedResponse(normalizedMessage, bestMatch);
      return bestMatch;
    }

    // Check restricted queries
    if (!isStudent && (normalizedMessage.contains("attendance") || normalizedMessage.contains("student portal"))) {
      return "This information is restricted to RIT Chennai students. Please log in as a student.";
    }

    // Fallback to Gemini API and save response for learning
    final geminiResponse = await getGeminiResponse(userMessage);
    await _saveCachedResponse(normalizedMessage, geminiResponse);
    await _saveLearnedResponse(userMessage, geminiResponse);
    return geminiResponse;
  }

  String _normalizeQuery(String query) {
    if (_normalizedQueryCache.containsKey(query)) {
      return _normalizedQueryCache[query]!;
    }

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
    };

    final synonymMap = {
      'fee': ['cost', 'price', 'charge', 'expense', 'tuition'],
      'hostel': ['dorm', 'residence', 'accommodation'],
      'placement': ['job', 'career', 'recruitment'],
      'course': ['program', 'degree', 'class'],
      'campus': ['grounds', 'site', 'premises'],
      'library': ['books', 'resources'],
      'transport': ['bus', 'shuttle'],
      'faculty': ['teacher', 'professor', 'staff'],
      'event': ['festival', 'celebration'],
      'club': ['group', 'society'],
    };

    String normalized = query.toLowerCase().trim().replaceAll(RegExp(r'[^\w\s]'), '');
    typoMap.forEach((wrong, correct) {
      normalized = normalized.replaceAll(wrong, correct);
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

    _normalizedQueryCache[query] = normalized;
    return normalized;
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
          if (word.contains(keyword) || keyword.contains(word)) {
            score += 0.5;
            break;
          }
        }
      }
    }
    return (score / keywords.length).clamp(0.0, 1.0);
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
      'admission',
      'scholarship',
      'faculty',
      'library',
      'transport',
      'club',
      'event',
    };

    final intersection = querySet.intersection(instructionWords);
    final union = querySet.union(instructionWords);
    double jaccardSimilarity = intersection.length / union.length;

    int keyTermMatches = intersection.where((word) => keyTerms.contains(word)).length;
    double keyTermBoost = keyTermMatches * 0.2;

    double lengthPenalty = (instructionWords.length < 3 || querySet.length < 3) ? 0.05 : 0.0;

    return (jaccardSimilarity + keyTermBoost - lengthPenalty).clamp(0.0, 1.0);
  }

  Future<String> getGeminiResponse(String userMessage) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      return "API key not configured. Please try again later.";
    }

    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                  'You are RITA, a chatbot for Rajalakshmi Institute of Technology (RIT Chennai). Provide accurate, concise answers about RIT Chennai. If unknown, say: "I don\'t have specific information on that. Please ask another question about RIT Chennai." Question: $userMessage'
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text']?.trim() ?? "Sorry, I couldn't process that.";
      }
      return "Sorry, I couldn't get a response. Try asking something specific about RIT Chennai!";
    } catch (e) {
      return "Sorry, I couldn't connect to the server. Try again later!";
    }
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
                  child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                ),
              if (isBot) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isBot ? Colors.blue[50]!.withOpacity(0.9) : Colors.green[100]!.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: isBot
                      ? AnimatedTextKit(
                    animatedTexts: [
                      TypewriterAnimatedText(
                        message['message']!,
                        textStyle: TextStyle(color: Colors.black87, fontSize: 16, fontFamily: 'Poppins'),
                        speed: const Duration(milliseconds: 20),
                      ),
                    ],
                    totalRepeatCount: 1,
                  )
                      : Text(
                    message['message']!,
                    style: TextStyle(color: Colors.black87, fontSize: 16, fontFamily: 'Poppins'),
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
              style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Poppins'),
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
        label: Text(label, style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
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
                  _isListening ? Colors.blueAccent.withOpacity(0.6) : Colors.blueAccent.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
                stops: [0.0, 0.5, 1.0],
                radius: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isListening ? Colors.blueAccent.withOpacity(0.5) : Colors.blueAccent.withOpacity(0.3),
                  blurRadius: _isListening ? 15.0 : 5.0,
                  spreadRadius: _isListening ? 5.0 : 2.0,
                ),
              ],
            ),
            child: ScaleTransition(
              scale: _isListening ? _micScaleAnimation : AlwaysStoppedAnimation(1.0),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white,
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
      {'label': 'Campus Size', 'query': 'What is the size of the RIT Chennai campus?'},
      {'label': 'Hostel Fees', 'query': 'What is the hostel fee at RIT Chennai?'},
      {'label': 'Placements', 'query': 'What are the placement statistics for RIT Chennai?'},
      {'label': 'Courses', 'query': 'What courses are offered at RIT Chennai?'},
      {'label': 'Admission', 'query': 'How can I apply for admission to RIT Chennai?'},
      {'label': 'Scholarships', 'query': 'Does RIT Chennai offer scholarships?'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/rit_building.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.dstATop),
          ),
        ),
        child: Column(
          children: [
            AppBar(
              title: Text('RITA - RIT Chennai Chatbot', style: Theme.of(context).textTheme.headlineSmall),
              backgroundColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent, Colors.blue],
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
                            child: Text('R', style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50]!.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: CircularProgressIndicator(strokeWidth: 2),
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
              color: Colors.white,
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
                          style: TextStyle(fontFamily: 'Poppins'),
                          decoration: InputDecoration(
                            hintText: 'Ask about RIT Chennai...',
                            hintStyle: TextStyle(fontFamily: 'Poppins'),
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
    );
  }
}