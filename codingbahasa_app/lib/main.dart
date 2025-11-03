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
          scaffoldBackgroundColor: Colors.white, // main content background
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
          // ---------- SLIDING MENU BAR ----------
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
  @override
  Widget build(BuildContext context) => const Text(
        'This is the Course Page',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
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
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        'Your Learning Progress',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
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

// ---------- Learning Material Model ----------
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
