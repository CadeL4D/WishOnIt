import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../firebase_options.dart';
import '../services/database_service.dart';
import 'register_screen.dart';
import 'dashboard_screen.dart';
import 'join_group_screen.dart';

enum ActiveForm { none, signIn, joinGroup }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  ActiveForm _activeForm = ActiveForm.none;
  bool _isLoading = false;
  bool _showSignInDetails = false;
  bool _showJoinGroupDetails = false;
  Timer? _signInRevealTimer;
  Timer? _joinGroupRevealTimer;

  // Controllers for Sign In
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Controller for Join Group
  final TextEditingController _joinCodeController = TextEditingController();

  // Defer DatabaseService instantiation to avoid Firebase init errors in testing
  DatabaseService get _databaseService => DatabaseService();

  @override
  void dispose() {
    _signInRevealTimer?.cancel();
    _joinGroupRevealTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  // --- Auth Logic ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? null : DefaultFirebaseOptions.ios.iosClientId,
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        await _databaseService.saveUserData(userCredential.user!);
        if (mounted) _routeToDashboard();
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An error occurred during sign in');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithEmailPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter both email and password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (userCredential.user != null && mounted) {
        _routeToDashboard();
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _routeToDashboard() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
      (route) => false,
    );
  }

  // --- Join Group Logic ---
  Future<void> _findGroupAndProceed() async {
    final code = _joinCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError('Please enter a Group Code.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final groupDoc = await _databaseService.getGroupByCode(code);
      if (groupDoc != null) {
        final data = groupDoc.data() as Map<String, dynamic>;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => JoinGroupScreen(
                initialGroupId: groupDoc.id,
                initialGroupName: data['name'],
                initialGroupCode: code,
              ),
            ),
          );
        }
      } else {
        _showError('Invalid group code. Please try again.');
      }
    } catch (e) {
      _showError('Error finding group: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setActiveForm(ActiveForm form) {
    if (_activeForm == form && (form != ActiveForm.signIn || _showSignInDetails)) {
      return;
    }

    _signInRevealTimer?.cancel();
    _joinGroupRevealTimer?.cancel();

    setState(() {
      _activeForm = form;
      _showSignInDetails = false;
      _showJoinGroupDetails = false;
    });

    if (form == ActiveForm.signIn) {
      _signInRevealTimer = Timer(const Duration(milliseconds: 420), () {
        if (!mounted || _activeForm != ActiveForm.signIn) return;
        setState(() => _showSignInDetails = true);
      });
    } else if (form == ActiveForm.joinGroup) {
      _joinGroupRevealTimer = Timer(const Duration(milliseconds: 420), () {
        if (!mounted || _activeForm != ActiveForm.joinGroup) return;
        setState(() => _showJoinGroupDetails = true);
      });
    }
  }

  // --- UI Builders ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Welcome to\nWishedOn',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              
              // Side-by-side Morphing Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final availableWidth = totalWidth - 16; // 16 is the SizedBox width gap
                  
                  double signInWidth;
                  double joinWidth;
                  
                  if (_activeForm == ActiveForm.signIn) {
                    signInWidth = availableWidth * 0.8;
                    joinWidth = availableWidth * 0.2;
                  } else if (_activeForm == ActiveForm.joinGroup) {
                    signInWidth = availableWidth * 0.2;
                    joinWidth = availableWidth * 0.8;
                  } else {
                    signInWidth = availableWidth * 0.5;
                    joinWidth = availableWidth * 0.5;
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sign In Card
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.fastOutSlowIn,
                        width: signInWidth,
                        child: _buildSignInCard(
                          isActive: _activeForm == ActiveForm.signIn,
                          isMinimized: _activeForm == ActiveForm.joinGroup,
                          onTap: () => _setActiveForm(ActiveForm.signIn),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Join Group Card
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.fastOutSlowIn,
                        width: joinWidth,
                        child: _buildJoinGroupCard(
                          isActive: _activeForm == ActiveForm.joinGroup,
                          isMinimized: _activeForm == ActiveForm.signIn,
                          onTap: () => _setActiveForm(ActiveForm.joinGroup),
                        ),
                      ),
                    ],
                  );
                }
              ),
              
              // Only when none is active, show the prompt to tap one.
              if (_activeForm == ActiveForm.none)
                Padding(
                  padding: const EdgeInsets.only(top: 40.0),
                  child: Text(
                    'Select an option to continue',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
      // Back button appears when a form is focused to return to default state
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      floatingActionButton: _activeForm != ActiveForm.none
          ? Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: FloatingActionButton.small(
                onPressed: () => _setActiveForm(ActiveForm.none),
                backgroundColor: Colors.white,
                elevation: 2,
                child: const Icon(Icons.arrow_back, color: Colors.black87),
              ),
            )
          : null,
    );
  }

  Widget _buildSignInCard({
    required bool isActive,
    required bool isMinimized,
    required VoidCallback onTap,
  }) {
    const color = Color(0xFF5D5FEF);

    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
        width: double.infinity,
        padding: isActive
            ? const EdgeInsets.all(20)
            : EdgeInsets.symmetric(vertical: 20, horizontal: isMinimized ? 8 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isActive ? 30 : 20),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha((isActive ? 0.2 : 0.15 * 255).toInt()),
              blurRadius: isActive ? 30 : 20,
              offset: Offset(0, isActive ? 15 : 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.fastOutSlowIn,
                padding: EdgeInsets.symmetric(
                  horizontal: isActive ? 20 : isMinimized ? 10 : 14,
                  vertical: isActive ? 16 : isMinimized ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(isActive ? 22 : 18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastOutSlowIn,
                      width: isActive ? 44 : isMinimized ? 28 : 36,
                      height: isActive ? 44 : isMinimized ? 28 : 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: color.withAlpha((0.12 * 255).toInt()),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.login_rounded,
                        size: isActive ? 24 : isMinimized ? 18 : 20,
                        color: color,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastOutSlowIn,
                      alignment: Alignment.centerLeft,
                      child: isMinimized
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: EdgeInsets.only(left: isActive ? 14 : 10),
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: isActive ? 24 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: isActive && _showSignInDetails ? 1 : 0,
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: _buildSignInForm(showTitle: false),
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    heightFactor: value,
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: value,
                      child: Padding(
                        padding: EdgeInsets.only(top: 20 * value),
                        child: IgnorePointer(
                          ignoring: value < 1,
                          child: child,
                        ),
                      ),
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

  Widget _buildJoinGroupCard({
    required bool isActive,
    required bool isMinimized,
    required VoidCallback onTap,
  }) {
    const color = Color(0xFF00C48C);

    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
        width: double.infinity,
        padding: isActive 
            ? const EdgeInsets.all(20) 
            : EdgeInsets.symmetric(vertical: 20, horizontal: isMinimized ? 8 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isActive ? 30 : 20),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha((isActive ? 0.2 : 0.15 * 255).toInt()),
              blurRadius: isActive ? 30 : 20,
              offset: Offset(0, isActive ? 15 : 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.fastOutSlowIn,
                padding: EdgeInsets.symmetric(
                  horizontal: isActive ? 20 : isMinimized ? 10 : 14,
                  vertical: isActive ? 16 : isMinimized ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(isActive ? 22 : 18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastOutSlowIn,
                      width: isActive ? 44 : isMinimized ? 28 : 36,
                      height: isActive ? 44 : isMinimized ? 28 : 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: color.withAlpha((0.12 * 255).toInt()),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.group_add_outlined,
                        size: isActive ? 24 : isMinimized ? 18 : 20,
                        color: color,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastOutSlowIn,
                      alignment: Alignment.centerLeft,
                      child: isMinimized
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: EdgeInsets.only(left: isActive ? 14 : 10),
                              child: Text(
                                isActive ? 'Enter Code' : 'Code',
                                style: TextStyle(
                                  fontSize: isActive ? 24 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: isActive && _showJoinGroupDetails ? 1 : 0,
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: _buildJoinGroupForm(showTitle: false),
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    heightFactor: value,
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: value,
                      child: Padding(
                        padding: EdgeInsets.only(top: 20 * value),
                        child: IgnorePointer(
                          ignoring: value < 1,
                          child: child,
                        ),
                      ),
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

  Widget _buildSignInForm({bool showTitle = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          const Text(
            'Sign In',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
        OutlinedButton(
          onPressed: _isLoading ? null : _signInWithGoogle,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Center(
                  child: Text('G', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('With Google', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email',
            filled: true,
            fillColor: const Color(0xFFF6F8FB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            filled: true,
            fillColor: const Color(0xFFF6F8FB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          obscureText: true,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 20),
        _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _signInWithEmailPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5D5FEF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: const Text('Log In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen())),
                    child: const Text('Create Account', style: TextStyle(color: Color(0xFF5D5FEF), fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
      ],
    );
  }

  Widget _buildJoinGroupForm({bool showTitle = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          const Text(
            'Join Group',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Enter 6-digit code',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _joinCodeController,
          decoration: InputDecoration(
            labelText: 'Code',
            hintText: 'A1B2C3',
            filled: true,
            fillColor: const Color(0xFFF6F8FB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ElevatedButton(
              onPressed: _findGroupAndProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C48C),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text('Find Group', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
      ],
    );
  }
}
