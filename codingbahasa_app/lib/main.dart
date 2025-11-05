import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';


// ========== MAIN FUNCTION WITH FIREBASE ==========
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => FirebaseUserState()),
        ChangeNotifierProvider(create: (context) => MaterialAppState()),
      ],
      child: const CodingBahasa(),
    ),
  );
}

// ========== USER MODEL ==========
enum UserType { student, teacher }

class AppUser {
  final String id;
  final String username;
  final String email;
  final UserType userType;
  String? profilePicture;
  String? className;
  String? formLevel;
  int points;
  List<String> badges;
  double completionLevel;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.userType,
    this.profilePicture,
    this.className,
    this.formLevel,
    this.points = 0,
    this.badges = const [],
    this.completionLevel = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      'userType': userType.toString(),
      'profilePicture': profilePicture,
      'className': className,
      'formLevel': formLevel,
      'points': points,
      'badges': badges,
      'completionLevel': completionLevel,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      userType: map['userType'] == 'UserType.teacher' 
          ? UserType.teacher 
          : UserType.student,
      profilePicture: map['profilePicture'],
      className: map['className'],
      formLevel: map['formLevel'],
      points: map['points'] ?? 0,
      badges: List<String>.from(map['badges'] ?? []),
      completionLevel: (map['completionLevel'] ?? 0.0).toDouble(),
    );
  }

  AppUser copyWith({
    String? username,
    String? profilePicture,
    String? className,
    String? formLevel,
    int? points,
    List<String>? badges,
    double? completionLevel,
  }) {
    return AppUser(
      id: id,
      username: username ?? this.username,
      email: email,
      userType: userType,
      profilePicture: profilePicture ?? this.profilePicture,
      className: className ?? this.className,
      formLevel: formLevel ?? this.formLevel,
      points: points ?? this.points,
      badges: badges ?? this.badges,
      completionLevel: completionLevel ?? this.completionLevel,
    );
  }
}

