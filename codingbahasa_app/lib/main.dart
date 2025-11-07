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
import 'forum_page.dart';



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
  String? get lastUnlockedMessage => _lastUnlockedMessage;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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
    
    print('Start registering user');
    
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

      print('Firebase Auth user created: ${userCredential.user!.uid}');

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
      print('Error during registration: $_errorMessage');
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

  Future<void> awardBadge({required String name, required String description}) async {
    if (_currentUser == null) return;

    if (_currentUser!.badges.contains(name)) {
        return; 
    }

    final newBadges = List<String>.from(_currentUser!.badges)..add(name);
    
    await _firestore.collection('users').doc(_currentUser!.id).update({'badges': newBadges});
    
    _currentUser = _currentUser!.copyWith(badges: newBadges);
    _lastUnlockedMessage = 'Congratulations! You unlocked the $name badge.'; 
    
    notifyListeners();
  }

  void consumeLastUnlockedMessage() {
    _lastUnlockedMessage = null;
    notifyListeners();
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

    final userState = context.read<FirebaseUserState>();
    final success = await userState.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

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
                        // -------------------
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: userState.isLoading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(builder: (context) => const HomePage()),
                                      );
                                    }
                                  },
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

                          // ------------------------
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

    //Probably Error Here
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
        page = const QuizPage();
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
      case 9:
        page = const ForumPage();

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
                  _buildMenuButton('Forum', 9),

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

// ---------- Quiz ----------
enum QuestionType { mcq, shortAnswer }
enum QuizStatus { draft, published }

class Question {
  final String questionText;
  final QuestionType type;
  final List<String> options; // For MCQ
  final String answer; // For short answer and correct answer for MCQ

  Question({
    required this.questionText,
    required this.type,
    this.options = const [],
    required this.answer,
  });
}

class Quiz {
  final String title;
  final String topic;
  final List<Question> questions;
  QuizStatus status;

