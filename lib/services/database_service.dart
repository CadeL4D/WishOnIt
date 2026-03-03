import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/my_list_item.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save or update user data in Firestore (Owner's master profile)
  Future<void> saveUserData(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? 'New User',
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving user data: $e');
    }
  }

  // Generate a random 6 character alphanumeric join code
  String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  // Create a new Group and automatically add the owner as the first member
  Future<String?> createGroup(String name, User owner) async {
    try {
      final joinCode = _generateJoinCode();
      
      // 1. Create the Group Document
      final groupRef = await _firestore.collection('groups').add({
        'name': name,
        'ownerUid': owner.uid,
        'joinCode': joinCode,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 2. Add the Owner as the first Member in the subcollection
      await groupRef.collection('members').doc(owner.uid).set({
        'id': owner.uid,
        'name': owner.displayName ?? 'Owner',
        'avatarUrl': owner.photoURL ?? '',
        'isRegisteredOwner': true,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      
      return groupRef.id;
    } catch (e) {
      print('Error creating group: $e');
      return null;
    }
  }

  // Join a Group anonymously using a Join Code
  // Returns a map with groupId and the newly created memberId, or null if failed
  Future<Map<String, String>?> joinGroupAsGuest(String joinCode, String guestName) async {
    try {
      // 1. Find the group by code
      final querySnapshot = await _firestore
          .collection('groups')
          .where('joinCode', isEqualTo: joinCode.toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('Invalid join code');
      }

      final groupId = querySnapshot.docs.first.id;
      final groupRef = _firestore.collection('groups').doc(groupId);

      // 2. Create the Guest Member profile
      final memberRef = await groupRef.collection('members').add({
        'name': guestName,
        'avatarUrl': '', // Guests have no default avatar
        'isRegisteredOwner': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      
      // We must explicitly set the ID field inside the document to make it easier to parse later
      await memberRef.update({'id': memberRef.id});

      return {
        'groupId': groupId,
        'memberId': memberRef.id,
      };
    } catch (e) {
      print('Error joining group: $e');
      return null;
    }
  }

  // Fetch the group document as a Stream
  Stream<DocumentSnapshot> getGroupStream(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots();
  }

  // Fetch all members of a specific group as a Stream
  Stream<QuerySnapshot> getGroupMembersStream(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .orderBy('joinedAt', descending: false)
        .snapshots();
  }

  // Fetch a specific member's wishlist as a Stream
  Stream<QuerySnapshot> getMemberWishlistStream(String groupId, String memberId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .collection('wishlist')
        .snapshots();
  }

  // Add an item to a specific member's wishlist inside a group
  Future<void> addWishlistItem(String groupId, String memberId, MyListItem item) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('wishlist')
          .doc(item.id)
          .set(item.toJson());
    } catch (e) {
      print('Error adding wishlist item: $e');
    }
  }

  // Delete an item from a specific member's wishlist inside a group
  Future<void> deleteWishlistItem(String groupId, String memberId, String itemId) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('wishlist')
          .doc(itemId)
          .delete();
    } catch (e) {
      print('Error deleting wishlist item: $e');
    }
  }
}
