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
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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

// ========== APP USER ==========
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

  // ----- loadUserData -----
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

// ----- registerUser -----
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
    // ✅ CREATE USER FIRST
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

    // ✅ THEN SAVE TO FIRESTORE
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
  } catch (e) {
    // ✅ ADD GENERAL ERROR HANDLING
    _errorMessage = 'Registration failed: $e';
    print('Error during registration: $_errorMessage');
    _isLoading = false;
    notifyListeners();
    return false;
  }
}


  // ----- login -----
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

  // ----- logout -----
  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  // ----- updateUserProfile -----
  Future<bool> updateUserProfile({
    String? username,
    String? profilePicture,
    String? className,
    String? formLevel,
  }) async {
    if (_currentUser == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (username != null && username != _currentUser!.username) {
        final usernameQuery = await _firestore
            .collection('users')
            .where('username', isEqualTo: username)
            .limit(1)
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

  // ----- changePassword -----
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

  // ----- deleteAccount -----
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
    final snapshot = await _firestore
        .collection('users')
        .limit(50)  // ✅ Added explicit limit
        .get();
    
    return snapshot.docs
        .map((doc) => AppUser.fromMap(doc.id, doc.data()))
        .where(
          (user) => user.username.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  } catch (e) {
    print('❌ Search error: $e');
    return [];
  }
}

 // ----- filterUsers -----
Future<List<AppUser>> filterUsers({
  String? className,
  String? formLevel,
}) async {
  try {
    Query query = _firestore.collection('users').limit(50);  // ✅ Added limit
    
    if (className != null) {
      query = query.where('className', isEqualTo: className);
    }
    if (formLevel != null) {
      query = query.where('formLevel', isEqualTo: formLevel);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>),
        )
        .toList();
  } catch (e) {
    print('❌ Filter error: $e');
    return [];
  }
}

  // ----- addPoints -----
  Future<void> addPoints(int points) async {
    if (_currentUser == null) return;
    final newPoints = _currentUser!.points + points;
    await _firestore.collection('users').doc(_currentUser!.id).update({
      'points': newPoints,
    });
    _currentUser = _currentUser!.copyWith(points: newPoints);
    notifyListeners();
  }

  // ----- awardBadge -----
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
      title: '< > CodingBahasa',
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

// ========== LOGIN PAGE STATE ==========
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

  // ----- handleLogin -----
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

// ========== REGISTER PAGE STATE ==========
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

  // ----- handleRegister -----
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
          content: Text(userState.errorMessage ?? 'Registration failed!'),
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

// ========== IN HOME PAGE ==========
class InHomePage extends StatelessWidget {
  const InHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FirebaseUserState>().currentUser;

    // ----- navigateToPage -----
    void navigateToPage(int pageIndex) {
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
                // App Logo 
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

          // Stats Cards (Students Only)
          if (user?.userType == UserType.student) ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => navigateToPage(8), // Navigate to Achievements
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
                    onTap: () => navigateToPage(8), // Navigate to Achievements
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('achievements')
                          .where('studentId', isEqualTo: user.id)
                          .snapshots(),
                      builder: (context, snapshot) {
                        int badgeCount = 0;
                        
                        if (snapshot.hasData) {
                          badgeCount = snapshot.data!.docs.length;
                        }
                        
                        return _buildStatCard(
                          icon: Icons.emoji_events,
                          title: 'Awards',
                          value: badgeCount.toString(),
                          color: Colors.orange,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => navigateToPage(7), // Navigate to Progress
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
                title: 'Course',
                color: Colors.blue,
                onTap: () => navigateToPage(2),
              ),
              _buildQuickActionCard(
                icon: Icons.folder,
                title: 'Material',
                color: Colors.orange,
                onTap: () => navigateToPage(3),
              ),
              _buildQuickActionCard(
                icon: Icons.quiz,
                title: 'Quiz',
                color: Colors.purple,
                onTap: () => navigateToPage(4),
              ),
              _buildQuickActionCard(
                icon: Icons.chat,
                title: 'AI Chatbot',
                color: Colors.teal,
                onTap: () => navigateToPage(6),
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

// ========== HOME PAGE STATE ==========
class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const InHomePage();
      case 1:
        page = const UserSearchPage(); 
      case 2:
        page = CoursePage(); 
      case 3:
        page = const MaterialsPage();
      case 4:
        page = const QuizPage(); 
      case 5:
        page = const ForumPage();  
      case 6:
        page = const AIChatbotPage(); 
      case 7:
        page = const ProgressPage(); 
      case 8:
        page = const AchievementsPage();
      case 9:
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
            onPressed: () => setState(() => selectedIndex = 9),
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
                  _buildMenuButton('User', 1),
                  _buildMenuButton('Course', 2),
                  _buildMenuButton('Material', 3),
                  _buildMenuButton('Quiz', 4),
                  _buildMenuButton('Forum', 5),
                  _buildMenuButton('AI Chatbot', 6),
                  _buildMenuButton('Progress', 7),
                  _buildMenuButton('Achievement', 8),
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

// ========== USER SEARCH PAGE STATE ==========
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

  // ----- loadAllUsers -----
Future<void> _loadAllUsers() async {
  setState(() => _isLoading = true);
  final userState = context.read<FirebaseUserState>();
  final users = await userState.searchUserByName('');
  setState(() {
    _displayedUsers = users;
    _isLoading = false;
  });
}

// ----- searchUsers -----
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

  // ----- applyFilters -----
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

  // ----- clearFilters -----
  void _clearFilters() {
    setState(() {
      _filterClassName = null;
      _filterFormLevel = null;
      _searchController.clear();
    });
    _loadAllUsers();
  }

  // ----- showUserDetailsDialog -----
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

  // ----- showFilterDialog -----
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
      title: const Text('🔍 Search User'),
      backgroundColor: Colors.lightBlue,
      foregroundColor: Colors.white,
      actions: [
        // ✅ FIXED: Only teachers can see filter options
        if (currentUser?.userType == UserType.teacher) ...[
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
      ],
    ),
    body: Column(
      children: [
        // ✅ Search bar - ACCESSIBLE TO EVERYONE
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
        
        // ✅ FIXED: Filter chips only visible to teachers
        if (currentUser?.userType == UserType.teacher && 
            (_filterClassName != null || _filterFormLevel != null))
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
        
        // Results count - everyone can see
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
        
        // User list - everyone can see
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

// ========== COURSE PAGE ==========
const String _kDoneStatusKeyPrefix = 'course_status_done_';
class CoursePage extends StatefulWidget {
  const CoursePage({super.key});

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  final List<Map<String, String>> topics = const [
    {
      "title": "1.1 Strategi Penyelesaian Masalah",
      "note": """MASALAH
Keraguan, situasi yang tidak diingini, cabaran & peluang yang dihadapi dalam kehidupan seseorang. 

🤔 (4) MENGAPAKAH PERLUNYA STRATEGI DALAM PENYELESAIAN MASALAH?
• Meningkatkan kemahiran berfikir
• Membantu pengembangan sesuatu konsep
• Mewujudkan komunikasi dua hala
• Menggalakkan pembelajaran kendir

🛠️ PENYELESAIAN MASALAH
Proses mengkaji butiran sesuatu masalah untuk mendapatkan satu penyelesaian.

🧠 (4) TEKNIK PEMIKIRAN KOMPUTASIONAL
• Leraian – Memecahkan masalah kepada bahagian yang lebih kecil
• Pengecaman corak – Mencari persamaan antara masalah & dalam masalah
• Peniskalaan – Menjana penyelesaian yang tepat kepada masalah yang dihadapi
• Algoritma – Membangunkan penyelesaian langkah demi langkah terhadap masalah yang dihadapi

✅ (3) CIRI PENYELESAIAN MASALAH BERKESAN 
• Kos - Harga yang perlu dibayar untuk memperoleh, mengeluarkan & menyenggara
• Masa - Sesuatu projek yang disiapkan mengikut masa yang telah ditetapkan
• Sumber - Stok / wang, bahan-bahan mentah, staf & aset lain

📋 (8) PROSES PENYELESAIAN MASALAH
1. Mengumpulkan & menganalisis data
2. Menentukan masalah
3. Menjana idea
4. Menjana penyelesaian
5. Menentukan tindakan
6. Melaksanakan penyelesaian
7. Membuat penilaian
8. Membuat penambahbaikan
""",
      "video": "https://youtu.be/Z7oPHbRlgfs?si=WmLMRmpssL31GH9x"
    },

    {
      "title": "1.2 Algoritma",
      "note": """✏️ ALGORITMA
Satu set arahan untuk menyelesaikan masalah. 

✅ (3) CIRI ALGORITMA
• Butiran jelas
• Boleh dilaksanakan
• Mempunyai batasan

-------------------------------------------------
INPUT ➡️ PROSES ➡️ OUTPUT
-------------------------------------------------

1️⃣ PSEUDOKOD
Senarai struktur kawalan komputer yang ditulis dalam bahasa pertuturan manusia & mempunyai nombor turutan.
1. Tulis kenyataan MULA
2. Baca INPUT
3. Proses data menggunakan ungkapan logik / matematik
4. Papar OUTPUT
5. Tulis kenyataan TAMAT

2️⃣ CARTA ALIR
Alternatif kepada pseudokod menggunakan simbol grafik untuk mewakili arahan-arahan penyelesaian.
1. Lukis nod terminal Mula
2. Lukis garis penghubung
3. Lukis nod input
4. Lukis garis penghubung
5. Lukis nod proses
6. Lukis garis penghubung
7. Sekiranya perlu, lukis nod proses / nod input lain-lain yang diperlukan
8. Sekiranya tiada, lukis nod terminal Tamat

🧑‍💻 (3) STRUKTUR KAWALAN DALAM PENGATURCARAAN
• Urutan
• Pilihan
• Pengulangan

-----------------------------------------------------------------
Tulis Algoritma ➡️ Uji ➡️ Pembetulan ➡️ Pengaturcaraan
-----------------------------------------------------------------

✅ (4) CIRI ALGORITMA YANG TELAH DIUJI
• Mudah difahami
• Lengkap
• Efisien
• Memenuhi kriteria reka bentuk

❌ (3) RALAT
• Sintaks
• Logik
• Masa Larian

📋 (4) LANGKAH PENGUJIAN ALGORITMA
1. Kenal pasti "Output Dijangka"
2. Kenal pasti "Output Diperoleh"
3. Bandingkan "Output Diperoleh" dengan "Output Dijangka"
4. Analisis & baiki algoritma
""",
      "video": "https://youtu.be/NL9c25tu6VU?si=724Ke4pZ-AokWaDJ"
    },

    {
      "title": "1.3 Pemboleh Ubah, Pemalar & Jenis Data",
      "note": """📝 PEMBOLEH UBAH
Ruang simpanan sementara untuk nombor, teks & objek.
Cth : float panjang

🔒 PEMALAR
Tetap & tidak akan berubah.
Cth : final double pi = 3.142

🗃️ (6) JENIS DATA
• Integer [Cth : 26]
• Float [Cth : 17.9]
• Double [Cth : 11.5]
• Char [Cth : z]
• String [Cth : hello world]
• Boolean [Cth : true, false]

PEMBOLEH UBAH SEJAGAT 🆚 SETEMPAT
1️⃣ Sejagat 
• Pengisytiharan dilakukan di luar mana-mana fungsi
• Boleh diakses di mana-mana fungsi
• Boleh digunakan hingga ke akhir program

2️⃣ Setempat
• Pemboleh ubah yang diisytiharkan dalam sebuah fungsi 
• Tidak boleh diakses di luar fungsi itu
• Hanya boleh digunakan untuk fungsi yang diisi
""",
      "video": "https://youtu.be/SwJKIcVwIDc?si=z_kZD_s_HxDJnbp8"
    },

    {
      "title": "1.4 Struktur Kawalan",
      "note": """🧑‍💻 (3) STRUKTUR KAWALAN 
• Urutan (Tidak bervariasi)
• Pilihan (if-else-if, switch)
• Pengulangan (for, while, do-while)

⚙️ (6) OPERATOR HUBUNGAN
• Sama dengan (==)
• Tidak sama dengan (!=) 
• Lebih besar daripada (>) 
• Lebih besar daripada / sama dengan (>=) 
• Kurang daripada (<)
• Kurang daripada / sama dengan (<=) 

💡 (3) OPERATOR LOGIC
• AND (Cth : Markah >=0 && Markah <= 100)
• OR (Cth : if (malam || hujan))
• NOT (Cth : if(!lulus))

while (<syarat boolean>){
  <Blok kenyataan berulang>
  <kemas kini nilai dalam syarat>
}
i+=1 🟰 i = i + 1

while (<syarat boolean>){
  <Blok kenyataan berulang>
  <kemas kini nilai dalam syarat>
}
i-=1 🟰 i = i – 1
""",
      "video": "https://youtu.be/FJ25cfsrufg?si=bs5PSK-bWDlLNd3X"
    },

    {
      "title": "1.5 Amalan Terbaik Pengaturcaraan",
      "note": """😆 AMALAN TERBAIK PENGATURCARAAN
Pengatur cara dapat mempraktikkan amalan-amalan yang biasa diikuti untuk menghasilkan atur cara yang baik.

🔎 (4) FAKTOR KEBOLEHBACAAN
• Inden yang konsisten
• Nama pemboleh ubah yang bermakna
• Komen [// @ /* */ @ /** */]
• Jenis data

❌ (3) JENIS RALAT
1. Sintaks
   • Kesalahan tatabahasa 
   • Penggunaan aksara yang tidak dikenali
2. Masa Larian 
   • Pengiraan data bukan berangka
   • Pembahagian dengan digit 0
   • Mencari punca kuasa dua bagi nombor negatif
3. Logik
   • Atur cara tidak berfungsi seperti yang diingini
""",
      "video": "https://youtu.be/E0i_O5RXqtM?si=W4BkFsV43DNSPb_N"
    },

    {
      "title": "1.6 Struktur Data dan Modular",
      "note": """🔢 TATASUSUNAN
Pemboleh ubah yang membolehkan koleksi beberapa nilai data dalam satu-satu masa dengan menyimpan setiap elemen dalam ruang memori berindeks.
Cth : 
int [] senaraiMarkah;
senaraiMarkah = new int[3];
senaraiMarkah[0] = 34;
senaraiMarkah[1] = 56;
senaraiMarkah[2] = 78;

👍 (5) KELEBIHAN STRUKTUR MODULAR
• Mudah diguna semula
• Mudah diuji, dinyah pijat & dibaiki
• Memudahkan projek kompleks
• Tugasan boleh dibahagi
• Proses lebih teratur

KATA KUNCI KHAS - (static) 
• Letak di hadapan nama subatur cara. Tanpa "static", subatur cara tidak dapat digunakan secara langsung. 

JENIS DATA PULANGAN
• Bergantung kepada jenis data yang ingin dipulangkan oleh "badan". Jika tidak memulangkan data, gunakan kata kunci "void".

NAMA SUBATUR CARA
• Mesti bermula dengan huruf & boleh mengandungi angka tetapi bukan simbol.

BEKAS PARAMETER 
• Dikepil oleh tanda kurung "(" & ")". Jika bekas parameter adalah kosong, "()" digunakan. Jika bekas menerima parameter, maka jenis data & nama parameter akan dikepilkan.

Cth : public static void main(String[] args){ }
• Kata kunci khas : public static
• Jenis data pulangan : void
• Nama wajib : main
• Parameter wajib : (String[] args) 
• Badan : {}
• Pengepala : public static void main(String[] args)

PARAMETER
• Pemboleh ubah yang membolehkan subatur cara menerima nilai daripada pemanggil.
• parameter rasmi (formal parameter) - Merujuk parameter bagi subatur cara
• parameter sebenar (actual parameter) - Merujuk pemboleh ubah di dalam subatur cara pemanggil
• Cth : 
  Tiada parameter : static void subAtur01 (){}
  Menerima parameter : static void subAtur01 (int x){}
""",
      "video": "https://youtu.be/1kw_OQmxU5c?si=JfuQ2-Z-GFL7-B_9"
    },

    {
      "title": "1.7 Pembangunan Aplikasi",
      "note": """🔄 SDLC (Kitaran Hayat Pembangunan Sistem)
Proses mengenal pasti keperluan program & mencari sebab sesuatu program dibina.

1. Analisis masalah - Dapatan data, analisis masalah, penyataan masalah
2. Reka bentuk penyelesaian - Disediakan daripada analisis masalah
3. Laksana penyelesaian - Kerja dibahagikan dalam sub modul
4. Uji & nyah ralat - Pelbagai jenis pengujian, menyah ralat, membaiki ralat & penambahbaikan dijalankan
5. Dokumentasi - Disediakan di setiap fasa
""",
      "video": "https://youtu.be/PQU16kOnQRk?si=1dCReplwhLzder9c"
    },
  ];
  late List<bool> _isDone;

  @override
  void initState() {
    super.initState();
    // Inisialisasi awal dengan false, kemudian muatkan status yang disimpan
    _isDone = List<bool>.filled(topics.length, false);
    _loadDoneStatus();
  }

  // Muatkan status selesai dari SharedPreferences
  Future<void> _loadDoneStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 0; i < topics.length; i++) {
        // Bina key unik untuk setiap topik
        final key = '$_kDoneStatusKeyPrefix$i';
        // Dapatkan status. Jika tiada status, nilai lalai adalah false.
        _isDone[i] = prefs.getBool(key) ?? false;
      }
    });
  }

  // Simpan status selesai ke SharedPreferences
  Future<void> _saveDoneStatus(int index, bool status) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kDoneStatusKeyPrefix$index';
    await prefs.setBool(key, status);
  }

  // Fungsi untuk menavigasi dan mengemas kini status
  void _navigateToDetails(BuildContext context, int index) async {
    final topic = topics[index];

    // Navigasi ke laman butiran dan tunggu sehingga pengguna kembali
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsPage(
          title: topic["title"]!,
          note: topic["note"]!,
          videoUrl: topic["video"]!,
        ),
      ),
    );

    // Apabila pengguna kembali (pop dari DetailsPage), 
    // kemas kini state di memori dan simpan ke penyimpanan tempatan
    setState(() {
      _isDone[index] = true;
    });
    // Simpan status baharu secara kekal
    _saveDoneStatus(index, true); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('📖 Course'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView.builder(
          itemCount: topics.length,
          itemBuilder: (context, index) {
            final topic = topics[index];
            final isDone = _isDone[index]; 

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. InkWell untuk keseluruhan kawasan tajuk
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _navigateToDetails(context, index),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        topic["title"]!,
                        style: TextStyle(
                          fontSize: 18,
                          color: isDone ? Colors.green[800] : Colors.black,
                          fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),

                  // 2. Garis Pemisah (Divider)
                  const Divider(height: 1, color: Colors.grey),

                  // 3. Butang "To View" / "Mark As Done"
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDone ? Colors.green : Colors.lightBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _navigateToDetails(context, index), 
                      child: Text(
                        isDone ? "Mark As Done" : "To View",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ========== DETAILS PAGE ==========
class DetailsPage extends StatefulWidget {
  final String title, note, videoUrl;

  const DetailsPage({
    super.key,
    required this.title,
    required this.note,
    required this.videoUrl,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

// ========== DETAILS PAGE STATE ==========
class _DetailsPageState extends State<DetailsPage> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();

    final videoId = YoutubePlayer.convertUrlToId(widget.videoUrl) ?? "";

    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.lightBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            YoutubePlayer(controller: _controller),
            const SizedBox(height: 20),
            Text(
              widget.note,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== QUIZ ==========
enum QuestionType { mcq, shortAnswer }
enum QuizStatus { draft, published }

enum AssessmentStatus {
  notStarted,
  completed,
}
enum AssessmentType {
  system,
  teacher,
}
class Question {
  final String id;
  final String questionText;
  final QuestionType type;
  final List<String> options;
  final String answer;
  final String? explanation;

  Question({
    required this.id,
    required this.questionText,
    required this.type,
    this.options = const [],
    required this.answer,
    this.explanation,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'questionText': questionText,
      'type': type.name,
      'options': options,
      'answer': answer,
      'explanation': explanation,
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as String,
      questionText: map['questionText'] as String,
      type: QuestionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => QuestionType.mcq,
      ),
      options: List<String>.from(map['options'] ?? []),
      answer: map['answer'] as String,
      explanation: map['explanation'] as String?,
    );
  }
}

/* ========== QUESTION ========== (Model for single question)
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

  // Convert Question object to a Map for Firestore
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

  // Create Question object from a Map 
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
}*/

// ========== QUIZ ========== (Model for Quiz (Created by teacher))
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

/* ========== QUIZ ATTEMPT ========== (Model to store student's quiz attempt and results (US006-02))
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
}*/

class QuizAttempt {
  final String quizTitle;
  final List<Question> questions;
  final Map<String, String> userAnswers;
  final int score;
  final int total;
  final DateTime timestamp;
  final Map<String, String>? aiFeedback;

  QuizAttempt({
    required this.quizTitle,
    required this.questions,
    required this.userAnswers,
    required this.score,
    required this.total,
    required this.timestamp,
    this.aiFeedback,
  });
}
class AssessmentItem {
  final String title;
  final String topic;
  final AssessmentType type;
  final List<Question> questions;
  final String? quizId;
  final AssessmentStatus status;

  AssessmentItem({
    required this.title,
    required this.topic,
    required this.type,
    required this.questions,
    this.quizId,
    required this.status,
  });
}

// ========== SYSTEM QUIZ ==========
// Dummy list for storing student quiz history (US006-02)
List<QuizAttempt> userQuizAttempts = [];

// System-Generated Quiz Data (US-System)
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

// System-Generated Summative Test (US-System)
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
// US008-03: Filter assessments by topic and status
class StudentAssessmentsPage extends StatefulWidget {
  const StudentAssessmentsPage({super.key});

  @override
  State<StudentAssessmentsPage> createState() => _StudentAssessmentsPageState();
}

class _StudentAssessmentsPageState extends State<StudentAssessmentsPage> {
  String? _selectedTopicFilter;
  AssessmentStatus? _selectedStatusFilter;
  bool _showFilters = false;
  final List<String> _availableTopics = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableTopics();
  }

  void _loadAvailableTopics() {
    _availableTopics.addAll(systemQuizData.keys.toList());
  }

  void _clearFilters() {
    setState(() {
      _selectedTopicFilter = null;
      _selectedStatusFilter = null;
    });
  }

  bool _isAssessmentCompleted(String quizTitle, String? quizId) {
    final userAttempts = userQuizAttempts.where((attempt) => 
      attempt.quizTitle == quizTitle
    );
    return userAttempts.isNotEmpty;
  }

  AssessmentStatus _getAssessmentStatus(String quizTitle, String? quizId) {
    return _isAssessmentCompleted(quizTitle, quizId) 
        ? AssessmentStatus.completed 
        : AssessmentStatus.notStarted;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FirebaseUserState>().currentUser;
    final isTeacher = user?.userType == UserType.teacher;

    if (isTeacher) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('This page is for students only.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assessments'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              setState(() => _showFilters = !_showFilters);
            },
            tooltip: 'Show/Hide Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilters) _buildFilterSection(),
          Expanded(child: _buildAssessmentsList()),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Assessments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            DropdownButtonFormField<String>(
              value: _selectedTopicFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by Topic',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Topics'),
                ),
                ..._availableTopics.map((topic) {
                  return DropdownMenuItem(
                    value: topic,
                    child: Text(
                      topic,
                      overflow: TextOverflow.ellipsis, // Add ellipsis for long text
                      maxLines: 1, // Limit to single line
                    ),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                setState(() => _selectedTopicFilter = value);
              },
            ),
            
            const SizedBox(height: 12),
            
            DropdownButtonFormField<AssessmentStatus>(
              value: _selectedStatusFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by Status',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text('All Statuses'),
                ),
                ...AssessmentStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(
                      status == AssessmentStatus.completed ? 'Completed' : 'Not Started',
                    ),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                setState(() => _selectedStatusFilter = value);
              },
            ),
            
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Filters'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('quizzes')
          .where('status', isEqualTo: 'published')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final teacherQuizzes = snapshot.data!.docs
            .map((doc) => Quiz.fromFirestore(doc))
            .where((quiz) => quiz.status == QuizStatus.published)
            .toList();

        final allAssessments = <AssessmentItem>[];
        
        systemQuizData.forEach((topic, questions) {
          allAssessments.add(AssessmentItem(
            title: topic,
            topic: topic,
            type: AssessmentType.system,
            questions: questions,
            status: _getAssessmentStatus(topic, null),
          ));
        });
        
        allAssessments.add(AssessmentItem(
          title: 'Summative Test (Bab 1)',
          topic: 'Comprehensive',
          type: AssessmentType.system,
          questions: summativeTestQuestions,
          status: _getAssessmentStatus('Summative Test (Bab 1)', null),
        ));
        
        for (final quiz in teacherQuizzes) {
          allAssessments.add(AssessmentItem(
            title: quiz.title,
            topic: quiz.topic,
            type: AssessmentType.teacher,
            questions: quiz.questions,
            quizId: quiz.id,
            status: _getAssessmentStatus(quiz.title, quiz.id),
          ));
        }

        final filteredAssessments = allAssessments.where((assessment) {
          if (_selectedTopicFilter != null && 
              assessment.topic != _selectedTopicFilter) {
            return false;
          }
          
          if (_selectedStatusFilter != null && 
              assessment.status != _selectedStatusFilter) {
            return false;
          }
          
          return true;
        }).toList();

        if (filteredAssessments.isEmpty) {
          return _buildNoResultsState();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: filteredAssessments.length,
          itemBuilder: (context, index) {
            final assessment = filteredAssessments[index];
            return _buildAssessmentCard(assessment);
          },
        );
      },
    );
  }

  Widget _buildAssessmentCard(AssessmentItem assessment) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: ListTile(
        leading: Icon(
          assessment.type == AssessmentType.system 
              ? Icons.auto_awesome 
              : Icons.school,
          color: assessment.status == AssessmentStatus.completed 
              ? Colors.green 
              : Colors.blue,
        ),
        title: Text(assessment.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Topic: ${assessment.topic}'),
            const SizedBox(height: 2),
            Text(
              'Status: ${assessment.status == AssessmentStatus.completed ? 'Completed' : 'Not Started'}',
              style: TextStyle(
                color: assessment.status == AssessmentStatus.completed 
                    ? Colors.green 
                    : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Questions: ${assessment.questions.length}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Icon(
          assessment.status == AssessmentStatus.completed
              ? Icons.check_circle
              : Icons.play_arrow,
          color: assessment.status == AssessmentStatus.completed
              ? Colors.green
              : Colors.blue,
        ),
        onTap: () {
          if (assessment.status == AssessmentStatus.completed) {
            final attempt = userQuizAttempts.firstWhere(
              (a) => a.quizTitle == assessment.title,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuizResultsPage(attempt: attempt),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TakeQuizPage(
                  quizTitle: assessment.title,
                  questions: assessment.questions,
                ),
              ),
            ).then((_) {
              setState(() {});
            });
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quiz, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No Assessments Available',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your teacher hasn\'t published any quizzes yet.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No Matching Assessments',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your filters to see more results.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _clearFilters,
            child: const Text('Clear All Filters'),
          ),
        ],
      ),
    );
  }
}
// ========== QUIZ PAGE ==========
class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

// ========== QUIZ PAGE STATE ==========
class _QuizPageState extends State<QuizPage> {

 @override
  void initState() {
    super.initState();
    _loadQuizAttempts();
  }

  // ✅ NEW: Load quiz attempts from Firestore
  Future<void> _loadQuizAttempts() async {
    final userState = context.read<FirebaseUserState>();
    final user = userState.currentUser;
    
    if (user == null || user.userType != UserType.student) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('quiz_attempts')
          .orderBy('timestamp', descending: true)
          .get();

      // Clear existing in-memory attempts
      userQuizAttempts.clear();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Convert questions back to Question objects
        final questionsData = data['questions'] as List<dynamic>;
        final questions = questionsData
            .map((q) => Question.fromMap(q as Map<String, dynamic>))
            .toList();

        final attempt = QuizAttempt(
          quizTitle: data['quizTitle'] ?? '',
          questions: questions,
          userAnswers: Map<String, String>.from(data['userAnswers'] ?? {}),
          score: data['score'] ?? 0,
          total: data['total'] ?? 0,
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          aiFeedback: data['aiFeedback'] != null 
              ? Map<String, String>.from(data['aiFeedback']) 
              : null,
        );

        userQuizAttempts.add(attempt);
      }

      print('✅ Loaded ${userQuizAttempts.length} quiz attempts from Firestore');
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Error loading quiz attempts: $e');
    }
  }

  // ----- startQuiz ----- (Helper function to navigate to the quiz-taking page)
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

  // ----- deleteQuiz ----- (Helper function to delete a quiz from Firestore)
  void _deleteQuiz(Quiz quiz) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: Text(
          'Are you sure you want to delete "${quiz.title}"?',
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
      try {
        await FirebaseFirestore.instance
            .collection('quizzes')
            .doc(quiz.id)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quiz deleted successfully!'),
              backgroundColor: Colors.green,
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

  // ----- editQuiz ----- (Helper function to edit quiz (US005-02))
  void _editQuiz(Quiz quiz) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateQuizPage(quizToEdit: quiz)),
    ).then((_) {
      // Refresh the list in case changes were made
      setState(() {});
    });
  }

  // ----- reviewQuiz ----- (Helper function to review quiz)
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
        title: const Text('🎯 Quiz'),
        backgroundColor: Colors.lightBlue,
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
            /*Card(
              elevation: 2,
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
            ),*/

            Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.quiz, color: Colors.blue),
              title: const Text('Summative Test (Bab 1)'),
              subtitle: const Text('Test your knowledge on the whole chapter'),
              trailing: Icon(isTeacher ? Icons.visibility : Icons.play_arrow), // ✅ MODIFIED
              onTap: () {
            if (isTeacher) {
              Navigator.push(
              context,
              MaterialPageRoute(
              builder: (context) => ReviewQuizPage(
              quizTitle: 'Summative Test (Bab 1)',
              questions: summativeTestQuestions,
            ),
          ),
        );
      } else {
        _startQuiz(context, 'Summative Test (Bab 1)', summativeTestQuestions);
      }
    },
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
          if (value == 'review') _reviewQuiz(quiz);
        },
        itemBuilder: (context) => [
          // ✅ MODIFIED: Show 'Edit' for BOTH draft and published
          const PopupMenuItem(value: 'edit', child: Text('Edit')),

          // Show 'Review' for all quizzes
          const PopupMenuItem(value: 'review', child: Text('Review Answers')),

          // Delete is available for both draft and published
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      )
    : const Icon(Icons.play_arrow),

                        /*trailing: isTeacher
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
                            : const Icon(Icons.play_arrow),*/
                        onTap: () {
                          if (isTeacher) {
                            // Default tap action for teacher is 'review'
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
             
            //US008-03: Filter assessments by topic and status
            if (!isTeacher) ...[
              const Divider(height: 30, thickness: 1),
              _buildSectionTitle('Assessments Management'),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.filter_alt, color: Colors.purple),
                  title: const Text('Filter My Assessments'),
                  subtitle: const Text('View and filter assessments by topic and status'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StudentAssessmentsPage(),
          ),
        );
      },
    ),
  ),
],
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
              trailing: Icon(isTeacher ? Icons.visibility : Icons.play_arrow),
              onTap: () {
                // ✅ MODIFIED: Teacher ALWAYS reviews, never takes quiz
                if (isTeacher) {
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
                  // Student takes the quiz
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

/* ========== SYSTEM QUIZ LIST PAGE ==========
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
}*/

// ========== REVIEW QUIZ PAGE (FOR TEACHERS) ==========
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

// ========== Quiz Creation / EDIT Page (US005-01 & US005-02) ==========
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

  final _newQuestionTextController = TextEditingController();
  final _newAnswerController = TextEditingController();
  final _newExplanationController = TextEditingController();
  QuestionType _newQuestionType = QuestionType.mcq;

// ✅ NEW: Show dialog to edit existing question
void _showEditQuestionDialog(int index) {
  final question = _questions[index];
  
  final editQuestionController = TextEditingController(text: question.questionText);
  final editAnswerController = TextEditingController(text: question.answer);
  final editExplanationController = TextEditingController(text: question.explanation ?? '');
  
  QuestionType editType = question.type;
  
  // Initialize MCQ options controllers
  List<TextEditingController> editMcqControllers = [];
  int editCorrectIndex = 0;
  
  if (question.type == QuestionType.mcq) {
    for (int i = 0; i < question.options.length; i++) {
      editMcqControllers.add(TextEditingController(text: question.options[i]));
      if (question.options[i] == question.answer) {
        editCorrectIndex = i;
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text('Edit Question ${index + 1}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Question Type Dropdown (Read-only, cannot change type after creation)
                DropdownButtonFormField<QuestionType>(
                  value: editType,
                  decoration: const InputDecoration(labelText: 'Question Type'),
                  items: const [
                    DropdownMenuItem(value: QuestionType.mcq, child: Text('Multiple Choice (MCQ)')),
                    DropdownMenuItem(value: QuestionType.shortAnswer, child: Text('Short Answer')),
                  ],
                  onChanged: null, // ✅ Disabled - cannot change type
                ),
                const SizedBox(height: 10),

                // Question Text
                TextFormField(
                  controller: editQuestionController,
                  decoration: InputDecoration(
                    labelText: 'Question Text',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 5,
                  minLines: 3,
                ),
                const SizedBox(height: 10),

                if (editType == QuestionType.mcq) ...[
                  // MCQ Options
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('MCQ Options:', style: TextStyle(fontWeight: FontWeight.w500)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          setDialogState(() {
                            editMcqControllers.add(TextEditingController());
                          });
                        },
                      ),
                    ],
                  ),
                  ...List.generate(editMcqControllers.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Radio<int>(
                            value: i,
                            groupValue: editCorrectIndex,
                            onChanged: (int? value) {
                              setDialogState(() => editCorrectIndex = value!);
                            },
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: editMcqControllers[i],
                              decoration: InputDecoration(
                                labelText: 'Option ${i + 1}',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              maxLines: 2,
                              minLines: 1,
                            ),
                          ),
                          if (editMcqControllers.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                if (editMcqControllers.length <= 2) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Minimum 2 options required')),
                                  );
                                  return;
                                }
                                setDialogState(() {
                                  editMcqControllers[i].dispose();
                                  editMcqControllers.removeAt(i);
                                  if (editCorrectIndex >= editMcqControllers.length) {
                                    editCorrectIndex = editMcqControllers.length - 1;
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    );
                  }),
                ] else ...[
                  // Short Answer
                  TextFormField(
                    controller: editAnswerController,
                    decoration: InputDecoration(
                      labelText: 'Correct Answer',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 3,
                    minLines: 2,
                  ),
                ],

                const SizedBox(height: 10),

                // Explanation
                TextFormField(
                  controller: editExplanationController,
                  decoration: InputDecoration(
                    labelText: 'Explanation (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 5,
                  minLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Dispose controllers
                editQuestionController.dispose();
                editAnswerController.dispose();
                editExplanationController.dispose();
                for (var c in editMcqControllers) {
                  c.dispose();
                }
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Validate
                if (editQuestionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Question text cannot be empty')),
                  );
                  return;
                }

                String updatedAnswer;
                List<String> updatedOptions = [];

                if (editType == QuestionType.mcq) {
                  updatedOptions = editMcqControllers.map((c) => c.text.trim()).toList();
                  final nonEmptyOptions = updatedOptions.where((opt) => opt.isNotEmpty).toList();
                  
                  if (nonEmptyOptions.length < 2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill at least 2 MCQ options')),
                    );
                    return;
                  }
                  
                  updatedOptions = nonEmptyOptions;
                  if (editCorrectIndex >= updatedOptions.length) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a valid correct answer')),
                    );
                    return;
                  }
                  updatedAnswer = updatedOptions[editCorrectIndex];
                } else {
                  if (editAnswerController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Answer cannot be empty')),
                    );
                    return;
                  }
                  updatedAnswer = editAnswerController.text.trim();
                }

                // Update the question
                setState(() {
                  _questions[index] = Question(
                    id: question.id, // Keep the same ID
                    questionText: editQuestionController.text.trim(),
                    type: editType,
                    options: updatedOptions,
                    answer: updatedAnswer,
                    explanation: editExplanationController.text.trim().isEmpty
                        ? null
                        : editExplanationController.text.trim(),
                  );
                });

                // Dispose controllers
                editQuestionController.dispose();
                editAnswerController.dispose();
                editExplanationController.dispose();
                for (var c in editMcqControllers) {
                  c.dispose();
                }

                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Question updated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    ),
  );
}

  //MODIFIED: Dynamic list of MCQ option controllers (starts with 2)
  List<TextEditingController> _mcqOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  int _correctMcqOptionIndex = 0;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.quizToEdit != null;

    if (_isEditing) {
      final quiz = widget.quizToEdit!;
      _titleController = TextEditingController(text: quiz.title);
      _topicController = TextEditingController(text: quiz.topic);
      _questions = List.from(quiz.questions);
    } else {
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

  // NEW: Add more MCQ options
  void _addMcqOption() {
    setState(() {
      _mcqOptionControllers.add(TextEditingController());
    });
  }

  // âœ… NEW: Remove MCQ option (minimum 2)
  void _removeMcqOption(int index) {
    if (_mcqOptionControllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 2 options required')),
      );
      return;
    }
    setState(() {
      _mcqOptionControllers[index].dispose();
      _mcqOptionControllers.removeAt(index);
      if (_correctMcqOptionIndex >= _mcqOptionControllers.length) {
        _correctMcqOptionIndex = _mcqOptionControllers.length - 1;
      }
    });
  }

  void _addQuestion() {
    if (_newQuestionTextController.text.isEmpty) {
      _showError('Please enter the question text.');
      return;
    }

    String answer;
    List<String> options = [];

    if (_newQuestionType == QuestionType.mcq) {
      options = _mcqOptionControllers.map((c) => c.text.trim()).toList();
      
      // âœ… MODIFIED: Check only non-empty options
      final nonEmptyOptions = options.where((opt) => opt.isNotEmpty).toList();
      if (nonEmptyOptions.length < 2) {
        _showError('Please fill at least 2 MCQ options.');
        return;
      }
      
      options = nonEmptyOptions;
      if (_correctMcqOptionIndex >= options.length) {
        _showError('Please select a valid correct answer.');
        return;
      }
      answer = options[_correctMcqOptionIndex];
    } else {
      if (_newAnswerController.text.isEmpty) {
        _showError('Please enter the correct answer.');
        return;
      }
      answer = _newAnswerController.text;
    }

    setState(() {
      _questions.add(
        Question(
          id: UniqueKey().toString(),
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
    
    // âœ… MODIFIED: Reset to 2 empty options
    for (var c in _mcqOptionControllers) {
      c.dispose();
    }
    _mcqOptionControllers = [
      TextEditingController(),
      TextEditingController(),
    ];
    setState(() => _correctMcqOptionIndex = 0);
  }

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
        final quiz = widget.quizToEdit!;
        quiz.title = _titleController.text;
        quiz.topic = _topicController.text;
        quiz.questions = _questions;
        quiz.status = status;

        await FirebaseFirestore.instance
            .collection('quizzes')
            .doc(quiz.id)
            .update(quiz.toMap());
      } else {
        final newQuiz = Quiz(
          id: '',
          title: _titleController.text,
          topic: _topicController.text.isEmpty ? 'General' : _topicController.text,
          questions: _questions,
          status: status,
          createdBy: user.id,
        );

        await FirebaseFirestore.instance.collection('quizzes').add(newQuiz.toMap());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quiz saved as ${status.name.toUpperCase()}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
                      decoration: InputDecoration(
                        labelText: 'Quiz Title',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter a title' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _topicController,
                      decoration: InputDecoration(
                        labelText: 'Topic (e.g., 1.1)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter a topic' : null,
                    ),
                    const Divider(height: 30, thickness: 2),

                    const Text(
                      'Add New Question:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<QuestionType>(
                      value: _newQuestionType,
                      items: const [
                        DropdownMenuItem(value: QuestionType.mcq, child: Text('Multiple Choice (MCQ)')),
                        DropdownMenuItem(value: QuestionType.shortAnswer, child: Text('Short Answer')),
                      ],
                      onChanged: (QuestionType? value) => setState(() => _newQuestionType = value!),
                      decoration: const InputDecoration(labelText: 'Question Type'),
                    ),
                    const SizedBox(height: 10),

                    // âœ… MODIFIED: Multiline question text
                    TextFormField(
                      controller: _newQuestionTextController,
                      decoration: InputDecoration(
                        labelText: 'Question Text',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: 'Enter your question here...',
                      ),
                      maxLines: 5,
                      minLines: 3,
                    ),
                    const SizedBox(height: 10),

                    if (_newQuestionType == QuestionType.mcq) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'MCQ Options (Select correct one):',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          // âœ… NEW: Add option button
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.green),
                            tooltip: 'Add Option',
                            onPressed: _addMcqOption,
                          ),
                        ],
                      ),
                      // âœ… MODIFIED: Dynamic MCQ options with delete button
                      ...List.generate(_mcqOptionControllers.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Radio<int>(
                                value: index,
                                groupValue: _correctMcqOptionIndex,
                                onChanged: (int? value) => setState(() => _correctMcqOptionIndex = value!),
                              ),
                              Expanded(
                                child: TextFormField(
                                  controller: _mcqOptionControllers[index],
                                  decoration: InputDecoration(
                                    labelText: 'Option ${index + 1}',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  maxLines: 2,
                                  minLines: 1,
                                ),
                              ),
                              // âœ… NEW: Delete option button (only if more than 2)
                              if (_mcqOptionControllers.length > 2)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  tooltip: 'Remove Option',
                                  onPressed: () => _removeMcqOption(index),
                                ),
                            ],
                          ),
                        );
                      }),
                    ] else ...[
                      // âœ… MODIFIED: Multiline short answer
                      TextFormField(
                        controller: _newAnswerController,
                        decoration: InputDecoration(
                          labelText: 'Correct Short Answer',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          hintText: 'Enter the correct answer...',
                        ),
                        maxLines: 3,
                        minLines: 2,
                      ),
                    ],

                    const SizedBox(height: 10),
                    // âœ… MODIFIED: Multiline explanation
                    TextFormField(
                      controller: _newExplanationController,
                      decoration: InputDecoration(
                        labelText: 'Explanation (Optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: 'Provide detailed feedback...',
                      ),
                      maxLines: 5,
                      minLines: 3,
                    ),

                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _addQuestion,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Question to Quiz'),
                      ),
                    ),
                    const Divider(height: 30, thickness: 2),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Quiz Questions:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text('${_questions.length} Question(s)'),
                      ],
                    ),
                    ..._questions.asMap().entries.map((entry) {
  int idx = entry.key;
  Question q = entry.value;
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      title: Text(
        'Q${idx + 1}: ${q.questionText}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type: ${q.type == QuestionType.mcq ? "MCQ" : "Short Answer"}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Answer: ${q.answer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ NEW: Edit button
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            tooltip: 'Edit Question',
            onPressed: () => _showEditQuestionDialog(idx),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Delete Question',
            onPressed: () => setState(() => _questions.removeAt(idx)),
          ),
        ],
      ),
    ),
  );
}),
                    const SizedBox(height: 30),

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
                          label: Text(_isEditing ? 'Update & Publish' : 'Publish Quiz'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
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

// ========== TAKE QUIZ PAGE (US006-01) ==========
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

// ========== TAKE QUIZ PAGE STATE ==========
class _TakeQuizPageState extends State<TakeQuizPage> {
  final PageController _pageController = PageController();
  final Map<String, String> _userAnswers = {}; // Map<QuestionID, UserAnswer>
  final Map<String, TextEditingController> _shortAnswerControllers = {};
  int _currentPage = 0;
  bool _isSubmitting = false; // NEW: Loading state for AI marking

  // AI Model for marking
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

    // Initialize AI model for marking
    final googleAI = FirebaseAI.googleAI();
    _markingModel = googleAI.generativeModel(
      model: 'gemini-2.5-flash',
      systemInstruction: Content.system(
        'Anda adalah AI yang menandakan kuiz. Anda akan diberi jawapan yang dijangka dan jawapan pengguna. '
      'Bandingkan keduanya untuk kesamaan semantik, bukan hanya padanan teks tepat, termasuk sinonim dan variasi, serta perbezaan huruf besar dan kecil. '
      'Balas dengan HANYA perkataan "YA" jika jawapan pengguna betul atau sinonim/variasi yang hampir. '
      'Balas dengan HANYA perkataan "TIDAK" jika jawapan pengguna salah. '
      'Berikan justifikasi untuk setiap jawapan dalam Bahasa Malaysia.',
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

  // ----- saveQuizScoreToDatabase -----
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

  // Save to progress_records collection for teacher filtering
  Future<void> _saveQuizToProgressRecords(int score, int total) async {
  final userState = context.read<FirebaseUserState>();
  final user = userState.currentUser;
  if (user == null || !mounted) return;

  try {
    final percentage = (score / total * 100).toDouble();
    
    await FirebaseFirestore.instance.collection('progress_records').add({
      'student': user.username,
      'studentId': user.id,
      'activity': widget.quizTitle,
      'score': percentage,
      'grade': _calculateGradeFromPercentage(percentage),
      'comments': 'Auto-generated from quiz completion',
      'timestamp': FieldValue.serverTimestamp(),
      'isAutoGenerated': true, 
    });
    
    print('✅ Quiz score saved to progress_records for filtering');
  } catch (e) {
    print('❌ Error saving to progress_records: $e');
  }
}

// Helper function to calculate grade
String _calculateGradeFromPercentage(double percentage) {
  if (percentage >= 80) return 'A';
  if (percentage >= 60) return 'B';
  if (percentage >= 50) return 'C';
  if (percentage >= 40) return 'D';
  return 'F';
}

Future<void> _submitQuiz() async {
  if (!mounted) return;

  setState(() => _isSubmitting = true);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('Menandakan kuiz...'),
        ],
      ),
    ),
  );

  int score = 0;
  
  // Store AI feedback for each question
  Map<String, String> aiFeedback = {};

  for (var q in widget.questions) {
    final userAnswer = _userAnswers[q.id]?.trim() ?? "";
    final correctAnswer = q.answer.trim();

    if (userAnswer.isEmpty) {
      aiFeedback[q.id] = "Tiada jawapan diberikan.";
      continue;
    }

    if (q.type == QuestionType.mcq) {
      // MCQ: Case-insensitive exact match
      if (userAnswer.toLowerCase() == correctAnswer.toLowerCase()) {
        score++;
        aiFeedback[q.id] = "✅ Betul!";
      } else {
        aiFeedback[q.id] = "❌ Salah. Jawapan yang betul ialah: ${q.answer}";
      }
    } else if (q.type == QuestionType.shortAnswer) {
      // Short Answer: Check case-insensitive match first
      if (userAnswer.toLowerCase() == correctAnswer.toLowerCase()) {
        score++;
        aiFeedback[q.id] = "✅ Jawapan sempurna!";
      } else {
        try {
          // IMPROVED: Better AI prompt that explicitly handles case sensitivity
          final prompt =
              'Anda sedang menilai jawapan pendek pelajar.\n\n'
              'Soalan: ${q.questionText}\n'
              'Jawapan Dijangka: $correctAnswer\n'
              'Jawapan Pelajar: $userAnswer\n\n'
              'Tugas:\n'
              '1. Tentukan sama ada jawapan pelajar adalah betul.\n'
              '2. ABAIKAN perbezaan huruf besar/kecil (contoh: "Java" = "java" = "JAVA").\n'
              '3. TERIMA sinonim, parafrase, dan variasi yang bermakna sama.\n'
              '4. TERIMA jawapan yang mempunyai makna yang sama walaupun perkataan berbeza sedikit.\n'
              '5. Balas dengan TEPAT "YA" atau "TIDAK" pada baris pertama.\n'
              '6. Pada baris kedua, berikan maklum balas peribadi ringkas (1-2 ayat) dalam Bahasa Malaysia.\n\n'
              'Contoh jawapan yang MESTI diterima:\n'
              '- "Pemboleh ubah sejagat" = "pemboleh ubah sejagat" = "PEMBOLEH UBAH SEJAGAT"\n'
              '- "Leraian" = "leraian" = "decomposition" = "memecahkan masalah"\n'
              '- "Integer" = "integer" = "nombor bulat"\n\n'
              'Format:\n'
              'YA atau TIDAK\n'
              'Maklum balas anda di sini';

          final response = await _markingModel.generateContent([
            Content.text(prompt),
          ]);

          final responseText = response.text?.trim() ?? "";
          final lines = responseText.split('\n');
          
          final verdict = lines.isNotEmpty ? lines[0].toUpperCase().trim() : "TIDAK";
          final feedback = lines.length > 1 ? lines.sublist(1).join(' ').trim() : "Tiada maklum balas tersedia.";

          // Accept both "YA" (Malay) and "YES" (English) from AI
          if (verdict == 'YA' || verdict == 'YES') {
            score++;
            aiFeedback[q.id] = "✅ $feedback";
          } else {
            aiFeedback[q.id] = "❌ $feedback\n\nJawapan Dijangka: $correctAnswer";
          }
        } catch (e) {
          print('AI marking error: $e');
          aiFeedback[q.id] = "❌ Tidak dapat mengesahkan jawapan. Dijangka: $correctAnswer";
        }
      }
    }
  }

  if (!mounted) return;

  await _saveQuizScoreToDatabase(score, widget.questions.length);
  await _saveQuizToProgressRecords(score, widget.questions.length);

  // Pass AI feedback to the attempt
  final attempt = QuizAttempt(
    quizTitle: widget.quizTitle,
    questions: widget.questions,
    userAnswers: Map.from(_userAnswers),
    score: score,
    total: widget.questions.length,
    timestamp: DateTime.now(),
    aiFeedback: aiFeedback,
  );

  await _saveQuizAttemptToFirestore(attempt);

  userQuizAttempts.add(attempt);

  if (!mounted) return;
  setState(() => _isSubmitting = false);

  if (!mounted) return;
  Navigator.pop(context);

  if (!mounted) return;
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => QuizResultsPage(attempt: attempt),
    ),
  );
}

