import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:animated_background/animated_background.dart';
import 'package:animate_do/animate_do.dart';

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
    {"sender": "bot", "message": "Hello! I'm the RIT Chennai FAQ Bot. Ask me anything about RIT Chennai!"}
  ];
  final ScrollController _scrollController = ScrollController();
  bool _isBotTyping = false;

  // FAQ data with keywords
  final List<Map<String, String>> faqs = [
    {
      "question": "What is the full name of RIT Chennai?",
      "answer": "The full name is Rajalakshmi Institute of Technology, Chennai.",
      "keywords": "full name, rit chennai, name, institute"
    },
    {
      "question": "When was RIT Chennai established?",
      "answer": "RIT Chennai was established in 2008.",
      "keywords": "established, founded, start year, creation"
    },
    {
      "question": "Where is RIT Chennai located?",
      "answer": "RIT Chennai is located in Chennai, Tamil Nadu, India, on the Chennai-Bangalore National Highway near Satellite City, opposite to EVP Film City.",
      "keywords": "location, address, where, campus"
    },
    {
      "question": "What are the affiliations and approvals of RIT Chennai?",
      "answer": "RIT Chennai is approved by AICTE, affiliated with Anna University, Chennai, and accredited with 'A++' Grade by NAAC. It is also one of the AICTE-approved colleges and offers NBA-approved courses.",
      "keywords": "affiliations, approvals, accreditation, naac, aicte, anna university"
    },
    {
      "question": "What courses does RIT Chennai offer?",
      "answer": "RIT Chennai offers undergraduate courses in various engineering disciplines, including B.Tech. in Artificial Intelligence & Data Science, B.Tech in Computer Science and Business Systems, B.E. in Computer & Communication Engineering, B.E. in Computer Science & Engineering, B.E. in Electronics & Communication Engineering, B.E. in Mechanical Engineering, and more.",
      "keywords": "courses, programs, b.tech, b.e., engineering, academics"
    },
    {
      "question": "What is the total student strength at RIT Chennai?",
      "answer": "As of 2023-24, the total student strength is 2,909 students, with 1,581 males and 1,328 females.",
      "keywords": "student strength, total students, enrollment, population"
    },
    {
      "question": "What is the sanctioned intake for UG programs at RIT Chennai?",
      "answer": "The sanctioned intake for UG 4-year programs has increased over the years: 600 in 2020-21, 660 in 2021-22, 780 in 2022-23, and 900 in 2023-24.",
      "keywords": "sanctioned intake, ug intake, admission capacity, seats"
    },
    {
      "question": "What are the placement statistics for RIT Chennai?",
      "answer": "For the academic years 2018-19 to 2020-21, placement rates were high, with 371 out of 382 (97%) placed in 2018-19 with a median salary of ₹4,75,000, 269 out of 282 (95%) in 2019-20 with ₹5,16,000, and 337 out of 348 (97%) in 2020-21 with ₹5,35,000.",
      "keywords": "placement statistics, placements, jobs, salary, career"
    },
    {
      "question": "Does RIT Chennai offer scholarships?",
      "answer": "Yes, RIT Chennai offers scholarships and stipends to meritorious students. For specific details, students should contact the institute administration.",
      "keywords": "scholarships, financial aid, stipends, funding"
    },
    {
      "question": "What are the facilities for physically challenged students at RIT Chennai?",
      "answer": "RIT Chennai provides lifts/ramps, walking aids including wheelchairs and transportation, and specially designed toilets in more than 80% of its buildings.",
      "keywords": "facilities for physically challenged, accessibility, disability, support"
    },
    {
      "question": "What are the sustainable living practices at RIT Chennai?",
      "answer": "RIT Chennai has implemented various sustainable practices, including a ban on single-use plastics, carbon footprint reduction efforts, comprehensive recycling infrastructure, rainwater harvesting systems, renewable energy installations, and food waste management.",
      "keywords": "sustainable practices, environment, green initiatives, eco-friendly"
    },
    {
      "question": "How many faculty members are there at RIT Chennai?",
      "answer": "There are approximately 206 faculty members, with various designations including Professors, Associate Professors, and Assistant Professors, many holding Ph.D. or M.E./M.Tech degrees.",
      "keywords": "faculty members, teachers, professors, staff"
    },
    {
      "question": "What is the gender distribution among students at RIT Chennai?",
      "answer": "As of 2023-24, there are 1,581 male students and 1,328 female students.",
      "keywords": "gender distribution, male female ratio, student demographics"
    },
    {
      "question": "Does RIT Chennai have hostels for students?",
      "answer": "Yes, RIT Chennai has separate hostels for boys and girls. The boys' hostel can accommodate 674 students, and the girls' hostel can accommodate 448 students. The hostels are equipped with modern facilities, including attached bathrooms, and are maintained by the college administration.",
      "keywords": "hostels, accommodation, dormitories, residence"
    },
    {
      "question": "What are the research opportunities at RIT Chennai?",
      "answer": "RIT Chennai has active research programs, with 9 full-time and 25 part-time Ph.D. students as of 2023-24. The institute also receives funding for research from various agencies, with amounts like ₹2,04,63,257 in 2023-24 from 14 agencies. Additionally, there are consultancy projects and executive development programs that faculty and students can participate in.",
      "keywords": "research opportunities, ph.d., funding, projects"
    },
    {
      "question": "Is RIT Chennai involved in any innovation or startup initiatives?",
      "answer": "Yes, RIT Chennai has a strong focus on innovation and entrepreneurship. It has received innovation grants from organizations like SERB, AICTE, DAE, and MSME. The institute has filed and been granted several patents, though none have been commercialized yet. There are over 100 innovations listed, covering areas like AI, IoT, Blockchain, and Healthcare. RIT also supports startups through incubation and pre-incubation activities, with participants and expenditures listed for recent years.",
      "keywords": "innovation, startups, entrepreneurship, incubation, patents"
    },
    {
      "question": "What is the placement record at RIT Chennai?",
      "answer": "RIT Chennai has a strong placement record, with high placement rates and increasing median salaries. For example, in 2020-21, 337 out of 348 graduates were placed, with a median salary of ₹5,35,000. Top recruiters include Infosys, Justdial, L & T InfoTech, Wipro, JBM Auto Systems, Amazon, Capgemini, and Altair, among others.",
      "keywords": "placement record, job placements, recruiters, employment"
    },
    {
      "question": "What are the sports facilities available at RIT Chennai?",
      "answer": "RIT Chennai has both indoor and outdoor sports facilities. Indoor facilities include Chess, Carom, Table Tennis, and Badminton, while outdoor facilities include Volleyball, Football, Cricket, Kho-Kho, and Kabaddi. The institute also has a qualified Physical Education staff to train students.",
      "keywords": "sports facilities, athletics, games, recreation"
    },
    {
      "question": "Is RIT Chennai accredited by NAAC?",
      "answer": "Yes, RIT Chennai is accredited with the highest grade of A++ by NAAC.",
      "keywords": "naac accreditation, naac grade, certification"
    },
    {
      "question": "What is the ranking of RIT Chennai?",
      "answer": "RIT Chennai is ranked between 151-200 in the 'Engineering' category by the NIRF ranking 2024.",
      "keywords": "ranking, nirf, position, rating"
    },
    {
      "question": "Does RIT Chennai have a library?",
      "answer": "Yes, RIT Chennai has a central library located in the institutional building, occupying 607 sq.m. It has a collection of 18,328 volumes of textbooks and reference books in various disciplines, and it is equipped with modern facilities.",
      "keywords": "library, books, resources, study"
    },
    {
      "question": "What are the transportation facilities at RIT Chennai?",
      "answer": "RIT Chennai provides transportation facilities for students and staff, with buses operating from various locations in the city.",
      "keywords": "transportation, buses, commute, travel"
    },
    {
      "question": "Are there any student clubs or societies at RIT Chennai?",
      "answer": "Yes, RIT Chennai has various student clubs and societies that promote extracurricular activities and personal development.",
      "keywords": "student clubs, societies, extracurricular, activities"
    },
    {
      "question": "What is the fee structure for UG programs at RIT Chennai?",
      "answer": "The tuition fee for BE and B.Tech courses is approximately INR 2 Lacs per year, which comes to a total course fee of near about INR 8 lakhs.",
      "keywords": "fee structure, tuition, cost, expenses"
    },
    {
      "question": "Does RIT Chennai offer PG programs?",
      "answer": "Yes, RIT Chennai offers postgraduate programs in various disciplines.",
      "keywords": "pg programs, postgraduate, masters, graduate"
    },
    {
      "question": "What is the admission process for RIT Chennai?",
      "answer": "Admission to UG programs is done through TNEA Counselling. For specific details, candidates can check the official website or contact the admissions office.",
      "keywords": "admission process, tnea, how to apply, enrollment"
    },
    {
      "question": "Are there any incubation centers or startup support at RIT Chennai?",
      "answer": "Yes, RIT Chennai supports startups through incubation and pre-incubation activities, with dedicated facilities and mentorship.",
      "keywords": "incubation centers, startup support, entrepreneurship, business"
    },
    {
      "question": "What are the environmental initiatives at RIT Chennai?",
      "answer": "RIT Chennai has implemented various environmental initiatives, including rainwater harvesting, solar energy installations, and waste management systems.",
      "keywords": "environmental initiatives, green practices, sustainability, eco"
    },
    {
      "question": "How can I contact RIT Chennai for more information?",
      "answer": "For more information, you can visit the official website of RIT Chennai or contact the admissions office directly.",
      "keywords": "contact, reach out, information, connect"
    }
  ];

  void _sendMessage() {
    if (_controller.text.isEmpty) return;

    String userMessage = _controller.text.trim().toLowerCase();
    setState(() {
      _messages.add({"sender": "user", "message": userMessage});
      _isBotTyping = true;
      _controller.clear();
    });

    // Scroll to the bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

    // Calculate relevance scores for FAQs based on keyword matches
    List<Map<String, dynamic>> scoredFaqs = [];
    for (var faq in faqs) {
      List<String> keywords = faq['keywords']!.toLowerCase().split(', ');
      int score = 0;
      for (var keyword in keywords) {
        if (userMessage.contains(keyword)) {
          score += 10; // Higher score for exact keyword match
        } else if (keyword.split(' ').any((word) => userMessage.contains(word))) {
          score += 3; // Lower score for partial word match
        }
      }
      if (score > 0) {
        scoredFaqs.add({'faq': faq, 'score': score});
      }
    }

    // Sort FAQs by score and select top matches
    scoredFaqs.sort((a, b) => b['score'].compareTo(a['score']));
    String botResponse;
    if (scoredFaqs.isEmpty) {
      botResponse = "No data about this question. Try asking about courses, admissions, or facilities!";
    } else {
      // Combine answers from top-scoring FAQs (up to 2 for brevity)
      List<String> answers = scoredFaqs
          .take(2)
          .map((scoredFaq) => scoredFaq['faq']['answer'] as String)
          .toList();
      botResponse = answers.join('\n\n');
    }

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

  Widget _buildMessage(String message, String sender, int index) {
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

  Widget _buildTypingIndicator() {
    return SlideInLeft(
      duration: const Duration(milliseconds: 300),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DotAnimation(),
              const SizedBox(width: 5),
              const DotAnimation(delay: 200),
              const SizedBox(width: 5),
              const DotAnimation(delay: 400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RIT Chennai FAQ Chatbot'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent, Colors.lightBlueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Animated Background with Gradient
          AnimatedBackground(
            behaviour: RandomParticleBehaviour(
              options: const ParticleOptions(
                baseColor: Colors.white,
                spawnMinSpeed: 5.0,
                spawnMaxSpeed: 20.0,
                spawnMinRadius: 1.0,
                spawnMaxRadius: 3.0,
                particleCount: 30,
                opacityChangeRate: 0.1,
              ),
            ),
            vsync: this,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF60A5FA)], // Dark blue to light blue
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Chat UI
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length + (_isBotTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isBotTyping && index == _messages.length) {
                      return _buildTypingIndicator();
                    }
                    return _buildMessage(
                        _messages[index]['message']!, _messages[index]['sender']!, index);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Focus(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: "Ask about RIT Chennai...",
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                        onFocusChange: (hasFocus) {
                          setState(() {}); // Trigger rebuild for glow effect
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ZoomIn(
                      duration: const Duration(milliseconds: 200),
                      child: FloatingActionButton(
                        onPressed: _sendMessage,
                        backgroundColor: Colors.blueAccent,
                        child: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class DotAnimation extends StatefulWidget {
  final int delay;

  const DotAnimation({super.key, this.delay = 0});

  @override
  _DotAnimationState createState() => _DotAnimationState();
}

class _DotAnimationState extends State<DotAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      _controller.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -_animation.value),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}