// ========== FIREBASE USER STATE ==========
class FirebaseUserState extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  
  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  String? _lastUnlockedMessage;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get lastUnlockedMessage => _lastUnlockedMessage;

  FirebaseUserState() {
    _auth.authStateChanges().listen((firebaseUser) {
      if (firebaseUser != null) {
        _loadUserData(firebaseUser.uid);
      } else {
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        _currentUser = AppUser.fromMap(uid, doc.data()!);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to load user data: $e';
      notifyListeners();
    }
  }

  Future<bool> registerUser({
    required String username,
    required String email,
    required String password,
    required UserType userType,
    String? className,
    String? formLevel,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        _errorMessage = 'Username already exists';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUser = AppUser(
        id: userCredential.user!.uid,
        username: username,
        email: email,
        userType: userType,
        className: className,
        formLevel: formLevel,
      );

      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(newUser.toMap());

      _currentUser = newUser;
      _isLoading = false;
      notifyListeners();
      return true;

    } on firebase_auth.FirebaseAuthException catch (e) {
      _errorMessage = _getAuthErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _loadUserData(userCredential.user!.uid);
      _isLoading = false;
      notifyListeners();
      return true;

    } on firebase_auth.FirebaseAuthException catch (e) {
      _errorMessage = _getAuthErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> updateUserProfile({
    String? username,
    String? profilePicture,
    String? className,
    String? formLevel,
  }) async {
    if (_currentUser == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      if (username != null && username != _currentUser!.username) {
        final usernameQuery = await _firestore
            .collection('users')
            .where('username', isEqualTo: username)
            .get();

        if (usernameQuery.docs.isNotEmpty) {
          _errorMessage = 'Username already exists';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      final updates = <String, dynamic>{};
      if (username != null) updates['username'] = username;
      if (profilePicture != null) updates['profilePicture'] = profilePicture;
      if (className != null) updates['className'] = className;
      if (formLevel != null) updates['formLevel'] = formLevel;

      await _firestore.collection('users').doc(_currentUser!.id).update(updates);

      _currentUser = _currentUser!.copyWith(
        username: username,
        profilePicture: profilePicture,
        className: className,
        formLevel: formLevel,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Update failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (_currentUser == null) return false;

    try {
      final user = _auth.currentUser!;
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      return true;
    } catch (e) {
      _errorMessage = 'Password change failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteAccount(String password) async {
    if (_currentUser == null) return false;

    try {
      final user = _auth.currentUser!;
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      
      await user.reauthenticateWithCredential(credential);
      await _firestore.collection('users').doc(_currentUser!.id).delete();
      await user.delete();

      _currentUser = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Account deletion failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<List<AppUser>> searchUserByName(String query) async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .where((user) => user.username.toLowerCase().contains(query.toLowerCase()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<AppUser>> filterUsers({String? className, String? formLevel}) async {
    try {
      Query query = _firestore.collection('users');
      if (className != null) query = query.where('className', isEqualTo: className);
      if (formLevel != null) query = query.where('formLevel', isEqualTo: formLevel);

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addPoints(int points) async {
    if (_currentUser == null) return;
    final newPoints = _currentUser!.points + points;
    await _firestore.collection('users').doc(_currentUser!.id).update({'points': newPoints});
    _currentUser = _currentUser!.copyWith(points: newPoints);
    notifyListeners();
  }

  Future<void> addBadge(String badge) async {
    if (_currentUser == null) return;
    final newBadges = List<String>.from(_currentUser!.badges)..add(badge);
    await _firestore.collection('users').doc(_currentUser!.id).update({'badges': newBadges});
    _currentUser = _currentUser!.copyWith(badges: newBadges);
    notifyListeners();
  }

  Future<void> awardBadge({
    required String title,
    required String description,
  }) async {
    if (_currentUser == null) return;
    try {
      await _firestore.collection('achievements').add({
        'studentId': _currentUser!.id,
        'studentName': _currentUser!.username,
        'title': title,
        'type': 'Badge',
        'description': description,
        'dateEarned': FieldValue.serverTimestamp(),
      });

      final updatedBadges = List<String>.from(_currentUser!.badges);
      if (!updatedBadges.contains(title)) {
        updatedBadges.add(title);
        await _firestore
            .collection('users')
            .doc(_currentUser!.id)
            .update({'badges': updatedBadges});
        _currentUser = _currentUser!.copyWith(badges: updatedBadges);
      }

      _lastUnlockedMessage = 'Achievement unlocked: $title';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error awarding achievement: $e';
      notifyListeners();
    }
  }

  void consumeLastUnlockedMessage() {
    _lastUnlockedMessage = null;
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use': return 'Email already registered';
      case 'invalid-email': return 'Invalid email address';
      case 'weak-password': return 'Password is too weak';
      case 'user-not-found': return 'No user found with this email';
      case 'wrong-password': return 'Incorrect password';
      case 'invalid-credential': return 'Invalid email or password';
      default: return 'Authentication error';
    }
  }
}

// ========== ROOT APP ==========
class CodingBahasa extends StatelessWidget {
  const CodingBahasa({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
       home: Consumer<FirebaseUserState>(
        builder: (context, userState, _) {
          if (userState.isLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
           return userState.isLoggedIn 
            ? const HomePage()  
            : const LoginPage();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ========== LOGIN PAGE ==========
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final userState = success;
    /*final success = await userState.login(
      _emailController.text.trim(),
      _passwordController.text,
    );*/

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userState.errorMessage ?? 'Login failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[700]!, Colors.blue[300]!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school, size: 80, color: Colors.blue[700]),
                        const SizedBox(height: 16),
                        const Text('CodingBahasa', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        const Text('Connect, Code and Challenge', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter email';
                            if (!value.contains('@')) return 'Please enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (value) => value == null || value.isEmpty ? 'Please enter password' : null,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: userState.isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: userState.isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Login', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())),
                          child: const Text("Don't have an account? Register"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ========== REGISTER PAGE ==========
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _classNameController = TextEditingController();
  UserType _selectedUserType = UserType.student;
  String? _selectedFormLevel;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _classNameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final userState = context.read<FirebaseUserState>();
    final success = await userState.registerUser(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      userType: _selectedUserType,
      className: _classNameController.text.trim().isEmpty ? null : _classNameController.text.trim(),
      formLevel: _selectedFormLevel,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userState.errorMessage ?? 'Registration failed'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account'), backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Register New Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter username';
                  if (value.length < 3) return 'Username must be at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter email';
                  if (!value.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter password';
                  if (value.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value != _passwordController.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 16),
              const Text('User Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<UserType>(
                      title: const Text('Student'),
                      value: UserType.student,
                      groupValue: _selectedUserType,
                      onChanged: (value) => setState(() => _selectedUserType = value!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<UserType>(
                      title: const Text('Teacher'),
                      value: UserType.teacher,
                      groupValue: _selectedUserType,
                      onChanged: (value) => setState(() => _selectedUserType = value!),
                    ),
                  ),
                ],
              ),
              if (_selectedUserType == UserType.student) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFormLevel,
                  decoration: InputDecoration(
                    labelText: 'Form Level',
                    prefixIcon: const Icon(Icons.school),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: ['Form 4', 'Form 5'].map((level) => DropdownMenuItem(value: level, child: Text(level))).toList(),
                  onChanged: (value) => setState(() => _selectedFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class Name (Optional)',
                    prefixIcon: const Icon(Icons.class_),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: userState.isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: userState.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Register', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ========== HOME PAGE ==========
class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
        page = QuizPage();
      case 4:
        page = const AIChatbotPage();
      case 5:
        page = const ProgressPage();
      case 6:
        page = const AchievementsPage();
      case 7:
        page = const ProfilePage();
      case 8:
        page = const UserSearchPage();
      default:
        page = const Center(child: Text('Page not found'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CodingBahasa', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Connect, Code and Challenge',
              style: TextStyle(fontSize: 15, color: Colors.white70),
            ),
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
                  _buildMenuButton('Users', 8),
                ],
              ),
            ),
          ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

// ========== USER SEARCH PAGE ==========
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _searchController = TextEditingController();
  List<AppUser> _displayedUsers = [];
  String? _filterClassName;
  String? _filterFormLevel;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    setState(() => _isLoading = true);
    final userState = context.read<FirebaseUserState>();
    final users = await userState.searchUserByName('');
    setState(() {
      _displayedUsers = users;
      _isLoading = false;
    });
  }

  Future<void> _searchUsers(String query) async {
    setState(() => _isLoading = true);
    final userState = context.read<FirebaseUserState>();
    var results = await userState.searchUserByName(query);

    if (_filterClassName != null || _filterFormLevel != null) {
      results = results.where((user) {
        if (_filterClassName != null && user.className != _filterClassName) return false;
        if (_filterFormLevel != null && user.formLevel != _filterFormLevel) return false;
        return true;
      }).toList();
    }

    setState(() {
      _displayedUsers = results;
      _isLoading = false;
    });
  }

  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);
    final userState = context.read<FirebaseUserState>();
    
    if (_filterClassName == null && _filterFormLevel == null) {
      _displayedUsers = await userState.searchUserByName(_searchController.text);
    } else {
      var results = await userState.filterUsers(className: _filterClassName, formLevel: _filterFormLevel);
      
      if (_searchController.text.isNotEmpty) {
        results = results.where((user) => user.username.toLowerCase().contains(_searchController.text.toLowerCase())).toList();
      }
      
      _displayedUsers = results;
    }
    
    setState(() => _isLoading = false);
  }

  void _clearFilters() {
    setState(() {
      _filterClassName = null;
      _filterFormLevel = null;
      _searchController.clear();
    });
    _loadAllUsers();
  }

  void _showFilterDialog() {
    String? tempClassName = _filterClassName;
    String? tempFormLevel = _filterFormLevel;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filter Users'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tempFormLevel,
                  decoration: const InputDecoration(labelText: 'Form Level', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...['Form 4', 'Form 5'].map((level) => DropdownMenuItem(value: level, child: Text(level))),
                  ],
                  onChanged: (value) => setDialogState(() => tempFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(labelText: 'Class Name', border: OutlineInputBorder()),
                  onChanged: (value) => setDialogState(() => tempClassName = value.isEmpty ? null : value),
                  controller: TextEditingController(text: tempClassName),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _filterClassName = tempClassName;
                    _filterFormLevel = tempFormLevel;
                  });
                  _applyFilters();
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<FirebaseUserState>().currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('🔍 Search Users'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterDialog, tooltip: 'Filter'),
          if (_filterClassName != null || _filterFormLevel != null)
            IconButton(icon: const Icon(Icons.clear), onPressed: _clearFilters, tooltip: 'Clear Filters'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear();
                        _searchUsers('');
                      })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: _searchUsers,
            ),
          ),
          if (_filterClassName != null || _filterFormLevel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Filters: '),
                  if (_filterFormLevel != null) Chip(label: Text(_filterFormLevel!), onDeleted: () => setState(() {
                    _filterFormLevel = null;
                    _applyFilters();
                  })),
                  if (_filterClassName != null) ...[
                    const SizedBox(width: 8),
                    Chip(label: Text(_filterClassName!), onDeleted: () => setState(() {
                      _filterClassName = null;
                      _applyFilters();
                    })),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_displayedUsers.length} user(s) found', style: TextStyle(color: Colors.grey[600])),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _displayedUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No users found', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _displayedUsers.length,
                        itemBuilder: (context, index) {
                          final user = _displayedUsers[index];
                          final isCurrentUser = user.id == currentUser?.id;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: user.userType == UserType.student ? Colors.blue[100] : Colors.green[100],
                                child: Icon(
                                  user.userType == UserType.student ? Icons.school : Icons.person,
                                  color: user.userType == UserType.student ? Colors.blue[700] : Colors.green[700],
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(user.username),
                                  if (isCurrentUser) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(10)),
                                      child: Text('You', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.userType == UserType.student ? 'Student' : 'Teacher',
                                      style: TextStyle(color: user.userType == UserType.student ? Colors.blue[700] : Colors.green[700])),
                                  if (user.formLevel != null) Text('Form: ${user.formLevel}'),
                                  if (user.className != null) Text('Class: ${user.className}'),
                                ],
                              ),
                              trailing: user.userType == UserType.student
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.star, size: 16, color: Colors.amber),
                                        Text('${user.points}', style: const TextStyle(fontSize: 12)),
                                      ],
                                    )
                                  : null,
                              onTap: () => _showUserDetailsDialog(user),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showUserDetailsDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: user.userType == UserType.student ? Colors.blue[100] : Colors.green[100],
              child: Icon(user.userType == UserType.student ? Icons.school : Icons.person,
                  color: user.userType == UserType.student ? Colors.blue[700] : Colors.green[700]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(user.username, style: const TextStyle(fontSize: 20))),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow('User Type', user.userType == UserType.student ? 'Student' : 'Teacher'),
            _buildDetailRow('Email', user.email),
            if (user.formLevel != null) _buildDetailRow('Form Level', user.formLevel!),
            if (user.className != null) _buildDetailRow('Class', user.className!),
            if (user.userType == UserType.student) ...[
              const Divider(),
              _buildDetailRow('Points', user.points.toString()),
              _buildDetailRow('Badges', user.badges.length.toString()),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
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
      "note": """MASALAH:
Keraguan, situasi yang tidak diingini, cabaran & peluang yang dihadapi dalam kehidupan seseorang 
\n🤔(4) MENGAPAKAH PERLUNYA STRATEGI DALAM PENYELESAIAN MASALAH?
• Meningkatkan kemahiran berfikir
• Membantu pengembangan sesuatu konsep
• Mewujudkan komunikasi dua hala
• Menggalakkan pembelajaran kendir
\nPENYELESAIAN MASALAH:
Proses mengkaji butiran sesuatu masalah untuk mendapatkan satu penyelesaian
\n🧠(4) TEKNIK PEMIKIRAN KOMPUTASIONAL
• Leraian – Memecahkan masalah kepada bahagian yang lebih kecil & terkawal
• Pengecaman corak – Mencari persamaan antara masalah & dalam masalah
• Peniskalaan – Menjana penyelesaian yang tepat kepada masalah yang dihadapi
• Algoritma – Membangunkan penyelesaian langkah demi langkah terhadap masalah yang dihadapi
\n✅(3) CIRI PENYELESAIAN MASALAH BERKESAN 
• Kos 
• Masa
• Sumber
\n📋(8) PROSES PENYELESAIAN MASALAH
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
      "note": """ALGORITMA
      Satu set arahan untuk menyelesaikan masalah 
\n✅(3) CIRI ALGORITMA
• Butiran jelas
• Boleh dilaksanakan
• Mempunyai batasan
\n----------------------
INPUT➡️PROSES➡️OUTPUT
----------------------
\nPSEUDOKOD
Senarai struktur kawalan komputer yang ditulis dalam bahasa pertuturan manusia & mempunyai nombor turutan
1. Tulis kenyataan MULA
2. Baca INPUT
3. Proses data menggunakan ungkapan logik / matematik
4. Papar OUTPUT
5. Tulis kenyataan TAMAT
\nCARTA ALIR
Alternatif kepada pseudokod menggunakan simbol grafik untuk mewakili arahanarahan penyelesaian
1. Lukis nod terminal Mula
2. Lukis garis penghubung
3. Lukis nod input
4. Lukis garis penghubung
5. Lukis nod proses
6. Lukis garis penghubung
7. Sekiranya perlu, lukis nod proses / nod input lain-lain 
8. Sekiranya tiada, lukis nod terminal Tamat
\n🧑‍💻(3) STRUKTUR KAWALAN DALAM PENGATURCARAAN
• Struktur Kawalan Urutan - Melaksanakan arahan komputer satu per satu
• Struktur Kawalan Pilihan - Membuat keputusan berasaskan syarat yang ditentukan
• Struktur Kawalan Pengulangan - Mengulang arahan komputer dalam blok
\n------------------------------------------------------------
Tulis Algortima➡️Uji ALgortima➡️Pembetulan➡️Pengaturcaraan
------------------------------------------------------------
\n✅(4) CIRI ALGORITMA YANG TELAH DIUJI 
• Mudah difahami
• Lengkap
• Efisien
• Memenuhi kriteria reka bentuk
\n❌(3) RALAT
• Ralat Sintaks - Tidak wujud dalam algoritma
• Ralat Logik - Tidak menjalankan fungsi-fungsi yang sepatutnya
• Ralat Masa Larian -  Timbul apabila atur cara dijalankan
\n📋(4) LANGKAH PENGUJIAN ALGORITMA
1. Kenal pasti "Output Dijangka"
2. Kenal pasti "Output Diperoleh"
3. Bandingkan "Output Diperoleh" dengan "Output Dijangka"
4. Analisis & baiki algoritma
"""
    },
    {
      "title": "1.3 Pemboleh Ubah, Pemalar dan Jenis Data",
      "note": """PEMBOLEH UBAH
Ruang simpanan sementara untuk nombor, teks & objek
\nPEMALAR
Tetap & tidak akan berubah
\n(6) JENIS DATA
• Integer [26]
• float [17.9]
• double [11.5]
• char [z]
• String [hello world]
• Boolean [true, false]
\nPEMBOLEH UBAH SEJAGAT (GLOBAL)
Hanya berfungsi dalam atur cara sahaja
\nPEMBOLEH UBAH SETEMPAT (LOCAL)
Hanya berfungsi dalam subatur cara yang diisytiharkan
"""
    },
    {
      "title": "1.4 Struktur Kawalan",
      "note": """✅(3) STRUKTUR KAWALAN 
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
\n✅(3) OPERATOR LOGICAL
• AND - ✅ jika semua betul
• OR - ✅ jika salah satu betul
• NOT - Menukarkan status kepada lawannya
"""
    },
    {
      "title": "1.5 Amalan Terbaik Pengaturcaraan",
      "note": """AMALAN TERBAIK PENGATURCARAAN
Apabila pengatur cara dapat mempraktikkan amalan-amalan yang biasa diikuti untuk menghasilkan
atur cara yang baik
\n🧑‍💻(4) FAKTOR MEMPENGARUHI KEBOLEHBACAAN KOD
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
      "note": """TATASUSUNAN
Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks
\n--------------------------------------------------
jenisData [] namaTatasusunan;
namaTatasusunan = new jenisData [saizTatasusunan];
--------------------------------------------------
\n👍(5) KELEBIHAN MENGGUNAKAN STRUKTUR MODUL
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
Menjelaskan proses merancang, mereka bentuk, menguji & mengimplementasi sesuatu aplikasi / perisian
\n1. Analisis masalah
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

// ---------- Quiz Models ----------
enum QuestionType { mcq, shortAnswer }

class Question {
  String id;
  String questionText;
  QuestionType type;
  List<String>? options; // For MCQ
  String? correctAnswer; // For MCQ, it's the option index; for short answer, it's the answer text
  String? correctAnswerText; // For MCQ, the actual answer text
  
  Question({
    required this.id,
    required this.questionText,
    required this.type,
    this.options,
    this.correctAnswer,
    this.correctAnswerText,
  });
}

class Quiz {
  String id;
  String title;
  String topic;
  List<Question> questions;
  bool isPublished;
  DateTime createdAt;
  DateTime? publishedAt;
  
  Quiz({
    required this.id,
    required this.title,
    required this.topic,
    required this.questions,
    this.isPublished = false,
    required this.createdAt,
    this.publishedAt,
  });
}

// ---------- App State ----------
// ---------- Quiz Page ----------
class QuizPage extends StatelessWidget {
  const QuizPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Page'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'This is the quiz page!',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

class QuizAppState extends ChangeNotifier {
  final List<Quiz> _quizzes = [];
  
  List<Quiz> get allQuizzes => _quizzes;
  List<Quiz> get publishedQuizzes => _quizzes.where((q) => q.isPublished).toList();
  List<Quiz> get draftQuizzes => _quizzes.where((q) => !q.isPublished).toList();
  
  void addQuiz(Quiz quiz) {
    _quizzes.add(quiz);
    notifyListeners();
  }
  
  void removeQuiz(Quiz quiz) {
    _quizzes.remove(quiz);
    notifyListeners();
  }
  
  void publishQuiz(Quiz quiz) {
    quiz.isPublished = true;
    quiz.publishedAt = DateTime.now();
    notifyListeners();
  }
  
  void unpublishQuiz(Quiz quiz) {
    quiz.isPublished = false;
    quiz.publishedAt = null;
    notifyListeners();
  }
  
  void updateQuiz(Quiz oldQuiz, Quiz newQuiz) {
    final index = _quizzes.indexWhere((q) => q.id == oldQuiz.id);
    if (index != -1) {
      _quizzes[index] = newQuiz;
      notifyListeners();
    }
  }

// System Quiz Generator based on learning notes
  void generateSystemQuizzes() {
    // Quiz 1: Strategi Penyelesaian Masalah
    _quizzes.add(Quiz(
      id: 'system_quiz_1',
      title: 'Quiz: Strategi Penyelesaian Masalah',
      topic: '1.1 Strategi Penyelesaian Masalah',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q1_1',
          questionText: 'Apakah maksud masalah?',
          type: QuestionType.mcq,
          options: [
            'Keraguan, situasi yang tidak diingini, cabaran & peluang yang dihadapi dalam kehidupan seseorang',
            'Hanya cabaran sahaja',
            'Situasi yang diingini',
            'Tiada jawapan yang betul',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Keraguan, situasi yang tidak diingini, cabaran & peluang yang dihadapi dalam kehidupan seseorang',
        ),
        Question(
          id: 'q1_2',
          questionText: 'Berapakah bilangan teknik pemikiran komputasional?',
          type: QuestionType.shortAnswer,
          correctAnswer: '4',
        ),
        Question(
          id: 'q1_3',
          questionText: 'Antara berikut, yang manakah BUKAN teknik pemikiran komputasional?',
          type: QuestionType.mcq,
          options: [
            'Leraian',
            'Pengecaman corak',
            'Peniskalaan',
            'Pengulangan',
          ],
          correctAnswer: '3',
          correctAnswerText: 'Pengulangan',
        ),
        Question(
          id: 'q1_4',
          questionText: 'Apakah maksud Leraian dalam pemikiran komputasional?',
          type: QuestionType.mcq,
          options: [
            'Memecahkan masalah kepada bahagian yang lebih kecil & terkawal',
            'Mencari persamaan antara masalah',
            'Menjana penyelesaian yang tepat',
            'Membangunkan penyelesaian langkah demi langkah',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Memecahkan masalah kepada bahagian yang lebih kecil & terkawal',
        ),
        Question(
          id: 'q1_5',
          questionText: 'Nyatakan 3 ciri penyelesaian masalah berkesan.',
          type: QuestionType.shortAnswer,
          correctAnswer: 'Kos, Masa, Sumber',
        ),
      ],
    ));
      
 // Quiz 2: Algoritma
    _quizzes.add(Quiz(
      id: 'system_quiz_2',
      title: 'Quiz: Algoritma',
      topic: '1.2 Algoritma',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q2_1',
          questionText: 'Apakah definisi algoritma?',
          type: QuestionType.mcq,
          options: [
            'Satu set arahan untuk menyelesaikan masalah',
            'Satu bahasa pengaturcaraan',
            'Satu jenis pemboleh ubah',
            'Satu struktur kawalan',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Satu set arahan untuk menyelesaikan masalah',
        ),
        Question(
          id: 'q2_2',
          questionText: 'Berapakah bilangan ciri algoritma?',
          type: QuestionType.shortAnswer,
          correctAnswer: '3',
        ),
        Question(
          id: 'q2_3',
          questionText: 'Apakah yang dimaksudkan dengan PSEUDOKOD?',
          type: QuestionType.mcq,
          options: [
            'Senarai struktur kawalan komputer yang ditulis dalam bahasa pertuturan manusia & mempunyai nombor turutan',
            'Simbol grafik untuk mewakili arahan-arahan penyelesaian',
            'Bahasa pengaturcaraan tingkat tinggi',
            'Struktur data linear',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Senarai struktur kawalan komputer yang ditulis dalam bahasa pertuturan manusia & mempunyai nombor turutan',
        ),
        Question(
          id: 'q2_4',
          questionText: 'Nyatakan 3 jenis ralat dalam pengaturcaraan.',
          type: QuestionType.shortAnswer,
          correctAnswer: 'Ralat Sintaks, Ralat Logik, Ralat Masa Larian',
        ),
        Question(
          id: 'q2_5',
          questionText: 'Apakah struktur kawalan dalam pengaturcaraan?',
          type: QuestionType.mcq,
          options: [
            'Struktur Kawalan Urutan, Struktur Kawalan Pilihan, Struktur Kawalan Pengulangan',
            'If, Else, While',
            'Integer, Float, String',
            'Input, Proses, Output',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Struktur Kawalan Urutan, Struktur Kawalan Pilihan, Struktur Kawalan Pengulangan',
        ),
      ],
    ));
    
    // Quiz 3: Pemboleh Ubah, Pemalar dan Jenis Data
    _quizzes.add(Quiz(
      id: 'system_quiz_3',
      title: 'Quiz: Pemboleh Ubah, Pemalar dan Jenis Data',
      topic: '1.3 Pemboleh Ubah, Pemalar dan Jenis Data',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q3_1',
          questionText: 'Apakah definisi PEMBOLEH UBAH?',
          type: QuestionType.mcq,
          options: [
            'Ruang simpanan sementara untuk nombor, teks & objek',
            'Nilai yang tetap dan tidak akan berubah',
            'Struktur kawalan',
            'Jenis data',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Ruang simpanan sementara untuk nombor, teks & objek',
        ),
        Question(
          id: 'q3_2',
          questionText: 'Berapakah bilangan jenis data asas?',
          type: QuestionType.shortAnswer,
          correctAnswer: '6',
        ),
        Question(
          id: 'q3_3',
          questionText: 'Antara berikut, yang manakah BUKAN jenis data?',
          type: QuestionType.mcq,
          options: [
            'Integer',
            'Double',
            'Array',
            'Boolean',
          ],
          correctAnswer: '2',
          correctAnswerText: 'Array',
        ),
        Question(
          id: 'q3_4',
          questionText: 'Apakah perbezaan antara PEMBOLEH UBAH SEJAGAT dan PEMBOLEH UBAH SETEMPAT?',
          type: QuestionType.mcq,
          options: [
            'Pemboleh ubah sejagat berfungsi dalam atur cara sahaja, manakala setempat hanya dalam subatur cara yang diisytiharkan',
            'Tiada perbezaan',
            'Pemboleh ubah setempat lebih besar',
            'Pemboleh ubah sejagat lebih kecil',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Pemboleh ubah sejagat berfungsi dalam atur cara sahaja, manakala setempat hanya dalam subatur cara yang diisytiharkan',
        ),
      ],
    ));

 // Quiz 4: Struktur Kawalan
    _quizzes.add(Quiz(
      id: 'system_quiz_4',
      title: 'Quiz: Struktur Kawalan',
      topic: '1.4 Struktur Kawalan',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q4_1',
          questionText: 'Berapakah bilangan struktur kawalan?',
          type: QuestionType.shortAnswer,
          correctAnswer: '3',
        ),
        Question(
          id: 'q4_2',
          questionText: 'Antara berikut, yang manakah operator hubungan?',
          type: QuestionType.mcq,
          options: [
            'Sama dengan (==)',
            'AND',
            'OR',
            'NOT',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Sama dengan (==)',
        ),
        Question(
          id: 'q4_3',
          questionText: 'Nyatakan 3 struktur kawalan pengulangan.',
          type: QuestionType.shortAnswer,
          correctAnswer: 'For, While, Do-while',
        ),
        Question(
          id: 'q4_4',
          questionText: 'Apakah operator logik?',
          type: QuestionType.mcq,
          options: [
            'AND, OR, NOT',
            '==, !=, >, <',
            '+, -, *, /',
            'If, Else, Switch',
          ],
          correctAnswer: '0',
          correctAnswerText: 'AND, OR, NOT',
        ),
      ],
    ));
    
    // Quiz 5: Amalan Terbaik Pengaturcaraan
    _quizzes.add(Quiz(
      id: 'system_quiz_5',
      title: 'Quiz: Amalan Terbaik Pengaturcaraan',
      topic: '1.5 Amalan Terbaik Pengaturcaraan',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q5_1',
          questionText: 'Berapakah bilangan faktor mempengaruhi kebolehbacaan kod?',
          type: QuestionType.shortAnswer,
          correctAnswer: '4',
        ),
        Question(
          id: 'q5_2',
          questionText: 'Antara berikut, yang manakah faktor mempengaruhi kebolehbacaan kod?',
          type: QuestionType.mcq,
          options: [
            'Inden yang konsisten',
            'Warna skrin',
            'Saiz fon',
            'Jenis komputer',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Inden yang konsisten',
        ),
        Question(
          id: 'q5_3',
          questionText: 'Apakah yang dimaksudkan dengan RALAT SINTAKS?',
          type: QuestionType.mcq,
          options: [
            'Kesalahan tatabahasa, penggunaan objek/aksara yang tidak dikenali',
            'Atur cara tidak berfungsi seperti yang diingini',
            'Pengiraan data bukan berangka',
            'Tiada jawapan yang betul',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Kesalahan tatabahasa, penggunaan objek/aksara yang tidak dikenali',
        ),
      ],
    ));

 // Quiz 6: Struktur Data dan Modular
    _quizzes.add(Quiz(
      id: 'system_quiz_6',
      title: 'Quiz: Struktur Data dan Modular',
      topic: '1.6 Struktur Data dan Modular',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q6_1',
          questionText: 'Apakah definisi TATASUSUNAN?',
          type: QuestionType.mcq,
          options: [
            'Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks',
            'Satu jenis pemboleh ubah',
            'Satu struktur kawalan',
            'Satu jenis data',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks',
        ),
        Question(
          id: 'q6_2',
          questionText: 'Berapakah bilangan kelebihan menggunakan struktur modul?',
          type: QuestionType.shortAnswer,
          correctAnswer: '5',
        ),
        Question(
          id: 'q6_3',
          questionText: 'Antara berikut, yang manakah kelebihan menggunakan struktur modul?',
          type: QuestionType.mcq,
          options: [
            'Lebih mudah untuk digunakan semula',
            'Lebih sukar untuk diuji',
            'Projek menjadi lebih kompleks',
            'Tidak boleh dibahagikan kepada ahli kumpulan',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Lebih mudah untuk digunakan semula',
        ),
      ],
    ));
    
    // Quiz 7: Pembangunan Aplikasi
    _quizzes.add(Quiz(
      id: 'system_quiz_7',
      title: 'Quiz: Pembangunan Aplikasi',
      topic: '1.7 Pembangunan Aplikasi',
      createdAt: DateTime.now(),
      isPublished: true,
      publishedAt: DateTime.now(),
      questions: [
        Question(
          id: 'q7_1',
          questionText: 'Apakah singkatan SDLC?',
          type: QuestionType.mcq,
          options: [
            'Kitaran Hayat Pembangunan Sistem',
            'Sistem Data Lokal',
            'Struktur Data Linear',
            'Sistem Dokumentasi Lengkap',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Kitaran Hayat Pembangunan Sistem',
        ),
        Question(
          id: 'q7_2',
          questionText: 'Berapakah bilangan fasa dalam SDLC?',
          type: QuestionType.shortAnswer,
          correctAnswer: '5',
        ),
        Question(
          id: 'q7_3',
          questionText: 'Antara berikut, yang manakah fasa dalam SDLC?',
          type: QuestionType.mcq,
          options: [
            'Analisis masalah',
            'Pengujian sahaja',
            'Dokumentasi sahaja',
            'Pelaksanaan sahaja',
          ],
          correctAnswer: '0',
          correctAnswerText: 'Analisis masalah',
        ),
      ],
    ));
    
    notifyListeners();
  }
}


      
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
class AddAchievementPage extends StatefulWidget {
  const AddAchievementPage({super.key});

  @override
  State<AddAchievementPage> createState() => _AddAchievementPageState();
}

class _AddAchievementPageState extends State<AddAchievementPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _message; // FIX: Added missing variable

  @override
  void dispose() {
    _titleCtrl.dispose();
    _typeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAddAchievement() async {
    if (!_formKey.currentState!.validate()) return;

    final userState = context.read<FirebaseUserState>();
    final currentUser = userState.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      await FirebaseFirestore.instance.collection('achievements').add({
        'studentId': currentUser.id,
        'studentName': currentUser.username,
        'title': _titleCtrl.text.trim(),
        'type': _typeCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'dateEarned': FieldValue.serverTimestamp(),
      });

      setState(() {
        _message = '✅ Achievement added successfully!';
      });

      _titleCtrl.clear();
      _typeCtrl.clear();
      _descCtrl.clear();
    } catch (e) {
      setState(() {
        _message = 'Error adding achievement: $e';
      });
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Achievement'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Type (Badge/Certificate)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter type' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter description' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _handleAddAchievement,
                    icon: const Icon(Icons.add_circle_outline),
                    label: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add Achievement'),
                  ),
                ),
                const SizedBox(height: 20),
                if (_message != null)
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _message!.startsWith('✅')
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== ACHIEVEMENTS PAGE - PLACEHOLDER ==========
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();
    final user = userState.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('🏆 Achievements'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: user == null
            ? null
            : () async {
                await context.read<FirebaseUserState>().awardBadge(
                      title: 'Quiz Master',
                      description: 'Scored 80% or above in a quiz',
                    );
                if (context.mounted) {
                  final msg = context.read<FirebaseUserState>().lastUnlockedMessage;
                  if (msg != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: Colors.green),
                    );
                    context.read<FirebaseUserState>().consumeLastUnlockedMessage();
                  }
                }
              },
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Simulate Milestone'),
      ),
      body: user == null
          ? const Center(child: Text('Not logged in'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (userState.lastUnlockedMessage != null)
                  Builder(
                    builder: (ctx) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final msg = userState.lastUnlockedMessage;
                        if (msg != null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(msg), backgroundColor: Colors.green),
                          );
                          context.read<FirebaseUserState>().consumeLastUnlockedMessage();
                        }
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events, size: 28, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text('Your Achievements',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AddAchievementPage()),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Achievement'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('achievements')
                        .where('studentId', isEqualTo: user.id)
                        .orderBy('dateEarned', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error loading achievements: ${snapshot.error}'),
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No achievements yet. Complete milestones to earn badges!',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final title = data['title'] as String? ?? 'Achievement';
                          final type = data['type'] as String? ?? 'Badge';
                          final description = data['description'] as String? ?? '';
                          final ts = data['dateEarned'];
                          DateTime? when;
                          if (ts is Timestamp) when = ts.toDate();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: type == 'Badge' ? Colors.amber[100] : Colors.blue[100],
                                child: Icon(
                                  type == 'Badge' ? Icons.emoji_events : Icons.workspace_premium,
                                  color: type == 'Badge' ? Colors.amber[800] : Colors.blue[800],
                                ),
                              ),
                              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(description),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Chip(label: Text(type)),
                                      const SizedBox(width: 8),
                                      if (when != null)
                                        Text(
                                          'Earned: ${when.toLocal()}',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------- Profile ----------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();
    final user = userState.currentUser;

    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('👤 User Profile'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(Icons.lock, size: 20),
                    SizedBox(width: 8),
                    Text('Change Password'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Account', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'edit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EditProfilePage()),
                );
              } else if (value == 'password') {
                _showChangePasswordDialog(context);
              } else if (value == 'delete') {
                _showDeleteDialog(context);
              } else if (value == 'logout') {
                _handleLogout(context);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.blue[300]!],
                ),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 50, color: Colors.blue),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user.userType == UserType.student ? 'Student' : 'Teacher',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoCard(
                    icon: Icons.email,
                    title: 'Email',
                    value: user.email,
                  ),
                  if (user.userType == UserType.student) ...[
                    _buildInfoCard(
                      icon: Icons.school,
                      title: 'Form Level',
                      value: user.formLevel ?? 'Not set',
                    ),
                    _buildInfoCard(
                      icon: Icons.class_,
                      title: 'Class',
                      value: user.className ?? 'Not set',
                    ),
                  ],
                  _buildInfoCard(
                    icon: Icons.stars,
                    title: 'Total Points',
                    value: user.points.toString(),
                  ),
                  _buildInfoCard(
                    icon: Icons.emoji_events,
                    title: 'Badges Earned',
                    value: user.badges.length.toString(),
                  ),
                  _buildInfoCard(
                    icon: Icons.trending_up,
                    title: 'Completion Level',
                    value: '${(user.completionLevel * 100).toStringAsFixed(1)}%',
                  ),
                  if (user.badges.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Badges',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: user.badges
                                  .map(
                                    (badge) => Chip(
                                      label: Text(badge),
                                      avatar: const Icon(Icons.emoji_events, size: 16),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue[700]),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty
                        ? 'Please enter current password'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter new password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value != newPasswordController.text
                        ? 'Passwords do not match'
                        : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final userState = context.read<FirebaseUserState>();
                final success = await userState.changePassword(
                  currentPasswordController.text,
                  newPasswordController.text,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Password changed successfully'
                            : userState.errorMessage ?? 'Failed to change password',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action cannot be undone. All your data will be permanently deleted.',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter your password to confirm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final userState = context.read<FirebaseUserState>();
              final success = await userState.deleteAccount(passwordController.text);
              if (context.mounted) {
                if (success) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        userState.errorMessage ?? 'Failed to delete account',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<FirebaseUserState>().logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ========== EDIT PROFILE PAGE ==========
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _classNameController;
  String? _selectedFormLevel;

  @override
  void initState() {
    super.initState();
    final user = context.read<FirebaseUserState>().currentUser!;
    _usernameController = TextEditingController(text: user.username);
    _classNameController = TextEditingController(text: user.className ?? '');
    _selectedFormLevel = user.formLevel;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _classNameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final userState = context.read<FirebaseUserState>();
    final success = await userState.updateUserProfile(
      username: _usernameController.text.trim(),
      className: _classNameController.text.trim().isEmpty ? null : _classNameController.text.trim(),
      formLevel: _selectedFormLevel,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userState.errorMessage ?? 'Update failed'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FirebaseUserState>().currentUser!;
    final userState = context.watch<FirebaseUserState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile'), backgroundColor: Colors.lightBlue, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Update Your Information', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter username';
                  if (value.length < 3) return 'Username must be at least 3 characters';
                  return null;
                },
              ),
              if (user.userType == UserType.student) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFormLevel,
                  decoration: InputDecoration(
                    labelText: 'Form Level',
                    prefixIcon: const Icon(Icons.school),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: ['Form 4', 'Form 5'].map((level) => DropdownMenuItem(value: level, child: Text(level))).toList(),
                  onChanged: (value) => setState(() => _selectedFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class Name',
                    prefixIcon: const Icon(Icons.class_),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: userState.isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: userState.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Changes', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

