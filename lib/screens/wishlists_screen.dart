import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/category.dart';
import '../models/person.dart';
import '../models/my_list_item.dart';
import '../widgets/person_card.dart';
import '../services/database_service.dart';
import 'person_wishlist_screen.dart';
import 'group_settings_screen.dart';
import 'my_list_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class _UpcomingEvent {
  final String title;
  final String monthLabel;
  final String dayLabel;
  final DateTime nextDate;
  final Color backgroundColor;
  final Color foregroundColor;
  final String? memberId;
  final String? memberName;

  const _UpcomingEvent({
    required this.title,
    required this.monthLabel,
    required this.dayLabel,
    required this.nextDate,
    required this.backgroundColor,
    required this.foregroundColor,
    this.memberId,
    this.memberName,
  });
}

class WishlistsScreen extends StatefulWidget {
  final bool isOwner;

  const WishlistsScreen({super.key, this.isOwner = false});

  @override
  State<WishlistsScreen> createState() => _WishlistsScreenState();
}

class _WishlistsScreenState extends State<WishlistsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  int _selectedIndex = 0;
  int _selectedTopTab = 0;
  String? _groupId;
  String? _myMemberId;
  bool _isLoading = true;
  bool _isCodeCopied = false;
  static const List<String> _monthLabels = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  Future<void> _submitFeedback(String text, String tag) async {
    const String feedbackUrl = 'https://script.google.com/macros/s/AKfycbyicIcomN9X6qHU7WqDe4DmQ3_rTfwUI0PWYDj3nmv2Q8vSVOwjowGEF2Au3ogplAvkaA/exec';
    await http.post(
      Uri.parse(feedbackUrl),
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

  @override
  void initState() {
    super.initState();
    _loadGroupSession();
  }

  Future<void> _loadGroupSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _groupId = prefs.getString('activeGroupId');
      _myMemberId = prefs.getString('activeMemberId');
      _isLoading = false;
    });
  }

  final List<Category> categories = [
    Category(
      title: 'Kayaking',
      icon: Icons.kayaking_outlined,
      iconColor: Colors.blueAccent,
    ),
    Category(
      title: 'Snorkeling',
      icon: Icons.scuba_diving_outlined,
      iconColor: Colors.orangeAccent,
    ),
    Category(
      title: 'Ballooning',
      icon: Icons.air,
      iconColor: Colors.purpleAccent,
    ),
    Category(
      title: 'Hiking',
      icon: Icons.hiking_outlined,
      iconColor: Colors.greenAccent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Determine the active pages based on role
    final List<Widget> pages = [
      _buildWishlistsContent(),
    ];
    
    final bool hasProfile = _myMemberId != null && _myMemberId!.isNotEmpty;
    if (hasProfile) {
      pages.add(MyListScreen(
        onBack: () {
          setState(() {
            _selectedIndex = 0; // Switch back to Wishlists tab
          });
        },
      ));
    }
    
    if (widget.isOwner && _groupId != null) {
      pages.add(GroupSettingsScreen(groupId: _groupId!));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Bottom Nav builder omitted for brevity...
  // (Assuming _buildBottomNav is unchanged)

  Widget? _buildBottomNav() {
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.grid_view_rounded),
        label: 'Wishlists',
      ),
    ];

    final bool hasProfile = _myMemberId != null && _myMemberId!.isNotEmpty;
    if (hasProfile) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.format_list_bulleted),
          label: 'My List',
        ),
      );
    }

    if (widget.isOwner) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Group Settings',
        ),
      );
    }

    if (items.length < 2) {
      return null;
    }

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedItemColor: const Color(0xFF5D5FEF),
      unselectedItemColor: Colors.grey,
      currentIndex: _selectedIndex < items.length ? _selectedIndex : 0, // Prevent out of bounds if tabs decrease dynamically
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      items: items,
    );
  }

  Widget _buildWishlistsContent() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top App Bar Area
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28, color: Colors.black87),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      // Check if the user is authenticated
                      final prefs = await SharedPreferences.getInstance();
                      
                      // Clear the active session so they don't get auto-routed back
                      await prefs.remove('activeGroupId');
                      await prefs.remove('activeMemberId');

                      bool isSignedIn = FirebaseAuth.instance.currentUser != null;
                      
                      if (context.mounted) {
                        if (isSignedIn) {
                           // Navigate straight to DashboardScreen if signed in.
                           // Getting the full route since we don't have a named route for it.
                           Navigator.of(context).pushAndRemoveUntil(
                             MaterialPageRoute(builder: (context) => const DashboardScreen()),
                             (route) => false,
                           );
                        } else {
                           // Guests should be kicked to root (LoginScreen) to rejoin
                           Navigator.of(context).pushAndRemoveUntil(
                             MaterialPageRoute(builder: (context) => const LoginScreen()),
                             (route) => false,
                           );
                        }
                      }
                    },
                  ),
                  if (_groupId != null)
                    StreamBuilder<DocumentSnapshot>(
                      stream: _databaseService.getGroupStream(_groupId!),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const SizedBox.shrink();
                        }
                        
                        final data = snapshot.data!.data() as Map<String, dynamic>?;
                        final joinCode = data?['joinCode'] ?? '';
                        
                        if (joinCode.isEmpty) return const SizedBox.shrink();

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _showFeedbackSheet,
                              icon: const Text('💬', style: TextStyle(fontSize: 14)),
                              label: Text(
                                'Feedback',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                backgroundColor: Colors.grey.withOpacity(0.05),
                                side: BorderSide(color: Colors.grey.withOpacity(0.3), width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: joinCode));
                                if (context.mounted) {
                                  setState(() {
                                    _isCodeCopied = true;
                                  });
                                  Future.delayed(const Duration(seconds: 2), () {
                                    if (mounted) {
                                      setState(() {
                                        _isCodeCopied = false;
                                      });
                                    }
                                  });
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _isCodeCopied ? const Color(0xFF00C48C).withOpacity(0.1) : const Color(0xFF5D5FEF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!_isCodeCopied)
                                      const Icon(Icons.group, size: 16, color: Color(0xFF5D5FEF)),
                                    if (_isCodeCopied)
                                      const Icon(Icons.check, size: 16, color: Color(0xFF00C48C)),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isCodeCopied ? 'Copied!' : 'Code: $joinCode',
                                      style: TextStyle(
                                        color: _isCodeCopied ? const Color(0xFF00C48C) : const Color(0xFF5D5FEF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 30),
              // Title
              const Text(
                'Wishlists',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Tabs
              Row(
                children: [
                  _buildTab('All', 0),
                  const SizedBox(width: 20),
                  _buildTab('Bought', 1),
                  const SizedBox(width: 20),
                  _buildTab('Remaining', 2),
                ],
              ),
              const SizedBox(height: 20),
              // Horizontal ListView wrapping a StreamBuilder
              SizedBox(
                height: 200,
                child: _groupId == null 
                  ? const Center(child: Text("No Group Found. Join or Create a group first."))
                  : StreamBuilder<QuerySnapshot>(
                      stream: _databaseService.getGroupMembersStream(_groupId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text("Error: ${snapshot.error}"));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text("No members in this group."));
                        }

                        final members = snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return Person(
                            id: doc.id,
                            name: doc.id == _myMemberId ? "${data['name']} (Me)" : data['name'] ?? 'Unknown',
                            avatarUrl: data['avatarUrl'] ?? '',
                            emoji: data['emoji'] ?? '',
                            wishlist: [], // Will fetch individually in PersonWishlistScreen
                          );
                        }).toList();

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            return StreamBuilder<QuerySnapshot>(
                              stream: _databaseService.getMemberWishlistStream(_groupId!, members[index].id),
                              builder: (context, wishlistSnapshot) {
                                final person = Person(
                                  id: members[index].id,
                                  name: members[index].name,
                                  avatarUrl: members[index].avatarUrl,
                                  emoji: members[index].emoji,
                                  wishlist: wishlistSnapshot.data?.docs ?? [],
                                );
                                return PersonCard(
                                  person: person,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PersonWishlistScreen(
                                          person: person,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
              ),
              const SizedBox(height: 30),
              // Upcoming section
              const Text(
                'Upcoming',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildUpcomingSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingSection() {
    if (_groupId == null) {
      return _buildUpcomingList(const []);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _databaseService.getGroupMembersStream(_groupId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Could not load upcoming events right now.');
        }

        final docs = snapshot.data?.docs ?? const [];
        final events = _buildUpcomingEvents(docs);
        return _buildUpcomingList(events);
      },
    );
  }

  List<_UpcomingEvent> _buildUpcomingEvents(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final events = <_UpcomingEvent>[
      _createFixedEvent(
        title: 'Christmas',
        month: 12,
        day: 25,
        today: today,
        backgroundColor: const Color(0xFFE5F7ED),
        foregroundColor: const Color(0xFF00C48C),
      ),
    ];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] as String?)?.trim();
      final birthdate = ((data['birthdate'] as String?)?.trim().isNotEmpty ?? false)
          ? (data['birthdate'] as String).trim()
          : (data['birthday'] as String?)?.trim();

      if (name == null || name.isEmpty || birthdate == null || birthdate.isEmpty) {
        continue;
      }

      final parts = _parseMonthDay(birthdate);
      if (parts == null) continue;

      final nextDate = _nextOccurrence(
        today: today,
        month: parts.$1,
        day: parts.$2,
      );

      events.add(
        _UpcomingEvent(
          title: "$name's Birthday",
          monthLabel: _monthLabels[parts.$1 - 1],
          dayLabel: parts.$2.toString(),
          nextDate: nextDate,
          backgroundColor: const Color(0xFFFFF1E8),
          foregroundColor: const Color(0xFFFF8A3D),
          memberId: doc.id,
          memberName: name,
        ),
      );
    }

    events.sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return events;
  }

  _UpcomingEvent _createFixedEvent({
    required String title,
    required int month,
    required int day,
    required DateTime today,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return _UpcomingEvent(
      title: title,
      monthLabel: _monthLabels[month - 1],
      dayLabel: day.toString(),
      nextDate: _nextOccurrence(today: today, month: month, day: day),
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }

  (int, int)? _parseMonthDay(String value) {
    final normalized = value.trim();
    final slashParts = normalized.split('/');
    if (slashParts.length < 2) return null;

    final month = int.tryParse(slashParts[0]);
    final day = int.tryParse(slashParts[1]);
    if (month == null || day == null) return null;
    if (month < 1 || month > 12) return null;

    final maxDay = DateTime(2024, month + 1, 0).day;
    if (day < 1 || day > maxDay) return null;
    return (month, day);
  }

  DateTime _nextOccurrence({
    required DateTime today,
    required int month,
    required int day,
  }) {
    var occurrence = _safeDate(today.year, month, day);
    if (occurrence.isBefore(today)) {
      occurrence = _safeDate(today.year + 1, month, day);
    }
    return occurrence;
  }

  DateTime _safeDate(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDayOfMonth ? lastDayOfMonth : day;
    return DateTime(year, month, safeDay);
  }

  Widget _buildUpcomingList(List<_UpcomingEvent> events) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: events.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) => _buildUpcomingCard(events[index]),
      ),
    );
  }

  Widget _buildUpcomingCard(_UpcomingEvent event) {
    return GestureDetector(
      onTap: event.memberId != null && _groupId != null
          ? () {
              final person = Person(
                id: event.memberId!,
                name: event.memberName ?? '',
                avatarUrl: '',
                emoji: '',
                wishlist: [],
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PersonWishlistScreen(person: person),
                ),
              );
            }
          : null,
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 84,
              width: 84,
              decoration: BoxDecoration(
                color: event.backgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    event.monthLabel,
                    style: TextStyle(
                      color: event.foregroundColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.dayLabel,
                    style: TextStyle(
                      color: event.foregroundColor,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String text, int index) {
    bool isSelected = _selectedTopTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTopTab = index;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: isSelected
                ? Container(
                    key: const ValueKey('selected'),
                    height: 6,
                    width: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5D5FEF),
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('unselected'),
                    height: 6,
                    width: 6,
                  ),
          ),
        ],
      ),
    );
  }
}
