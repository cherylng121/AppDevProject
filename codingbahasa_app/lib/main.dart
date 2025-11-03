import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';

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
        break;
      case 1:
        page = const CoursePage();
        break;
      case 2:
        page = MaterialsPage();
        break;
      case 3:
        page = const QuizPage();
        break;
      case 4:
        page = const AIChatbotPage();
        break;
      case 5:
        page = const ProgressPage();
        break;
      case 6:
        page = const AchievementsPage();
        break;
      case 7:
        page = const ProfilePage();
        break;
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
class AIChatbotPage extends StatelessWidget {
  const AIChatbotPage({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        '🤖 AI Chatbot Page',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Learning Material deleted successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
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