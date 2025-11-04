import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';


void main() {
  runApp(const CodingBahasa());
}

// ---------- Root ----------
class CodingBahasa extends StatelessWidget {
  const CodingBahasa({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MaterialAppState(),
      child: MaterialApp(
        title: 'CodingBahasa',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        home: HomePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// ---------- Home ----------
class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const Center(
          child: Text(
            'Welcome to CodingBahasa!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        );
        
      case 1:
        page = const CoursePage();
       
      case 2:
        page = MaterialsPage();
       
      case 3:
        page = const QuizPage();
        
      case 4:
        page = const AIChatbotPage();
        
      case 5:
        page = const ProgressPage();
       
      case 6:
        page = const AchievementsPage();
        
      case 7:
        page = const ProfilePage();
        
      default:
        page = const Center(child: Text('Page not found'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CodingBahasa', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Connect, Code and Challenge',
                style: TextStyle(fontSize: 15, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 32),
            tooltip: 'Profile',
            onPressed: () => setState(() => selectedIndex = 7),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // ---------- MENU ----------
          Container(
            color: Colors.grey[200],
            height: 50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _buildMenuButton('Home', 0),
                  _buildMenuButton('Courses', 1),
                  _buildMenuButton('Materials', 2),
                  _buildMenuButton('Quiz', 3),
                  _buildMenuButton('AI Chatbot', 4),
                  _buildMenuButton('Progress', 5),
                  _buildMenuButton('Achievements', 6),
                ],
              ),
            ),
          ),

          // ---------- MAIN CONTENT ----------
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Container(
                key: ValueKey(selectedIndex),
                color: Colors.white,
                alignment: Alignment.center,
                child: page,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(String label, int index) {
    final isSelected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton(
        onPressed: () => setState(() => selectedIndex = index),
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? Colors.blue[900] : Colors.black,
          backgroundColor: isSelected ? Colors.blue[100] : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

// ---------- Course ----------
class CoursePage extends StatelessWidget {
  const CoursePage({super.key});

  final List<Map<String, String>> topics = const [
    {
      "title": "1.1 Strategi Penyelesaian Masalah",
      "note": """MASALAH - Keraguan, situasi yang tidak diingini, cabaran & peluang yang dihadapi dalam kehidupan seseorang 
\n(4) TEKNIK PEMIKIRAN KOMPUTASIONAL
• Leraian – Memecahkan masalah kepada bahagian yang lebih kecil & terkawal
• Pengecaman corak – Mencari persamaan antara masalah & dalam masalah
• Peniskalaan – Menjana penyelesaian yang tepat kepada masalah yang dihadapi
• Algoritma – Membangunkan penyelesaian langkah demi langkah terhadap masalah yang dihadapi
\n(3) CIRI PENYELESAIAN MASALAH BERKESAN 
• Kos 
• Masa
• Sumber
\n(8) PROSES PENYELESAIAN MASALAH
1. Mengumpulkan & menganalisis data
2. Menentukan masalah
3. Menjana idea
4. Menjana penyelesaian
5. Menentukan tindakan
6. Melaksanakan penyelesaian
7. Membuat penilaian
8. Membuat penambahbaikan"""
    },
    {
      "title": "1.2 Algoritma",
      "note": """Algoritma - Satu set arahan untuk menyelesaikan masalah 
\n(3) CIRI ALGORITMA
• Butiran jelas
• Boleh dilaksanakan
• Mempunyai batasan
\nINPUT -> PROSES -> OUTPUT
\nPSEUDOKOD - Senarai struktur kawalan komputer yang ditulis dalam bahasa pertuturan manusia & mempunyai nombor turutan
\nCARTA ALIR - Alternatif kepada pseudokod menggunakan simbol grafik untuk mewakili arahanarahan penyelesaian
\n(3) STRUKTUR KAWALAN DALAM PENGATURCARAAN
• Struktur Kawalan Urutan
• Struktur Kawalan Pilihan
• Struktur Kawalan Pengulangan
\nTulis Algortima -> Uji ALgortima -> Pembetulan -> Pengaturcaraan
\n (3) RALAT
• Ralat Sintaks
• Ralat Logik
• Ralat Masa Larian
\n(4) LANGKAH PENGUJIAN ALGORITMA
1. Kenal pasti "Output Dijangka"
2. Kenal pasti "Output Diperoleh"
3. Bandingkan "Output Diperoleh" dengan "Output Dijangka"
4. Analisis & baiki algoritma
"""
    },
    {
      "title": "1.3 Pemboleh Ubah, Pemalar dan Jenis Data",
      "note": """PEMBOLEH UBAH - Ruang simpanan sementara untuk nombor, teks & objek
\nPEMALAR - Tetap & tidak akan berubah
\n(6) JENIS DATA
• Integer
• float
• double
• char
• String
• Boolean
\nPEMBOLEH UBAH SEJAGAT (GLOBAL) - Hanya berfungsi dalam atur cara sahaja
PEMBOLEH UBAH SETEMPAT (LOCAL) - Hanya berfungsi dalam subatur cara yang diisytiharkan

"""
    },
    {
      "title": "1.4 Struktur Kawalan",
      "note": """(3) STRUKTUR KAWALAN 
• Kawalan Urutan - Tidak bervariasi
• Kawalan Pilihan - If-else-if, Switch-case
• Kawalan Pengulangan - For, While, Do-while
\n(6) OPERATOR HUBUNGAN
• Sama dengan (==)
• Tidak sama dengan (!=)
• Lebih besar daripada (>)
• Lebih besar / sama dengan (>=)
• Kurang daripada (<)
• Kurang / sama dengan (<=)
\n(3) OPERATOR LOGICAL
• AND
• OR
• NOT
"""
    },
    {
      "title": "1.5 Amalan Terbaik Pengaturcaraan",
      "note": """AMALAN TERBAIK PENGATURCARAAN - Apabila pengatur cara dapat mempraktikkan amalan-amalan yang biasa diikuti untuk menghasilkan
atur cara yang baik
\n(4) FAKTOR MEMPENGARUHI KEBOLEHBACAAN KOD
• Inden yang konsisten
• Jenis data
• Pemboleh ubah yang bermakna
• Komen
\nRALAT SINTAKS
• Kesalahan tatabahasa
• Penggunaan objek / aksara yang tidak dikenali
\nRALAT MASA LARIAN
• Pengiraan data bukan berangka
• Pembahagian dengan digit 0
• Mencari punca kuasa dua bagi nombor negatif
\nRALAT MASA LARIAN
• Atur cara tidak berfungsi seperti yang diingini
• Tidak dapat dikesan
"""
    },
    {
      "title": "1.6 Struktur Data dan Modular",
      "note": """TATASUSUNAN - Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks
\n(5) KELEBIHAN MENGGUNAKAN STRUKTUR MODUL
• Lebih mudah untuk digunakan semula
• Lebih mudah untuk diuji, dinyah pijat & dibaiki
• Projek kompleks menjadi lebiringkas
• Lebih mudah untuk menangani projek komputer
• Membolehkan tugasan pengaturcaraan dibahagikan kepada ahli kumpulan yang berbeza
"""
    },
    {
      "title": "1.7 Pembagunan Aplikasi",
      "note": """KITARAN HAYAT PEMBANGUNAN SISTEM (SDLC)
1. Analisis masalah
2. Reka bentuk penyelesaian - Logikal, Fizikal
3. Laksana penyelesaian
4. Uji & nyah ralat
5. Dokumentasi
"""
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('📘 Courses'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView.builder(
          itemCount: topics.length,
          itemBuilder: (context, index) {
            final topic = topics[index];
            return Card(
              elevation: 2,
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Topic title
                    Text(
                      topic["title"]!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.lightBlue,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Pre-written note (read-only)
                    Text(
                      topic["note"]!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


// ---------- Quiz ----------
class QuizPage extends StatelessWidget {
  const QuizPage({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        'This is the Quiz Page',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
}

// ---------- AI Chatbot ----------
// ---------- AI Chatbot ----------
class AIChatbotPage extends StatelessWidget {
  const AIChatbotPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            AppBar(
              title: const Text('🤖 AI Study Buddy'),
              backgroundColor: Colors.lightBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            const Expanded(
              child: _ChatBody(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state is ChatLoaded) {
                return _buildChatList(state.messages);
              } else if (state is ChatError) {
                return Center(
                  child: Text(
                    'Error: ${state.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              } else if (state is ChatLoading) {
                return _buildChatList(const []);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildChatList(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Start a conversation with AI Study Buddy!',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Try asking about: photosynthesis, quadratic equations, Java, etc.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      reverse: false,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _buildChatBubble(message);
      },
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0), // ← FIX 2: properties first
      child: Row( // ← FIX 2: child last
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.lightBlue,
              radius: 16, // ← Also fix this CircleAvatar
              child: Text(
                'AI',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: message.isUser 
                    ? Colors.lightBlue[50] 
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  if (message.responseTime != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${message.responseTime}ms',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        if (message.confidence != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getConfidenceColor(message.confidence!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              message.confidence!.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 8, 
                                color: Colors.white, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.green,
              radius: 16, // ← Fix child order here too
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Color _getConfidenceColor(String confidence) {
    switch (confidence) {
      case 'high': return Colors.green;
      case 'medium': return Colors.orange;
      case 'low': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildMessageInput() {
    final controller = TextEditingController();
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Ask about Math, Science, Programming...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              ),
              onSubmitted: (value) => _sendMessage(controller),
            ),
          ),
          const SizedBox(width: 8),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              final isLoading = state is ChatLoading;
              return Container(
                decoration: BoxDecoration(
                  color: isLoading ? Colors.grey : Colors.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                  onPressed: isLoading ? null : () => _sendMessage(controller),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _sendMessage(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isNotEmpty) {
      // FIX 3: Now we can use mounted safely
      if (mounted) {
        context.read<ChatBloc>().add(SendMessageEvent(text));
      }
      controller.clear();
    }
  }
}

// ========== AI CHATBOT SUPPORTING CLASSES ==========

// Chat Message Model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final int? responseTime;
  final String? confidence;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.responseTime,
    this.confidence,
  });

  @override
  String toString() {
    return 'ChatMessage{text: $text, isUser: $isUser, timestamp: $timestamp}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser &&
          timestamp == other.timestamp;

  @override
  int get hashCode => text.hashCode ^ isUser.hashCode ^ timestamp.hashCode;
}

// Chat BLoC Events
abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object> get props => [];
}

class SendMessageEvent extends ChatEvent {
  final String message;

  const SendMessageEvent(this.message);

  @override
  List<Object> get props => [message];
}

class ClearChatEvent extends ChatEvent {}

// Chat BLoC Events 
class LoadWelcomeEvent extends ChatEvent {
  const LoadWelcomeEvent();

  @override
  List<Object> get props => [];
}

// Chat BLoC States
abstract class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object> get props => [];
}

class ChatInitial extends ChatState {
  const ChatInitial();
}

class ChatLoading extends ChatState {
  const ChatLoading();
}

class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final int responseTime;

  const ChatLoaded({required this.messages, this.responseTime = 0});

  @override
  List<Object> get props => [messages, responseTime];
}

class ChatError extends ChatState {
  final String error;

  const ChatError({required this.error});

  @override
  List<Object> get props => [error];
}

// Chat BLoC Implementation

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: "Hello! I'm your AI study buddy. Ask me about: photosynthesis, quadratic equations, Java programming, gravity, or mitochondria!",
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ];

  // Predefined FAQs for Sprint 1
  final Map<String, Map<String, dynamic>> _faqs = {
    'photosynthesis': {
      'answer': 'Photosynthesis is the process plants use to convert sunlight, water, and carbon dioxide into glucose and oxygen. The chemical equation is: 6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂',
      'keywords': ['photosynthesis', 'plants', 'energy', 'sunlight', 'oxygen'],
      'category': 'biology'
    },
    'quadratic equation': {
      'answer': 'A quadratic equation is in the form ax² + bx + c = 0. Solve using the quadratic formula: x = [-b ± √(b² - 4ac)] / 2a. The discriminant (b² - 4ac) determines the nature of roots.',
      'keywords': ['quadratic', 'equation', 'formula', 'algebra', 'solve'],
      'category': 'math'
    },
    'java programming': {
      'answer': 'Java is an object-oriented programming language known for its "write once, run anywhere" capability using the Java Virtual Machine (JVM). It\'s strongly typed and platform-independent.',
      'keywords': ['java', 'programming', 'language', 'oop', 'jvm'],
      'category': 'computer science'
    },
    'gravity': {
      'answer': 'Gravity is the force that attracts two bodies toward each other. Newton\'s law: F = G(m₁m₂)/r². On Earth, acceleration due to gravity is approximately 9.8 m/s².',
      'keywords': ['gravity', 'force', 'newton', 'earth', 'attraction'],
      'category': 'physics'
    },
    'mitochondria': {
      'answer': 'Mitochondria are the powerhouse of the cell! They generate most of the cell\'s supply of adenosine triphosphate (ATP), used as a source of chemical energy.',
      'keywords': ['mitochondria', 'powerhouse', 'cell', 'energy', 'atp'],
      'category': 'biology'
    },
  };

  ChatBloc() : super(ChatInitial()) {
    on<SendMessageEvent>(_onSendMessage);
    on<ClearChatEvent>(_onClearChat);
    on<LoadWelcomeEvent>(_onLoadWelcome);
    
    // Initialize with welcome message
    add(const LoadWelcomeEvent());
  }

  void _onLoadWelcome(LoadWelcomeEvent event, Emitter<ChatState> emit) {
    emit(ChatLoaded(messages: List.from(_messages)));
  }

  Future<void> _onSendMessage(SendMessageEvent event, Emitter<ChatState> emit) async {
    if (event.message.trim().isEmpty) return;

    final stopwatch = Stopwatch()..start();

    try {
      // Add user message immediately
      _messages.add(ChatMessage(
        text: event.message,
        isUser: true,
        timestamp: DateTime.now(),
      ));

      emit(ChatLoading());

      // Simulate API call delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Get FAQ response
      final response = _getFAQResponse(event.message);
      stopwatch.stop();

      // Add bot response
      _messages.add(ChatMessage(
        text: response['answer'],
        isUser: false,
        timestamp: DateTime.now(),
        responseTime: stopwatch.elapsedMilliseconds,
        confidence: response['confidence'],
      ));

      emit(ChatLoaded(
        messages: List.from(_messages),
        responseTime: stopwatch.elapsedMilliseconds,
      ));

    } catch (e) {
      // Add error message
      _messages.add(ChatMessage(
        text: "Sorry, I encountered an error. Please try again.",
        isUser: false,
        timestamp: DateTime.now(),
      ));

      emit(ChatError(error: e.toString()));
      
      // Re-emit loaded state to show error message
      await Future.delayed(const Duration(milliseconds: 100));
      emit(ChatLoaded(messages: List.from(_messages)));
    }
  }

  void _onClearChat(ClearChatEvent event, Emitter<ChatState> emit) {
    _messages.clear();
    // Add welcome message back
    _messages.add(ChatMessage(
      text: "Hello! I'm your AI study buddy. Ask me anything!",
      isUser: false,
      timestamp: DateTime.now(),
    ));
    emit(ChatLoaded(messages: List.from(_messages)));
  }

  Map<String, dynamic> _getFAQResponse(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();
    Map<String, dynamic>? bestMatch;
    int highestScore = 0;

    for (var faq in _faqs.entries) {
      final keywords = List<String>.from(faq.value['keywords']);
      int score = _calculateMatchScore(lowerMessage, keywords);

      if (score > highestScore) {
        highestScore = score;
        bestMatch = {
          'answer': faq.value['answer'],
          'matchedQuestion': faq.key,
          'confidence': score >= 3 ? 'high' : score >= 2 ? 'medium' : 'low',
          'category': faq.value['category'],
        };
      }
    }

    if (bestMatch != null && highestScore >= 1) {
      return bestMatch;
    } else {
      return {
        'answer': "I'm still learning! I don't have an answer for that yet. Try asking about: ${_faqs.keys.join(', ')}",
        'matchedQuestion': null,
        'confidence': 'low',
        'category': 'general',
      };
    }
  }

  int _calculateMatchScore(String userMessage, List<String> keywords) {
    int score = 0;
    
    for (String keyword in keywords) {
      final cleanKeyword = keyword.trim().toLowerCase();
      if (cleanKeyword.isEmpty) continue;

      // Exact word match (higher score)
      if (RegExp(r'\b' + RegExp.escape(cleanKeyword) + r'\b').hasMatch(userMessage)) {
        score += 2;
      }
      // Partial match
      else if (userMessage.contains(cleanKeyword)) {
        score += 1;
      }
    }
    
    return score;
  }
}

// ---------- Progress ----------
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  _ProgressPageState createState() => _ProgressPageState();
}

class ProgressRecord {
  final String activity;
  final double score;
  final String grade;
  final String comments;

  ProgressRecord({
    required this.activity,
    required this.score,
    required this.grade,
    required this.comments,
  });
}

class _ProgressPageState extends State<ProgressPage> {
  final List<ProgressRecord> progressList = [];
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _activityController = TextEditingController();
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  void _addProgress() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        progressList.add(
          ProgressRecord(
            activity: _activityController.text,
            score: double.parse(_scoreController.text),
            grade: _gradeController.text,
            comments: _commentsController.text,
          ),
        );
      });
      _activityController.clear();
      _scoreController.clear();
      _gradeController.clear();
      _commentsController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Learning Progress')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: progressList.length,
                itemBuilder: (context, index) {
                  final record = progressList[index];
                  return Card(
                    child: ListTile(
                      title: Text('${record.activity} - ${record.grade}'),
                      subtitle: Text(
                          'Score: ${record.score}\nComments: ${record.comments}'),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _activityController,
                    decoration:
                        const InputDecoration(labelText: 'Activity Type'),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter an activity' : null,
                  ),
                  TextFormField(
                    controller: _scoreController,
                    decoration: const InputDecoration(labelText: 'Score'),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a score' : null,
                  ),
                  TextFormField(
                    controller: _gradeController,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a grade' : null,
                  ),
                  TextFormField(
                    controller: _commentsController,
                    decoration: const InputDecoration(labelText: 'Comments'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _addProgress,
                    child: const Text('Add Progress'),
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

// ---------- Achievements ----------
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        'Your Achievements',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
}

// ---------- Profile ----------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        '👤 User Profile Page',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
}

// ---------- Learning Material ----------
class LearningMaterial {
  String name, description, file;
  DateTime time;
  LearningMaterial({
    required this.name,
    required this.description,
    required this.file,
    required this.time,
  });
}

// ---------- App State ----------
class MaterialAppState extends ChangeNotifier {
  final List<LearningMaterial> lm = [];
  void addMaterial(LearningMaterial material) {
    lm.add(material);
    notifyListeners();
  }

  void removeMaterial(LearningMaterial material) {
    lm.remove(material);
    notifyListeners();
  }
}

// ---------- Materials Page ----------
class MaterialsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MaterialAppState>();
    var materials = appState.lm;
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Materials'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UploadPage()),
        ),
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
      body: materials.isEmpty
          ? const Center(
              child: Text(
                'No learning materials uploaded yet.\nClick "+" to add learning materials.',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView.builder(
                itemCount: materials.length,
                itemBuilder: (context, index) {
                  final material = materials[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: Icon(Icons.file_present,
                          color: theme.colorScheme.primary),
                      title: Text(material.name),
                      subtitle: Text(
                        '${material.description}\nUploaded At: ${material.time}',
                      ),
                      onTap: () => OpenFile.open(material.file),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Confirmation'),
                              content: const Text(
                                  'Are you sure you want to delete this learning material?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            appState.removeMaterial(material);
                             if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Learning Material deleted successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                          
                        }

                        },
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ---------- Upload Page ----------
class UploadPage extends StatefulWidget {
  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _formKey = GlobalKey<FormState>();
  String name = '';
  String description = '';
  String? filePath;

  void pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => filePath = result.files.single.path!);
    }
  }

  void submit(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    if (filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first.')),
      );
      return;
    }

    _formKey.currentState!.save();
    final newMaterial = LearningMaterial(
      name: name,
      description: description,
      file: filePath!,
      time: DateTime.now(),
    );

    context.read<MaterialAppState>().addMaterial(newMaterial);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Learning Material')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
                onSaved: (v) => name = v ?? '',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 3,
                onSaved: (v) => description = v ?? '',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter a description' : null,
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose File'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      filePath != null
                          ? filePath!.split('/').last
                          : 'No file selected',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                onPressed: () => submit(context),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Upload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}