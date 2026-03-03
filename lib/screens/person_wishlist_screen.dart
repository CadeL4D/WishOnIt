import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/person.dart';
import '../models/my_list_item.dart';
import '../services/database_service.dart';

class PersonWishlistScreen extends StatefulWidget {
  final Person person;

  const PersonWishlistScreen({
    super.key,
    required this.person,
  });

  @override
  State<PersonWishlistScreen> createState() => _PersonWishlistScreenState();
}

class _PersonWishlistScreenState extends State<PersonWishlistScreen> {
  final DatabaseService _databaseService = DatabaseService();
  String? _groupId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _groupId = prefs.getString('activeGroupId');
      _isLoading = false;
    });
  }

  String? _getLogoUrl(String domain) {
    const logos = {
      'amazon.com': 'https://upload.wikimedia.org/wikipedia/commons/4/4a/Amazon_icon.svg',
      'target.com': 'https://upload.wikimedia.org/wikipedia/commons/c/c5/Target_Corporation_logo_%28vector%29.svg',
      'ulta.com': 'https://s3.amazonaws.com/images.ecwid.com/images/33423725/1483864195.jpg',
      'walmart.com': 'https://upload.wikimedia.org/wikipedia/commons/c/ca/Walmart_logo.svg',
      'bestbuy.com': 'https://upload.wikimedia.org/wikipedia/commons/f/f5/Best_Buy_Logo.svg',
      'sephora.com': 'https://upload.wikimedia.org/wikipedia/commons/4/41/Sephora_logo.svg',
      'etsy.com': 'https://upload.wikimedia.org/wikipedia/commons/8/89/Etsy_logo.svg',
      'ebay.com': 'https://upload.wikimedia.org/wikipedia/commons/1/1b/EBay_logo.svg',
      'homedepot.com': 'https://upload.wikimedia.org/wikipedia/commons/5/5f/TheHomeDepot.svg',
      'ikea.com': 'https://upload.wikimedia.org/wikipedia/commons/c/c5/Ikea_logo.svg',
      'shein.com': 'https://upload.wikimedia.org/wikipedia/commons/9/91/SHEIN_LOGO.svg',
      'apple.com': 'https://upload.wikimedia.org/wikipedia/commons/f/fa/Apple_logo_black.svg',
    };
    return logos[domain];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text('${widget.person.name}\'s Wishlist'),
        backgroundColor: const Color(0xFFF6F8FB),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupId == null
              ? const Center(child: Text('No active group joined.'))
              : StreamBuilder<QuerySnapshot>(
                  stream: _databaseService.getMemberWishlistStream(
                      _groupId!, widget.person.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error loading wishlist: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Text(
                          '${widget.person.name} has no items yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }

                    final items = snapshot.data!.docs.map((doc) {
                      return MyListItem.fromJson(doc.data() as Map<String, dynamic>);
                    }).toList();

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final domain = item.domain ?? '';
                        final logoUrl = _getLogoUrl(domain);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[200],
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: domain.isNotEmpty && logoUrl != null
                                  ? logoUrl.endsWith('.svg')
                                      ? SvgPicture.network(
                                          logoUrl,
                                          fit: BoxFit.contain,
                                        )
                                      : Image.network(
                                          logoUrl,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error,
                                                  stackTrace) =>
                                              const Icon(Icons.link,
                                                  color: Colors.grey),
                                        )
                                  : const Icon(Icons.link, color: Colors.grey),
                            ),
                            title: Text(item.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle:
                                Text('\$${item.price.toStringAsFixed(2)}'),
                            trailing: const Icon(Icons.shopping_bag_outlined,
                                color: Colors.grey),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
