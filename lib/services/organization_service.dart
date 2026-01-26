import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class OrganizationService {
  // Create instance of Firestore to interact with the database
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // UUID generator for creating unique invite codes
  final Uuid _uuid = Uuid();

  // Generate a unique 8-character invite code
  String _generateInviteCode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  // Create a new organization
  Future<Organization?> createOrganization({
    required String name,
    required String ownerId,
    String? address,      // NEW: Optional address
    String? phone,        // NEW: Optional phone
    String? email,        // NEW: Optional email
  }) async {
    try {
      // Create a new document reference in 'organizations' collection
      final orgRef = _firestore.collection("organizations").doc();

      // Create an Organization object with the generated ID
      final organization = Organization(
        id: orgRef.id, // Use the auto-generated ID
        name: name, // Organization name from parameter
        address: address, // NEW: Optional address
        phone: phone,     // NEW: Optional phone
        email: email,     // NEW: Optional email
        createdBy: ownerId, // Store who created this organization 
        createdAt: DateTime.now(), // Store when it was created
      );

      // Save the organization to Firestore
      // toMap() converts the Organization object to a Map that Firestore can store
      await orgRef.set(organization.toMap());

      // Now create a membership for the creator
      // The creator should be an admin of their own organization
      
      // Create a unique membership ID by combining ownerID and orgID
      final membershipId = '${ownerId}_${orgRef.id}';

      // Create a Membership object
      final membership = Membership(
        id: membershipId, 
        organizationId: orgRef.id, 
        ownerId: ownerId, 
        role: 'admin', 
        inviteCode: _generateInviteCode(), 
        status: 'active', 
        joinedAt: DateTime.now(),
      ); 

      // Save the membership to Firestore
      await _firestore.collection('memberships').doc(membershipId).set(membership.toMap());

      // Log success message
      print('✅ Organization created: ${organization.name}');

      return organization;
    } catch (e) {
      print('❌ Error creating organization: $e');
      return null;
    }
  }

  // NEW: Update organization details
  // Only admins can update organization information
  Future<bool> updateOrganization({
    required String ownerId,
    required String orgId,
    String? name,
    String? address,
    String? phone,
    String? email,
  }) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin');
        return false;
      }

      // Build update map with only non-null values
      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (address != null) updates['address'] = address;
      if (phone != null) updates['phone'] = phone;
      if (email != null) updates['email'] = email;

      // If no updates provided, return early
      if (updates.isEmpty) {
        print('⚠️ No updates provided');
        return false;
      }

      // Update the organization
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update(updates);

      print('✅ Organization updated');
      return true;
    } catch (e) {
      print('❌ Error updating organization: $e');
      return false;
    }
  }

  // Get user's membership in an organization
  Future<Membership?> getUserMembership(String ownerId, String orgId) async {
    try {
      final membershipId = '${ownerId}_${orgId}';
      final doc = await _firestore.collection('memberships').doc(membershipId).get();
      
      if (!doc.exists) {
        return null;
      }
      
      return Membership.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('❌ Error getting membership: $e');
      return null;
    }
  }

  // Leave an organization
  Future<bool> leaveOrganization(String ownerId, String orgId) async {
    try {
      // Create the membership ID
      final membershipId = '${ownerId}_${orgId}';
      
      // Delete the membership document
      await _firestore
          .collection('memberships')
          .doc(membershipId)
          .delete();
      
      // Log success
      print('✅ User left organization');
      return true;
    } catch (e) {
      print('❌ Error leaving organization: $e');
      return false;
    }
  }

  // Delete an organization
  // Only admins can delete organizations
  // This also deletes all memberships
  Future<bool> deleteOrganization(String ownerId, String orgId) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
      // Verify membership exists and user is admin
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin');
        return false;
      }

      WriteBatch batch = _firestore.batch();
      int operationCount = 0;

      // Helper to add delete operation safely
      void safeDelete(DocumentReference ref) {
        batch.delete(ref);
        operationCount++;
        if (operationCount >= 490) { // Safety margin for 500 limit
          batch.commit();
          batch = _firestore.batch();
          operationCount = 0;
        }
      }

      // Delete all memberships for this organization
      // First, get all memberships
      final memberships = await _firestore
          .collection('memberships')
          .where('organizationId', isEqualTo: orgId)
          .get();

      for (var doc in memberships.docs) {
        safeDelete(doc.reference);
      }

      // Delete buildings and their related data
      final buildings = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: orgId)
          .get();

      for (var buildingDoc in buildings.docs) {
        final buildingId = buildingDoc.id;

        // Delete rooms in this building
        final rooms = await _firestore
            .collection('rooms')
            .where('buildingId', isEqualTo: buildingId)
            .get();

        for (var roomDoc in rooms.docs) {
          final roomId = roomDoc.id;

          // Delete tenants in this room
          final tenants = await _firestore
              .collection('tenants')
              .where('roomId', isEqualTo: roomId)
              .get();

          for (var tenantDoc in tenants.docs) {
            final tenantId = tenantDoc.id;

            // Delete payments for this tenant
            final payments = await _firestore
                .collection('payments')
                .where('tenantId', isEqualTo: tenantId)
                .get();

            for (var paymentDoc in payments.docs) {
              safeDelete(paymentDoc.reference);
            }

            safeDelete(tenantDoc.reference);
          }

          safeDelete(roomDoc.reference);
        }

        safeDelete(buildingDoc.reference);
      }

      // Delete the organization itself
      safeDelete(_firestore.collection('organizations').doc(orgId));

      // Commit any remaining operations
      if (operationCount > 0) {
        await batch.commit();
      }

      // Log success
      print('✅ Organization deleted');
      return true;
    } catch (e) {
      // If anything goes wrong, log the error and return false
      print('❌ Error deleting organization: $e');
      return false;
    }
  }

  // Promote a member to admin
  // Only existing admins can promote members
  Future<bool> promoteMemberToAdmin({
    required String currentAdminId,
    required String memberIdToPromote,
    required String orgId,
  }) async {
    try {
      // Verify that the current user is an admin
      final currentAdminMembership = await getUserMembership(currentAdminId, orgId);
      
      if (currentAdminMembership == null || currentAdminMembership.role != 'admin') {
        print('❌ Only admins can promote members');
        return false;
      }

      // Get the membership of the user to be promoted
      final memberMembershipId = '${memberIdToPromote}_${orgId}';
      final memberDoc = await _firestore
          .collection('memberships')
          .doc(memberMembershipId)
          .get();

      // Check if the membership exists
      if (!memberDoc.exists) {
        print('❌ Member not found in this organization');
        return false;
      }

      final memberMembership = Membership.fromMap(
        memberDoc.id,
        memberDoc.data()!,
      );

      // Check if member is already an admin
      if (memberMembership.role == 'admin') {
        print('⚠️ User is already an admin');
        return false;
      }

      // Check if membership is active
      if (memberMembership.status != 'active') {
        print('❌ Cannot promote inactive member');
        return false;
      }

      // Update the role to admin
      await _firestore
          .collection('memberships')
          .doc(memberMembershipId)
          .update({'role': 'admin'});

      print('✅ Member promoted to admin successfully');
      return true;
    } catch (e) {
      print('❌ Error promoting member to admin: $e');
      return false;
    }
  }

    // Get all active members of an organization
  Future<List<Membership>> getOrganizationMembers(String orgId) async {
    try {
      final snapshot = await _firestore
          .collection('memberships')
          .where('organizationId', isEqualTo: orgId)
          .where('status', isEqualTo: 'active')
          .get();

      return snapshot.docs
          .map((doc) => Membership.fromMap(doc.id, doc.data()!))
          .toList();
    } catch (e) {
      print('❌ Error getting organization members: $e');
      return [];
    }
  }

  Future<String?> getInviteCode(String ownerId, String orgId) async {
    try {
      final membership = await getUserMembership(ownerId, orgId);
      if (membership == null) {
        print('❌ No membership found for user $ownerId in org $orgId');
        return null;
      }
      return membership.inviteCode;
    } catch (e) {
      print('❌ Error getting invite code: $e');
      return null;
    }
  }
    
  // Join an organization using an invite code
  Future<bool> joinOrganization({
    required String ownerId,      // the user who wants to join
    required String inviteCode,
  }) async {
    try {
      // Find any membership that has this invite code
      // (invite codes are unique per organization in your current model)
      final query = await _firestore
          .collection('memberships')
          .where('inviteCode', isEqualTo: inviteCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        print('❌ Invalid or expired invite code');
        return false;
      }

      final existingMembership = Membership.fromMap(
        query.docs.first.id,
        query.docs.first.data()!,
      );

      final orgId = existingMembership.organizationId;

      // Prevent joining the same organization twice
      final membershipId = '${ownerId}_$orgId';
      final alreadyMember = await _firestore
          .collection('memberships')
          .doc(membershipId)
          .get();

      if (alreadyMember.exists) {
        print('⚠️ User is already a member of this organization');
        return false;
      }

      // Create new membership as regular member
      final newMembership = Membership(
        id: membershipId,
        organizationId: orgId,
        ownerId: ownerId,
        role: 'member',
        inviteCode: inviteCode,
        status: 'active',
        joinedAt: DateTime.now(),
      );

      await _firestore
          .collection('memberships')
          .doc(membershipId)
          .set(newMembership.toMap());

      print('✅ User $ownerId joined organization $orgId via invite code');
      return true;
    } catch (e) {
      print('❌ Error joining organization: $e');
      return false;
    }
  }

  // Get all organizations the current user is a member of (active only)
  Future<List<Organization>> getUserOrganizations(String ownerId) async {
    try {
      // Find all active memberships for this user
      final membershipsSnap = await _firestore
          .collection('memberships')
          .where('ownerId', isEqualTo: ownerId)
          .where('status', isEqualTo: 'active')
          .get();

      if (membershipsSnap.docs.isEmpty) {
        return [];
      }

      // Collect all unique organization IDs
      final orgIds = membershipsSnap.docs
          .map((doc) => doc.data()['organizationId'] as String)
          .toSet()
          .toList();

      // Fetch the actual organization documents
      final orgsSnap = await _firestore
          .collection('organizations')
          .where(FieldPath.documentId, whereIn: orgIds)
          .get();

      return orgsSnap.docs
          .map((doc) => Organization.fromMap(doc.id, doc.data()!))
          .toList();
    } catch (e) {
      print('❌ Error fetching user organizations for $ownerId: $e');
      return [];
    }
  }
}