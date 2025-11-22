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
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart'; // For kIsWeb

// ========== MAIN FUNCTION WITH FIREBASE ==========
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

      await _firestore
          .collection('users')
          .doc(_currentUser!.id)
          .update(updates);

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

  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
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
          .where(
            (user) => user.username.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<AppUser>> filterUsers({
    String? className,
    String? formLevel,
  }) async {
    try {
      Query query = _firestore.collection('users');
      if (className != null) {
        query = query.where('className', isEqualTo: className);
      }
      if (formLevel != null) {
        query = query.where('formLevel', isEqualTo: formLevel);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map(
            (doc) =>
                AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addPoints(int points) async {
    if (_currentUser == null) return;
    final newPoints = _currentUser!.points + points;
    await _firestore.collection('users').doc(_currentUser!.id).update({
      'points': newPoints,
    });
    _currentUser = _currentUser!.copyWith(points: newPoints);
    notifyListeners();
  }

  Future<void> awardBadge({
    required String name,
    required String description,
  }) async {
    if (_currentUser == null) return;

    if (_currentUser!.badges.contains(name)) {
      return;
    }

    final newBadges = List<String>.from(_currentUser!.badges)..add(name);

    await _firestore.collection('users').doc(_currentUser!.id).update({
      'badges': newBadges,
    });

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
      case 'email-already-in-use':
        return 'Email already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return 'Authentication error';
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
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return userState.isLoggedIn ? const HomePage() : const LoginPage();
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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (context) => HomePage()));
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school, size: 80, color: Colors.blue[700]),
                        const SizedBox(height: 16),
                        const Text(
                          'CodingBahasa',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Connect, Code and Challenge',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
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
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Please enter password'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: userState.isLoading
                                ? null
                                : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: userState.isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterPage(),
                            ),
                          ),
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
      className: _classNameController.text.trim().isEmpty
          ? null
          : _classNameController.text.trim(),
      formLevel: _selectedFormLevel,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration successful!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userState.errorMessage ?? 'Registration failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Register New Account',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  if (value.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter email';
                  }
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
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
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
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Passwords do not match'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'User Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<UserType>(
                      title: const Text('Student'),
                      value: UserType.student,
                      groupValue: _selectedUserType,
                      onChanged: (value) =>
                          setState(() => _selectedUserType = value!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<UserType>(
                      title: const Text('Teacher'),
                      value: UserType.teacher,
                      groupValue: _selectedUserType,
                      onChanged: (value) =>
                          setState(() => _selectedUserType = value!),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: ['Form 4', 'Form 5']
                      .map(
                        (level) =>
                            DropdownMenuItem(value: level, child: Text(level)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class Name (Optional)',
                    prefixIcon: const Icon(Icons.class_),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

// ✅ NEW: Interactive Homepage with Logo
class InHomePage extends StatelessWidget {
  const InHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FirebaseUserState>().currentUser;

    void navigateToPage(int pageIndex) {
      // Find the HomePage in the widget tree and update its selectedIndex
      final homePageState = context.findAncestorStateOfType<_HomePageState>();
      if (homePageState != null) {
        homePageState.setState(() {
          homePageState.selectedIndex = pageIndex;
        });
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[700]!, Colors.purple[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                // App Logo (using icon since we can't load images in this environment)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.code, size: 80, color: Colors.blue[700]),
                ),
                const SizedBox(height: 16),
                const Text(
                  'CodingBahasa',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'Connect, Code and Challenge',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Welcome Message
          Text(
            'Welcome back, ${user?.username ?? "User"}!',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Stats Cards (for students only)
          if (user?.userType == UserType.student) ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => navigateToPage(6), // Navigate to Achievements
                    child: _buildStatCard(
                      icon: Icons.star,
                      title: 'Points',
                      value: user!.points.toString(),
                      color: Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => navigateToPage(6), // Navigate to Achievements
                    child: _buildStatCard(
                      icon: Icons.emoji_events,
                      title: 'Badges',
                      value: user.badges.length.toString(),
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => navigateToPage(5), // Navigate to Progress
              child: _buildStatCard(
                icon: Icons.trending_up,
                title: 'Completion',
                value: '${(user.completionLevel * 100).toStringAsFixed(0)}%',
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 30),
          ],

          // Quick Actions
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _buildQuickActionCard(
                icon: Icons.book,
                title: 'Courses',
                color: Colors.blue,
                onTap: () => navigateToPage(1),
              ),
              _buildQuickActionCard(
                icon: Icons.quiz,
                title: 'Quizzes',
                color: Colors.purple,
                onTap: () => navigateToPage(3),
              ),
              _buildQuickActionCard(
                icon: Icons.chat,
                title: 'AI Chatbot',
                color: Colors.teal,
                onTap: () => navigateToPage(4),
              ),
              _buildQuickActionCard(
                icon: Icons.folder,
                title: 'Materials',
                color: Colors.orange,
                onTap: () => navigateToPage(2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const InHomePage();
      /*Center(
          child: Text(
            'Welcome to CodingBahasa!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        );*/
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
        if (_filterClassName != null && user.className != _filterClassName) {
          return false;
        }
        if (_filterFormLevel != null && user.formLevel != _filterFormLevel) {
          return false;
        }
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
      _displayedUsers = await userState.searchUserByName(
        _searchController.text,
      );
    } else {
      var results = await userState.filterUsers(
        className: _filterClassName,
        formLevel: _filterFormLevel,
      );

      if (_searchController.text.isNotEmpty) {
        results = results
            .where(
              (user) => user.username.toLowerCase().contains(
                _searchController.text.toLowerCase(),
              ),
            )
            .toList();
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

  void _showUserDetailsDialog(AppUser user) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: user.userType == UserType.student
                ? Colors.blue[100]
                : Colors.green[100],
            backgroundImage: user.profilePicture != null &&
                             user.profilePicture!.isNotEmpty &&
                             user.profilePicture!.startsWith('http')
                ? NetworkImage(user.profilePicture!)
                : null,
            child: user.profilePicture == null ||
                   user.profilePicture!.isEmpty ||
                   !user.profilePicture!.startsWith('http')
                ? Icon(
                    user.userType == UserType.student ? Icons.school : Icons.person,
                    color: user.userType == UserType.student
                        ? Colors.blue[700]
                        : Colors.green[700],
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(user.username, style: const TextStyle(fontSize: 20)),
          ),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
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
                  decoration: const InputDecoration(
                    labelText: 'Form Level',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...['Form 4', 'Form 5'].map(
                      (level) =>
                          DropdownMenuItem(value: level, child: Text(level)),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => tempFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Class Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setDialogState(
                    () => tempClassName = value.isEmpty ? null : value,
                  ),
                  controller: TextEditingController(text: tempClassName),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
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
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          if (_filterClassName != null || _filterFormLevel != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilters,
              tooltip: 'Clear Filters',
            ),
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
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  if (_filterFormLevel != null)
                    Chip(
                      label: Text(_filterFormLevel!),
                      onDeleted: () => setState(() {
                        _filterFormLevel = null;
                        _applyFilters();
                      }),
                    ),
                  if (_filterClassName != null) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(_filterClassName!),
                      onDeleted: () => setState(() {
                        _filterClassName = null;
                        _applyFilters();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_displayedUsers.length} user(s) found',
                style: TextStyle(color: Colors.grey[600]),
              ),
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
                        Icon(
                          Icons.person_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
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
  backgroundColor: user.userType == UserType.student
      ? Colors.blue[100]
      : Colors.green[100],
  backgroundImage: user.profilePicture != null &&
                   user.profilePicture!.isNotEmpty &&
                   user.profilePicture!.startsWith('http')
      ? NetworkImage(user.profilePicture!)
      : null,
  child: user.profilePicture == null ||
         user.profilePicture!.isEmpty ||
         !user.profilePicture!.startsWith('http')
      ? Icon(
          user.userType == UserType.student ? Icons.school : Icons.person,
          color: user.userType == UserType.student
              ? Colors.blue[700]
              : Colors.green[700],
        )
      : null,
),
                          title: Row(
                            children: [
                              Text(user.username),
                              if (isCurrentUser) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'You',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.userType == UserType.student
                                    ? 'Student'
                                    : 'Teacher',
                                style: TextStyle(
                                  color: user.userType == UserType.student
                                      ? Colors.blue[700]
                                      : Colors.green[700],
                                ),
                              ),
                              if (user.formLevel != null)
                                Text('Form: ${user.formLevel}'),
                              if (user.className != null)
                                Text('Class: ${user.className}'),
                            ],
                          ),
                          trailing: user.userType == UserType.student
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      size: 16,
                                      color: Colors.amber,
                                    ),
                                    Text(
                                      '${user.points}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
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


  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
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
8. Membuat penambahbaikan""",
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
""",
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
""",
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
""",
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
""",
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
""",
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
""",
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
                    Text(topic["note"]!, style: const TextStyle(fontSize: 16)),
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

/// Model for a single question
class Question {
  final String id; // Unique ID for each question
  final String questionText;
  final QuestionType type;
  final List<String> options; // For MCQ
  final String answer; // Correct answer
  final String? explanation; // For detailed feedback (US006-03)

  Question({
    required this.id,
    required this.questionText,
    required this.type,
    this.options = const [],
    required this.answer,
    this.explanation,
  });

  // NEW: Convert Question object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'questionText': questionText,
      'type': type.name, // Store enum as string
      'options': options,
      'answer': answer,
      'explanation': explanation,
    };
  }

  // NEW: Create a Question object from a Map (e.g., from Firestore)
  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as String,
      questionText: map['questionText'] as String,
      type: QuestionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () =>
            QuestionType.mcq, // Default to MCQ if type is missing/invalid
      ),
      options: List<String>.from(map['options'] ?? []),
      answer: map['answer'] as String,
      explanation: map['explanation'] as String?,
    );
  }
}

/// Model for a Quiz (created by a teacher)
class Quiz {
  final String id; // Unique ID for the quiz
  String title;
  String topic;
  List<Question> questions;
  QuizStatus status;
  String createdBy;

  Quiz({
    required this.id,
    required this.title,
    required this.topic,
    required this.questions,
    this.status = QuizStatus.draft,
    required this.createdBy,
  });

  // Convert Quiz object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'topic': topic,
      'questions': questions
          .map((q) => q.toMap())
          .toList(), // Convert list of Questions
      'status': status.name, // Store enum as string
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(), // Good practice
    };
  }

  // Create a Quiz object from a Firestore document
  factory Quiz.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Quiz(
      id: doc.id,
      title: data['title'] ?? '',
      topic: data['topic'] ?? '',
      questions:
          (data['questions'] as List<dynamic>?)
              ?.map((qMap) => Question.fromMap(qMap as Map<String, dynamic>))
              .toList() ??
          [],
      status: QuizStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => QuizStatus.draft,
      ),
      createdBy: data['createdBy'] ?? '',
    );
  }
}

/// Model to store a student's quiz attempt and results (US006-02)
class QuizAttempt {
  final String quizTitle;
  final List<Question> questions;
  final Map<String, String> userAnswers; // Map<QuestionID, UserAnswer>
  final int score;
  final int total;
  final DateTime timestamp;

  QuizAttempt({
    required this.quizTitle,
    required this.questions,
    required this.userAnswers,
    required this.score,
    required this.total,
    required this.timestamp,
  });
}

// ----------System Quiz ----------
///Dummy list for storing student quiz history (US006-02)
List<QuizAttempt> userQuizAttempts = [];

/// System-Generated Quiz Data (US-System)
final Map<String, List<Question>> systemQuizData = {
  "1.1 Strategi Penyelesaian Masalah": [
    Question(
      id: 's1-1',
      questionText: 'Senaraikan empat teknik pemikiran komputasional.',
      type: QuestionType.shortAnswer,
      answer: 'Leraian, Pengecaman corak, Peniskalaan, Algoritma',
      explanation:
          'Keempat-empat teknik ini adalah asas kepada pemikiran komputasional.',
    ),
    Question(
      id: 's1-2',
      questionText:
          'Manakah antara berikut BUKAN ciri penyelesaian masalah berkesan?',
      type: QuestionType.mcq,
      options: const ['Kos', 'Masa', 'Sumber', 'Populariti'],
      answer: 'Populariti',
      explanation:
          'Penyelesaian berkesan dinilai berdasarkan kos, masa, dan sumber yang digunakan.',
    ),
    Question(
      id: 's1-3',
      questionText:
          'Proses memecahkan masalah kepada bahagian yang lebih kecil & terkawal dipanggil...',
      type: QuestionType.mcq,
      options: const [
        'Leraian',
        'Pengecaman corak',
        'Peniskalaan',
        'Algoritma',
      ],
      answer: 'Leraian',
      explanation:
          'Leraian (Decomposition) adalah langkah pertama dalam mempermudahkan masalah yang kompleks.',
    ),
    Question(
      id: 's1-4',
      questionText:
          'Apakah proses penyelesaian masalah yang kelapan (terakhir)?',
      type: QuestionType.shortAnswer,
      answer: 'Membuat penambahbaikan',
      explanation:
          'Selepas penilaian, langkah terakhir adalah membuat penambahbaikan berdasarkan maklum balas.',
    ),
    Question(
      id: 's1-5',
      questionText:
          'Mencari persamaan antara masalah & dalam masalah ialah teknik...',
      type: QuestionType.mcq,
      options: const [
        'Leraian',
        'Pengecaman corak',
        'Peniskalaan',
        'Algoritma',
      ],
      answer: 'Pengecaman corak',
      explanation:
          'Pengecaman corak membantu kita mencari penyelesaian yang boleh diguna semula.',
    ),
  ],
  "1.2 Algoritma": [
    Question(
      id: 's2-1',
      questionText: 'Senaraikan tiga (3) ciri algoritma.',
      type: QuestionType.shortAnswer,
      answer: 'Butiran jelas, Boleh dilaksanakan, Mempunyai batasan',
      explanation:
          'Algoritma mesti jelas, boleh diikuti, dan mempunyai titik permulaan dan penamat yang terhad.',
    ),
    Question(
      id: 's2-2',
      questionText:
          'Apakah perwakilan algoritma yang menggunakan simbol grafik?',
      type: QuestionType.mcq,
      options: const [
        'Pseudokod',
        'Carta Alir',
        'Kod Atur Cara',
        'Ralat Sintaks',
      ],
      answer: 'Carta Alir',
      explanation:
          'Carta Alir (Flowchart) menggunakan simbol-simbol piawai untuk mewakili arahan dan aliran.',
    ),
    Question(
      id: 's2-3',
      questionText:
          'Struktur kawalan yang manakah membuat keputusan berasaskan syarat?',
      type: QuestionType.mcq,
      options: const [
        'Struktur Kawalan Urutan',
        'Struktur Kawalan Pilihan',
        'Struktur Kawalan Pengulangan',
        'Struktur Kawalan Data',
      ],
      answer: 'Struktur Kawalan Pilihan',
      explanation:
          'Struktur Kawalan Pilihan (Selection) menggunakan "if-else" atau "switch-case" untuk membuat keputusan.',
    ),
    Question(
      id: 's2-4',
      questionText:
          'Ralat yang timbul apabila atur cara dijalankan, seperti pembahagian dengan sifar, dipanggil...',
      type: QuestionType.mcq,
      options: const [
        'Ralat Sintaks',
        'Ralat Logik',
        'Ralat Masa Larian',
        'Ralat Algoritma',
      ],
      answer: 'Ralat Masa Larian',
      explanation:
          'Ralat Masa Larian (Run-time Error) berlaku semasa program sedang dilaksanakan.',
    ),
    Question(
      id: 's2-5',
      questionText:
          'Ralat yang menyebabkan atur cara tidak berfungsi seperti yang diingini (cth: output salah) dipanggil...',
      type: QuestionType.mcq,
      options: const [
        'Ralat Sintaks',
        'Ralat Logik',
        'Ralat Masa Larian',
        'Ralat Pengecaman',
      ],
      answer: 'Ralat Logik',
      explanation:
          'Ralat Logik (Logic Error) bermakna atur cara boleh berjalan, tetapi menghasilkan output yang salah.',
    ),
  ],
  "1.3 Pemboleh Ubah, Pemalar dan Jenis Data": [
    Question(
      id: 's3-1',
      questionText:
          'Apakah jenis data yang sesuai untuk menyimpan nilai "hello world"?',
      type: QuestionType.mcq,
      options: const ['int', 'double', 'char', 'String'],
      answer: 'String',
      explanation: 'String digunakan untuk menyimpan jujukan aksara (teks).',
    ),
    Question(
      id: 's3-2',
      questionText: 'Apakah jenis data yang sesuai untuk menyimpan nilai "z"?',
      type: QuestionType.mcq,
      options: const ['int', 'double', 'char', 'String'],
      answer: 'char',
      explanation: 'char digunakan untuk menyimpan satu aksara sahaja.',
    ),
    Question(
      id: 's3-3',
      questionText:
          'Apakah jenis data yang sesuai untuk menyimpan nilai "true" atau "false"?',
      type: QuestionType.mcq,
      options: const ['int', 'boolean', 'char', 'String'],
      answer: 'boolean',
      explanation:
          'Boolean hanya boleh memegang nilai benar (true) atau palsu (false).',
    ),
    Question(
      id: 's3-4',
      questionText:
          'Pemboleh ubah yang diisytiharkan di luar mana-mana fungsi dan boleh diakses di mana-mana dipanggil...',
      type: QuestionType.shortAnswer,
      answer: 'Pemboleh ubah sejagat',
      explanation:
          'Pemboleh ubah Sejagat (Global Variable) mempunyai skop di seluruh atur cara.',
    ),
    Question(
      id: 's3-5',
      questionText:
          'Pemboleh ubah yang diisytiharkan dalam sebuah fungsi dan tidak boleh diakses di luar fungsi itu dipanggil...',
      type: QuestionType.shortAnswer,
      answer: 'Pemboleh ubah setempat',
      explanation:
          'Pemboleh ubah Setempat (Local Variable) hanya wujud di dalam fungsi ia diisytiharkan.',
    ),
  ],
  "1.4 Struktur Kawalan": [
    Question(
      id: 's4-1',
      questionText:
          'Operator logikal yang manakah hanya benar jika SEMUA syarat benar?',
      type: QuestionType.mcq,
      options: const ['AND', 'OR', 'NOT', 'IF'],
      answer: 'AND',
      explanation:
          'Operator AND (&&) memerlukan semua syarat benar untuk menghasilkan "true".',
    ),
    Question(
      id: 's4-2',
      questionText:
          'Operator logikal yang manakah benar jika SALAH SATU syarat benar?',
      type: QuestionType.mcq,
      options: const ['AND', 'OR', 'NOT', 'IF'],
      answer: 'OR',
      explanation:
          'Operator OR (||) hanya memerlukan satu syarat benar untuk menghasilkan "true".',
    ),
    Question(
      id: 's4-3',
      questionText: 'Apakah operator hubungan untuk "Tidak sama dengan"?',
      type: QuestionType.mcq,
      options: const ['==', '!=', '>=', '<='],
      answer: '!=',
      explanation: '`!=` digunakan untuk menyemak jika dua nilai tidak sama.',
    ),
    Question(
      id: 's4-4',
      questionText:
          'Apakah struktur kawalan yang menggunakan "For", "While", dan "Do-while"?',
      type: QuestionType.shortAnswer,
      answer: 'Struktur Kawalan Pengulangan',
      explanation:
          'Ini adalah jenis-jenis gelung (loops) yang digunakan untuk pengulangan.',
    ),
    Question(
      id: 's4-5',
      questionText:
          'Struktur kawalan "Switch-case" adalah sejenis struktur kawalan...',
      type: QuestionType.shortAnswer,
      answer: 'Pilihan',
      explanation:
          'Switch-case ialah satu cara untuk melaksanakan Struktur Kawalan Pilihan, alternatif kepada "if-else-if".',
    ),
  ],
  "1.5 Amalan Terbaik Pengaturcaraan": [
    Question(
      id: 's5-1',
      questionText:
          'Senaraikan tiga (3) faktor yang mempengaruhi kebolehbacaan kod.',
      type: QuestionType.shortAnswer,
      answer: 'Inden yang konsisten, Pemboleh ubah yang bermakna, Komen',
      explanation:
          'Faktor-faktor ini (termasuk juga jenis data) membantu pengatur cara lain memahami kod anda.',
    ),
    Question(
      id: 's5-2',
      questionText:
          'Apakah jenis ralat yang disebabkan oleh kesalahan tatabahasa dalam kod?',
      type: QuestionType.mcq,
      options: const [
        'Ralat Sintaks',
        'Ralat Logik',
        'Ralat Masa Larian',
        'Ralat Amalan',
      ],
      answer: 'Ralat Sintaks',
      explanation:
          'Ralat Sintaks (Syntax Error) adalah seperti kesalahan ejaan atau tatabahasa yang tidak difahami oleh pengkompil.',
    ),
    Question(
      id: 's5-3',
      questionText:
          'Penggunaan nama pemboleh ubah seperti "x" dan "y" adalah amalan yang baik. (Benar/Palsu)',
      type: QuestionType.mcq,
      options: const ['Benar', 'Palsu'],
      answer: 'Palsu',
      explanation:
          'Nama pemboleh ubah harus bermakna (cth: "lebar", "tinggi") supaya kod mudah difahami.',
    ),
    Question(
      id: 's5-4',
      questionText:
          'Apakah tujuan utama meletakkan "komen" (comments) dalam atur cara?',
      type: QuestionType.shortAnswer,
      answer: 'Untuk menerangkan fungsi kod',
      explanation:
          'Komen membantu manusia (pengatur cara) memahami apa yang dilakukan oleh sesuatu bahagian kod.',
    ),
    Question(
      id: 's5-5',
      questionText:
          'Pembahagian dengan digit 0 akan menyebabkan ralat jenis apa?',
      type: QuestionType.mcq,
      options: const [
        'Ralat Sintaks',
        'Ralat Logik',
        'Ralat Masa Larian',
        'Ralat Komen',
      ],
      answer: 'Ralat Masa Larian',
      explanation:
          'Ini adalah Ralat Masa Larian (Run-time Error) kerana ia hanya boleh dikesan semasa atur cara dijalankan.',
    ),
  ],
  "1.6 Struktur Data dan Modular": [
    Question(
      id: 's6-1',
      questionText:
          'Apakah nama struktur data yang membolehkan koleksi beberapa nilai data dalam satu pemboleh ubah menggunakan indeks?',
      type: QuestionType.shortAnswer,
      answer: 'Tatasusunan',
      explanation:
          'Tatasusunan (Array) menyimpan elemen dalam ruang memori berindeks.',
    ),
    Question(
      id: 's6-2',
      questionText:
          'Jika diberi: int[] senaraiUmur = {17, 18, 19}; Apakah nilai bagi senaraiUmur[1]?',
      type: QuestionType.mcq,
      options: const ['17', '18', '19', 'Ralat'],
      answer: '18',
      explanation:
          'Indeks tatasusunan bermula dari 0. Jadi, indeks 0 ialah 17, dan indeks 1 ialah 18.',
    ),
    Question(
      id: 's6-3',
      questionText:
          'Nyatakan satu kelebihan menggunakan struktur modul (subatur cara).',
      type: QuestionType.shortAnswer,
      answer: 'Lebih mudah untuk digunakan semula',
      explanation:
          'Kelebihan lain: lebih mudah diuji, projek kompleks jadi ringkas, mudah dibahagikan tugas. (Mana-mana jawapan ini diterima)',
    ),
    Question(
      id: 's6-4',
      questionText: 'Subatur cara yang MEMULANGKAN nilai dipanggil...',
      type: QuestionType.mcq,
      options: const ['Prosedur', 'Fungsi', 'Tatasusunan', 'Modul'],
      answer: 'Fungsi',
      explanation:
          'Fungsi (Function) memulangkan nilai (cth: "int kiraLuas()"), manakala Prosedur (Procedure) tidak (cth: "void paparNama()").',
    ),
    Question(
      id: 's6-5',
      questionText:
          'Dalam "void paparHarga(String item, double h)", "item" dan "h" dipanggil...',
      type: QuestionType.mcq,
      options: const ['Parameter', 'Pemboleh ubah', 'Fungsi', 'Jenis Data'],
      answer: 'Parameter',
      explanation:
          'Ini adalah parameter yang menerima nilai apabila subatur cara itu dipanggil.',
    ),
  ],
  "1.7 Pembagunan Aplikasi": [
    Question(
      id: 's7-1',
      questionText: 'Apakah maksud singkatan SDLC?',
      type: QuestionType.shortAnswer,
      answer: 'Kitaran Hayat Pembangunan Sistem',
      explanation: 'SDLC bermaksud "System Development Life Cycle".',
    ),
    Question(
      id: 's7-2',
      questionText: 'Nyatakan fasa pertama dalam SDLC.',
      type: QuestionType.shortAnswer,
      answer: 'Analisis masalah',
      explanation:
          'Fasa pertama ialah Analisis Masalah, diikuti Reka Bentuk, Laksana, Uji & Nyah Ralat, dan Dokumentasi.',
    ),
    Question(
      id: 's7-3',
      questionText: 'Fasa "Uji & Nyah Ralat" datang SELEPAS fasa mana?',
      type: QuestionType.mcq,
      options: const [
        'Analisis masalah',
        'Reka bentuk penyelesaian',
        'Laksana penyelesaian',
        'Dokumentasi',
      ],
      answer: 'Laksana penyelesaian',
      explanation:
          'Selepas kod ditulis (dilaksana), ia mesti diuji untuk mencari ralat.',
    ),
    Question(
      id: 's7-4',
      questionText:
          'Reka bentuk yang manakah melibatkan reka bentuk antara muka (GUI)?',
      type: QuestionType.mcq,
      options: const ['Logikal', 'Fizikal', 'Analisis', 'Laksana'],
      answer: 'Fizikal',
      explanation:
          'Reka bentuk logikal ialah aliran (carta alir/pseudokod), manakala reka bentuk fizikal ialah rupa (GUI) dan pangkalan data.',
    ),
    Question(
      id: 's7-5',
      questionText: 'Apakah fasa terakhir dalam SDLC?',
      type: QuestionType.shortAnswer,
      answer: 'Dokumentasi',
      explanation:
          'Fasa terakhir ialah Dokumentasi, yang penting untuk rujukan dan penyelenggaraan masa depan.',
    ),
  ],
};

/// System-Generated Summative Test (US-System)
final List<Question> summativeTestQuestions = [
  Question(
    id: 'sum-1',
    questionText:
        'Yang manakah penyataan yang tidak tepat mengenai mengapa perlunya strategi dalam penyelesaian masalah?',
    type: QuestionType.mcq,
    options: const [
      'Membantu pengembangan sesuatu konsep',
      'Menggalakkan pembelajaran kendiri',
      'Meningkatkan kemahiran berfikir',
      'Mewujudkan komunikasi sehala',
    ],
    answer: 'Mewujudkan komunikasi sehala',
    explanation:
        'Strategi penyelesaian masalah menggalakkan komunikasi DUA hala, bukan sehala.',
  ),
  Question(
    id: 'sum-2',
    questionText:
        'Proses mengkaji butiran sesuatu masalah untuk mendapatkan satu penyelesaian, merujuk kepada konsep...',
    type: QuestionType.mcq,
    options: const [
      'Analisis Masalah',
      'Penyelesaian Masalah',
      'Reka Bentuk Sistem',
      'Algoritma',
    ],
    answer: 'Penyelesaian Masalah',
    explanation: 'Ini adalah definisi asas bagi penyelesaian masalah.',
  ),
  Question(
    id: 'sum-3',
    questionText:
        'Teknik Leraian, Pengecaman Corak, Peniskalaan, dan Algoritma adalah teknik dalam...',
    type: QuestionType.mcq,
    options: const [
      'SDLC',
      'Amalan Terbaik',
      'Pemikiran Komputasional',
      'Struktur Kawalan',
    ],
    answer: 'Pemikiran Komputasional',
    explanation:
        'Ini adalah empat tonggak utama dalam Pemikiran Komputasional.',
  ),
  Question(
    id: 'sum-4',
    questionText: 'Apakah fungsi bagi struktur kawalan pilihan?',
    type: QuestionType.mcq,
    options: const [
      'Memberikan perisian komputer keupayaan untuk membuat keputusan berasaskan syarat',
      'Mengulang satu set arahan sehingga syarat dipenuhi',
      'Melaksanakan arahan satu per satu mengikut urutan',
      'Menyimpan data dalam memori',
    ],
    answer:
        'Memberikan perisian komputer keupayaan untuk membuat keputusan berasaskan syarat',
    explanation:
        'Struktur kawalan pilihan (cth: "if", "switch") membenarkan atur cara membuat keputusan.',
  ),
  Question(
    id: 'sum-5',
    questionText:
        'Apakah yang dimaksudkan dengan amalan terbaik dalam pengaturcaraan?',
    type: QuestionType.mcq,
    options: const [
      'Menjalankan atur cara tanpa sebarang ralat',
      'Mempraktikkan amalan-amalan untuk menghasilkan atur cara yang baik dan mudah difahami',
      'Menulis kod atur cara dengan paling pantas',
      'Menggunakan pemboleh ubah yang paling sedikit',
    ],
    answer:
        'Mempraktikkan amalan-amalan untuk menghasilkan atur cara yang baik dan mudah difahami',
    explanation:
        'Amalan terbaik mementingkan kebolehbacaan, kecekapan, dan penyelenggaraan kod.',
  ),
  Question(
    id: 'sum-6',
    questionText:
        'Kata kunci "int" dalam Java digunakan untuk mengisytiharkan pemboleh ubah jenis...',
    type: QuestionType.shortAnswer,
    answer: 'Integer',
    explanation:
        '`int` adalah singkatan untuk "Integer", yang merupakan nombor bulat.',
  ),
  Question(
    id: 'sum-7',
    questionText:
        'Jenis data "float" atau "double" digunakan untuk menyimpan nombor yang mempunyai...',
    type: QuestionType.shortAnswer,
    answer: 'Titik perpuluhan',
    explanation:
        'Nombor perpuluhan (cth: 10.5) disimpan sebagai "float" atau "double".',
  ),
  Question(
    id: 'sum-8',
    questionText:
        'Data dalam bentuk pilihan "Benar" (True) atau "Palsu" (False) ialah jenis data...',
    type: QuestionType.shortAnswer,
    answer: 'Boolean',
    explanation:
        'Jenis data "boolean" hanya boleh menyimpan nilai "true" atau "false".',
  ),
  Question(
    id: 'sum-9',
    questionText:
        'Perwakilan algoritma yang menggunakan senarai arahan dalam bahasa pertuturan manusia dipanggil...',
    type: QuestionType.shortAnswer,
    answer: 'Pseudokod',
    explanation:
        'Pseudokod ialah cara menulis logik atur cara menggunakan bahasa biasa, bukan kod sebenar.',
  ),
  Question(
    id: 'sum-10',
    questionText:
        'Perwakilan algoritma yang menggunakan simbol grafik dipanggil...',
    type: QuestionType.shortAnswer,
    answer: 'Carta alir',
    explanation:
        'Carta alir (flowchart) menggunakan simbol untuk mewakili proses, keputusan, dan aliran.',
  ),
  Question(
    id: 'sum-11',
    questionText:
        'Pemboleh ubah yang diisytiharkan di luar mana-mana fungsi dan boleh diakses di mana-mana dipanggil...',
    type: QuestionType.mcq,
    options: const [
      'Pemboleh ubah setempat',
      'Pemboleh ubah sejagat',
      'Pemalar',
      'Jenis Data',
    ],
    answer: 'Pemboleh ubah sejagat',
    explanation:
        'Pemboleh ubah sejagat (global) boleh diakses dari mana-mana bahagian atur cara.',
  ),
  Question(
    id: 'sum-12',
    questionText:
        'Fasa pertama dalam Kitaran Hayat Pembangunan Sistem (SDLC) ialah...',
    type: QuestionType.mcq,
    options: const [
      'Reka bentuk penyelesaian',
      'Laksana penyelesaian',
      'Analisis Masalah',
      'Dokumentasi',
    ],
    answer: 'Analisis Masalah',
    explanation:
        'Proses SDLC sentiasa bermula dengan menganalisis masalah yang perlu diselesaikan.',
  ),
  Question(
    id: 'sum-13',
    questionText:
        'Ralat yang berlaku disebabkan pembahagian dengan digit 0 ialah...',
    type: QuestionType.mcq,
    options: const [
      'Ralat logik',
      'Ralat masa larian',
      'Ralat sintaks',
      'Ralat pengguna',
    ],
    answer: 'Ralat masa larian',
    explanation:
        'Ini adalah Ralat Masa Larian (Run-time Error) kerana ia hanya dikesan semasa atur cara cuba melakukan pembahagian itu.',
  ),
  Question(
    id: 'sum-14',
    questionText:
        'Fasa "Menguji dan Menyahralat" dalam SDLC datang selepas fasa...',
    type: QuestionType.mcq,
    options: const [
      'Analisis Masalah',
      'Reka Bentuk Penyelesaian',
      'Laksana Penyelesaian',
      'Dokumentasi',
    ],
    answer: 'Laksana Penyelesaian',
    explanation:
        'Selepas atur cara ditulis (dilaksanakan), ia mesti diuji untuk mencari ralat.',
  ),
  Question(
    id: 'sum-15',
    questionText:
        'Diberi: String[] senaraiWarna = {"Ungu", "Biru", "Merah"}; Apakah indeks bagi "Biru"?',
    type: QuestionType.mcq,
    options: const ['0', '1', '2', '3'],
    answer: '1',
    explanation:
        'Indeks tatasusunan (array) bermula dari 0. "Ungu" ialah [0], "Biru" ialah [1], dan "Merah" ialah [2].',
  ),
];

// ---------- Quiz Page ----------
class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  // Helper function to navigate to the quiz-taking page
  void _startQuiz(
    BuildContext context,
    String title,
    List<Question> questions,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TakeQuizPage(quizTitle: title, questions: questions),
      ),
    ).then((_) {
      // When returning from a quiz, refresh the state to show new quiz history
      setState(() {});
    });
  }

  // Helper function to delete a quiz from Firestore
  void _deleteQuiz(Quiz quiz) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quiz'),
        content: Text(
          'Are you sure you want to delete "${quiz.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('quizzes')
            .doc(quiz.id)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quiz deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete quiz: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Helper function to edit a quiz (US005-02)
  void _editQuiz(Quiz quiz) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateQuizPage(quizToEdit: quiz)),
    ).then((_) {
      // Refresh the list in case changes were made
      setState(() {});
    });
  }

  // Helper function to review a quiz
  void _reviewQuiz(Quiz quiz) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ReviewQuizPage(quizTitle: quiz.title, questions: quiz.questions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get user type to show/hide teacher buttons
    final user = context.watch<FirebaseUserState>().currentUser;
    final isTeacher = user?.userType == UserType.teacher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 Quizzes'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        actions: [
          if (isTeacher)
            IconButton(
              icon: const Icon(Icons.add_box),
              tooltip: 'Create New Quiz',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateQuizPage(),
                  ),
                ).then((_) {
                  // Refresh list when returning from create page
                  setState(() {});
                });
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // --- 1. System Quizzes ---
            _buildSectionTitle('System Quizzes'),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.auto_stories, color: Colors.blue),
                title: const Text('Sub-Topic Quizzes'),
                subtitle: const Text('Practice questions for each topic'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SystemQuizListPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              color: Colors.blue[50],
              child: ListTile(
                leading: const Icon(Icons.quiz, color: Colors.blue),
                title: const Text('Summative Test (Bab 1)'),
                subtitle: const Text(
                  'Test your knowledge on the whole chapter',
                ),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _startQuiz(
                  context,
                  'Summative Test (Bab 1)',
                  summativeTestQuestions,
                ),
              ),
            ),
            const Divider(height: 30, thickness: 1),

            // --- 2. Teacher-Created Quizzes ---
            _buildSectionTitle('Teacher Quizzes'),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('quizzes')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No quizzes published by your teacher yet.'),
                    ),
                  );
                }

                final quizzes = snapshot.data!.docs
                    .map((doc) => Quiz.fromFirestore(doc))
                    .toList();

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: quizzes.length,
                  itemBuilder: (context, index) {
                    final quiz = quizzes[index];

                    // Show drafts only to teachers
                    if (quiz.status == QuizStatus.draft && !isTeacher) {
                      return const SizedBox.shrink();
                    }

                    return Card(
                      elevation: 2,
                      child: ListTile(
                        leading: Icon(
                          quiz.status == QuizStatus.published
                              ? Icons.check_circle
                              : Icons.edit,
                          color: quiz.status == QuizStatus.published
                              ? Colors.green
                              : Colors.orange,
                        ),
                        title: Text(quiz.title),
                        subtitle: Text(
                          '${quiz.topic} - ${quiz.questions.length} questions',
                        ),
                        trailing: isTeacher
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _editQuiz(quiz);
                                  if (value == 'delete') _deleteQuiz(quiz);
                                  if (value == 'review') {
                                    _reviewQuiz(quiz); // NEW: Handle review
                                  }
                                },
                                itemBuilder: (context) => [
                                  // NEW: Only show 'Edit' if quiz is a draft
                                  if (quiz.status == QuizStatus.draft)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),

                                  // NEW: Show 'Review' for all
                                  const PopupMenuItem(
                                    value: 'review',
                                    child: Text('Review Answers'),
                                  ),

                                  // 'Delete' is always available for teachers
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            : const Icon(Icons.play_arrow),
                        onTap: () {
                          if (isTeacher) {
                            // NEW: Default tap action for teacher is 'review'
                            _reviewQuiz(quiz);
                          } else if (quiz.status == QuizStatus.published) {
                            // Student tap action is 'start quiz'
                            _startQuiz(context, quiz.title, quiz.questions);
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),

            const Divider(height: 30, thickness: 1),

            // --- 3. Student Quiz History (US006-02) ---
            if (!isTeacher) ...[
              _buildSectionTitle('My Quiz History'),
              userQuizAttempts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('You have not completed any quizzes yet.'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: userQuizAttempts.length,
                      itemBuilder: (context, index) {
                        final attempt = userQuizAttempts.reversed
                            .toList()[index]; // Show newest first
                        return Card(
                          elevation: 2,
                          child: ListTile(
                            leading: const Icon(
                              Icons.history,
                              color: Colors.purple,
                            ),
                            title: Text(attempt.quizTitle),
                            subtitle: Text(
                              'Score: ${attempt.score}/${attempt.total} - Completed on ${attempt.timestamp.toLocal().toString().split(' ')[0]}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              // Navigate to the results page to review
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      QuizResultsPage(attempt: attempt),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
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
    final user = context.watch<FirebaseUserState>().currentUser;
    final isTeacher = user?.userType == UserType.teacher;

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
              title: Text(topicTitle),
              subtitle: Text('${generatedQuestions.length} Questions'),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                // Navigate to the quiz-taking page (US006-01)
                if (isTeacher) {
                  // NEW: Teacher reviews the quiz
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReviewQuizPage(
                        quizTitle: topicTitle,
                        questions: generatedQuestions,
                      ),
                    ),
                  );
                } else {
                  // Student starts the quiz
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TakeQuizPage(
                        quizTitle: topicTitle,
                        questions: generatedQuestions,
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------- REVIEW QUIZ PAGE (FOR TEACHERS) ----------
class ReviewQuizPage extends StatelessWidget {
  final String quizTitle;
  final List<Question> questions;

  const ReviewQuizPage({
    super.key,
    required this.quizTitle,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Review: $quizTitle'),
        backgroundColor: Colors.orange[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reviewing Answers (${questions.length} questions)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(thickness: 1),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final q = questions[index];

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${index + 1}: ${q.questionText}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (q.type == QuestionType.mcq)
                          ...q.options.map(
                            (opt) => Text(
                              '- $opt',
                              style: TextStyle(
                                color: opt == q.answer
                                    ? Colors.green[800]
                                    : Colors.black87,
                                fontWeight: opt == q.answer
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),

                        const SizedBox(height: 8),
                        Text(
                          'Correct Answer: ${q.answer}',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (q.explanation != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: Text(
                              'Explanation: ${q.explanation}',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
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

// ---------- Quiz Creation / EDIT Page (US005-01 & US005-02) ----------
class CreateQuizPage extends StatefulWidget {
  final Quiz? quizToEdit; // If not null, we are in "Edit" mode
  const CreateQuizPage({super.key, this.quizToEdit});

  @override
  State<CreateQuizPage> createState() => _CreateQuizPageState();
}

class _CreateQuizPageState extends State<CreateQuizPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _topicController;
  List<Question> _questions = [];
  bool _isEditing = false;
  bool _isLoading = false;

  // Controllers for adding a new question
  final _newQuestionTextController = TextEditingController();
  final _newAnswerController = TextEditingController();
  final _newExplanationController = TextEditingController(); // For feedback
  QuestionType _newQuestionType = QuestionType.mcq;
  final List<TextEditingController> _mcqOptionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int _correctMcqOptionIndex = 0; // Index of the correct option

  @override
  void initState() {
    super.initState();
    _isEditing = widget.quizToEdit != null;

    if (_isEditing) {
      // Populate fields from existing quiz
      final quiz = widget.quizToEdit!;
      _titleController = TextEditingController(text: quiz.title);
      _topicController = TextEditingController(text: quiz.topic);
      _questions = List.from(quiz.questions);
    } else {
      // Start fresh
      _titleController = TextEditingController();
      _topicController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _topicController.dispose();
    _newQuestionTextController.dispose();
    _newAnswerController.dispose();
    _newExplanationController.dispose();
    for (var controller in _mcqOptionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Helper to add a question to the local list
  void _addQuestion() {
    if (_newQuestionTextController.text.isEmpty) {
      _showError('Please enter the question text.');
      return;
    }

    String answer;
    List<String> options = [];

    if (_newQuestionType == QuestionType.mcq) {
      options = _mcqOptionControllers.map((c) => c.text).toList();
      if (options.any((opt) => opt.isEmpty)) {
        _showError('Please fill all 4 MCQ options.');
        return;
      }
      answer = options[_correctMcqOptionIndex];
    } else {
      // Short Answer
      if (_newAnswerController.text.isEmpty) {
        _showError('Please enter the correct answer.');
        return;
      }
      answer = _newAnswerController.text;
    }

    setState(() {
      _questions.add(
        Question(
          id: UniqueKey().toString(), // Simple unique ID
          questionText: _newQuestionTextController.text,
          type: _newQuestionType,
          options: options,
          answer: answer,
          explanation: _newExplanationController.text.isEmpty
              ? null
              : _newExplanationController.text,
        ),
      );
    });

    // Reset controllers
    _newQuestionTextController.clear();
    _newAnswerController.clear();
    _newExplanationController.clear();
    for (var c in _mcqOptionControllers) {
      c.clear();
    }
    setState(() => _correctMcqOptionIndex = 0);
  }

  // Save or Update the quiz (US005-01, US005-02)
  Future<void> _saveQuiz(QuizStatus status) async {
    if (!_formKey.currentState!.validate()) return;
    if (_questions.isEmpty) {
      _showError('Please add at least one question.');
      return;
    }

    _formKey.currentState!.save();

    final user = context.read<FirebaseUserState>().currentUser;
    if (user == null) {
      _showError('You must be logged in to create a quiz.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        // Find and update the existing quiz in the global list
        final quiz = widget.quizToEdit!;
        quiz.title = _titleController.text;
        quiz.topic = _topicController.text;
        quiz.questions = _questions;
        quiz.status = status;

        // Update in Firestore
        await FirebaseFirestore.instance
            .collection('quizzes')
            .doc(quiz.id)
            .update(quiz.toMap());
      } else {
        // Add a new quiz to the global list
        final newQuiz = Quiz(
          id: '', // ID will be auto-generated by Firestore
          title: _titleController.text,
          topic: _topicController.text.isEmpty
              ? 'General'
              : _topicController.text,
          questions: _questions,
          status: status,
          createdBy: user.id, // Link quiz to the teacher
        );

        // Add to Firestore
        await FirebaseFirestore.instance
            .collection('quizzes')
            .add(newQuiz.toMap());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quiz saved as ${status.name.toUpperCase()}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back to the QuizPage
      }
    } catch (e) {
      _showError('Failed to save quiz: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Quiz' : 'Create New Quiz')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Quiz Title',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Please enter a title' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _topicController,
                      decoration: const InputDecoration(
                        labelText: 'Topic (e.g., 1.1)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'Please enter a topic' : null,
                    ),
                    const Divider(height: 30, thickness: 2),

                    // --- Add New Question Form ---
                    const Text(
                      'Add New Question:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    DropdownButtonFormField<QuestionType>(
                      initialValue: _newQuestionType,
                      items: const [
                        DropdownMenuItem(
                          value: QuestionType.mcq,
                          child: Text('Multiple Choice (MCQ)'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.shortAnswer,
                          child: Text('Short Answer'),
                        ),
                      ],
                      onChanged: (QuestionType? value) =>
                          setState(() => _newQuestionType = value!),
                      decoration: const InputDecoration(
                        labelText: 'Question Type',
                      ),
                    ),
                    const SizedBox(height: 10),
                    /*TextFormField(
                controller: _newQuestionTextController,
                decoration: const InputDecoration(labelText: 'Question Text', border: OutlineInputBorder()),
              ),*/
                    TextFormField(
                      controller: _newQuestionTextController,
                      decoration: const InputDecoration(
                        labelText: 'Question Text',
                        border: OutlineInputBorder(),
                        hintText: 'Enter your question here...',
                      ),
                      maxLines: 5, // ✅ Allow multiple lines
                      minLines: 3,
                    ),
                    const SizedBox(height: 10),

                    if (_newQuestionType == QuestionType.mcq) ...[
                      const Text(
                        'MCQ Options (Select the correct one):',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      ...List.generate(_mcqOptionControllers.length, (index) {
                        return Row(
                          children: [
                            Radio<int>(
                              value: index,
                              groupValue: _correctMcqOptionIndex,
                              onChanged: (int? value) => setState(
                                () => _correctMcqOptionIndex = value!,
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _mcqOptionControllers[index],
                                decoration: InputDecoration(
                                  labelText: 'Option ${index + 1}',
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ] else ...[
                      TextFormField(
                        controller: _newAnswerController,
                        decoration: const InputDecoration(
                          labelText: 'Correct Short Answer',
                          border: OutlineInputBorder(),
                          hintText: 'Enter the correct answer...',
                        ),
                        maxLines: 3, // ✅ Allow multiple lines
                        minLines: 2,
                      ),
                      /*TextFormField(
                  controller: _newAnswerController,
                  decoration: const InputDecoration(labelText: 'Correct Short Answer', border: OutlineInputBorder()),
                ),*/
                    ],

                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _newExplanationController,
                      decoration: const InputDecoration(
                        labelText: 'Explanation (Optional)',
                        border: OutlineInputBorder(),
                        hintText: 'Provide detailed feedback...',
                      ),
                      maxLines: 5, // ✅ Allow multiple lines
                      minLines: 3,
                    ),

                    /*TextFormField(
                controller: _newExplanationController,
                decoration: const InputDecoration(labelText: 'Explanation (Optional)', border: OutlineInputBorder()),
              ),*/
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _addQuestion,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Question to Quiz'),
                      ),
                    ),
                    const Divider(height: 30, thickness: 2),

                    // --- Added Questions List ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Quiz Questions:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('${_questions.length} Question(s)'),
                      ],
                    ),
                    ..._questions.asMap().entries.map((entry) {
                      int idx = entry.key;
                      Question q = entry.value;
                      return ListTile(
                        title: Text('Q${idx + 1}: ${q.questionText}'),
                        subtitle: Text('Answer: ${q.answer}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              setState(() => _questions.removeAt(idx)),
                        ),
                      );
                    }),
                    const SizedBox(height: 30),

                    // --- Save/Publish Buttons ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _saveQuiz(QuizStatus.draft),
                          icon: const Icon(Icons.drafts),
                          label: const Text('Save as Draft'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _saveQuiz(QuizStatus.published),
                          icon: const Icon(Icons.cloud_upload),
                          label: Text(
                            _isEditing ? 'Update & Publish' : 'Publish Quiz',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
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
}

// ---------- TAKE QUIZ PAGE (US006-01) ----------
class TakeQuizPage extends StatefulWidget {
  final String quizTitle;
  final List<Question> questions;

  const TakeQuizPage({
    super.key,
    required this.quizTitle,
    required this.questions,
  });

  @override
  State<TakeQuizPage> createState() => _TakeQuizPageState();
}

class _TakeQuizPageState extends State<TakeQuizPage> {
  final PageController _pageController = PageController();
  final Map<String, String> _userAnswers = {}; // Map<QuestionID, UserAnswer>
  final Map<String, TextEditingController> _shortAnswerControllers = {};
  int _currentPage = 0;
  bool _isSubmitting = false; // NEW: Loading state for AI marking

  // NEW: AI Model for marking
  late final GenerativeModel _markingModel;

  @override
  void initState() {
    super.initState();
    // Initialize controllers for short answer questions
    for (var q in widget.questions) {
      if (q.type == QuestionType.shortAnswer) {
        _shortAnswerControllers[q.id] = TextEditingController();
      }
    }

    // NEW: Initialize AI model for marking
    final googleAI = FirebaseAI.googleAI();
    _markingModel = googleAI.generativeModel(
      model: 'gemini-2.5-flash',
      systemInstruction: Content.system(
        'You are an AI quiz marker. You will be given an expected answer and a user answer. '
        'Compare them for semantic similarity, not just exact text match, including synonyms and variations, and lowercase and uppercase differences. '
        'Respond with only the word "YES" if the user answer is correct or a close synonym/variation. '
        'Respond with only the word "NO" if the user answer is incorrect.'
        'Give an justification for each answer.',
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _shortAnswerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveQuizScoreToDatabase(int score, int total) async {
    final userState = context.read<FirebaseUserState>();
    final user = userState.currentUser;
    if (user == null || !mounted) return;

    try {
      // 1. Save quiz attempt
      await FirebaseFirestore.instance.collection('quiz_attempts').add({
        'userId': user.id,
        'username': user.username,
        'quizTitle': widget.quizTitle,
        'score': score,
        'total': total,
        'percentage': (score / total * 100).toDouble(),
        'timestamp': FieldValue.serverTimestamp(),
        'userAnswers': _userAnswers,
      });

      if (!mounted) return;

      // 2. Add points
      final earnedPoints = (score / total * 100).toInt();
      await userState.addPoints(earnedPoints);

      // 3. Check for automatic badge (80% or above)
      if (score / total >= 0.8) {
        const badgeName = 'Quiz Master';
        const badgeDescription = 'Scored 80% or above in a system quiz';

        // Check if user already has the badge based on the current user state model.
        if (!user.badges.contains(badgeName)) {
          // 3a. Award the badge (updates AppUser model & Firestore 'users' collection)
          // This call must happen before the Firestore write to 'achievements' so we know the badge was newly earned.
          await userState.awardBadge(
            name: badgeName,
            description: badgeDescription,
          );

          // 3b. Create a persistent record in the teacher-facing 'achievements' collection
          // This fulfills the requirement for the auto-awarded badge to appear in the teacher's list (US012-01 req).
          await FirebaseFirestore.instance.collection('achievements').add({
            'title': badgeName,
            'type': 'Badge (Auto)',
            'description': '$badgeDescription on Quiz: ${widget.quizTitle}',
            'studentId': user.id,
            'studentName': user.username,
            'dateEarned': FieldValue.serverTimestamp(),
            'awardedBy': 'System',
          });
        }
      }
    } catch (e) {
      print('Error saving quiz score: $e');
    }
  }

  // NEW: Updated submit quiz with AI Marking
  Future<void> _submitQuiz() async {
    if (!mounted) return; // Add this check

    setState(() => _isSubmitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Marking quiz...'),
          ],
        ),
      ),
    );

    int score = 0;
    for (var q in widget.questions) {
      final userAnswer = _userAnswers[q.id]?.toLowerCase().trim() ?? "";
      final correctAnswer = q.answer.toLowerCase().trim();

      if (userAnswer.isEmpty) continue;

      if (q.type == QuestionType.mcq) {
        if (userAnswer == correctAnswer) {
          score++;
        }
      } else if (q.type == QuestionType.shortAnswer) {
        if (userAnswer == correctAnswer) {
          score++;
        } else {
          try {
            final prompt =
                'Is the following user answer similar to or a correct variation of the expected answer?\n\n'
                'Expected Answer: $correctAnswer\n'
                'User Answer: $userAnswer\n\n'
                'Respond with only "YES" or "NO".';

            final response = await _markingModel.generateContent([
              Content.text(prompt),
            ]);

            if (response.text?.trim().toUpperCase() == 'YES') {
              score++;
            }
          } catch (e) {
            print('AI marking error: $e');
          }
        }
      }
    }

    // Add mounted check before saving to database
    if (!mounted) return;

    await _saveQuizScoreToDatabase(score, widget.questions.length);

    final attempt = QuizAttempt(
      quizTitle: widget.quizTitle,
      questions: widget.questions,
      userAnswers: Map.from(_userAnswers),
      score: score,
      total: widget.questions.length,
      timestamp: DateTime.now(),
    );

    userQuizAttempts.add(attempt);

    if (!mounted) return; // Add this check
    setState(() => _isSubmitting = false);

    if (!mounted) return; // Add this check
    Navigator.pop(context); // Close loading dialog

    if (!mounted) return; // Add this check
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => QuizResultsPage(attempt: attempt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quizTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: LinearProgressIndicator(
            value: (_currentPage + 1) / widget.questions.length,
            backgroundColor: Colors.grey[300],
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swiping
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final question = widget.questions[index];
          return _buildQuestionPage(question, index);
        },
        onPageChanged: (index) => setState(() => _currentPage = index),
      ),
      bottomNavigationBar: BottomAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _currentPage == 0 || _isSubmitting
                  ? null
                  : () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeIn,
                    ),
              child: const Text('Previous'),
            ),
            Text('Question ${_currentPage + 1}/${widget.questions.length}'),
            ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      if (_currentPage < widget.questions.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeIn,
                        );
                      } else {
                        // Last page, show submit dialog
                        _showSubmitDialog();
                      }
                    },
              child: Text(
                _currentPage == widget.questions.length - 1 ? 'Submit' : 'Next',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubmitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Quiz'),
        content: const Text('Are you sure you want to submit your answers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _submitQuiz();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionPage(Question question, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${index + 1}: ${question.questionText}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          if (question.type == QuestionType.mcq)
            ...question.options.map((option) {
              return RadioListTile<String>(
                title: Text(option),
                value: option,
                groupValue: _userAnswers[question.id],
                onChanged: (value) {
                  setState(() {
                    _userAnswers[question.id] = value!;
                  });
                },
              );
            }),
          if (question.type == QuestionType.shortAnswer)
            TextField(
              controller: _shortAnswerControllers[question.id],
              decoration: const InputDecoration(
                labelText: 'Your Answer',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _userAnswers[question.id] = value;
                });
              },
            ),
        ],
      ),
    );
  }
}

// ---------- QUIZ RESULTS PAGE (US006-02 & US006-03) ----------
class QuizResultsPage extends StatelessWidget {
  final QuizAttempt attempt;
  const QuizResultsPage({super.key, required this.attempt});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Results: ${attempt.quizTitle}'),
        automaticallyImplyLeading: false, // No back button
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- 1. Score Summary ---
            Text(
              'Quiz Complete!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your Score: ${attempt.score} / ${attempt.total}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),

            // --- 2. Detailed Feedback List ---
            const Text(
              'Detailed Feedback',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: attempt.questions.length,
              itemBuilder: (context, index) {
                final q = attempt.questions[index];
                final userAnswer = attempt.userAnswers[q.id];
                final isCorrect =
                    userAnswer?.toLowerCase().trim() ==
                    q.answer.toLowerCase().trim();

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  // Simple color coding (won't reflect AI-marked 'YES' answers)
                  color: isCorrect ? Colors.green[50] : Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${index + 1}: ${q.questionText}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your Answer: $userAnswer',
                          style: TextStyle(
                            color: isCorrect
                                ? Colors.green[800]
                                : Colors.red[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!isCorrect) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Correct Answer: ${q.answer}',
                            style: TextStyle(
                              color: Colors.blue[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (q.explanation != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: Text(
                              'Explanation: ${q.explanation}',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: () {
              // Pop back to the main Quiz Page
              Navigator.pop(context);
            },
            child: const Text('Back to Quiz Home'),
          ),
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
              'Hello! Saya pembantu pembelajaran AI anda.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Tanyalah saya tentang: Pengaturcaraan Java!',
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
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.lightBlue,
              radius: 16,
              child: const Text(
                'AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.lightBlue[50] : Colors.grey[100],
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
                        const Icon(
                          Icons.schedule,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${message.responseTime}ms',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
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
                    hintText: 'Tanyalah saya tentang: Pengaturcaraan Java...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: isLoading
                          ? null
                          : () => _sendMessage(controller),
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
                            content: Text(
                              'Thanks! You rated the bot $s star(s).',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                ],
              ),

              // --- Stop Conversation Button ---
              IconButton(
                icon: const Icon(
                  Icons.stop_circle,
                  color: Colors.red,
                  size: 32,
                ),
                tooltip: 'End Conversation',
                onPressed: () {
                  context.read<ChatBloc>().add(ClearChatEvent());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Perbualan telah tamat. Memulakan semula'),
                    ),
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

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.responseTime,
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

class LoadChatHistoryEvent extends ChatEvent {}

// Chat BLoC Implementation
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final List<ChatMessage> _messages = [];
  final List<Content> _conversationHistory = [];
  late final GenerativeModel _model;

  ChatBloc() : super(ChatInitial()) {
    // Initialize the Gemini API
    final googleAI = FirebaseAI.googleAI();

    // ✅ FIXED: Use _model instead of aiModel
    _model = googleAI.generativeModel(
      model: 'gemini-2.5-flash',
      systemInstruction: Content.system(
        'You are a helpful AI tutor specializing in Java programming for Malaysian students. '
        'Answer questions about Java concepts, syntax, OOP principles, and help with coding problems. '
        'Keep responses clear, educational, and supportive. You can respond in both English and Bahasa Malaysia.',
      ),
    );

    on<SendMessageEvent>(_onSendMessage);
    on<ClearChatEvent>(_onClearChat);
    on<LoadWelcomeEvent>(_onLoadWelcome);
    on<LoadChatHistoryEvent>(_onLoadChatHistory);

    // Initialize with welcome message
    add(const LoadWelcomeEvent());

    // Load chat history on initialization
    add(LoadChatHistoryEvent());
  }

  void _onLoadWelcome(LoadWelcomeEvent event, Emitter<ChatState> emit) {
    _messages.add(
      ChatMessage(
        text:
            "Hello! Saya pembantu pembelajaran AI anda. Tanyalah saya tentang Pengaturcaraan Java!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
    emit(ChatLoaded(messages: List.from(_messages)));
  }

  // ✅ ADD: Load chat history from Firestore
  Future<void> _onLoadChatHistory(
    LoadChatHistoryEvent event,
    Emitter<ChatState> emit,
  ) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      emit(const ChatLoaded(messages: []));
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('timestamp', descending: false)
          .get();

      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          text: data['message'] ?? '',
          isUser: data['isUser'] ?? false,
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      _messages.clear();
      _messages.addAll(messages);

      if (_messages.isEmpty) {
        _messages.add(
          ChatMessage(
            text:
                "Hello! Saya pembantu pembelajaran AI anda. Tanyalah saya tentang Pengaturcaraan Java!",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      }

      emit(ChatLoaded(messages: List.from(_messages)));
    } catch (e) {
      print('Error loading chat history: $e');
      emit(ChatError(error: e.toString()));
    }
  }

  // ✅ MODIFY _onSendMessage to save to Firestore:
  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (event.message.trim().isEmpty) return;

    final stopwatch = Stopwatch()..start();
    final user = firebase_auth.FirebaseAuth.instance.currentUser;

    try {
      // Add user message immediately
      _messages.add(
        ChatMessage(
          text: event.message,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );

      // ✅ Save user message to Firestore
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('chat_history')
            .add({
              'message': event.message,
              'isUser': true,
              'timestamp': FieldValue.serverTimestamp(),
            });
      }

      _conversationHistory.add(Content.text(event.message));

      emit(const ChatLoading());

      final response = await _model.generateContent(_conversationHistory);

      stopwatch.stop();

      final responseText =
          response.text ??
          "Maaf, saya tidak dapat memahami pertanyaan anda. Cuba tanya dengan cara lain.";

      _conversationHistory.add(Content.model([TextPart(responseText)]));

      // Add bot response to messages
      _messages.add(
        ChatMessage(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
          responseTime: stopwatch.elapsedMilliseconds,
        ),
      );

      // ✅ Save bot response to Firestore
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('chat_history')
            .add({
              'message': responseText,
              'isUser': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
      }

      emit(
        ChatLoaded(
          messages: List.from(_messages),
          responseTime: stopwatch.elapsedMilliseconds,
        ),
      );
    } catch (e) {
      print('Error calling Gemini API: $e');

      _messages.add(
        ChatMessage(
          text: "Maaf, saya menghadapi ralat: ${e.toString()}. Sila cuba lagi.",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );

      emit(ChatError(error: e.toString()));

      await Future.delayed(const Duration(milliseconds: 100));
      emit(ChatLoaded(messages: List.from(_messages)));
    }
  }

  // ✅ MODIFY _onClearChat to delete from Firestore:
  void _onClearChat(ClearChatEvent event, Emitter<ChatState> emit) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Delete all chat history from Firestore
        final batch = FirebaseFirestore.instance.batch();
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('chat_history')
            .get();

        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      } catch (e) {
        print('Error clearing chat history: $e');
      }
    }

    _messages.clear();
    _conversationHistory.clear();

    _messages.add(
      ChatMessage(
        text:
            "Hello! Saya pembantu pembelajaran AI anda. Tanyalah saya apa sahaja tentang Pengaturcaraan Java!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
    emit(ChatLoaded(messages: List.from(_messages)));
  }
}

// Progress Page
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class ProgressRecord {
  final String id;
  final String student;
  final String activity;
  final double score;
  final String grade;
  final String comments;
  final Timestamp? timestamp;

  ProgressRecord({
    required this.id,
    required this.student,
    required this.activity,
    required this.score,
    required this.grade,
    required this.comments,
    required this.timestamp,
  });

  factory ProgressRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProgressRecord(
      id: doc.id,
      student: data['student'] ?? '',
      activity: data['activity'] ?? '',
      score: (data['score'] ?? 0).toDouble(),
      grade: data['grade'] ?? '',
      comments: data['comments'] ?? '',
      timestamp: data['timestamp'] as Timestamp?,
    );
  }
}

class _ProgressPageState extends State<ProgressPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _activityController = TextEditingController();
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  String? _selectedStudentUsername;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final snapshot = await _fs
          .collection('users')
          .where('userType', isEqualTo: 'UserType.student')
          .get();

      final results = snapshot.docs
          .where((doc) {
            final username = (doc.data()['username'] ?? '').toLowerCase();
            return username.contains(query.toLowerCase());
          })
          .map((doc) => {
                'id': doc.id,
                'username': doc['username'],
              })
          .toList();

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User search failed: $e')),
      );
    }
  }

  Future<void> _addProgress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentUsername == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student first')),
      );
      return;
    }

    try {
      final record = {
        'student': _selectedStudentUsername,
        'activity': _activityController.text.trim(),
        'score': double.tryParse(_scoreController.text) ?? 0,
        'grade': _gradeController.text.trim(),
        'comments': _commentsController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _fs.collection('progress_records').add(record);

      _activityController.clear();
      _scoreController.clear();
      _gradeController.clear();
      _commentsController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress added successfully'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add progress: $e')));
    }
  }

  Future<void> _confirmAndDelete(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _fs.collection('progress_records').doc(docId).delete();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  void _showEditDialog(ProgressRecord record) {
    final activityCtl = TextEditingController(text: record.activity);
    final scoreCtl = TextEditingController(text: record.score.toString());
    final gradeCtl = TextEditingController(text: record.grade);
    final commentsCtl = TextEditingController(text: record.comments);

    final editFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Progress'),
        content: Form(
          key: editFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Student: ${record.student}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextFormField(
                controller: activityCtl,
                decoration: const InputDecoration(labelText: 'Activity', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Enter activity' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: scoreCtl,
                decoration: const InputDecoration(labelText: 'Score', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? 'Enter score' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: gradeCtl,
                decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Enter grade' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: commentsCtl,
                decoration: const InputDecoration(labelText: 'Comments', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Save'),
            onPressed: () async {
              if (!(editFormKey.currentState?.validate() ?? false)) return;

              await _fs.collection('progress_records').doc(record.id).update({
                'activity': activityCtl.text.trim(),
                'score': double.tryParse(scoreCtl.text) ?? 0,
                'grade': gradeCtl.text.trim(),
                'comments': commentsCtl.text.trim(),
              });

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record updated')));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();
    final currentUser = userState.currentUser;
    final isTeacher = currentUser?.userType == UserType.teacher;
    final currentUsername = currentUser?.username;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Progress'),
        actions: [
          if (isTeacher)
            TextButton.icon(
              icon: const Icon(Icons.history, color: Colors.white),
              label: const Text('Progress History', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProgressHistoryPage()),
              ),
            ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isTeacher) ...[
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search student (username)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _searchUsers,
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (_, i) {
                            final u = _searchResults[i];
                            return ListTile(
                              title: Text(u['username']),
                              onTap: () {
                                setState(() {
                                  _selectedStudentUsername = u['username'];
                                  _searchController.text = u['username'];
                                  _searchResults.clear();
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    if (_selectedStudentUsername != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Text('Selected: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_selectedStudentUsername!, style: const TextStyle(color: Colors.blue)),
                            const Spacer(),
                            TextButton(
                              child: const Text('Clear'),
                              onPressed: () {
                                setState(() {
                                  _selectedStudentUsername = null;
                                  _searchController.clear();
                                });
                              },
                            )
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _activityController,
                      decoration: const InputDecoration(
                        labelText: 'Activity',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter activity' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _scoreController,
                      decoration: const InputDecoration(
                        labelText: 'Score',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Please enter score' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _gradeController,
                      decoration: const InputDecoration(
                        labelText: 'Grade',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter grade' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _commentsController,
                      decoration: const InputDecoration(
                        labelText: 'Comments',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      onPressed: _addProgress,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Progress'),
                    ),

                    const Divider(height: 30),
                  ],
                ),
              ),
            ],

            if (!isTeacher) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: const [
                      Icon(Icons.school, size: 60, color: Colors.blue),
                      SizedBox(height: 12),
                      Text('Your Progress Records', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Below are progress records your teacher has added for you.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                isTeacher ? 'Latest Records' : 'Your Progress Records',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            StreamBuilder<QuerySnapshot>(
              stream: isTeacher
              ? _fs.collection('progress_records').limit(3).snapshots()
              : _fs
              .collection('progress_records')
              .where('student', isEqualTo: currentUsername)
              .snapshots(),


              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Text(isTeacher ? 'No recent records' : 'No progress records');
                }

                final records = docs.map((d) => ProgressRecord.fromDoc(d)).toList();

                return Column(
                  children: records.map((r) {
                    return Card(
                      child: ListTile(
                        title: Text('${r.student} — ${r.activity}'),
                        subtitle: Text('Score: ${r.score}, Grade: ${r.grade}\n${r.comments}'),
                        isThreeLine: true,
                        trailing: isTeacher
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showEditDialog(r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _confirmAndDelete(r.id),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// --------------------------
///     PROGRESS HISTORY PAGE
///  (TEACHER ONLY ACCESS)
/// --------------------------
class ProgressHistoryPage extends StatelessWidget {
  const ProgressHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();
    final currentUser = userState.currentUser;
    final isTeacher = currentUser?.userType == UserType.teacher;
    final currentUsername = currentUser?.username;

    if (!isTeacher) {
      return const Scaffold(
        body: Center(child: Text('You are not allowed to view this page')),
      );
    }

    final FirebaseFirestore fs = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress History')),
      body: StreamBuilder<QuerySnapshot>(
        stream: fs.collection('progress_records').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final records = snap.data!.docs.map((d) => ProgressRecord.fromDoc(d)).toList();
          if (records.isEmpty) {
            return const Center(child: Text('No progress records found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (_, i) {
              final r = records[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text('${r.student} — ${r.activity}'),
                  subtitle: Text('Score: ${r.score}, Grade: ${r.grade}\n${r.comments}'),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------- Achievements ----------

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  // Helper function to get the correct achievement stream
  /* Stream<QuerySnapshot> getAchievementStream(AppUser? user) {
    var query = FirebaseFirestore.instance
        .collection('achievements')
        .orderBy('dateEarned', descending: true);

    // Filter to show only the current user's achievements if logged in, otherwise show public feed
    if (user != null) {
      query = query.where('studentId', isEqualTo: user.id);
    } else {
      // If not logged in, show a public feed of recent achievements (limited for performance)
      query = query.limit(30);
    }
    return query.snapshots();
  }*/

  Stream<QuerySnapshot> getAchievementStream(AppUser? user) {
    var query = FirebaseFirestore.instance.collection('achievements');

    if (user != null && user.userType == UserType.student) {
      // Student view: show only their achievements
      return query.where('studentId', isEqualTo: user.id).snapshots();
    } else if (user != null && user.userType == UserType.teacher) {
      // Teacher view: show all achievements
      return query.orderBy('dateEarned', descending: true).snapshots();
    } else {
      // Public feed with ordering (single field index is auto-created)
      return query
          .orderBy('dateEarned', descending: true)
          .limit(30)
          .snapshots();
    }
  }

  // Function to delete an achievement (US012-03)
  Future<void> _deleteAchievement(
    String achievementId,
    String achievementTitle,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Achievement'),
        content: Text(
          'Are you sure you want to delete the achievement: "$achievementTitle"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('achievements')
            .doc(achievementId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Achievement "$achievementTitle" deleted.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete achievement: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ⚠️ Function to show edit dialog (US012-02)
  Future<void> _showEditAchievementDialog(
    Map<String, dynamic> achievement,
  ) async {
    final editFormKey = GlobalKey<FormState>();
    final TextEditingController titleController = TextEditingController(
      text: achievement['title'] ?? '',
    );
    final TextEditingController descriptionController = TextEditingController(
      text: achievement['description'] ?? '',
    );
    String type = achievement['type'] ?? 'Badge';
    final List<String> achievementTypes = [
      'Badge',
      'Certificate',
      'Milestone',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Achievement: ${achievement['studentName']}'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return SingleChildScrollView(
                child: Form(
                  key: editFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Student: ${achievement['studentName']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v!.isEmpty ? 'Enter a title' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: type,
                        items: achievementTypes
                            .map(
                              (type) => DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (newValue) =>
                            setState(() => type = newValue!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        validator: (v) =>
                            v!.isEmpty ? 'Enter a description' : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (editFormKey.currentState!.validate()) {
                  try {
                    // Update the existing achievement record in Firestore
                    await FirebaseFirestore.instance
                        .collection('achievements')
                        .doc(achievement['id'])
                        .update({
                          'title': titleController.text.trim(),
                          'type': type,
                          'description': descriptionController.text.trim(),
                          // Note: We are only updating the *record* here. Student profile badges (string list) remain unchanged.
                        });

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Achievement updated successfully.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update achievement: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rely exclusively on live FirebaseUserState
    final userState = context.watch<FirebaseUserState>();
    final isLoggedIn = userState.isLoggedIn;
    final user = userState.currentUser;
    final bool isTeacher = user?.userType == UserType.teacher ?? false;
    final bool isStudent = user?.userType == UserType.student ?? false;

    // Page title
    final String pageTitle = isLoggedIn
        ? '🏆 Achievements'
        : '🏅 Community Achievements';

    // If not logged in, show a simplified message (re-using old logic for non-logged-in state)
    if (!isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: Text(pageTitle),
          backgroundColor: Colors.amber,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'Please log in to view personalized achievements or community feed.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logic to show the 'unlocked message'
          if (userState.lastUnlockedMessage != null)
            Builder(
              builder: (ctx) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final msg = userState.lastUnlockedMessage;
                  if (msg != null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        backgroundColor: Colors.green,
                      ),
                    );
                    context
                        .read<FirebaseUserState>()
                        .consumeLastUnlockedMessage();
                  }
                });
                return const SizedBox.shrink();
              },
            ),

          Expanded(
            // Use live StreamBuilder
            child: StreamBuilder<QuerySnapshot>(
              stream: getAchievementStream(
                user,
              ), // Fetch achievements for current user
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading achievements: ${snapshot.error}',
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Map DocumentSnapshot list to Map list, including the document ID
                final achievements = snapshot.data!.docs
                    .map(
                      (doc) => {
                        'id': doc.id,
                        ...doc.data() as Map<String, dynamic>,
                      },
                    )
                    .toList();

                return _buildAchievementListView(
                  achievements,
                  isLoggedIn,
                  isTeacher,
                  user!.id,
                );
              },
            ),
          ),


if (isStudent && user!.badges.isNotEmpty)
  Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.amber[100]!, Colors.orange[100]!],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.amber, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber[700], size: 28),
            const SizedBox(width: 8),
            Text(
              'My Badge Collection (${user.badges.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.amber[900],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: user.badges.map((badge) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber[700], size: 18),
                  const SizedBox(width: 6),
                  Text(
                    badge,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber[900],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ),
  ),
          // Teacher Action Buttons (Only 'Add Achievement' remains, full width)
          if (isTeacher)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // 1. Add Achievement Button (now takes full width)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // ACTION ENABLED: Navigate to AddAchievementPage
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddAchievementPage(),
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

  

  Widget _buildAchievementListView(
    List<Map<String, dynamic>> achievements,
    bool isLoggedIn,
    bool isTeacher,
    String? currentUserId,
  ) {
    // Sort achievements manually by date
    achievements.sort((a, b) {
      final dateA = a['dateEarned'];
      final dateB = b['dateEarned'];
      if (dateA is Timestamp && dateB is Timestamp) {
        return dateB.toDate().compareTo(dateA.toDate());
      }
      return 0;
    });

    if (achievements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                isLoggedIn
                    ? 'You have no achievements yet. Start learning and completing quizzes!'
                    : 'No public achievements found.',
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
        final String? achievementId = achievement['id'] as String?;
        final String studentId = achievement['studentId'] ?? '';

        final dateEarned = achievement['dateEarned'];
        DateTime? when;
        if (dateEarned is Timestamp) when = dateEarned.toDate();

        final bool canEdit = isTeacher;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 4),
                if (!isLoggedIn || studentId != currentUserId)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      'Earned by: ${achievement['studentName'] ?? 'Unknown User'}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Chip(label: Text(type)),
                    const SizedBox(width: 8),
                    if (when != null)
                      Text(
                        'Earned: ${when.toLocal().toString().split(' ')[0]}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
            trailing: canEdit && achievementId != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _showEditAchievementDialog(achievement),
                        tooltip: 'Edit Achievement',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            _deleteAchievement(achievementId, title),
                        tooltip: 'Delete Achievement',
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

// ========== Add Achievement Page (LIVE FIREBASE IMPLEMENTATION) ==========
class AddAchievementPage extends StatefulWidget {
  const AddAchievementPage({super.key});

  // ⚠️ FIX: Removed duplicate createState function from the previous erroneous code.

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
  bool _isLoading = false; // Add loading state

  final List<String> _achievementTypes = [
    'Badge',
    'Certificate',
    'Milestone',
    'Other',
  ];

  // ⚠️ Function to fetch live student list from Firestore
  Future<List<AppUser>> _getStudentsList() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(
            'userType',
            isEqualTo: UserType.student.toString(),
          ) // FIX: Use enum.toString()
          .orderBy('username')
          .get();

      return snapshot.docs
          .map(
            (doc) =>
                AppUser.fromMap(doc.id, doc.data()),
          )
          .toList();
    } catch (e) {
      print("Error fetching student list: $e");
      // Fallback list when fetching live data fails (e.g., due to rules)
      return [
        AppUser(
          id: 'FALLBACK_1',
          username: 'LOAD_ERROR: John Doe',
          email: '',
          userType: UserType.student,
        ),
        AppUser(
          id: 'FALLBACK_2',
          username: 'LOAD_ERROR: Jane Smith',
          email: '',
          userType: UserType.student,
        ),
      ];
    }
  }

  // ⚠️ Function to submit the achievement to Firestore (Live Write)
  Future<void> _submitAchievement() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      if (_selectedStudentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a student.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _isLoading = true);

      try {
        // Get current logged-in teacher username
        final teacherUsername =
            context.read<FirebaseUserState>().currentUser?.username ??
            'System Admin';

        final achievementData = {
          'title': _title,
          'type': _type,
          'description': _description,
          'studentId': _selectedStudentId,
          'studentName': _selectedStudentName,
          'dateEarned': FieldValue.serverTimestamp(),
          'awardedBy': teacherUsername,
        };

        // Live write to Firestore
        await FirebaseFirestore.instance
            .collection('achievements')
            .add(achievementData);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Achievement "$_title" manually awarded to $_selectedStudentName.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to award achievement: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // 1. Student Selection Field (Uses Live Data)
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
                initialValue: _type,
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
                onPressed: _isLoading ? null : _submitAchievement,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _isLoading ? 'Awarding...' : 'Award Achievement',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Builds the student selection field using LIVE Firestore data
  Widget _buildStudentSelectionField() {
    return FutureBuilder<List<AppUser>>(
      future: _getStudentsList(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final studentList = snapshot.data ?? [];

        if (studentList.isEmpty) {
          return const Text(
            'Error loading students or no students found. Check Firestore rules and data.',
            style: TextStyle(color: Colors.red),
          );
        }

        final studentItems = studentList.map((user) {
          // Format: StudentName (FormLevel, ClassName)
          String displayText = user.username;
          List<String> details = [];
  
          if (user.formLevel != null && user.formLevel!.isNotEmpty) {
            details.add(user.formLevel!);
          }
          if (user.className != null && user.className!.isNotEmpty) {
          details.add(user.className!);
          }
  
          if (details.isNotEmpty) {
          displayText += ' (${details.join(', ')})';
          }
  
          return DropdownMenuItem<String>(
          value: user.id,
          child: Text(displayText),
          );
          }).toList();

        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Select Student to Award',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
          initialValue: _selectedStudentId,
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
              final selectedUser = studentList.cast<AppUser?>().firstWhere(
                (user) => user?.id == newValue,
                orElse: () => null,
              );
              _selectedStudentName = selectedUser?.username;
            });
          },
        );
      },
    );
  }
}

// ---------- Profile ----------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

 // Replace the _pickAndUploadProfilePicture function in ProfilePage class

Future<String?> _pickAndUploadProfilePicture(BuildContext context) async {
  try {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image == null) return null;

    // Show loading dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Uploading profile picture...'),
            ],
          ),
        ),
      );
    }

    // Get current user ID
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not logged in');
    }

    // Read image bytes
    final imageBytes = await image.readAsBytes();
    
    // Create unique filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = image.path.split('.').last;
    final fileName = 'profile_$timestamp.$extension';

    print('📤 Uploading profile picture...');
    print('   User ID: $userId');
    print('   File: $fileName');
    print('   Size: ${imageBytes.length} bytes');

    // Upload to Firebase Storage
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('profile_pictures')
        .child(userId)
        .child(fileName);

    final metadata = SettableMetadata(
      contentType: 'image/${extension == 'jpg' ? 'jpeg' : extension}',
      customMetadata: {
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    final uploadTask = await storageRef.putData(imageBytes, metadata);

    if (uploadTask.state != TaskState.success) {
      throw Exception('Upload failed');
    }

    // Get download URL
    final downloadUrl = await uploadTask.ref.getDownloadURL();
    
    print('✅ Profile picture uploaded successfully!');
    print('   URL: $downloadUrl');

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    return downloadUrl;

  } on FirebaseException catch (e) {
    print('❌ Firebase error: ${e.code} - ${e.message}');
    
    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return null;
    
  } catch (e) {
    print('❌ Upload error: $e');
    
    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return null;
  }
}

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<FirebaseUserState>();
    final user = userState.currentUser;

    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }
    final isTeacher = user.userType == UserType.teacher;

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
            ],
            onSelected: (value) {
              if (value == 'edit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage(),
                  ),
                );
              } else if (value == 'password') {
                _showChangePasswordDialog(context);
              } else if (value == 'delete') {
                _showDeleteDialog(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header Section with Profile Picture
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
                        // Profile picture with edit button
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              backgroundImage:
                                  user.profilePicture != null &&
                                      user.profilePicture!.isNotEmpty &&
                                      user.profilePicture!.startsWith('http')
                                  ? NetworkImage(user.profilePicture!)
                                  : null,
                              child:
                                  user.profilePicture == null ||
                                      user.profilePicture!.isEmpty ||
             !user.profilePicture!.startsWith('http')
          ? const Icon(Icons.person, size: 50, color: Colors.blue)
          : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: InkWell(
                                onTap: () async {
                                  final picturePath =
                                      await _pickAndUploadProfilePicture(
                                        context,
                                      );
                                  if (picturePath != null && context.mounted) {
                                    final success = await context
                                        .read<FirebaseUserState>()
                                        .updateUserProfile(
                                          profilePicture: picturePath,
                                        );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Profile picture updated!'
                                                : 'Failed to update picture',
                                          ),
                                          backgroundColor: success
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isTeacher ? 'Teacher' : 'Student',
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
                        // Common Info for Both Teacher and Student
                        _buildInfoCard(
                          icon: Icons.email,
                          title: 'Email',
                          value: user.email,
                        ),

                        // STUDENT-SPECIFIC FIELDS
                        if (!isTeacher) ...[
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

                          // Points Card (Students Only)
                          _buildInfoCard(
                            icon: Icons.stars,
                            title: 'Total Points',
                            value: user.points.toString(),
                            color: Colors.amber,
                          ),

                          // Badges Card (Students Only)
                          /*_buildInfoCard(
                            icon: Icons.emoji_events,
                            title: 'Badges Earned',
                            value: user.badges.length.toString(),
                            color: Colors.orange,
                          ),*/
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                              .collection('achievements')
                              .where('studentId', isEqualTo: user.id)
                              .snapshots(),
                            builder: (context, snapshot) {
                            int totalAchievements = 0;
                            if (snapshot.hasData) {
                              totalAchievements = snapshot.data!.docs.length;
                            }
                            
                            return _buildInfoCard(
                            icon: Icons.emoji_events,
                            title: 'Total Achievements',
                            value: totalAchievements.toString(),
                            color: Colors.orange,
                            );
                          },
                        ),

                          /*// Completion Level (Students Only)
                          _buildInfoCard(
                            icon: Icons.trending_up,
                            title: 'Completion Level',
                            value:
                                '${(user.completionLevel * 100).toStringAsFixed(1)}%',
                            color: Colors.green,
                          ),*/
                         /* if (user.badges.isNotEmpty) ...[
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
                                              avatar: const Icon(
                                                Icons.emoji_events,
                                                size: 16,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],*/

                          // ✅ NEW: All Achievements Display (Badges, Certificates, Milestones)
const SizedBox(height: 16),
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('achievements')
      .where('studentId', isEqualTo: user.id)
      .orderBy('dateEarned', descending: true)
      .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.emoji_events_outlined, 
                size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'No achievements yet',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Start completing quizzes to earn badges!',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final achievements = snapshot.data!.docs;
    
    // Group achievements by type
    final badges = achievements.where((doc) => 
      doc['type']?.toString().toLowerCase().contains('badge') ?? false
    ).toList();
    
    final certificates = achievements.where((doc) => 
      doc['type']?.toString().toLowerCase().contains('certificate') ?? false
    ).toList();
    
    final milestones = achievements.where((doc) => 
      doc['type']?.toString().toLowerCase().contains('milestone') ?? false
    ).toList();
    
    final others = achievements.where((doc) {
      final type = doc['type']?.toString().toLowerCase() ?? '';
      return !type.contains('badge') && 
             !type.contains('certificate') && 
             !type.contains('milestone');
    }).toList();

    return Column(
      children: [
        // Badges Section
        if (badges.isNotEmpty)
          _buildAchievementSection(
            title: '🏅 Badges (${badges.length})',
            achievements: badges,
            color: Colors.amber,
            icon: Icons.star,
          ),
        
        // Certificates Section
        if (certificates.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildAchievementSection(
            title: '📜 Certificates (${certificates.length})',
            achievements: certificates,
            color: Colors.blue,
            icon: Icons.workspace_premium,
          ),
        ],
        
        // Milestones Section
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildAchievementSection(
            title: '🎯 Milestones (${milestones.length})',
            achievements: milestones,
            color: Colors.purple,
            icon: Icons.flag,
          ),
        ],
        
        // Others Section
        if (others.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildAchievementSection(
            title: '⭐ Other Achievements (${others.length})',
            achievements: others,
            color: Colors.green,
            icon: Icons.emoji_events,
          ),
        ],
      ],
    );
  },
),

                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ NEW: Logout button at the bottom
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () => _handleLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Logout', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Keep the logout handler function as is
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
          ElevatedButton(
            onPressed: () async {
              await context.read<FirebaseUserState>().logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    Color? color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: color ?? Colors.blue[700]),
        title: Text(title),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
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
                validator: (value) => value == null || value.isEmpty
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
                validator: (value) => value != newPasswordController.text
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
                            : userState.errorMessage ??
                                  'Failed to change password',
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
              final success = await userState.deleteAccount(
                passwordController.text,
              );
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
}

// ✅ NEW: Helper method to build achievement sections
Widget _buildAchievementSection({
  required String title,
  required List<QueryDocumentSnapshot> achievements,
  required Color color,
  required IconData icon,
}) {
  return Card(
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: achievements.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final achievementTitle = data['title'] ?? 'Achievement';
              final dateEarned = data['dateEarned'];
              DateTime? earnedDate;
              if (dateEarned is Timestamp) {
                earnedDate = dateEarned.toDate();
              }

              return Tooltip(
                message: data['description'] ?? achievementTitle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(
                            achievementTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: color.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                      if (earnedDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${earnedDate.day}/${earnedDate.month}/${earnedDate.year}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
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
      className: _classNameController.text.trim().isEmpty
          ? null
          : _classNameController.text.trim(),
      formLevel: _selectedFormLevel,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userState.errorMessage ?? 'Update failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FirebaseUserState>().currentUser!;
    final userState = context.watch<FirebaseUserState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update Your Information',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  if (value.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: ['Form 4', 'Form 5']
                      .map(
                        (level) =>
                            DropdownMenuItem(value: level, child: Text(level)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedFormLevel = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class Name',
                    prefixIcon: const Icon(Icons.class_),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: userState.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16),
                        ),
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

  Future<void> checkStorageConfiguration() async {
  try {
    final ref = FirebaseStorage.instance.ref().child('learning_materials');
    await ref.listAll();
    print('✅ Storage configuration OK');
  } catch (e) {
    print('❌ Storage error: $e');
  }
}

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
    return _db
        .collection('materials')
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
              })
              .toList();
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
  const MaterialsPage({super.key});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class 
_MaterialsPageState extends State<MaterialsPage> {
  String searchQuery = '';
  String userType = 'UserType.student'; // default

Future<void> _downloadFile(BuildContext context, LearningMaterial material) async {
  final filePath = material.file;

  // Handle local files
  if (!filePath.startsWith('http')) {
    try {
      final File sourceFile = File(filePath);
      if (!sourceFile.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Local file not found.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await OpenFile.open(sourceFile.path);
      return;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      return;
    }
  }

  // ✅ Request storage permission for Android
  if (Platform.isAndroid) {
    // Check Android version
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    
    if (androidInfo.version.sdkInt >= 30) {
      // Android 11+ (API 30+) - Request MANAGE_EXTERNAL_STORAGE
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to download files.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    } else {
      // Android 10 and below - Request regular storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission denied.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }
  }

  try {
    // Show loading
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Downloading...'),
            ],
          ),
        ),
      );
    }

    // Get filename
    final Uri uri = Uri.parse(filePath);
    String fileName = uri.pathSegments.last.split('?').first;
    fileName = Uri.decodeComponent(fileName);
    
    if (fileName.contains('learning_materials/')) {
      fileName = fileName.split('learning_materials/').last;
    }
    if (fileName.contains('_') && int.tryParse(fileName.split('_')[0]) != null) {
      fileName = fileName.split('_').sublist(1).join('_');
    }

    // ✅ Save to Downloads folder
    Directory? downloadDir;
    if (Platform.isAndroid) {
      downloadDir = Directory('/storage/emulated/0/Download');
      if (!downloadDir.existsSync()) {
        downloadDir = await getExternalStorageDirectory();
      }
    } else {
      downloadDir = await getApplicationDocumentsDirectory();
    }

    final String savePath = '${downloadDir!.path}/$fileName';
    final File downloadFile = File(savePath);

    // Download from Firebase
    final ref = FirebaseStorage.instance.refFromURL(filePath);
    await ref.writeToFile(downloadFile);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded to: ${downloadDir.path}/$fileName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OPEN',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(downloadFile.path),
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _migrateToCloud(BuildContext context, LearningMaterial material) async {
  if (material.file.startsWith('http')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This file is already in the cloud.')),
    );
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Migrate to Cloud Storage'),
      content: const Text(
        'This will upload the local file to Firebase Storage so all users can download it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Upload'),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Uploading to cloud...'),
          ],
        ),
      ),
    );

    final file = File(material.file);
    
    if (!file.existsSync()) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local file not found. Please re-upload this material.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final storageRef = FirebaseStorage.instance.ref().child('learning_materials/$fileName');
    
    final uploadTask = await storageRef.putFile(file);
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    // Update Firestore with new URL
    final updatedMaterial = LearningMaterial(
      id: material.id,
      name: material.name,
      description: material.description,
      file: downloadUrl,
      time: material.time,
    );

    await context.read<MaterialAppState>().editMaterial(updatedMaterial);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully migrated to cloud storage!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Migration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
  /*Future<void> _downloadFile(BuildContext context, LearningMaterial material) async {
  final downloadUrl = material.file;

  // ✅ Check if it's a valid URL
  if (!downloadUrl.startsWith('http')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error: This file is stored locally and cannot be downloaded.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  // 1. Check/Request Permission
  PermissionStatus status = PermissionStatus.granted;
  if (Platform.isAndroid || Platform.isIOS) {
    status = await Permission.storage.request();
  }
  
  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Storage permission denied. Cannot download.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  try {
    // 2. Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Downloading...'),
          ],
        ),
      ),
    );

    // 3. Get file name from URL
    final Uri uri = Uri.parse(downloadUrl);
    String fileName = uri.pathSegments.last.split('?').first;
    
    // Decode URL-encoded filename
    fileName = Uri.decodeComponent(fileName);
    
    // If filename still contains path, extract just the name
    if (fileName.contains('learning_materials%2F')) {
      fileName = fileName.split('learning_materials%2F').last;
    }
    if (fileName.contains('learning_materials/')) {
      fileName = fileName.split('learning_materials/').last;
    }

    // 4. Determine save location
    final Directory tempDir = await getApplicationDocumentsDirectory();
    final String savePath = '${tempDir.path}/$fileName';
    final File downloadFile = File(savePath);

    // 5. Download file from Firebase Storage
    final ref = FirebaseStorage.instance.refFromURL(downloadUrl);
    await ref.writeToFile(downloadFile);

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    // 6. Confirm download and offer to open
    if (downloadFile.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () async {
                final result = await OpenFile.open(downloadFile.path);
                if (result.type != ResultType.done) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot open this file type'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    }
  } on FirebaseException catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}*/

  @override
  void initState() {
    super.initState();
    final appState = context.read<MaterialAppState>();
    appState.createMaterialsCollection();
    appState.checkStorageConfiguration();
    fetchUserType();
  }

  void fetchUserType() async {
    final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists) {
      setState(() {
        // Updated retrieval to be safer and match stored value (which is a string)
        userType =
            doc.data()?['userType'] as String? ?? UserType.student.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MaterialAppState>();
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Learning Materials')),
      floatingActionButton: userType == UserType.teacher.toString()
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UploadPage()),
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
              },
              tooltip: 'Add',
              child: const Icon(Icons.add),
            )
          : null,
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
                      .where(
                        (m) =>
                            m.name.toLowerCase().contains(searchQuery) ||
                            m.description.toLowerCase().contains(searchQuery),
                      )
                      .toList();

                  if (materials.isEmpty) {
                    return const Center(
                      child: Text('No materials match your search.'),
                    );
                  }

                  return ListView.builder(
                    itemCount: materials.length,
                    itemBuilder: (context, index) {
                      final material = materials[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            Icons.file_present,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(material.name),
                          subtitle: Text(
                            '${material.description}\nUploaded At: ${material.time}',
                          ),
                          onTap: () async {
                            if (material.file.startsWith('http')) {
                              // It's a URL
                              final url = Uri.parse(material.file);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cannot open file URL.'),
                                  ),
                                );
                              }
                            } else {
                              // It's a local file path
                              /*final result = await OpenFile.open(material.file);
                              if (result.type != ResultType.done) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cannot open local file.'),
                                  ),
                                );
                              }
                            }*/

                            final result = await OpenFile.open(material.file);
                              if (result.type != ResultType.done) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('File not found or cannot be opened. Use the download button if it is a cloud file.'),
                                  ),
                                );
                              }
                            }
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // NEW: Dedicated Download Button for all users
                              IconButton(
                                icon: const Icon(Icons.download, color: Colors.green),
                                tooltip: 'Download File',
                                onPressed: () => _downloadFile(context, material),
                              ),
  
                           if (userType == UserType.teacher.toString())
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                          existingMaterial: material,
                        ),
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
                  } else if (value == 'migrate') {
        await _migrateToCloud(context, material);
      } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Confirmation'),
                        content: const Text(
                          'Are you sure you want to delete this material?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await appState.deleteMaterial(material.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Material deleted successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
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
  PlatformFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    if (widget.existingMaterial != null) {
      name = widget.existingMaterial!.name;
      description = widget.existingMaterial!.description;
      filePath = widget.existingMaterial!.file;
    }
  }

  // ✅ FIXED: Proper file picker
  Future<void> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFile = result.files.first;
          filePath = _pickedFile!.path; // For display purposes
        });
        
        print('✅ File picked: ${_pickedFile!.name}');
        print('   Size: ${_pickedFile!.size} bytes');
      }
    } catch (e) {
      print('❌ File picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ FIXED: Proper content type detection
  String _getContentType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  // ✅ FIXED: Proper file upload with error handling
  Future<void> submit(BuildContext context) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    
    final isEditing = widget.existingMaterial != null;
    
    // Check if file is required for new uploads
    if (!isEditing && _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file to upload.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _formKey.currentState!.save();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Update Material' : 'Upload Material'),
        content: Text(
          isEditing
              ? 'Update this learning material?'
              : 'Upload this new material? File: ${_pickedFile?.name ?? "Unknown"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Uploading file to cloud storage...'),
            ],
          ),
        ),
      );

      String downloadUrl;

      // If editing and no new file selected, keep existing URL
      if (isEditing && _pickedFile == null && widget.existingMaterial!.file.startsWith('http')) {
        downloadUrl = widget.existingMaterial!.file;
      } else if (_pickedFile != null) {
        // Get file bytes
        Uint8List? fileBytes;
        
        if (kIsWeb) {
          fileBytes = _pickedFile!.bytes;
        } else {
          if (_pickedFile!.path != null) {
            final file = File(_pickedFile!.path!);
            if (!await file.exists()) {
              throw Exception('Selected file does not exist on device');
            }
            fileBytes = await file.readAsBytes();
          }
        }

        if (fileBytes == null || fileBytes.isEmpty) {
          throw Exception('Could not read file data');
        }

        print('📤 Uploading file: ${_pickedFile!.name}');
        print('   Size: ${fileBytes.length} bytes');

        // Clean filename - remove special characters
        String cleanFileName = _pickedFile!.name
            .replaceAll(RegExp(r'[^\w\s\-\.]'), '_')
            .replaceAll(RegExp(r'\s+'), '_');
        
        // Create unique filename with timestamp
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = '${timestamp}_$cleanFileName';

        print('   Clean name: $fileName');
        print('   Storage path: learning_materials/$fileName');

        // Get storage reference - CRITICAL: Ensure correct path
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('learning_materials')
            .child(fileName);

        // Create metadata
        final metadata = SettableMetadata(
          contentType: _getContentType(_pickedFile!.name),
          customMetadata: {
            'originalName': _pickedFile!.name,
            'uploadedBy': firebase_auth.FirebaseAuth.instance.currentUser?.email ?? 'unknown',
            'uploadedById': firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'uploadTimestamp': DateTime.now().toIso8601String(),
          },
        );

        print('🚀 Starting upload...');

        // Upload file
        final uploadTask = await storageRef.putData(fileBytes, metadata);

        print('   Upload state: ${uploadTask.state}');
        print('   Bytes: ${uploadTask.bytesTransferred}/${uploadTask.totalBytes}');

        if (uploadTask.state != TaskState.success) {
          throw Exception('Upload failed with state: ${uploadTask.state}');
        }

        // Get download URL
        downloadUrl = await uploadTask.ref.getDownloadURL();
        print('✅ Upload successful!');
        print('   Download URL: $downloadUrl');
      } else {
        throw Exception('No file selected for upload');
      }

      // Save to Firestore
      final appState = context.read<MaterialAppState>();
      final newMaterial = LearningMaterial(
        id: widget.existingMaterial?.id ?? '',
        name: name,
        description: description,
        file: downloadUrl,
        time: DateTime.now(),
      );

      if (isEditing) {
        await appState.editMaterial(newMaterial);
      } else {
        await appState.addMaterial(newMaterial);
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.pop(context, {
          'success': true,
          'message': isEditing
              ? 'Material updated successfully!'
              : 'Material uploaded successfully!',
        });
      }
    } on FirebaseException catch (e) {
      print('❌ Firebase error: ${e.code}');
      print('   Message: ${e.message}');
      print('   Plugin: ${e.plugin}');

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        String errorMessage = 'Upload failed: ${e.message ?? e.code}';

        // Specific error handling
        switch (e.code) {
          case 'object-not-found':
            errorMessage = '❌ Storage bucket not found.\n\n'
                'Solutions:\n'
                '1. Check Firebase Storage is enabled\n'
                '2. Verify storage rules are deployed\n'
                '3. Ensure learning_materials folder exists';
            break;
          case 'unauthorized':
          case 'permission-denied':
            errorMessage = '❌ Permission denied.\n\n'
                'You need teacher permissions to upload files.\n'
                'Contact admin if you should have access.';
            break;
          case 'unauthenticated':
            errorMessage = '❌ Not logged in.\n\n'
                'Please log in to upload files.';
            break;
          case 'quota-exceeded':
            errorMessage = '❌ Storage quota exceeded.\n\n'
                'Contact admin to upgrade storage plan.';
            break;
          case 'retry-limit-exceeded':
            errorMessage = '❌ Upload timeout.\n\n'
                'Check your internet connection and try again.';
            break;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ General upload error: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingMaterial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Material' : 'Upload Material'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Name field
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(
                  labelText: 'Material Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                onSaved: (v) => name = v?.trim() ?? '',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),

              // Description field
              TextFormField(
                initialValue: description,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                onSaved: (v) => description = v?.trim() ?? '',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
              ),
              const SizedBox(height: 16),

              // File picker
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File ${isEditing ? "(optional)" : "*"}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Choose File'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _pickedFile != null
                                  ? '✅ ${_pickedFile!.name}'
                                  : (filePath != null && filePath!.startsWith('http'))
                                      ? 'Current: Cloud file'
                                      : '⚠️  No file selected',
                              style: TextStyle(
                                color: _pickedFile != null
                                    ? Colors.green
                                    : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                      if (_pickedFile != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Size: ${(_pickedFile!.size / 1024 / 1024).toStringAsFixed(2)} MB',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Submit button
              ElevatedButton.icon(
                onPressed: () => submit(context),
                icon: Icon(isEditing ? Icons.save : Icons.cloud_upload),
                label: Text(
                  isEditing ? 'Update Material' : 'Upload Material',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/*class _UploadPageState extends State<UploadPage> {
  final _formKey = GlobalKey<FormState>();
  String name = '';
  String description = '';
  String? filePath;
  PlatformFile? _pickedFile;

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
  if (_pickedFile == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a file first.')),
    );
    return;
  }

  _formKey.currentState!.save();

  final appState = context.read<MaterialAppState>();
  final isEditing = widget.existingMaterial != null;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isEditing ? 'Edit Confirmation' : 'Upload Confirmation'),
      content: Text(
        isEditing
            ? 'Are you sure you want to update this material?'
            : 'Are you sure you want to upload this new material?',
      ),
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
      // Show loading dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Uploading file...'),
              ],
            ),
          ),
        );
      }

      String downloadUrl;
      
      // Check if we're editing and the file URL hasn't changed
      if (isEditing && 
          widget.existingMaterial!.file.startsWith('http') && 
          filePath == widget.existingMaterial!.name) {
        // If editing and file wasn't changed, keep the old URL
        downloadUrl = widget.existingMaterial!.file;
      } else {
        // Get file bytes (works on both mobile and web)
        final Uint8List? fileBytes = _pickedFile!.bytes ?? 
            (kIsWeb ? null : await File(_pickedFile!.path!).readAsBytes());
        
        if (fileBytes == null) {
          throw Exception('Could not read file data');
        }
        
        print('File size: ${fileBytes.length} bytes');
        
        // Clean filename
        String originalFileName = _pickedFile!.name;
        originalFileName = originalFileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
        
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalFileName';
        
        print('Cleaned filename: $fileName');
        print('Storage path: learning_materials/$fileName');
        
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('learning_materials')
            .child(fileName);
        
        // Upload with metadata - use putData for web compatibility  Future<void> submit(BuildContext context) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (_pickedFile == null && filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first.')),
      );
      return;
    }

    _formKey.currentState!.save();

    final appState = context.read<MaterialAppState>();
    final isEditing = widget.existingMaterial != null;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Confirmation' : 'Upload Confirmation'),
        content: Text(
          isEditing
              ? 'Are you sure you want to update this material?'
              : 'Are you sure you want to upload this new material?',
        ),
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
        // Show loading dialog
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Uploading file...'),
                ],
              ),
            ),
          );
        }

        String downloadUrl;

        // Check if editing and file wasn't changed
        if (isEditing && 
            widget.existingMaterial!.file.startsWith('http') && 
            _pickedFile == null) {
          downloadUrl = widget.existingMaterial!.file;
        } else {
          // Get file bytes (works on both mobile and web)
          Uint8List? fileBytes;
          
          if (kIsWeb) {
            // Web: use bytes directly from PlatformFile
            fileBytes = _pickedFile!.bytes;
          } else {
            // Mobile: read from file path
            if (_pickedFile!.path != null) {
              final file = File(_pickedFile!.path!);
              if (!await file.exists()) {
                throw Exception('Selected file does not exist');
              }
              fileBytes = await file.readAsBytes();
            }
          }

          if (fileBytes == null) {
            throw Exception('Could not read file data');
          }

          print('File size: ${fileBytes.length} bytes');

          // Clean filename
          String originalFileName = _pickedFile!.name;
          originalFileName = originalFileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');

          final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalFileName';

          print('Cleaned filename: $fileName');
          print('Storage path: learning_materials/$fileName');

          // Get storage reference
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('learning_materials')
              .child(fileName);

          // Upload with metadata - use putData for web compatibility
          final metadata = SettableMetadata(
            contentType: _getContentType(_pickedFile!.name),
            customMetadata: {
              'originalName': originalFileName,
              'uploadedBy': firebase_auth.FirebaseAuth.instance.currentUser?.email ?? 'unknown',
              'uploadTimestamp': DateTime.now().toIso8601String(),
            },
          );

          print('Starting upload...');

          // Use putData instead of putFile for web compatibility
          final TaskSnapshot uploadSnapshot = await storageRef.putData(fileBytes, metadata);

          print('Upload state: ${uploadSnapshot.state}');
          print('Bytes transferred: ${uploadSnapshot.bytesTransferred}/${uploadSnapshot.totalBytes}');

          if (uploadSnapshot.state == TaskState.success) {
            downloadUrl = await uploadSnapshot.ref.getDownloadURL();
            print('Upload successful! Download URL: $downloadUrl');
          } else {
            throw Exception('Upload did not complete successfully. State: ${uploadSnapshot.state}');
          }
        }

        // Create material object with Firebase Storage URL
        final newMaterial = LearningMaterial(
          id: widget.existingMaterial?.id ?? '',
          name: name,
          description: description,
          file: downloadUrl,
          time: DateTime.now(),
        );

        if (isEditing) {
          await appState.editMaterial(newMaterial);
        } else {
          await appState.addMaterial(newMaterial);
        }

        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog
          Navigator.pop(context, {
            'success': true,
            'message': isEditing
                ? 'Material updated successfully!'
                : 'Material uploaded successfully!',
          });
        }
      } on FirebaseException catch (e) {
        print('Firebase error code: ${e.code}');
        print('Firebase error message: ${e.message}');
        print('Firebase error plugin: ${e.plugin}');

        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog

          String errorMessage = 'Upload failed: ${e.message ?? e.code}';

          if (e.code == 'object-not-found') {
            errorMessage = 'Upload failed: Please check your Firebase Storage rules.\n\nError: ${e.message}';
          } else if (e.code == 'unauthorized') {
            errorMessage = 'Upload failed: You do not have permission to upload files.';
          } else if (e.code == 'unauthenticated') {
            errorMessage = 'Upload failed: You must be logged in to upload files.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 7),
            ),
          );
        }
      } catch (e, stackTrace) {
        print('General upload error: $e');
        print('Stack trace: $stackTrace');
        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 7),
            ),
          );
        }
      }
    }
  }

// Helper method to determine content type
String _getContentType(String filePath) {
  final extension = filePath.split('.').last.toLowerCase();
  switch (extension) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'txt':
      return 'text/plain';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    default:
      return 'application/octet-stream';
  }
}
    
    /*catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}*/

  /*Future<void> submit(BuildContext context) async {
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
        content: Text(
          isEditing
              ? 'Are you sure you want to update this material?'
              : 'Are you sure you want to upload this new material?',
        ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }*/

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingMaterial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Learning Material' : 'Upload Learning Material',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                onSaved: (v) => name = v ?? '',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                initialValue: description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onSaved: (v) => description = v ?? '',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter a description' : null,
              ),
              const SizedBox(height: 15),
              /*Row(
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
              ),*/
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
            ? (filePath!.startsWith('http') 
                ? 'Cloud file (click to change)' 
                : filePath!.split('/').last)
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
}*/