// ✅ NEW: Save quiz attempt to Firestore
Future<void> _saveQuizAttemptToFirestore(QuizAttempt attempt) async {
  final userState = context.read<FirebaseUserState>();
  final user = userState.currentUser;
  if (user == null || !mounted) return;

  try {
    // Convert questions to map format
    final questionsData = attempt.questions.map((q) => q.toMap()).toList();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.id)
        .collection('quiz_attempts')
        .add({
      'quizTitle': attempt.quizTitle,
      'questions': questionsData,
      'userAnswers': attempt.userAnswers,
      'score': attempt.score,
      'total': attempt.total,
      'timestamp': FieldValue.serverTimestamp(),
      'aiFeedback': attempt.aiFeedback ?? {},
    });

    print('✅ Quiz attempt saved to Firestore');
  } catch (e) {
    print('❌ Error saving quiz attempt: $e');
  }
}

  /* ----- submitQuiz ----- (Updated submit quiz with AI Marking)
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

    // ✅ Save Quiz to Progress Records function
    await _saveQuizToProgressRecords(score, widget.questions.length);

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
  }*/

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

  // ----- showSubmitDialog -----
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

// ========== QUIZ RESULTS PAGE (US006-02 & US006-03) ==========
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
    final isCorrect = userAnswer?.toLowerCase().trim() == q.answer.toLowerCase().trim();
    
    // NEW: Get AI feedback
    final feedback = attempt.aiFeedback?[q.id] ?? '';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: isCorrect ? Colors.green[50] : Colors.red[50],
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
            Text(
              'Your Answer: $userAnswer',
              style: TextStyle(
                color: isCorrect ? Colors.green[800] : Colors.red[800],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!isCorrect) ...[
              const SizedBox(height: 4),
              Text(
                'Correct Answer: ${q.answer}',
                style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w500),
              ),
            ],
            
            // NEW: Display AI personalized feedback
            if (feedback.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8.0),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.psychology, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 6),
                        Text(
                          'AI Feedback:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: TextStyle(color: Colors.blue[900], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
            
            // Show explanation if available
            if (q.explanation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8.0),
                width: double.infinity,
                color: Colors.grey[200],
                child: Text(
                  'Explanation: ${q.explanation}',
                  style: TextStyle(color: Colors.grey[800], fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  },
)

            /*ListView.builder(
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
            ),*/
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

// ========== AI CHATBOT PAGE ==========
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

// ========== CHATBODY ==========
class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

// ========== CHATBODY STATE ==========
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
                      borderRadius: BorderRadius.circular(12),
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

                        context.read<ChatBloc>().add(
            SubmitChatRatingEvent(s),
          );
          
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

class SubmitChatRatingEvent extends ChatEvent {
  final int rating;
  SubmitChatRatingEvent(this.rating);
}

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
        'Anda adalah seorang tutor AI yang membantu dalam pengaturcaraan Java untuk pelajar Malaysia. '
        'Jawab soalan tentang konsep Java, sintaks, prinsip OOP, dan bantu dengan masalah pengaturcaraan. '
        'Pastikan respons jelas, mendidik, dan menyokong. Anda boleh menjawab dalam Bahasa Inggeris dan Bahasa Malaysia.',
      ),
    );

    on<SendMessageEvent>(_onSendMessage);
    on<ClearChatEvent>(_onClearChat);
    on<LoadWelcomeEvent>(_onLoadWelcome);
    on<LoadChatHistoryEvent>(_onLoadChatHistory);
    on<SubmitChatRatingEvent>(_onSubmitChatRating);

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

  Future<void> _onSubmitChatRating(
  SubmitChatRatingEvent event,
  Emitter<ChatState> emit,
) async {
  final user = firebase_auth.FirebaseAuth.instance.currentUser;

  if (user == null) {
    debugPrint('❌ No logged-in user');
    return;
  }

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chatbot_ratings')
        .add({
      'rating': event.rating,
      'source': 'AI Chatbot',
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint('✅ Chatbot rating saved');
  } catch (e) {
    debugPrint('❌ Failed to save rating: $e');
  }
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
  final String? studentId;
  final String activity;
  final double score;
  final String grade;
  final String comments;
  final Timestamp? timestamp;
  final bool isAutoGenerated; 

  ProgressRecord({
    required this.id,
    required this.student,
    this.studentId,
    required this.activity,
    required this.score,
    required this.grade,
    required this.comments,
    required this.timestamp,
    this.isAutoGenerated = false, 
  });

  factory ProgressRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProgressRecord(
      id: doc.id,
      student: data['student'] ?? '',
      studentId: data['studentId'] as String?,
      activity: data['activity'] ?? '',
      score: (data['score'] ?? 0).toDouble(),
      grade: data['grade'] ?? '',
      comments: data['comments'] ?? '',
      timestamp: data['timestamp'] as Timestamp?,
      isAutoGenerated: data['isAutoGenerated'] ?? false,
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

   // Filtering state variables
  String? _selectedQuizFilter;
  double _minScoreFilter = 0;
  double _maxScoreFilter = 100;
  bool _showFilterOptions = false;
  List<String> _availableQuizzes = []; 

  @override
  void initState() {
    super.initState();
    _loadAvailableQuizzes();
  }

// Fetch available quizzes for the dropdown
Future<void> _loadAvailableQuizzes() async {
  try {
    final snapshot = await _fs
        .collection('progress_records')
        .get();

    final quizTitles = snapshot.docs
        .map((doc) => doc['activity'] as String)
        .toSet()
        .toList();

    setState(() {
      _availableQuizzes = quizTitles..sort();
    });
  } catch (e) {
    print('Error loading quiz list: $e');
    // Provide empty list on error
    setState(() {
      _availableQuizzes = [];
    });
  }
}

  // Clear all filters
  void _clearFilters() {
    setState(() {
      _selectedQuizFilter = null;
      _minScoreFilter = 0;
      _maxScoreFilter = 100;
      _showFilterOptions = false;
    });
  }

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
        .limit(50)  
        .get();

    // Filter results locally
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
    print('❌ User search error: $e');
    setState(() => _isSearching = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User search failed: $e')),
      );
    }
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
    // Get the student ID from search results
    final studentId = _searchResults
        .firstWhere(
          (result) => result['username'] == _selectedStudentUsername,
          orElse: () => {},
        )
        ['id'];

    final record = {
      'student': _selectedStudentUsername,
      'studentId': studentId, 
      'activity': _activityController.text.trim(),
      'score': double.tryParse(_scoreController.text) ?? 0,
      'grade': _gradeController.text.trim(),
      'comments': _commentsController.text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'isAutoGenerated': false, 
    };

    await _fs.collection('progress_records').add(record);

    // Clear form
    _activityController.clear();
    _scoreController.clear();
    _gradeController.clear();
    _commentsController.clear();
    setState(() {
      _selectedStudentUsername = null;
      _searchController.clear();
      _searchResults.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress added successfully'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to add progress: $e')),
    );
  }
}

  Future<void> _confirmAndDelete(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted successfully!')));
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
                decoration: InputDecoration(labelText: 'Activity', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),)),
                validator: (v) => v!.isEmpty ? 'Enter activity' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: scoreCtl,
                decoration: InputDecoration(labelText: 'Score', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),)),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? 'Enter score' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: gradeCtl,
                decoration: InputDecoration(labelText: 'Grade', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),)),
                validator: (v) => v!.isEmpty ? 'Enter grade' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: commentsCtl,
                decoration: InputDecoration(labelText: 'Comments', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),)),
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
        title: const Text('📈 Student Progress'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          if (isTeacher)
          // Class Dashboard Button
          IconButton(
            icon: const Icon(Icons.dashboard, color: Colors.white),
            tooltip: 'Class Dashboard',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClassDashboardPage()),
              ),
              ),
            // Progress History Button
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              tooltip: 'Progress History',
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
              Card(
          elevation: 3,
          color: Colors.blue[50],
          child: ExpansionTile(
            leading: const Icon(Icons.filter_list, color: Colors.blue),
            title: const Text(
              'Filter Students by Quiz Score',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: _showFilterOptions,
            onExpansionChanged: (expanded) {
              setState(() => _showFilterOptions = expanded);
            },
             tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
             childrenPadding: EdgeInsets.zero, 
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quiz Selector Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedQuizFilter,
                      decoration: InputDecoration(
                        labelText: 'Select Quiz',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.quiz),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      hint: const Text('All Quizzes'),
                      isExpanded: true, 
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Quizzes'),
                        ),
                        ..._availableQuizzes.map(
                          (quiz) => DropdownMenuItem(
                            value: quiz,
                            child: Text(
                              quiz,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedQuizFilter = value);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Score Range Slider
                    const Text(
                      'Score Range',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    RangeSlider(
                      values: RangeValues(_minScoreFilter, _maxScoreFilter),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      labels: RangeLabels(
                        '${_minScoreFilter.toStringAsFixed(0)}%',
                        '${_maxScoreFilter.toStringAsFixed(0)}%',
                      ),
                      onChanged: (RangeValues values) {
                        setState(() {
                          _minScoreFilter = values.start;
                          _maxScoreFilter = values.end;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Min: ${_minScoreFilter.toStringAsFixed(0)}%'),
                        Text('Max: ${_maxScoreFilter.toStringAsFixed(0)}%'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Clear Filters Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Filters'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search by username...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
                      decoration: InputDecoration(
                        labelText: 'Activity',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter activity' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _scoreController,
                      decoration: InputDecoration(
                        labelText: 'Score',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Please enter score' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _gradeController,
                      decoration: InputDecoration(
                        labelText: 'Grade',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
                      ),
                      validator: (v) => v!.isEmpty ? 'Please enter grade' : null,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _commentsController,
                      decoration: InputDecoration(
                        labelText: 'Comments',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
                      Text('Below are manually and automated progress records.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                isTeacher ? 'Progress Records' : 'Your Progress Records',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ),
              const SizedBox(height: 8),
              
              // TEACHER VIEW with Filtering
              if (isTeacher)
              StreamBuilder<QuerySnapshot>(
                stream: _fs.collection('progress_records').snapshots(),
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                    }
                    
                    // Apply filters
                    var records = snap.data!.docs
                    .map((d) => ProgressRecord.fromDoc(d))
                    .toList();
                    
                    // Filter by selected quiz
                    if (_selectedQuizFilter != null) {
                      records = records
                      .where((r) => r.activity == _selectedQuizFilter)
                      .toList();
                      }
                      
                      // Filter by score range
                      records = records
                      .where((r) => r.score >= _minScoreFilter && r.score <= _maxScoreFilter)
                      .toList();

      // Sort by timestamp (newest first)
      records.sort((a, b) {
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return b.timestamp!.compareTo(a.timestamp!);
      });

       // LIMIT TO LATEST 3 RECORDS
      final limitedRecords = records.take(3).toList();
      final totalRecords = records.length;

      // Show "No students found" if empty after filtering
      if (records.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'No students found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedQuizFilter != null
                      ? 'No students match the filter criteria for "$_selectedQuizFilter"'
                      : 'Try adjusting your filters',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }

      // Show filter summary if filters are active
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedQuizFilter != null || _minScoreFilter > 0 || _maxScoreFilter < 100)
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing ${records.length} result(s) for '
                        '${_selectedQuizFilter ?? "all quizzes"} '
                        '(${_minScoreFilter.toStringAsFixed(0)}% - ${_maxScoreFilter.toStringAsFixed(0)}%)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // INFO BANNER: Showing latest 3 only
          if (totalRecords > 3)
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing latest 3 of ${totalRecords} records. View all in History.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProgressHistoryPage(),
                        ),
                      ),
                      child: const Text('View All'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // Display filtered records (LATEST 3 ONLY)
          ...limitedRecords.map((r) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  r.isAutoGenerated ? Icons.auto_awesome : Icons.edit,
                  color: r.isAutoGenerated ? Colors.purple : Colors.blue,
                ),
                title: Text('${r.student} — ${r.activity}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Score: ${r.score.toStringAsFixed(1)}%, Grade: ${r.grade}'),
                    if (r.comments.isNotEmpty) Text(r.comments),
                    if (r.isAutoGenerated)
                      const Text(
                        '🤖 Auto-generated from quiz',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.purple,
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: !r.isAutoGenerated
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
          }),
        ],
      );
    },
  ),

// STUDENT VIEW (shows both manual and auto-generated)
if (!isTeacher)
  StreamBuilder<QuerySnapshot>(
    stream: _fs
        .collection('progress_records')
        .where('student', isEqualTo: currentUsername)
        .snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final records = snap.data!.docs
          .map((d) => ProgressRecord.fromDoc(d))
          .toList();
      
      records.sort((a, b) {
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return b.timestamp!.compareTo(a.timestamp!);
      });

      if (records.isEmpty) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('No progress records yet.'),
            ),
          ),
        );
      }

      return Column(
        children: records.map((r) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                r.isAutoGenerated ? Icons.auto_awesome : Icons.school,
                color: r.isAutoGenerated ? Colors.purple : Colors.blue,
              ),
              title: Text(r.activity),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score: ${r.score.toStringAsFixed(1)}%, Grade: ${r.grade}'),
                  if (r.comments.isNotEmpty) Text(r.comments),
                  if (r.isAutoGenerated)
                    const Text(
                      '🤖 Auto-recorded from quiz',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.purple,
                      ),
                    ),
                ],
              ),
              isThreeLine: true,
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


// PROGRESS HISTORY PAGE - WITH EDIT & DELETE
class ProgressHistoryPage extends StatefulWidget {
  const ProgressHistoryPage({super.key});

  @override
  State<ProgressHistoryPage> createState() => _ProgressHistoryPageState();
}

class _ProgressHistoryPageState extends State<ProgressHistoryPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Search and filter state
  String _searchQuery = '';
  String? _selectedActivityFilter;
  List<String> _availableActivities = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableActivities();
  }

  Future<void> _loadAvailableActivities() async {
    try {
      final snapshot = await _fs.collection('progress_records').get();
      final activities = snapshot.docs
          .map((doc) => doc['activity'] as String)
          .toSet()
          .toList();

      setState(() {
        _availableActivities = activities..sort();
      });
    } catch (e) {
      print('Error loading activities: $e');
    }
  }

  Future<void> _confirmAndDelete(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _fs.collection('progress_records').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Record deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
        title: const Text('Edit Progress Record'),
        content: SingleChildScrollView(
          child: Form(
            key: editFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Student: ${record.student}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: activityCtl,
                  decoration: InputDecoration(
                    labelText: 'Activity',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.assignment),
                  ),
                  validator: (v) => v!.isEmpty ? 'Enter activity' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: scoreCtl,
                  decoration: InputDecoration(
                    labelText: 'Score',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.score),
                    suffixText: '%',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v!.isEmpty) return 'Enter score';
                    final score = double.tryParse(v);
                    if (score == null || score < 0 || score > 100) {
                      return 'Enter valid score (0-100)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: gradeCtl,
                  decoration: InputDecoration(
                    labelText: 'Grade',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.grade),
                  ),
                  validator: (v) => v!.isEmpty ? 'Enter grade' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: commentsCtl,
                  decoration: InputDecoration(
                    labelText: 'Comments (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.comment),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Changes'),
            onPressed: () async {
              if (!(editFormKey.currentState?.validate() ?? false)) return;

              try {
                await _fs.collection('progress_records').doc(record.id).update({
                  'activity': activityCtl.text.trim(),
                  'score': double.tryParse(scoreCtl.text) ?? 0,
                  'grade': gradeCtl.text.trim(),
                  'comments': commentsCtl.text.trim(),
                });

                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Record updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Update failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

    if (!isTeacher) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'You are not allowed to view this page',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('📜 Progress History'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Search by student name or activity...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
                ),
                const SizedBox(height: 12),

                // Activity Filter Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedActivityFilter,
                  decoration: InputDecoration(
                    labelText: 'Filter by Activity',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.filter_list),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  hint: const Text('All Activities'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Activities'),
                    ),
                    ..._availableActivities.map(
                      (activity) => DropdownMenuItem(
                        value: activity,
                        child: Text(activity),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedActivityFilter = value);
                  },
                ),
              ],
            ),
          ),

          // Records List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fs.collection('progress_records').snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var records = snap.data!.docs
                    .map((d) => ProgressRecord.fromDoc(d))
                    .toList();

                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  records = records.where((r) {
                    return r.student.toLowerCase().contains(_searchQuery) ||
                        r.activity.toLowerCase().contains(_searchQuery);
                  }).toList();
                }

                // Apply activity filter
                if (_selectedActivityFilter != null) {
                  records = records
                      .where((r) => r.activity == _selectedActivityFilter)
                      .toList();
                }

                // Sort by timestamp (newest first)
                records.sort((a, b) {
                  if (a.timestamp == null) return 1;
                  if (b.timestamp == null) return -1;
                  return b.timestamp!.compareTo(a.timestamp!);
                });

                if (records.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _selectedActivityFilter != null
                              ? 'No records match your filters'
                              : 'No progress records found.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: r.isAutoGenerated
                              ? Colors.purple[100]
                              : Colors.blue[100],
                          child: Icon(
                            r.isAutoGenerated ? Icons.auto_awesome : Icons.edit,
                            color: r.isAutoGenerated ? Colors.purple : Colors.blue,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${r.student} — ${r.activity}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(r.grade),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Grade: ${r.grade}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Score: ${r.score.toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            if (r.comments.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                r.comments,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                            if (r.timestamp != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.yMMMd().add_jm().format(
                                      r.timestamp!.toDate(),
                                    ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                            if (r.isAutoGenerated)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  '🤖 Auto-generated from quiz',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.purple,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: !r.isAutoGenerated
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Edit Record',
                                    onPressed: () => _showEditDialog(r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Delete Record',
                                    onPressed: () => _confirmAndDelete(r.id),
                                  ),
                                ],
                              )
                            : Tooltip(
                                message: 'Auto-generated records cannot be edited',
                                child: Icon(
                                  Icons.lock,
                                  color: Colors.grey[400],
                                  size: 20,
                                ),
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

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      case 'F':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
// Dashbord Page within Progress Page
class ClassDashboardPage extends StatelessWidget {
  const ClassDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore fs = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Class Performance'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: fs.collection('progress_records').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!.docs
              .map((doc) => ProgressRecord.fromDoc(doc))
              .toList();

          if (records.isEmpty) {
            return const Center(
              child: Text('No progress data available yet.'),
            );
          }

          return FutureBuilder<Map<String, dynamic>>(
            future: _calculateAnalytics(records),
            builder: (context, analyticsSnapshot) {
              if (!analyticsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final analytics = analyticsSnapshot.data!;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. KEY METRICS CARDS
                    _buildKeyMetricsSection(analytics),
                    const SizedBox(height: 16),

                    // 2. GRADE DISTRIBUTION PIE CHART
                    _buildGradeDistributionCard(analytics),
                    const SizedBox(height: 16),

                    // 3. TOPIC PERFORMANCE BAR CHART + SORTED LIST
                    _buildTopicPerformanceCard(analytics),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }


  // ANALYTICS CALCULATION
  Future <Map<String, dynamic>> _calculateAnalytics(List<ProgressRecord> records) async {
    final FirebaseFirestore fs = FirebaseFirestore.instance;
     // Get all registered students
  final usersSnapshot = await fs.collection('users')
      .where('userType', isEqualTo: 'UserType.student')
      .get();
  final registeredStudents = usersSnapshot.docs.length;

   // Overall class average
    final totalScore = records.fold<double>(0, (sum, r) => sum + r.score);
    final classAverage = records.isEmpty ? 0.0 : totalScore / records.length;

    // Grade distribution
    final gradeCount = <String, int>{};
    for (var record in records) {
      gradeCount[record.grade] = (gradeCount[record.grade] ?? 0) + 1;
    }

    // Topic performance (average per topic)
    final topicScores = <String, List<double>>{};
    for (var record in records) {
      topicScores.putIfAbsent(record.activity, () => []).add(record.score);
    }

    final topicAverages = topicScores.map((topic, scores) {
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      return MapEntry(topic, avg);
    });

    // Sort topics by average (lowest first = struggling topics)
    final sortedTopics = topicAverages.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Student completion tracking
    final uniqueStudents = records.map((r) => r.student).toSet();
    final autoGeneratedRecords = records.where((r) => r.isAutoGenerated).toList();
    final studentsWithQuizzes = autoGeneratedRecords.map((r) => r.student).toSet();
    final completionRate = registeredStudents == 0 
        ? 0.0 
        : (studentsWithQuizzes.length / registeredStudents) * 100;

    return {
      'classAverage': classAverage,
      'totalStudents': registeredStudents,
      'totalRecords': records.length,
      'gradeDistribution': gradeCount,
      'topicAverages': sortedTopics,
      'completionRate': completionRate,
      'studentsWithQuizzes': studentsWithQuizzes.length,
    };
  }

  // 1. KEY METRICS SECTION
  Widget _buildKeyMetricsSection(Map<String, dynamic> analytics) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Class Average',
            '${analytics['classAverage'].toStringAsFixed(1)}%',
            Icons.trending_up,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Total Students',
            '${analytics['totalStudents']}',
            Icons.people,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Completion Rate',
            '${analytics['completionRate'].toStringAsFixed(0)}%',
            Icons.check_circle,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. GRADE DISTRIBUTION PIE CHART
  Widget _buildGradeDistributionCard(Map<String, dynamic> analytics) {
    final gradeDistribution = analytics['gradeDistribution'] as Map<String, int>;
    final totalRecords = analytics['totalRecords'] as int;

    if (gradeDistribution.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.pie_chart, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Grade Distribution',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: gradeDistribution.entries.map((entry) {
                    final percentage = (entry.value / totalRecords) * 100;
                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      title: '${entry.key}\n${percentage.toStringAsFixed(0)}%',
                      color: _getGradeColor(entry.key),
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: gradeDistribution.entries.map((entry) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _getGradeColor(entry.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${entry.key}: ${entry.value} students'),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      case 'F':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

// 3. TOPIC PERFORMANCE (BAR CHART WITH NUMBERED LABELS + LEGEND)
Widget _buildTopicPerformanceCard(Map<String, dynamic> analytics) {
  final sortedTopics = analytics['topicAverages'] as List<MapEntry<String, double>>;

  if (sortedTopics.isEmpty) {
    return const SizedBox.shrink();
  }

  // Limit to top 5 struggling topics (lowest scores)
  final topicsToShow = sortedTopics.take(5).toList();

  return Card(
    elevation: 3,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Topic Performance Analysis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Top 5 topics needing attention (sorted by average score)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // BAR CHART WITH NUMBERED LABELS
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barGroups: topicsToShow.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.value,
                        color: entry.value.value < 60
                            ? Colors.red
                            : entry.value.value < 75
                                ? Colors.orange
                                : Colors.green,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < topicsToShow.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${value.toInt() + 1}', // Show numbers: 1, 2, 3, 4, 5
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toInt()}%');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // LEGEND - NUMBERED LIST WITH TOPIC NAMES
          Text(
            'Legend',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          
          ...topicsToShow.asMap().entries.map((entry) {
            final index = entry.key;
            final topic = entry.value;
            final isStruggling = topic.value < 60;
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  // Number badge matching the chart
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: topic.value < 60
                          ? Colors.red
                          : topic.value < 75
                              ? Colors.orange
                              : Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        if (isStruggling)
                          const Text(
                            '⚠️ Students struggling with this topic',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${topic.value.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: topic.value < 60
                          ? Colors.red
                          : topic.value < 75
                              ? Colors.orange
                              : Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
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
  // FIX: Initialize the filter state variable
  String _selectedCategory = 'All'; // 'All', 'Badge', 'Certificate', 'Milestone', 'Other'

  String _searchQuery = '';
  // Helper function to get the correct achievement stream (Your original code)
  Stream<QuerySnapshot> getAchievementStream(AppUser? user) {
    var query = FirebaseFirestore.instance.collection('achievements');

    if (user != null && user.userType == UserType.student) {
      return query.where('studentId', isEqualTo: user.id).snapshots();
    } else if (user != null && user.userType == UserType.teacher) {
      return query.orderBy('dateEarned', descending: true).snapshots();
    } else {
      return query
          .orderBy('dateEarned', descending: true)
          .limit(30)
          .snapshots();
    }
  }

  // Function to delete an achievement 
  Future<void> _deleteAchievement(
    String achievementId,
    String achievementTitle,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Achievement'),
        content: Text('Are you sure you want to delete the achievement "$achievementTitle"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
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
            const SnackBar(
              content: Text('Achievement deleted successfully!'),
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

  // ⚠️ Function to show edit dialog 
  Future<void> _showEditAchievementDialog(
  Map<String, dynamic> achievement,
) async {
  // Navigate to the new EditAchievementPage
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => EditAchievementPage(achievement: achievement),
    ),
  );
  
  // Check for success message from EditAchievementPage
  if (result != null && result['success'] == true && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']),
        backgroundColor: Colors.green,
      ),
    );
    // StreamBuilder handles the UI refresh automatically
  }
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
        ? '🏆 Achievement'
        : '🏅 Community Achievement';

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
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
    if (isTeacher)
      IconButton(
        icon: const Icon(Icons.add_box),
        tooltip: 'Add Achievement',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddAchievementPage(),
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
        },
      ),
  ],
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

          // === START US0010-02 SEARCH UI ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search achievements by name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          // === END US0010-02 SEARCH UI ===

          // === START US013-01 FILTER UI ===
          if (isStudent)
            _buildCategoryFilter(),
          // === END US013-01 FILTER UI ===

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
                var achievements = snapshot.data!.docs
                    .map(
                      (doc) => {
                        'id': doc.id,
                        ...doc.data() as Map<String, dynamic>,
                      },
                    )
                    .toList();

                // === START FILTERING LOGIC (Applied to list after loading) ===

                // 1. Apply Search Filter (US0010-02)
                if (_searchQuery.isNotEmpty) {
                    achievements = achievements.where((a) {
                        final title = (a['title'] ?? '').toString().toLowerCase();
                        return title.contains(_searchQuery);
                    }).toList();
                }

                // 2. Apply Category Filter (US013-01) - Only for Students
                if (isStudent && _selectedCategory != 'All') {
                  achievements = achievements.where((a) {
                    final type = (a['type'] ?? 'Other').toString();
                    if (_selectedCategory == 'Badge' && (type.toLowerCase().contains('badge') || type.toLowerCase().contains('auto'))) return true;
                    if (_selectedCategory == 'Certificate' && type.toLowerCase().contains('certificate')) return true;
                    if (_selectedCategory == 'Milestone' && type.toLowerCase().contains('milestone')) return true;
                    if (_selectedCategory == 'Other' && !type.toLowerCase().contains('badge') && !type.toLowerCase().contains('certificate') && !type.toLowerCase().contains('milestone')) return true;
                    return false;
                  }).toList();
                }
                // === END FILTERING LOGIC ===
                final totalAchievements = snapshot.data!.docs.length;

                final isFilteredEmpty = totalAchievements > 0 && achievements.isEmpty;
                
                return _buildAchievementListView(
                  achievements,
                  isLoggedIn,
                  isTeacher,
                  user!.id,
                  isFilteredEmpty,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // === START US013-01 NEW WIDGETS ===
  Widget _buildCategoryFilter() {
    // Categories based on types used in database
    final categories = ['All', 'Badge', 'Certificate', 'Milestone', 'Other'];
    
    // Helper to change state
    void _setCategory(String category) {
      setState(() {
        _selectedCategory = category;
        _searchQuery = ''; // Clear search when changing category filter
      });
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((category) {
          final isSelected = _selectedCategory == category;
          return Padding(
             padding: const EdgeInsets.only(right: 8.0),
             child: ActionChip(
                label: Text(
                  category,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.blueGrey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                backgroundColor: isSelected ? Colors.lightBlue : Colors.grey[200],
                onPressed: () => _setCategory(category),
                avatar: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
              ),
          );
        }).toList(),
      ),
    );
  }
  // === END US013-01 NEW WIDGETS ===

  // Note: Include _buildAchievementListView, _deleteAchievement, _showEditAchievementDialog logic here from your file
  
  Widget _buildAchievementListView(
    List<Map<String, dynamic>> achievements,
    bool isLoggedIn,
    bool isTeacher,
    String? currentUserId,
    bool isFilteredEmpty,
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
                // MODIFIED: Use the new flag to show the correct message
                isFilteredEmpty
                    ? 'No achievements match your search or filter criteria.'
                    : (isLoggedIn
                        ? 'You have no achievements yet. Start learning and completing quizzes!'
                        : 'No public achievements found.'),
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
                      // FIX: Wrap the date text in Expanded to prevent overflow
                      Expanded(
                        child: Text(
                          'Earned: ${when.toLocal().toString().split(' ')[0]}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
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
    // ✅ FIX: Simplified query - remove orderBy to avoid index requirement
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('userType', isEqualTo: 'UserType.student')
        .limit(50)
        .get();

    // ✅ Sort in code instead of in query
    final students = snapshot.docs
        .map((doc) => AppUser.fromMap(doc.id, doc.data()))
        .toList();
    
    // Sort by username locally
    students.sort((a, b) => a.username.compareTo(b.username));
    
    return students;
  } catch (e) {
    print("❌ Error fetching student list: $e");
    // Return empty list instead of fallback data
    return [];
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
                decoration:  InputDecoration(
                  labelText: 'Achievement Title',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
                decoration:  InputDecoration(
                  labelText: 'Achievement Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
          decoration:  InputDecoration(
            labelText: 'Select Student to Award',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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

// ========== EDIT ACHIEVEMENT PAGE ==========
class EditAchievementPage extends StatefulWidget {
  final Map<String, dynamic> achievement;
  const EditAchievementPage({super.key, required this.achievement});

  @override
  State<EditAchievementPage> createState() => _EditAchievementPageState();
}

class _EditAchievementPageState extends State<EditAchievementPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late String _currentType;
  bool _isLoading = false;

  final List<String> _achievementTypes = [
    'Badge',
    'Certificate',
    'Milestone',
    'Other',
    'Badge (Auto)',
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.achievement['title'] ?? '');
    _descriptionController = TextEditingController(text: widget.achievement['description'] ?? '');
    _currentType = widget.achievement['type'] ?? 'Badge';

    // Ensure the current type is available in the dropdown if it's a special type
    if (!_achievementTypes.contains(_currentType)) {
      _achievementTypes.add(_currentType);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() => _isLoading = true);

      try {
        final achievementId = widget.achievement['id'] as String;

        final achievementData = {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'type': _currentType,
          'editedAt': FieldValue.serverTimestamp(),
          // Student details are not updated, only content fields
        };

        await FirebaseFirestore.instance
            .collection('achievements')
            .doc(achievementId)
            .update(achievementData);

        if (context.mounted) {
          Navigator.pop(context, {
            'success': true,
            'message': 'Achievement "${_titleController.text.trim()}" updated successfully.',
          });
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
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentName = widget.achievement['studentName'] ?? 'Unknown Student';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Achievement'),
        backgroundColor: Colors.amber, // Matches the Add page's AppBar color
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Display Student Name (Replaces the student selector from AddAchievementPage)
              Card(
                color: Colors.blue[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Student Awarded:',
                              style: TextStyle(color: Colors.grey[700], fontSize: 13),
                            ),
                            Text(
                              studentName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 1. Title Input
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Achievement Title',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.star),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 2. Type Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Achievement Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.category),
                ),
                value: _currentType,
                items: _achievementTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _currentType = newValue!;
                  });
                },
              ),
              const SizedBox(height: 20),

              // 3. Description Input
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              // 4. Save Button (Styled like the Add button)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSave,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isLoading ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Use green for consistency with save/award
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
}

// ---------- Profile ----------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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

    // ✅ FIX: Use putData directly without storing uploadTask
    await storageRef.putData(imageBytes, metadata);

    // Get download URL after upload completes
    final downloadUrl = await storageRef.getDownloadURL();
    
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

// ========== LEARNING MATERIAL ==========
class LearningMaterial {
  final String id, name, description, file;
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

// ========== MATERIAL APP STATE ==========
class MaterialAppState extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ----- checkStorageConfiguration -----
  Future<void> checkStorageConfiguration() async {
    try {
      final ref = FirebaseStorage.instance.ref().child('learning_materials');
      await ref.listAll();
      print('✅ Storage configuration OK');
    } catch (e) {
      print('❌ Storage error: $e');
    }
  }

  // ----- createMaterialsCollection -----
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

  // ----- addMaterial -----
  Future<void> addMaterial(LearningMaterial material) async {
    final map = material.toMap();
    map['time'] ??= Timestamp.now();
    await _db.collection('materials').add(map);
  }

  // ----- ditMaterial -----
  Future<void> editMaterial(LearningMaterial material) async {
    final map = material.toMap();
    map['time'] ??= Timestamp.now();
    await _db.collection('materials').doc(material.id).update(map);
  }

  // ----- deleteMaterial -----
  Future<void> deleteMaterial(LearningMaterial material) async {
    await _db.collection('materials').doc(material.id).delete();

    if (material.file.startsWith('http')) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(material.file);
        await ref.delete();
        print('✅ File deleted from storage');
      } catch (e) {
        print('❌ Error deleting file from storage: $e');
      }
    }
  }
}

// ========== MATERIALS PAGE ==========
class MaterialsPage extends StatefulWidget {
  const MaterialsPage({super.key});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

// ========== MATERIALS PAGE STATE ==========
class _MaterialsPageState extends State<MaterialsPage> {
  String searchQuery = '';
  String userType = 'UserType.student';

  String _getUniqueFileName(LearningMaterial material) {
    if (!material.file.startsWith('http')) return '';

    final Uri uri = Uri.parse(material.file);
    String fileName = uri.pathSegments.last.split('?').first;
    fileName = Uri.decodeComponent(fileName);

    if (fileName.contains('learning_materials/')) {
      fileName = fileName.split('learning_materials/').last;
    }
    return fileName;
  }

  Future<String> _getLocalFilePath(LearningMaterial material) async {
    final fileName = _getUniqueFileName(material);
    if (fileName.isEmpty) return '';

    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$fileName';
  }

  // ----- downloadFile -----
  Future<void> _downloadFile(BuildContext context, LearningMaterial material,
      {bool openAfterDownload = true}) async {
    final filePath = material.file;

    if (!filePath.startsWith('http')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Only cloud files can be downloaded.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final savePath = await _getLocalFilePath(material);
    final downloadFile = File(savePath);

    // 1. Check local status first
    if (await downloadFile.exists()) {
      if (openAfterDownload) {
        await OpenFile.open(downloadFile.path);
      }
      return;
    }

    // 2. CHECK INTERNET BEFORE SHOWING DIALOG
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Internet Connection. Cannot download file.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return; 
    }

    try {
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

      final ref = FirebaseStorage.instance.refFromURL(filePath);
      await ref.writeToFile(downloadFile);

      if (context.mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Material downloaded successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () => OpenFile.open(downloadFile.path),
            ),
          ),
        );

        if (openAfterDownload) {
          await OpenFile.open(downloadFile.path);
        }
      }
    } catch (e) {
      if (context.mounted) {
        if (Navigator.of(context).canPop()) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      setState(() {
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
      appBar: AppBar(
        title: const Text('📚 Material'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        actions: [
          if (userType == UserType.teacher.toString())
            IconButton(
              icon: const Icon(Icons.add_box),
              tooltip: 'Upload material',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UploadPage()),
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
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Search materials...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                        'No materials uploaded yet.\nClick "+" to add materials.',
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

                      return FutureBuilder<bool>(
                        future: _getLocalFilePath(material)
                            .then((localPath) => File(localPath).exists()),
                        builder: (context, snapshot) {
                          final isDownloaded = snapshot.data ?? false;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              leading: Icon(
                                Icons.file_present,
                                color: isDownloaded
                                    ? Colors.green
                                    : theme.colorScheme.primary,
                                size: 32,
                              ),
                              title: Text(
                                material.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (material.description.isNotEmpty)
                                    Text(
                                      material.description,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Uploaded: ${DateFormat.yMMMd().add_jm().format(material.time)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final localPath =
                                    await _getLocalFilePath(material);
                                if (await File(localPath).exists()) {
                                  await OpenFile.open(localPath);
                                } else {
                                  await _downloadFile(context, material,
                                      openAfterDownload: true);
                                }
                                setState(() {});
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // DOWNLOAD/FOLDER BUTTON
                                  IconButton(
                                    icon: Icon(
                                      isDownloaded
                                          ? Icons.folder_open
                                          : Icons.cloud_download,
                                      color: isDownloaded
                                          ? Colors.blue
                                          : Colors.green,
                                    ),
                                    tooltip: isDownloaded
                                        ? 'Open Local File'
                                        : 'Download File',
                                    onPressed: () async {
                                      await _downloadFile(context, material);
                                      setState(() {});
                                    },
                                  ),

                                  // Teacher actions
                                  if (userType == UserType.teacher.toString()) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          color: Colors.blue),
                                      onPressed: () async {
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
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                            content: Text(result['message']),
                                            backgroundColor: Colors.green,
                                          ));
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                                'Delete Confirmation'),
                                            content: const Text(
                                                'Are you sure you want to delete this material?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        context, false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        context, true),
                                                child: const Text('Confirm'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          await appState
                                              .deleteMaterial(material);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text(
                                                'Material deleted successfully!'),
                                            backgroundColor: Colors.green,
                                          ));
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
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

// ========== UPLOAD PAGE ==========
class UploadPage extends StatefulWidget {
  final LearningMaterial? existingMaterial;
  const UploadPage({super.key, this.existingMaterial});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

// ========== UPLOAD PAGE STATE ==========
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

  // ----- pickFile -----
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

  // ----- getContentType -----
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

  // ----- submit -----
  Future<void> submit(BuildContext context) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    
    final isEditing = widget.existingMaterial != null;
    
    if (!isEditing && _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file to upload.'),
          backgroundColor: Colors.red,
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
              ? 'Are you sure you want to update this material?'
              : 'Are you sure you want to upload this material?',
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
                decoration: InputDecoration(
                  labelText: 'Material Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
                decoration: InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),),
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
