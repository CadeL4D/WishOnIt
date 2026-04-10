import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../services/database_service.dart';
import '../screens/join_group_screen.dart' show DateTextFormatter;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _nameController = TextEditingController();
  final _birthdateController = TextEditingController();
  final _emojiController = TextEditingController(text: '😊');
  final _databaseService = DatabaseService();

  bool _isLoading = true;
  bool _isSaving = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user == null) return;

    // Pre-fill display name from Auth
    _nameController.text = _user!.displayName ?? '';

    // Load extra fields from Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data['emoji'] != null && (data['emoji'] as String).isNotEmpty) {
          _emojiController.text = data['emoji'];
        }
        if (data['birthday'] != null && (data['birthday'] as String).isNotEmpty) {
          _birthdateController.text = data['birthday'];
        }
        // Also try displayName from Firestore if Auth one is blank
        if (_nameController.text.isEmpty && data['displayName'] != null) {
          _nameController.text = data['displayName'];
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }

    setState(() => _isLoading = false);
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 280,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            _emojiController.text = emoji.emoji;
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name cannot be empty.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final emoji = _emojiController.text.trim();

      // Update Firebase Auth display name
      await _user!.updateDisplayName(name);

      // Update Firestore user doc
      await _databaseService.updateUserProfile(
        _user!.uid,
        displayName: name,
        emoji: emoji,
        birthday: _birthdateController.text.trim(),
      );

      // Propagate emoji to all group member docs
      if (emoji.isNotEmpty) {
        await _databaseService.updateEmojiAcrossGroups(_user!.uid, emoji);
      }

      // Propagate birthday to all group member docs
      final birthday = _birthdateController.text.trim();
      if (birthday.isNotEmpty) {
        await _databaseService.updateBirthdayAcrossGroups(_user!.uid, birthday);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved!'),
            backgroundColor: Color(0xFF00C48C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  @override
  void dispose() {
    _nameController.dispose();
    _birthdateController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text('Account Settings'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D5FEF)))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar / emoji preview
                    Center(
                      child: GestureDetector(
                        onTap: _showEmojiPicker,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5D5FEF).withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _emojiController,
                              builder: (_, value, __) => Text(
                                value.text.isNotEmpty ? value.text : '😊',
                                style: const TextStyle(fontSize: 42),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Tap to change emoji',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Email (read-only)
                    _buildLabel('Email'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        _user?.email ?? '—',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Display name
                    _buildLabel('Display Name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration('Your name'),
                    ),
                    const SizedBox(height: 20),

                    // Birthday
                    _buildLabel('Birthday'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _birthdateController,
                      decoration: _inputDecoration('MM/DD/YYYY').copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today, color: Colors.grey),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime(2000),
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              final m = picked.month.toString().padLeft(2, '0');
                              final d = picked.day.toString().padLeft(2, '0');
                              final y = picked.year.toString();
                              _birthdateController.text = '$m/$d/$y';
                            }
                          },
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [DateTextFormatter()],
                      maxLength: 10,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    ),
                    const SizedBox(height: 32),

                    // Save button
                    _isSaving
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D5FEF)))
                        : ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5D5FEF),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
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

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      );
}
