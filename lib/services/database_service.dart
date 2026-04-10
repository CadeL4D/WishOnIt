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

  // Update user profile fields in Firestore
  Future<void> updateUserProfile(
    String uid, {
    String? displayName,
    String? emoji,
    String? birthday,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['displayName'] = displayName;
    if (emoji != null) data['emoji'] = emoji;
    if (birthday != null) data['birthday'] = birthday;
    if (data.isEmpty) return;
    await _firestore.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  // Propagate the user's birthday to every group member doc they own or have claimed
  Future<void> updateBirthdayAcrossGroups(String uid, String birthday) async {
    try {
      final groupsSnap = await _firestore
          .collection('groups')
          .where('memberIds', arrayContains: uid)
          .get();

      for (final groupDoc in groupsSnap.docs) {
        final groupId = groupDoc.id;
        final batch = _firestore.batch();
        bool batchHasWrites = false;

        // 1. Owner doc — keyed directly by uid
        final ownerRef = _firestore
            .collection('groups').doc(groupId)
            .collection('members').doc(uid);
        final ownerSnap = await ownerRef.get();
        if (ownerSnap.exists) {
          batch.update(ownerRef, {'birthday': birthday});
          batchHasWrites = true;
        }

        // 2. Any guest profile this user has claimed
        final claimedSnap = await _firestore
            .collection('groups').doc(groupId)
            .collection('members')
            .where('claimedByUid', isEqualTo: uid)
            .get();
        for (final memberDoc in claimedSnap.docs) {
          batch.update(memberDoc.reference, {'birthday': birthday});
          batchHasWrites = true;
        }

        if (batchHasWrites) await batch.commit();
      }
    } catch (e) {
      print('Error updating birthday across groups: $e');
      rethrow;
    }
  }

  // Propagate the user's emoji to every group member doc they own or have claimed
  Future<void> updateEmojiAcrossGroups(String uid, String emoji) async {
    try {
      // Find all groups this user is a member of
      final groupsSnap = await _firestore
          .collection('groups')
          .where('memberIds', arrayContains: uid)
          .get();

      for (final groupDoc in groupsSnap.docs) {
        final groupId = groupDoc.id;
        final batch = _firestore.batch();
        bool batchHasWrites = false;

        // 1. Owner doc — keyed directly by uid
        final ownerRef = _firestore
            .collection('groups').doc(groupId)
            .collection('members').doc(uid);
        final ownerSnap = await ownerRef.get();
        if (ownerSnap.exists) {
          batch.update(ownerRef, {'emoji': emoji});
          batchHasWrites = true;
        }

        // 2. Any guest profile this user has claimed
        final claimedSnap = await _firestore
            .collection('groups').doc(groupId)
            .collection('members')
            .where('claimedByUid', isEqualTo: uid)
            .get();
        for (final memberDoc in claimedSnap.docs) {
          batch.update(memberDoc.reference, {'emoji': emoji});
          batchHasWrites = true;
        }

        if (batchHasWrites) await batch.commit();
      }
    } catch (e) {
      print('Error updating emoji across groups: $e');
      rethrow;
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
  Future<String?> createGroup(String name, User owner, {String? emoji}) async {
    try {
      final joinCode = _generateJoinCode();
      
      // 1. Create the Group Document
      final groupRef = await _firestore.collection('groups').add({
        'name': name,
        'ownerUid': owner.uid,
        'joinCode': joinCode,
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [owner.uid], // Array to allow easy querying of what groups a user is in
      });
      
      // 2. Fetch the owner's birthday from their user profile
      final userDoc = await _firestore.collection('users').doc(owner.uid).get();
      final birthday = (userDoc.data()?['birthday'] as String?) ?? '';

      // 3. Add the Owner as the first Member in the subcollection
      await groupRef.collection('members').doc(owner.uid).set({
        'id': owner.uid,
        'name': owner.displayName ?? 'Owner',
        'avatarUrl': owner.photoURL ?? '',
        'emoji': emoji ?? '',
        'birthday': birthday,
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
  Future<Map<String, String>?> joinGroupAsGuest(String joinCode, String guestName, {String? birthdate, String? pin, String? emoji}) async {
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
        'birthdate': birthdate ?? '',
        'pin': pin ?? '',
        'avatarUrl': '', // Guests have no default avatar
        'emoji': emoji ?? '',
        'isRegisteredOwner': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      
      // We must explicitly set the ID field inside the document to make it easier to parse later
      await memberRef.update({'id': memberRef.id});

      // 3. Update the Group Document to include this new member in the queryable array
      await groupRef.update({
        'memberIds': FieldValue.arrayUnion([memberRef.id]),
      });

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

  // Look up a group by its Join Code directly, returning the DocumentSnapshot if found
  Future<DocumentSnapshot?> getGroupByCode(String code) async {
    try {
      final querySnapshot = await _firestore
          .collection('groups')
          .where('joinCode', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first;
      }
      return null;
    } catch (e) {
      print('Error getting group by code: $e');
      return null;
    }
  }

  // Claim an existing anonymous profile in a group and link it to a logged-in User
  Future<void> claimExistingMember(String groupId, String memberId, String userId) async {
    try {
      final groupRef = _firestore.collection('groups').doc(groupId);
      
      // Update top-level memberIds array so it shows up in their dashboard
      await groupRef.update({
        'memberIds': FieldValue.arrayUnion([userId]),
      });
      // Update the member sub-doc to indicate it has been claimed by this user
      await groupRef.collection('members').doc(memberId).set({
        'claimedByUid': userId,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error claiming member: $e');
      throw e;
    }
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

  // Fetch all groups that a specific user is a member of
  Stream<QuerySnapshot> getUserGroupsStream(String userId) {
    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
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

  Future<void> updateWishlistItem(String groupId, String memberId, MyListItem item) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('wishlist')
          .doc(item.id)
          .update(item.toJson());
    } catch (e) {
      print('Error updating wishlist item: $e');
    }
  }

  // Update the purchased status of a wishlist item
  Future<void> updateWishlistItemStatus(String groupId, String memberId, String itemId, bool isPurchased) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('wishlist')
          .doc(itemId)
          .update({'isPurchased': isPurchased});
    } catch (e) {
      print('Error updating wishlist item status: $e');
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

  // --- Owner/Admin Functions ---

  // Clear all wishlist items for everyone in the group
  Future<void> resetAllListItems(String groupId) async {
    try {
      final membersSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      for (var memberDoc in membersSnapshot.docs) {
        final wishlistSnapshot = await memberDoc.reference.collection('wishlist').get();
        for (var itemDoc in wishlistSnapshot.docs) {
          await itemDoc.reference.delete();
        }
      }
    } catch (e) {
      print('Error resetting all list items: $e');
      throw e;
    }
  }

  // Clear all wishlist items for a specific individual in the group
  Future<void> resetMemberWishlist(String groupId, String memberId) async {
    try {
      final wishlistSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('wishlist')
          .get();

      for (var itemDoc in wishlistSnapshot.docs) {
        await itemDoc.reference.delete();
      }
    } catch (e) {
      print('Error resetting member wishlist: $e');
      throw e;
    }
  }

  // Update a member's PIN
  Future<void> resetMemberPin(String groupId, String memberId, String newPin) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .update({
        'pin': newPin,
      });
    } catch (e) {
      print('Error resetting member PIN: $e');
      throw e;
    }
  }

  // Delete an entire group and all its subcollections entirely
  Future<void> deleteGroup(String groupId) async {
    try {
      final groupRef = _firestore.collection('groups').doc(groupId);
      final membersSnapshot = await groupRef.collection('members').get();

      // First, delete all wishlists and then the member documents
      for (var memberDoc in membersSnapshot.docs) {
        final wishlistSnapshot = await memberDoc.reference.collection('wishlist').get();
        for (var itemDoc in wishlistSnapshot.docs) {
          await itemDoc.reference.delete();
        }
        await memberDoc.reference.delete();
      }

      // Finally, delete the group document itself
      await groupRef.delete();
    } catch (e) {
      print('Error deleting group: $e');
      throw e;
    }
  }
}