  Quiz({
    required this.title,
    required this.topic,
    required this.questions,
    this.status = QuizStatus.draft,
  });
}
List<Quiz> dummyQuizzes = [];
// ----------System Quiz ----------
final Map<String, List<Question>> systemQuizData = {
  "1.1 Strategi Penyelesaian Masalah": [
    Question(
      questionText: 'State the four (4) reasons why strategy is needed in problem-solving.',
      type: QuestionType.shortAnswer,
      answer: 'Meningkatkan kemahiran berfikir, Membantu pengembangan sesuatu konsep, Mewujudkan komunikasi dua hala, Menggalakkan pembelajaran kendiri',
    ),
    Question(
      questionText: 'Which of the following is NOT one of the four (4) techniques of Computational Thinking?',
      type: QuestionType.mcq,
      options: const ['Leraian', 'Pengecaman corak', 'Peniskalaan', 'Perhubungan'],
      answer: 'Perhubungan',
    ),
    Question(
      questionText: 'List the three (3) characteristics of effective problem-solving.',
      type: QuestionType.shortAnswer,
      answer: 'Kos, Masa, Sumber',
    ),
    Question(
      questionText: 'Which step immediately follows "Menjana idea" in the eight (8) Problem-Solving Processes?',
      type: QuestionType.mcq,
      options: const ['Menentukan masalah', 'Menjana penyelesaian', 'Melaksanakan penyelesaian', 'Membuat penilaian'],
      answer: 'Menjana penyelesaian',
    ),
  ],
  "1.2 Algoritma": [
    Question(
      questionText: 'State the three (3) main characteristics of an effective Algorithm.',
      type: QuestionType.shortAnswer,
      answer: 'Butiran jelas, Boleh dilaksanakan, Mempunyai batasan',
    ),
    Question(
      questionText: 'Which component is missing in the fundamental process flow: INPUT → ? → OUTPUT?',
      type: QuestionType.mcq,
      options: const ['Data', 'Pembolehubah', 'Proses', 'Algoritma'],
      answer: 'Proses',
    ),
    Question(
      questionText: 'What are the three (3) Control Structures found in programming?',
      type: QuestionType.shortAnswer,
      answer: 'Struktur Kawalan Urutan, Struktur Kawalan Pilihan, Struktur Kawalan Pengulangan',
    ),
    Question(
      questionText: 'What type of error is one that does not perform the intended functions?',
      type: QuestionType.mcq,
      options: const ['Ralat Sintaks', 'Ralat Masa Larian', 'Ralat Logik', 'Ralat Kawalan'],
      answer: 'Ralat Logik',
    ),
  ],
  "1.3 Pemboleh Ubah, Pemalar dan Jenis Data": [
    Question(
      questionText: 'Briefly define a PEMBOLEH UBAH (Variable).',
      type: QuestionType.shortAnswer,
      answer: 'Ruang simpanan sementara untuk nombor, teks & objek',
    ),
    Question(
      questionText: 'Which of the following data types would be most suitable for storing the value 17.9?',
      type: QuestionType.mcq,
      options: const ['Integer', 'double', 'char', 'Boolean'],
      answer: 'double',
    ),
    Question(
      questionText: 'What is the difference between a Pemboleh Ubah Sejagat (Global) and a Pemboleh Ubah Setempat (Local)?',
      type: QuestionType.shortAnswer,
      answer: 'Global functions in the entire program; Local functions only within the sub-program where it is declared.',
    ),
  ],
  "1.4 Struktur Kawalan": [
    Question(
      questionText: 'The control structure that uses If-else-if and Switch-case is known as:',
      type: QuestionType.mcq,
      options: const ['Kawalan Urutan', 'Kawalan Pilihan', 'Kawalan Pengulangan', 'Kawalan Logikal'],
      answer: 'Kawalan Pilihan',
    ),
    Question(
      questionText: 'State the two (2) primary operators that check for equality and inequality in the Relational Operators.',
      type: QuestionType.shortAnswer,
      answer: 'Sama dengan (==), Tidak sama dengan (!=)',
    ),
    Question(
      questionText: 'In Logical Operators, which operator is only TRUE (✅) if ALL conditions are TRUE?',
      type: QuestionType.mcq,
      options: const ['OR', 'NOT', 'AND', 'IF'],
      answer: 'AND',
    ),
  ],
  "1.5 Amalan Terbaik Pengaturcaraan": [
    Question(
      questionText: 'List the four (4) factors that influence code readability.',
      type: QuestionType.shortAnswer,
      answer: 'Inden yang konsisten, Jenis data, Pemboleh ubah yang bermakna, Komen',
    ),
    Question(
      questionText: 'Which type of error occurs due to grammar mistakes or the use of unrecognized characters/objects?',
      type: QuestionType.mcq,
      options: const ['Ralat Masa Larian', 'Ralat Logik', 'Ralat Sintaks', 'Ralat Struktur'],
      answer: 'Ralat Sintaks',
    ),
    Question(
      questionText: 'Give two (2) examples of common Ralat Masa Larian (Runtime Errors).',
      type: QuestionType.shortAnswer,
      answer: 'Pembahagian dengan digit 0, Mencari punca kuasa dua bagi nombor negatif',
    ),
  ],
  "1.6 Struktur Data dan Modular": [
    Question(
      questionText: 'What is the definition of a TATASUSUNAN (Array)?',
      type: QuestionType.shortAnswer,
      answer: 'Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks',
    ),
    Question(
      questionText: 'Which of the following is NOT a benefit of using a Modular Structure?',
      type: QuestionType.mcq,
      options: const ['Projek kompleks menjadi lebiringkas', 'Lebih mudah untuk diuji', 'Lebih mudah untuk digunakan semula', 'Memastikan kod hanya ditulis oleh satu orang'],
      answer: 'Memastikan kod hanya ditulis oleh satu orang',
    ),
  ],
  "1.7 Pembagunan Aplikasi": [
    Question(
      questionText: 'What does the acronym SDLC stand for in software development?',
      type: QuestionType.shortAnswer,
      answer: 'Kitaran Hayat Pembangunan Sistem (System Development Life Cycle)',
    ),
    Question(
      questionText: 'List the five (5) steps in the System Development Life Cycle (SDLC).',
      type: QuestionType.shortAnswer,
      answer: '1. Analisis masalah, 2. Reka bentuk penyelesaian, 3. Laksana penyelesaian, 4. Uji & nyah ralat, 5. Dokumentasi',
    ),
  ],
};
// ---------- Quiz Page ----------
class QuizPage extends StatelessWidget {
  const QuizPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Management'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // --- 1. System Quiz Button ---
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to a page showing system-generated quizzes
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SystemQuizListPage(),
                  ),
                );
              },
              icon: const Icon(Icons.auto_stories),
              label: const Text('Generate System Quizzes (From Notes)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            // --- 2. Teacher Create Quiz Button ---
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to the quiz creation form
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateQuizPage(),
                  ),
                );
              },
              icon: const Icon(Icons.add_box),
              label: const Text('Create New Quiz (Teacher)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                backgroundColor: Colors.green, // Differentiate teacher function
              ),
            ),
            const SizedBox(height: 40),
            
            // Placeholder for displaying saved/published quizzes (Note: This relies on a ListView which needs a StateFul Widget or Provider/Bloc listener to update in real-time. For simplicity, we use a ListView here, but a proper solution would use a state management solution to update `dummyQuizzes`.)
            const Text(
              'My Quizzes (Drafts & Published)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: ValueNotifier(dummyQuizzes.length),
                builder: (context, _, child) {
                  return ListView.builder(
                    itemCount: dummyQuizzes.length,
                    itemBuilder: (context, index) {
                      final quiz = dummyQuizzes[index];
                      return ListTile(
                        title: Text(quiz.title),
                        subtitle: Text('${quiz.topic} - Status: ${quiz.status.name.toUpperCase()}'),
                        trailing: Icon(quiz.status == QuizStatus.published ? Icons.check_circle : Icons.edit),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------- System Quiz List Page ----------
class SystemQuizListPage extends StatelessWidget {
  const SystemQuizListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System-Generated Quizzes')),
      body: ListView.builder(
        itemCount: systemQuizData.length,
        itemBuilder: (context, index) {
          final topicTitle = systemQuizData.keys.elementAt(index);
          final generatedQuestions = systemQuizData[topicTitle]!;
          
          return Card(
            margin: const EdgeInsets.all(8.0),
            child: ListTile(
              title: Text('Quiz for topicTitle'),
              subtitle: Text('${generatedQuestions.length} Questions (System Generated)'),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                // Navigate to the detailed quiz view or start the quiz.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DetailedQuizView(
                      quizTitle: 'System Quiz: $topicTitle',
                      questions: generatedQuestions,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
class DetailedQuizView extends StatelessWidget {
  final String quizTitle;
  final List<Question> questions;

  const DetailedQuizView({super.key, required this.quizTitle, required this.questions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(quizTitle)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final q = questions[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${index + 1}: ${q.questionText}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text('Type: ${q.type.name.toUpperCase()}'),
                  if (q.type == QuestionType.mcq)
                    ...q.options.asMap().entries.map((e) => Text('  - ${e.value}')),
                  const SizedBox(height: 4),
                  Text('Correct Answer: ${q.answer}', style: const TextStyle(color: Colors.green)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
// ---------- Quiz Creation ----------
class CreateQuizPage extends StatefulWidget {
  const CreateQuizPage({super.key});

  @override
  State<CreateQuizPage> createState() => _CreateQuizPageState();
}

class _CreateQuizPageState extends State<CreateQuizPage> {
  final _titleController = TextEditingController();
  final _topicController = TextEditingController();
  List<Question> _questions = [];

  // Used for adding a new question
  final _newQuestionTextController = TextEditingController();
  final _newAnswerController = TextEditingController();
  QuestionType _newQuestionType = QuestionType.mcq;
  final List<TextEditingController> _mcqOptionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController()
  ];
  int _correctMcqOptionIndex = 0; // Index of the correct option

  @override
  void dispose() {
    _titleController.dispose();
    _topicController.dispose();
    _newQuestionTextController.dispose();
    _newAnswerController.dispose();
    for (var controller in _mcqOptionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Helper to add a question to the list
  void _addQuestion() {
    if (_newQuestionTextController.text.isEmpty || (_newQuestionType == QuestionType.shortAnswer && _newAnswerController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the question text and answer/options.')),
      );
      return;
    }

    if (_newQuestionType == QuestionType.mcq) {
      final options = _mcqOptionControllers.map((c) => c.text).toList();
      if (options.any((opt) => opt.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all 4 MCQ options.')),
        );
        return;
      }
      final correctAnswer = options[_correctMcqOptionIndex];

      setState(() {
        _questions.add(
          Question(
            questionText: _newQuestionTextController.text,
            type: QuestionType.mcq,
            options: options,
            answer: correctAnswer,
          ),
        );
      });
    } else { // Short Answer
      setState(() {
        _questions.add(
          Question(
            questionText: _newQuestionTextController.text,
            type: QuestionType.shortAnswer,
            answer: _newAnswerController.text,
          ),
        );
      });
    }

    // Reset controllers for next question
    _newQuestionTextController.clear();
    _newAnswerController.clear();
    for (var c in _mcqOptionControllers) {
      c.clear();
    }
    setState(() {
      _newQuestionType = QuestionType.mcq; 
      _correctMcqOptionIndex = 0;
    });
  }

  // Save the quiz as draft or publish it
  void _saveQuiz(QuizStatus status) {
    if (_titleController.text.isEmpty || _questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title and add at least one question.')),
      );
      return;
    }

    final newQuiz = Quiz(
      title: _titleController.text,
      topic: _topicController.text.isEmpty ? 'General' : _topicController.text,
      questions: _questions,
      status: status,
    );

    // Add to dummy storage
    dummyQuizzes.add(newQuiz);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${newQuiz.title} saved as ${status.name.toUpperCase()}!')),
    );
    
    // Go back to the QuizPage
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Quiz (Teacher)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Quiz Title and Topic
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Quiz Title'),
            ),
            TextFormField(
              controller: _topicController,
              decoration: const InputDecoration(labelText: 'Topic (e.g., 1.1 Strategi Penyelesaian Masalah)'),
            ),
            const SizedBox(height: 20),

            const Text('Add New Question:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            
            // Question Type
            Row(
              children: [
                const Text('Type:'),
                Radio<QuestionType>(
                  value: QuestionType.mcq,
                  groupValue: _newQuestionType,
                  onChanged: (QuestionType? value) {
                    setState(() {
                      _newQuestionType = value!;
                    });
                  },
                ),
                const Text('MCQ'),
                Radio<QuestionType>(
                  value: QuestionType.shortAnswer,
                  groupValue: _newQuestionType,
                  onChanged: (QuestionType? value) {
                    setState(() {
                      _newQuestionType = value!;
                    });
                  },
                ),
                const Text('Short Answer'),
              ],
            ),
            
            // Question Text
            TextFormField(
              controller: _newQuestionTextController,
              decoration: const InputDecoration(labelText: 'Question Text'),
            ),
            const SizedBox(height: 10),

            // MCQ Options / Short Answer Field
            if (_newQuestionType == QuestionType.mcq) ...[
              const Text('MCQ Options (Select the correct one):', style: TextStyle(fontWeight: FontWeight.w500)),
              ...List.generate(_mcqOptionControllers.length, (index) {
                return Row(
                  children: [
                    Radio<int>(
                      value: index,
                      groupValue: _correctMcqOptionIndex,
                      onChanged: (int? value) {
                        setState(() {
                          _correctMcqOptionIndex = value!;
                        });
                      },
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _mcqOptionControllers[index],
                        decoration: InputDecoration(labelText: 'Option ${index + 1}'),
                      ),
                    ),
                  ],
                );
              }),
            ] else ...[
              TextFormField(
                controller: _newAnswerController,
                decoration: const InputDecoration(labelText: 'Correct Short Answer'),
              ),
            ],
            const SizedBox(height: 10),

            Center(
              child: ElevatedButton.icon(
                onPressed: _addQuestion,
                icon: const Icon(Icons.add),
                label: const Text('Add Question'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              ),
            ),
            const Divider(height: 30, thickness: 2),

            // Added Questions List
            const Text('Questions Added:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ..._questions.asMap().entries.map((entry) {
              int index = entry.key;
              Question q = entry.value;
              return ListTile(
                title: Text('Q${index + 1}: ${q.questionText}'),
                subtitle: Text('Type: ${q.type.name.toUpperCase()} | Answer: ${q.answer}'),
                trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                        setState(() {
                            _questions.removeAt(index);
                        });
                    },
                ),
              );
            }),
            const SizedBox(height: 30),

            // Save and Publish Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _saveQuiz(QuizStatus.draft),
                  icon: const Icon(Icons.drafts),
                  label: const Text('Save as Draft'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: () => _saveQuiz(QuizStatus.published),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Publish Quiz'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                ),
              ],
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
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
        appBar: AppBar(
          title: const Text('🤖 AI Study Buddy'),
          backgroundColor: Colors.lightBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const _ChatBody(),
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
  int lastRating = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Chat content
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

        // Input, rating, stop button
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
              'Try asking about: CS, Java, etc.',
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
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.lightBlue,
              radius: 16,
              child: const Text('AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color:
                    message.isUser ? Colors.lightBlue[50] : Colors.grey[100],
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
                        const Icon(Icons.schedule, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${message.responseTime}ms',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        if (message.confidence != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  _getConfidenceColor(message.confidence!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              message.confidence!.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
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
            const CircleAvatar(
              backgroundColor: Colors.green,
              radius: 16,
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  static Color _getConfidenceColor(String confidence) {
    switch (confidence) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMessageInput() {
    final controller = TextEditingController();

    return Column(
      children: [
        // ---- Text Input Row ----
        Container(
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
                    hintText: 'Ask about Java Programming...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed:
                          isLoading ? null : () => _sendMessage(controller),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // ---- Rating + End Conversation Row ----
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- Rating Section ---
              Row(
                children: [
                  const Text('Rate chatbot:'),
                  const SizedBox(width: 8),
                  for (int s = 1; s <= 5; s++)
                    IconButton(
                      icon: Icon(
                        s <= lastRating ? Icons.star : Icons.star_border,
                        color: Colors.orange,
                      ),
                      onPressed: () {
                        setState(() => lastRating = s);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Thanks! You rated the bot $s star(s).'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                ],
              ),

              // --- Stop Conversation Button ---
              IconButton(
                icon: const Icon(Icons.stop_circle, color: Colors.red, size: 32),
                tooltip: 'End Conversation',
                onPressed: () {
                  context.read<ChatBloc>().add(ClearChatEvent());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Conversation ended. Starting fresh.')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendMessage(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isNotEmpty && mounted) {
      context.read<ChatBloc>().add(SendMessageEvent(text));
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
      text: "Hello! I'm your AI study buddy. Ask me about: Java programming!",
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ];

  // Predefined FAQs for Java (Bloc version)
final Map<String, Map<String, dynamic>> _faqs = {
  'variable': {
    'answer': 'In Java, a variable is a container that holds data of a specific type. Example: int age = 20;',
    'keywords': ['variable', 'data', 'int', 'container'],
    'category': 'Java Basics'
  },
  'datatype': {
    'answer': 'Java has primitive data types such as int, double, char, boolean, and non-primitive types like String and arrays.',
    'keywords': ['datatype', 'primitive', 'string', 'array'],
    'category': 'Java Basics'
  },
  'loop': {
    'answer': 'Java supports for, while, and do-while loops. Example: for(int i=0; i<5; i++) { System.out.println(i); }',
    'keywords': ['loop', 'for', 'while', 'iteration'],
    'category': 'Control Structure'
  },
  'if': {
    'answer': 'An if statement in Java checks a condition: if(x > 0) { System.out.println("Positive"); } else { System.out.println("Negative"); }',
    'keywords': ['if', 'else', 'condition', 'decision'],
    'category': 'Control Structure'
  },
  'class': {
    'answer': 'A class in Java defines the blueprint for objects. Example: class Car { String model; void drive() { System.out.println("Driving"); } }',
    'keywords': ['class', 'blueprint', 'object'],
    'category': 'OOP'
  },
  'object': {
    'answer': 'Objects are instances of classes. Example: Car myCar = new Car(); myCar.drive();',
    'keywords': ['object', 'instance', 'class'],
    'category': 'OOP'
  },
  'constructor': {
    'answer': 'A constructor initializes an object when it is created. It has the same name as the class and no return type.',
    'keywords': ['constructor', 'initialize', 'object', 'class'],
    'category': 'OOP'
  },
  'inheritance': {
    'answer': 'Inheritance allows a class to use fields and methods of another class. Use the extends keyword: class Dog extends Animal { }',
    'keywords': ['inheritance', 'extends', 'parent', 'child', 'class'],
    'category': 'OOP'
  },
  'polymorphism': {
    'answer': 'Polymorphism means the same method can behave differently based on the object calling it (method overriding).',
    'keywords': ['polymorphism', 'method overriding', 'oop'],
    'category': 'OOP'
  },
  'encapsulation': {
    'answer': 'Encapsulation hides internal data using private fields and public getters/setters to control access.',
    'keywords': ['encapsulation', 'getter', 'setter', 'private', 'oop'],
    'category': 'OOP'
  },
  'abstraction': {
    'answer': 'Abstraction hides complex implementation details; use abstract classes or interfaces to define contracts.',
    'keywords': ['abstraction', 'abstract', 'interface', 'oop'],
    'category': 'OOP'
  },
  'oop': {
    'answer': 'Java OOP concepts include Class, Object, Inheritance, Polymorphism, Abstraction, and Encapsulation.',
    'keywords': ['oop', 'object oriented', 'java'],
    'category': 'OOP'
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

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  _ProgressPageState createState() => _ProgressPageState();
}

class ProgressRecord {
  final String student;
  final String activity;
  final double score;
  final String grade;
  final String comments;

  ProgressRecord({
    required this.student,
    required this.activity,
    required this.score,
    required this.grade,
    required this.comments,
  });
}

class _ProgressPageState extends State<ProgressPage> {
  final _formKey = GlobalKey<FormState>();
  final List<ProgressRecord> _progressList = [];

  // Sample students
  final List<String> _students = ['Ali Ahmad', 'Siti Nur', 'John Tan'];

  // Form controllers
  String? _selectedStudent;
  final TextEditingController _activityController = TextEditingController();
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  void _addProgress() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _progressList.add(
          ProgressRecord(
            student: _selectedStudent ?? '',
            activity: _activityController.text,
            score: double.tryParse(_scoreController.text) ?? 0,
            grade: _gradeController.text,
            comments: _commentsController.text,
          ),
        );
      });
      _clearForm();
    }
  }

  void _clearForm() {
    _selectedStudent = null;
    _activityController.clear();
    _scoreController.clear();
    _gradeController.clear();
    _commentsController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Student Progress')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ---------- Add Progress Form ----------
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedStudent,
                    items: _students
                        .map((student) =>
                            DropdownMenuItem(value: student, child: Text(student)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedStudent = value),
                    decoration:
                        const InputDecoration(labelText: 'Select Student'),
                    validator: (value) =>
                        value == null ? 'Please select a student' : null,
                  ),
                  TextFormField(
                    controller: _activityController,
                    decoration:
                        const InputDecoration(labelText: 'Activity Name'),
                    validator: (v) =>
                        v!.isEmpty ? 'Please enter an activity' : null,
                  ),
                  TextFormField(
                    controller: _scoreController,
                    decoration: const InputDecoration(labelText: 'Score'),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v!.isEmpty ? 'Please enter a score' : null,
                  ),
                  TextFormField(
                    controller: _gradeController,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    validator: (v) =>
                        v!.isEmpty ? 'Please enter a grade' : null,
                  ),
                  TextFormField(
                    controller: _commentsController,
                    decoration: const InputDecoration(labelText: 'Comments'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _addProgress,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Progress'),
                  ),
                  const Divider(height: 30, thickness: 1),
                ],
              ),
            ),

            // ---------- List of Progress Records ----------
            _progressList.isEmpty
                ? const Text(
                    'No progress records yet.',
                    style: TextStyle(color: Colors.grey),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _progressList.length,
                    itemBuilder: (context, index) {
                      final record = _progressList[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title:
                              Text('${record.student} — ${record.activity}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Score: ${record.score}, Grade: ${record.grade}'),
                              Text('Comments: ${record.comments}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

// ---------- Achievements ----------
const bool isDemoMode = true;
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  // Mock data for demonstration purposes (moved inside state for mutability)
  static final AppUser _mockTeacherUser = AppUser(
    id: 'mock_teacher_id',
    username: 'Teacher Demo',
    email: 'teacher@demo.com',
    userType: UserType.teacher, // Crucial for enabling teacher actions
    points: 1200,
    badges: ['Quiz Master', 'Top Contributor', 'File Uploader'],
    completionLevel: 0.9,
  );

  // ⚠️ Mock achievements list is now mutable
  final List<Map<String, dynamic>> _mockAchievements = [
    {'title': 'Quiz Master', 'type': 'Badge', 'description': 'Scored 80% or above in a quiz', 'dateEarned': DateTime.now().subtract(const Duration(days: 5)), 'studentName': _mockTeacherUser.username},
    {'title': 'Top Contributor', 'type': 'Milestone', 'description': 'Posted 10 times in the forum', 'dateEarned': DateTime.now().subtract(const Duration(days: 10)), 'studentName': _mockTeacherUser.username},
    {'title': 'File Uploader', 'type': 'Badge', 'description': 'Uploaded a resource file', 'dateEarned': DateTime.now().subtract(const Duration(days: 20)), 'studentName': _mockTeacherUser.username},
  ];

  // ⚠️ NEW: Function to add a new achievement to the mock list
  void _addMockAchievement(Map<String, dynamic> newAchievement) {
    setState(() {
      // Add new achievement to the start of the list to show it immediately
      _mockAchievements.insert(0, newAchievement);
    });
  }

  // Helper function to get the correct achievement stream for *real* mode
  Stream<QuerySnapshot> getAchievementStream(AppUser? user) {
    var query = FirebaseFirestore.instance.collection('achievements').orderBy('dateEarned', descending: true);
    
    // If user is logged in (user != null), filter for their achievements.
    if (user != null) {
      query = query.where('studentId', isEqualTo: user.id);
    } else {
      // If not logged in, show a public feed of recent achievements.
      query = query.limit(30); 
    }
    return query.snapshots();
  }
  
  @override
  Widget build(BuildContext context) {
    // Conditional setup for state variables: use mock data if in demo mode
    final userState = isDemoMode ? null : context.watch<FirebaseUserState>();
    final isLoggedIn = isDemoMode ? true : (userState?.isLoggedIn ?? false);
    final user = isDemoMode ? _mockTeacherUser : userState?.currentUser;
    // Force isTeacher to true in demo mode, otherwise use actual user type
    final bool isTeacher = isDemoMode ? true : (user?.userType == UserType.teacher ?? false);

    
    // Page title (Yellow Section)
    final String pageTitle = isLoggedIn ? '🏆 Your Achievements' : '🏅 Community Achievements';
    

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logic to show the 'unlocked message' for logged-in users (disabled in demo mode)
          if (!isDemoMode && userState != null && userState.lastUnlockedMessage != null) Builder(
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
          
          Expanded(
            // Conditional rendering: Mock list for demo, or StreamBuilder for real data
            child: isDemoMode 
                ? _buildAchievementListView(_mockAchievements, isLoggedIn) 
                : StreamBuilder<QuerySnapshot>(
              stream: getAchievementStream(user), // Pass the user object to the stream
              builder: (context, snapshot) {
// ========== ACHIEVEMENTS PAGE - PLACEHOLDER ==========
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Map DocumentSnapshot list to Map list for use in helper function
                final achievements = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

                return _buildAchievementListView(achievements, isLoggedIn);
              },
            ),
          ),
          
          // NEW POSITION: Two buttons side-by-side at the bottom, visible only to teachers
          if (isTeacher) Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // 1. Simulate Milestone Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // ⚠️ Fake success message for demo mode
                      if (isDemoMode) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Successfully simulated "Quiz Master" achievement unlocked!'),
                            backgroundColor: Colors.green, // Show success colour
                          ),
                        );
                        return;
                      }
                      
                      // Actual implementation for non-demo mode
                      await context.read<FirebaseUserState>().awardBadge(
                        name: 'Quiz Master',
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
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                
                const SizedBox(width: 10),
                
                // 2. Add Achievement Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // ⚠️ ACTION ENABLED: Pass the callback function
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddAchievementPage(
                            onAchievementAwarded: _addMockAchievement,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Achievement'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build the list view for both mock and real data
  Widget _buildAchievementListView(List<Map<String, dynamic>> achievements, bool isLoggedIn) {
    // Determine the message based on list size and login status
    final String emptyMessage = isLoggedIn 
        ? 'You have no achievements yet. Start learning and completing quizzes!' 
        : 'No community achievements found. Check back later!';
        
    if (achievements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        final title = achievement['title'] ?? 'No Title';
        final type = achievement['type'] ?? 'General';
        final description = achievement['description'] ?? 'No Description';
        
        // Handle both Timestamp (from Firestore) and DateTime (from Mock data)
        final dateEarned = achievement['dateEarned'];
        final DateTime? when;
        if (dateEarned is Timestamp) {
          when = dateEarned.toDate();
        } else if (dateEarned is DateTime) {
          when = dateEarned;
        } else {
          when = null;
        }
        
        final studentName = achievement['studentName'] ?? 'Unknown User';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 4),
                // Show user name in public feed, but not in personal feed
                if (!isLoggedIn) Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text('Earned by: $studentName', style: TextStyle(color: Colors.blue[700], fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                Row(
                  children: [
                    Chip(label: Text(type)),
                    const SizedBox(width: 8),
                    if (when != null) Text(
                      'Earned: ${when.toLocal().toString().split(' ')[0]}', // Only show date
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
  }
}

// ========== Add Achievement Page (MOCK STUDENT LIST & FAKE SUBMIT IMPLEMENTATION) ==========
class AddAchievementPage extends StatefulWidget {
  // ⚠️ NEW: Define a callback function to update the parent's mock list
  final void Function(Map<String, dynamic>)? onAchievementAwarded;
  
  const AddAchievementPage({super.key, this.onAchievementAwarded});

  @override
  State<AddAchievementPage> createState() => _AddAchievementPageState();
}

class _AddAchievementPageState extends State<AddAchievementPage> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _type = 'Badge'; // Default type
  String _description = '';
  String? _selectedStudentId;
  String? _selectedStudentName;

  final List<String> _achievementTypes = ['Badge', 'Certificate', 'Milestone', 'Other'];

  // 統 MOCK STUDENT DATA: Used instead of fetching from Firestore
  final List<Map<String, String>> _mockStudents = const [
    {'id': 'student_mock_001', 'name': 'John'},
    {'id': 'student_mock_002', 'name': 'Bob Johnson'},
    {'id': 'student_mock_003', 'name': 'Charlie Brown'},
  ];

  // 統 Function to submit the achievement to Firestore / Mock List
  Future<void> _submitAchievement() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      if (_selectedStudentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a student.'), backgroundColor: Colors.red),
        );
        return;
      }

      // Prepare the achievement data regardless of mode
      final newAchievement = {
        'title': _title,
        'type': _type,
        'description': _description,
        'studentId': _selectedStudentId,
        'studentName': _selectedStudentName,
        'dateEarned': DateTime.now(), // Use DateTime object for mock list
        'awardedBy': 'Manual Teacher Award',
      };

      // ⚠️ NEW LOGIC: FAKE SUBMISSION FOR DEMO MODE
      if (isDemoMode) {
        // 1. Add achievement to the parent's mock list
        widget.onAchievementAwarded?.call(newAchievement);
        
        if (context.mounted) {
          // 2. Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Achievement "${_title}" (${_type}) awarded to ${_selectedStudentName}.'),
              backgroundColor: Colors.green,
            ),
          );
          // 3. Close the form page, which rebuilds AchievementsPage with the new data
          Navigator.pop(context); 
        }
        return;
      }
      // ⚠️ END NEW LOGIC
      

      try {
        // --- ORIGINAL FIREBASE WRITE LOGIC (Only runs if isDemoMode is false) ---
        // Convert date to FieldValue.serverTimestamp() for real Firestore write
        newAchievement['dateEarned'] = FieldValue.serverTimestamp(); 
        
        await FirebaseFirestore.instance.collection('achievements').add(newAchievement);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Achievement "${_title}" manually awarded to ${_selectedStudentName}.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to award achievement: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (rest of the build method is unchanged)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Achievement Award'),
        backgroundColor: Colors.amber,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. Student Selection Field (Uses Mock Data)
              _buildStudentSelectionField(),
              const SizedBox(height: 20),

              // 2. Title Input
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Achievement Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title.';
                  }
                  return null;
                },
                onSaved: (value) => _title = value!,
              ),
              const SizedBox(height: 20),

              // 3. Type Dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Achievement Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                value: _type,
                items: _achievementTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _type = newValue!;
                  });
                },
                onSaved: (value) => _type = value!,
              ),
              const SizedBox(height: 20),

              // 4. Description Input
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description.';
                  }
                  return null;
                },
                onSaved: (value) => _description = value!,
              ),
              const SizedBox(height: 30),

              // 5. Submit Button
              ElevatedButton.icon(
                onPressed: _submitAchievement,
                icon: const Icon(Icons.send),
                label: const Text('Award Achievement', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 統 Builds the student selection field using mock data
  Widget _buildStudentSelectionField() {
    final studentItems = _mockStudents.map((student) {
      return DropdownMenuItem<String>(
        value: student['id'],
        child: Text(student['name']!),
      );
    }).toList();

    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Select Student to Award',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
      value: _selectedStudentId,
      items: studentItems,
      hint: const Text('Choose a student'),
      validator: (value) {
        if (value == null) {
          return 'You must select a student.';
        }
        return null;
      },
      onChanged: (String? newValue) {
        setState(() {
          _selectedStudentId = newValue;
          // Find the selected student's name from the mock list
          _selectedStudentName = _mockStudents.firstWhere((s) => s['id'] == newValue)['name'];
        });
      },
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

// ---------- LEARNING MATERIAL ----------
class LearningMaterial {
  final String id;
  final String name;
  final String description;
  final String file;
  final DateTime time;

  LearningMaterial({
    this.id = '',
    required this.name,
    required this.description,
    required this.file,
    required this.time,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'file': file,
      'time': time.toIso8601String(),
    };
  }

  factory LearningMaterial.fromMap(String id, Map<String, dynamic> data) {
    return LearningMaterial(
      id: id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      file: data['file'] ?? '',
      time: DateTime.tryParse(data['time'] ?? '') ?? DateTime.now(),
    );
  }
}

// ===== FIREBASE STATE =====
class MaterialAppState extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createMaterialsCollection() async {
    final collectionRef = _db.collection('materials');
    final snapshot = await collectionRef.limit(1).get();

    if (snapshot.docs.isEmpty) {
      await collectionRef.add({
        'name': '___placeholder___', 
        'description': '',
        'file': '',
        'time': Timestamp.now(),
      });
    }
  }

  Stream<List<LearningMaterial>> getMaterialsStream() {
    return _db.collection('materials')
        .orderBy('time', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.data()['name'] != '___placeholder___')
          .map((doc) {
        final data = doc.data();
        if (!data.containsKey('time') || data['time'] == null) {
          data['time'] = Timestamp.now();
        }
        return LearningMaterial.fromMap(doc.id, data);
      }).toList();
    });
  }

  // Add a new material
  Future<void> addMaterial(LearningMaterial material) async {
    final map = material.toMap();
    map['time'] ??= Timestamp.now();
    await _db.collection('materials').add(map);
  }

  // Edit existing material
  Future<void> editMaterial(LearningMaterial material) async {
    final map = material.toMap();
    map['time'] ??= Timestamp.now();
    await _db.collection('materials').doc(material.id).update(map);
  }

  // Delete material
  Future<void> deleteMaterial(String id) async {
    await _db.collection('materials').doc(id).delete();
  }
}

// ===== MATERIALS PAGE =====
class MaterialsPage extends StatefulWidget {
  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    final appState = context.read<MaterialAppState>();
    appState.createMaterialsCollection(); 
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MaterialAppState>();
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Materials'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UploadPage()),
          );

          if (result != null && result['success'] == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search materials...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => searchQuery = value.toLowerCase()),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<List<LearningMaterial>>(
                stream: appState.getMaterialsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        'No learning materials uploaded yet.\nClick "+" to add learning materials.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final materials = snapshot.data!
                      .where((m) =>
                          m.name.toLowerCase().contains(searchQuery) ||
                          m.description.toLowerCase().contains(searchQuery))
                      .toList();

                  if (materials.isEmpty) {
                    return const Center(
                        child: Text('No materials match your search.'));
                  }

                  return ListView.builder(
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
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UploadPage(
                                        existingMaterial: material),
                                  ),
                                );
                                if (result != null &&
                                    result['success'] == true &&
                                    context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(result['message']),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else if (value == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Confirmation'),
                                    content: const Text(
                                        'Are you sure you want to delete this material?'),
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
                                  await appState.deleteMaterial(material.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Material deleted successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
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
      ),
    );
  }
}

// ===== UPLOAD PAGE =====
class UploadPage extends StatefulWidget {
  final LearningMaterial? existingMaterial;

  const UploadPage({super.key, this.existingMaterial});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _formKey = GlobalKey<FormState>();
  String name = '';
  String description = '';
  String? filePath;

  @override
  void initState() {
    super.initState();
    if (widget.existingMaterial != null) {
      name = widget.existingMaterial!.name;
      description = widget.existingMaterial!.description;
      filePath = widget.existingMaterial!.file;
    }
  }

  void pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => filePath = result.files.single.path!);
    }
  }

  Future<void> submit(BuildContext context) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first.')),
      );
      return;
    }

    _formKey.currentState!.save();

    final appState = context.read<MaterialAppState>();
    final isEditing = widget.existingMaterial != null;

    final newMaterial = LearningMaterial(
      id: widget.existingMaterial?.id ?? '',
      name: name,
      description: description,
      file: filePath!,
      time: DateTime.now(),
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Confirmation' : 'Upload Confirmation'),
        content: Text(isEditing
            ? 'Are you sure you want to update this material?'
            : 'Are you sure you want to upload this new material?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (isEditing) {
          await appState.editMaterial(newMaterial);
        } else {
          await appState.addMaterial(newMaterial);
        }

        if (context.mounted) {
          Navigator.pop(context, {
            'success': true,
            'message': isEditing
                ? 'Material updated successfully!'
                : 'Material uploaded successfully!',
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingMaterial != null;

    return Scaffold(
      appBar: AppBar(
          title: Text(isEditing
              ? 'Edit Learning Material'
              : 'Upload Learning Material')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
                onSaved: (v) => name = v ?? '',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                initialValue: description,
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
              Builder(
                builder: (context) => ElevatedButton.icon(
                  onPressed: () => submit(context),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(isEditing ? 'Update' : 'Upload'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

