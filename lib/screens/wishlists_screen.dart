import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category.dart';
import '../models/person.dart';
import '../models/my_list_item.dart';
import '../widgets/person_card.dart';
import '../services/database_service.dart';
import 'person_wishlist_screen.dart';
import 'group_settings_screen.dart';
import 'my_list_screen.dart';

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
      pages.add(const MyListScreen());
    }
    
    if (widget.isOwner) {
      pages.add(const GroupSettingsScreen());
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
                  const Icon(Icons.menu, size: 30),
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

                        return GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: joinCode));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Group code copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5D5FEF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.group, size: 16, color: Color(0xFF5D5FEF)),
                                const SizedBox(width: 6),
                                Text(
                                  'Code: $joinCode',
                                  style: const TextStyle(
                                    color: Color(0xFF5D5FEF),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                            avatarUrl: data['avatarUrl'],
                            wishlist: [], // Will fetch individually in PersonWishlistScreen
                          );
                        }).toList();

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            return PersonCard(
                              person: members[index],
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PersonWishlistScreen(
                                      person: members[index],
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
              // Christmas Card (Square with Icon)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F7ED), // Light green background
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.park, // Christmas tree-like icon
                        color: Color(0xFF00C48C),
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 4.0),
                    child: Text(
                      'Christmas',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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
