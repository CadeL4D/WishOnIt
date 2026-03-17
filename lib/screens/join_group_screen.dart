import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'wishlists_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  final String? initialGroupId;
  final String? initialGroupName;
  final String? initialGroupCode;

  const JoinGroupScreen({
    super.key, 
    this.initialGroupId, 
    this.initialGroupName, 
    this.initialGroupCode,
  });

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  
  bool _isLoading = false;
  bool _stepTwo = false;
  
  // Group data fetched in Step 1 (or passed in)
  String? _foundGroupId;
  String? _foundGroupName;
  
  // User auth details
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    if (widget.initialGroupId != null && widget.initialGroupName != null) {
      _foundGroupId = widget.initialGroupId;
      _foundGroupName = widget.initialGroupName;
      _stepTwo = true;
      if (widget.initialGroupCode != null) {
        _codeController.text = widget.initialGroupCode!;
      }
    }
  }

  Future<void> _findGroup() async {
    final code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Group Code.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final groupDoc = await _databaseService.getGroupByCode(code);
      if (groupDoc != null) {
        final data = groupDoc.data() as Map<String, dynamic>;
        setState(() {
          _foundGroupId = groupDoc.id;
          _foundGroupName = data['name'];
          _stepTwo = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid group code. Please try again.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Old claim member process, updated to ask for PIN first
  Future<void> _loginAsGuest(String memberId, String storedPin) async {
    // We already checked this when they tapped, but double check
    if (_foundGroupId == null) return;
    
    // Instead of forcing a claim, we just authenticate them locally as this guest
    if (_currentUserId != null) {
      // If the user *is* logged in to a Firebase account, we'll link it for convenience
      try {
        await _databaseService.claimExistingMember(_foundGroupId!, memberId, _currentUserId!);
      } catch (e) {
        // Just log the error, don't stop them from entering the group session
        print('Error silently linking profile: $e');
      }
    }

    _completeJoinFlow(_foundGroupId!, memberId);
  }

  Future<void> _showPinDialog(String memberId, String name, String storedPin) async {
    final TextEditingController pinInputController = TextEditingController();
    String errorText = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Enter PIN for $name'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Please enter the 4-digit PIN for this profile.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinInputController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'PIN',
                      errorText: errorText.isNotEmpty ? errorText : null,
                      filled: true,
                      fillColor: const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      counterText: '',
                    ),
                    onChanged: (val) {
                      if (errorText.isNotEmpty) {
                        setDialogState(() => errorText = '');
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (pinInputController.text == storedPin || storedPin.isEmpty) {
                      Navigator.pop(context);
                      _loginAsGuest(memberId, storedPin);
                    } else {
                      setDialogState(() {
                        errorText = 'Incorrect PIN';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Enter', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _joinAsViewer() async {
    if (_foundGroupId == null) return;
    
    // Save active session data locally, but without a memberId
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeGroupId', _foundGroupId!);
    await prefs.remove('activeMemberId'); // Ensure no member is set
    await prefs.setBool('isOwner', false);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const WishlistsScreen(isOwner: false),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _joinAsNewGuest() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    final birthdate = _birthdateController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for your new profile.')),
      );
      return;
    }
    
    if (pin.length != 4 || int.tryParse(pin) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 4-digit PIN.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // The DatabaseService currently expects both code and name to create the guest profile.
      final result = await _databaseService.joinGroupAsGuest(
        _codeController.text.trim(), 
        name,
        birthdate: birthdate,
        pin: pin,
      );
      if (result != null) {
        // If the current user is logged in, we also want to add their UID to the group's memberIds array so it shows on dashboard.
        if (_currentUserId != null) {
          await _databaseService.claimExistingMember(result['groupId']!, result['memberId']!, _currentUserId!);
        }
        _completeJoinFlow(result['groupId']!, result['memberId']!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating guest profile: $e')),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _completeJoinFlow(String groupId, String memberId) async {
    // Save active session data locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeGroupId', groupId);
    await prefs.setString('activeMemberId', memberId);
    await prefs.setBool('isOwner', false);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const WishlistsScreen(isOwner: false),
        ),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdateController.dispose();
    _pinController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text(_stepTwo ? 'Join ${_foundGroupName ?? 'Group'}' : 'Find a Group'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _stepTwo && !_isLoading
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () {
                  setState(() {
                    _stepTwo = false;
                    _foundGroupId = null;
                    _foundGroupName = null;
                  });
                },
              )
            : const BackButton(color: Colors.black87),
      ),
      body: SafeArea(
        child: _stepTwo ? _buildStepTwo() : _buildStepOne(),
      ),
    );
  }

  Widget _buildStepOne() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.search,
            size: 80,
            color: Color(0xFF5D5FEF),
          ),
          const SizedBox(height: 24),
          const Text(
            'Enter Group Code',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the group owner for their 6-character code.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              labelText: 'Group Code',
              hintText: 'e.g., A1B2C3',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _findGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D5FEF),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Find Group',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildStepTwo() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _databaseService.getGroupMembersStream(_foundGroupId!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final allMembers = snapshot.data?.docs ?? [];
              // Filter out the registered owner so they cannot be claimed
              final members = allMembers.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['isRegisteredOwner'] != true;
              }).toList();
              
              if (members.isEmpty) {
                return const Center(child: Text('No members found yet.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: members.length + 1, // Add 1 for the title
                itemBuilder: (context, index) {
                  if (index == 0) {
                     return const Padding(
                       padding: EdgeInsets.only(bottom: 16.0),
                       child: Text(
                         'Claim an existing profile:',
                         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                       ),
                     );
                  }

                  final doc = members[index - 1];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'Unknown Member';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF5D5FEF).withAlpha((0.1 * 255).toInt()),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Color(0xFF5D5FEF), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: _isLoading ? null : () => _showPinDialog(doc.id, name, data['pin'] ?? ''),
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Create New Member Section
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.05 * 255).toInt()),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Or create a new guest profile:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Your Name',
                  filled: true,
                  fillColor: const Color(0xFFF6F8FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _birthdateController,
                decoration: InputDecoration(
                  labelText: 'Birthdate (Optional)',
                  hintText: 'MM/DD/YYYY',
                  filled: true,
                  fillColor: const Color(0xFFF6F8FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                decoration: InputDecoration(
                  labelText: 'Create 4-Digit PIN',
                  filled: true,
                  fillColor: const Color(0xFFF6F8FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                  onPressed: _joinAsNewGuest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C48C),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Join as New Member',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _joinAsViewer,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    side: const BorderSide(color: Color(0xFF5D5FEF), width: 1.5),
                  ),
                  child: const Text(
                    'View Wishlists Only',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5D5FEF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

