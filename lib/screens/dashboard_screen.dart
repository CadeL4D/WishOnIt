import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../services/database_service.dart';
import 'wishlists_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'account_settings_screen.dart';

/// Paste your Google Apps Script Web App URL here after deployment.
const String _kFeedbackUrl = 'https://script.google.com/macros/s/AKfycbyicIcomN9X6qHU7WqDe4DmQ3_rTfwUI0PWYDj3nmv2Q8vSVOwjowGEF2Au3ogplAvkaA/exec';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _databaseService = DatabaseService();
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _userId = user?.uid;
    });

    // Check if this user has a birthday set; if not, prompt them
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final birthday = (userDoc.data()?['birthday'] as String?)?.trim() ?? '';
      if (birthday.isEmpty && mounted) {
        _showBirthdayPrompt();
      }
    }
  }

  void _showBirthdayPrompt() {
    DateTime? selectedDate;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'When\'s your birthday?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This helps your group see your birthday in the Upcoming section.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2000, 1, 1),
                        firstDate: DateTime(1920),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        selectedDate != null
                            ? '${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.year}'
                            : 'Tap to select date',
                        style: TextStyle(
                          fontSize: 16,
                          color: selectedDate != null ? Colors.black87 : Colors.grey.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Skip', style: TextStyle(color: Colors.grey.shade500)),
                ),
                ElevatedButton(
                  onPressed: selectedDate == null
                      ? null
                      : () async {
                          final birthday =
                              '${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.year}';
                          await _databaseService.updateUserProfile(
                            _userId!,
                            birthday: birthday,
                          );
                          await _databaseService.updateBirthdayAcrossGroups(_userId!, birthday);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Birthday saved!'),
                                backgroundColor: Color(0xFF00C48C),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _joinExistingGroup(String groupId, String ownerUid) async {
    if (_userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeGroupId', groupId);

    print('[WishedOn] _joinExistingGroup: userId=$_userId ownerUid=$ownerUid groupId=$groupId');

    String activeMemberId = '';
    
    try {
      // Step 1: Check if the user has a direct member doc (i.e. they are the owner)
      final ownerDocRef = FirebaseFirestore.instance
          .collection('groups').doc(groupId)
          .collection('members').doc(_userId);
      final ownerDocSnap = await ownerDocRef.get();
      
      if (ownerDocSnap.exists) {
        // User IS the owner or was added directly with their UID as document ID
        print('[WishedOn] Found direct member doc -> activeMemberId=$_userId (owner)');
        activeMemberId = _userId!;
      } else {
        // Step 2: Search for a guest profile they claimed (must NOT be the owner's profile)
        final qs = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .where('claimedByUid', isEqualTo: _userId)
            .get();
        
        for (final doc in qs.docs) {
          final docData = doc.data() as Map<String, dynamic>;
          final isOwnerDoc = doc.id == ownerUid || docData['isRegisteredOwner'] == true;
          
          if (!isOwnerDoc) {
            // Valid claimed profile
            print('[WishedOn] Found claimed guest profile -> activeMemberId=${doc.id}');
            activeMemberId = doc.id;
            break;
          } else {
            // Bad state: they've incorrectly claimed the owner's profile. Self-heal.
            print('[WishedOn] Removing bad claimedByUid from owner doc: ${doc.id}');
            try {
              await doc.reference.update({'claimedByUid': FieldValue.delete()});
            } catch (e) {
              print('[WishedOn] Error self-healing: $e');
            }
          }
        }
        // If activeMemberId is still '', they join as a viewer (no My List tab)
      }
    } catch (e) {
      print('Error finding member: $e');
    }

    print('[WishedOn] Final activeMemberId=$activeMemberId isOwner=${_userId == ownerUid}');

    await prefs.setString('activeMemberId', activeMemberId);
      if (activeMemberId.isEmpty) {
      await prefs.remove('activeMemberId');
    }

    
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WishlistsScreen(
            isOwner: _userId != null && ownerUid == _userId,
          ),
        ),
      );
    }
  }
  Future<void> _submitFeedback(String text, String tag) async {
    if (_kFeedbackUrl == 'YOUR_APPS_SCRIPT_URL_HERE') return;
    
    // We CANNOT use application/json here. Flutter Web runs in a browser. 
    // Sending JSON triggers a CORS preflight OPTIONS request, which 
    // Google Apps Script usually rejects/fails on. Form data avoids the preflight entirely.
    await http.post(
      Uri.parse(_kFeedbackUrl),
      body: {'feedback': text, 'tag': tag},
    );
  }

  void _showFeedbackSheet() {
    final controller = TextEditingController();
    bool isSubmitting = false;
    String selectedTag = 'Comment';
    final tags = ['Comment', 'Bug', 'Wanted Feature', 'Good Feature'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24, right: 24, top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Leave Feedback',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Anonymous — no personal data is collected.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'What can we improve? What do you love?',
                      filled: true,
                      fillColor: const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: tags.map((tag) {
                      final isSelected = selectedTag == tag;
                      return ChoiceChip(
                        label: Text(tag),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() => selectedTag = tag);
                          }
                        },
                        selectedColor: const Color(0xFF5D5FEF).withOpacity(0.2),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF5D5FEF) : Colors.grey.shade300,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? const Color(0xFF5D5FEF) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  isSubmitting
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D5FEF)))
                      : ElevatedButton(
                          onPressed: () async {
                            final text = controller.text.trim();
                            if (text.isEmpty) return;
                            setSheetState(() => isSubmitting = true);
                            try {
                              await _submitFeedback(text, selectedTag);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Thanks for your feedback! 🙏'),
                                    backgroundColor: Color(0xFF00C48C),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not send feedback. Try again later.')),
                                );
                              }
                              setSheetState(() => isSubmitting = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5D5FEF),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Submit',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showJoinGroupDialog(BuildContext context) {
    final TextEditingController codeController = TextEditingController();
    bool isDialogLoading = false;
    String errorMsg = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Join Group'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter the 6-digit group code.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      hintText: 'Code',
                      errorText: errorMsg.isNotEmpty ? errorMsg : null,
                      filled: true,
                      fillColor: const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.bold),
                    onChanged: (v) {
                      if (errorMsg.isNotEmpty) setDialogState(() => errorMsg = '');
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                isDialogLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        final code = codeController.text.trim().toUpperCase();
                        if (code.isEmpty) {
                          setDialogState(() => errorMsg = 'Code cannot be empty');
                          return;
                        }
                        
                        setDialogState(() => isDialogLoading = true);
                        try {
                          final groupDoc = await _databaseService.getGroupByCode(code);
                          if (groupDoc != null) {
                            final data = groupDoc.data() as Map<String, dynamic>;
                            if (context.mounted) {
                              Navigator.pop(context); // close dialog
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
                            setDialogState(() {
                              isDialogLoading = false;
                              errorMsg = 'Invalid group code';
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            isDialogLoading = false;
                            errorMsg = 'Error: $e';
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C48C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Find Group', style: TextStyle(color: Colors.white)),
                    ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text('My Groups'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            tooltip: 'Account Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AccountSettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              try {
                await GoogleSignIn().disconnect();
              } catch (e) {
                print("Error disconnecting Google: $e");
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('activeGroupId');
              await prefs.remove('activeMemberId');
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
        ],
      ),
      body: _userId == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back!',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'My Groups',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _databaseService.getUserGroupsStream(_userId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SliverToBoxAdapter(
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return SliverToBoxAdapter(
                            child: Center(child: Text("Error: ${snapshot.error}")),
                          );
                        }

                        final groups = snapshot.data?.docs ?? [];

                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index < groups.length) {
                                  final doc = groups[index];
                                  final data = doc.data() as Map<String, dynamic>;
                                  return _buildGroupCard(
                                    name: data['name'] ?? 'Unknown Group',
                                    ownerUid: data['ownerUid'] ?? '',
                                    joinCode: data['joinCode'] ?? '',
                                    onTap: () => _joinExistingGroup(doc.id, data['ownerUid']),
                                  );
                                } else {
                                  return _buildAddGroupCard(context);
                                }
                              },
                              childCount: groups.length + 1, // Add 1 for the Add button
                            ),
                          ),
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showFeedbackSheet,
                            icon: const Text('💬', style: TextStyle(fontSize: 16)),
                            label: Text(
                              'Leave Feedback',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.grey.withOpacity(0.05),
                              side: BorderSide(color: Colors.grey.withOpacity(0.3), width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGroupCard({
    required String name,
    required String ownerUid,
    required String joinCode,
    required VoidCallback onTap,
  }) {
    final isOwner = _userId != null && ownerUid == _userId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.05 * 255).toInt()),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF5D5FEF).withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.group,
                  color: Color(0xFF5D5FEF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOwner ? 'Owner • Code: $joinCode' : 'Member',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddGroupCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF5D5FEF).withOpacity(0.05),
                  border: Border.all(color: const Color(0xFF5D5FEF).withOpacity(0.3), width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(16),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF5D5FEF),
                      size: 28,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Create Group',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF5D5FEF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _showJoinGroupDialog(context);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00C48C).withOpacity(0.05),
                  border: Border.all(color: const Color(0xFF00C48C).withOpacity(0.3), width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(16),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_add_outlined,
                      color: Color(0xFF00C48C),
                      size: 28,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Join Group',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF00C48C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
