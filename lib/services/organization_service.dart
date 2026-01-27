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

  // ========================================
  // CREATE - Create a new organization
  // ========================================
  Future<Organization?> createOrganization({
    required String name,
    required String ownerId,
    String? address,
    String? phone,
    String? email,
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountName,
    String? taxCode,
  }) async {
    try {
      // Create a new document reference in 'organizations' collection
      final orgRef = _firestore.collection("organizations").doc();

      // Create an Organization object with the generated ID
      final organization = Organization(
        id: orgRef.id,
        name: name,
        address: address,
        phone: phone,
        email: email,
        bankName: bankName,
        bankAccountNumber: bankAccountNumber,
        bankAccountName: bankAccountName,
        taxCode: taxCode,
        createdBy: ownerId,
        createdAt: DateTime.now(),
      );

      // Save the organization to Firestore
      await orgRef.set(organization.toMap());

      // Create a membership for the creator as admin
      final membershipId = '${ownerId}_${orgRef.id}';
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

      print('✅ Organization created: ${organization.name}');
      return organization;
    } catch (e) {
      print('❌ Error creating organization: $e');
      return null;
    }
  }

  // ========================================
  // UPDATE - Update organization details
  // ========================================
  Future<bool> updateOrganization({
    required String ownerId,
    required String orgId,
    String? name,
    String? address,
    String? phone,
    String? email,
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountName,
    String? taxCode,
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
      if (bankName != null) updates['bankName'] = bankName;
      if (bankAccountNumber != null) updates['bankAccountNumber'] = bankAccountNumber;
      if (bankAccountName != null) updates['bankAccountName'] = bankAccountName;
      if (taxCode != null) updates['taxCode'] = taxCode;
      
      // Always update the updatedAt timestamp
      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());

      // If no updates provided, return early
      if (updates.isEmpty || (updates.length == 1 && updates.containsKey('updatedAt'))) {
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

  // ========================================
  // UPDATE - Update bank information specifically
  // ========================================
  Future<bool> updateBankInformation({
    required String ownerId,
    required String orgId,
    required String bankName,
    required String bankAccountNumber,
    required String bankAccountName,
    String? taxCode,
  }) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin');
        return false;
      }

      // Build update map
      final Map<String, dynamic> updates = {
        'bankName': bankName,
        'bankAccountNumber': bankAccountNumber,
        'bankAccountName': bankAccountName,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (taxCode != null) {
        updates['taxCode'] = taxCode;
      }

      // Update the organization
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update(updates);

      print('✅ Bank information updated');
      return true;
    } catch (e) {
      print('❌ Error updating bank information: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Clear bank information
  // ========================================
  Future<bool> clearBankInformation({
    required String ownerId,
    required String orgId,
  }) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin');
        return false;
      }

      // Update the organization - set bank fields to null
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update({
        'bankName': null,
        'bankAccountNumber': null,
        'bankAccountName': null,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ Bank information cleared');
      return true;
    } catch (e) {
      print('❌ Error clearing bank information: $e');
      return false;
    }
  }

  // ========================================
  // READ - Get organization by ID
  // ========================================
  Future<Organization?> getOrganizationById(String orgId) async {
    try {
      final doc = await _firestore.collection('organizations').doc(orgId).get();
      
      if (!doc.exists) {
        print('❌ Organization not found: $orgId');
        return null;
      }
      
      return Organization.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('❌ Error getting organization: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get user's membership in an organization
  // ========================================
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

  // ========================================
  // READ - Get all active members of an organization
  // ========================================
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

  // ========================================
  // READ - Get invite code
  // ========================================
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

  // ========================================
  // READ - Get all organizations the current user is a member of
  // ========================================
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

  // ========================================
  // JOIN - Join an organization using an invite code
  // ========================================
  Future<bool> joinOrganization({
    required String ownerId,
    required String inviteCode,
  }) async {
    try {
      // Find any membership that has this invite code
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

  // ========================================
  // LEAVE - Leave an organization
  // ========================================
  Future<bool> leaveOrganization(String ownerId, String orgId) async {
    try {
      // Create the membership ID
      final membershipId = '${ownerId}_${orgId}';
      
      // Get membership to check role
      final membership = await getUserMembership(ownerId, orgId);
      
      if (membership == null) {
        print('❌ User is not a member of this organization');
        return false;
      }

      // Prevent the last admin from leaving
      if (membership.role == 'admin') {
        final members = await getOrganizationMembers(orgId);
        final adminCount = members.where((m) => m.role == 'admin').length;
        
        if (adminCount <= 1) {
          print('❌ Cannot leave: You are the last admin. Delete the organization instead or promote another member.');
          return false;
        }
      }
      
      // Delete the membership document
      await _firestore
          .collection('memberships')
          .doc(membershipId)
          .delete();
      
      print('✅ User left organization');
      return true;
    } catch (e) {
      print('❌ Error leaving organization: $e');
      return false;
    }
  }

  // ========================================
  // PROMOTE - Promote a member to admin
  // ========================================
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

  // ========================================
  // DEMOTE - Demote an admin to member
  // ========================================
  Future<bool> demoteAdminToMember({
    required String currentAdminId,
    required String adminIdToDemote,
    required String orgId,
  }) async {
    try {
      // Verify that the current user is an admin
      final currentAdminMembership = await getUserMembership(currentAdminId, orgId);
      
      if (currentAdminMembership == null || currentAdminMembership.role != 'admin') {
        print('❌ Only admins can demote other admins');
        return false;
      }

      // Prevent self-demotion if you're the last admin
      final members = await getOrganizationMembers(orgId);
      final adminCount = members.where((m) => m.role == 'admin').length;
      
      if (adminCount <= 1) {
        print('❌ Cannot demote: This is the last admin in the organization');
        return false;
      }

      // Get the membership of the admin to be demoted
      final adminMembershipId = '${adminIdToDemote}_${orgId}';
      final adminDoc = await _firestore
          .collection('memberships')
          .doc(adminMembershipId)
          .get();

      if (!adminDoc.exists) {
        print('❌ Admin not found in this organization');
        return false;
      }

      final adminMembership = Membership.fromMap(
        adminDoc.id,
        adminDoc.data()!,
      );

      if (adminMembership.role != 'admin') {
        print('⚠️ User is not an admin');
        return false;
      }

      // Update the role to member
      await _firestore
          .collection('memberships')
          .doc(adminMembershipId)
          .update({'role': 'member'});

      print('✅ Admin demoted to member successfully');
      return true;
    } catch (e) {
      print('❌ Error demoting admin: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete an organization
  // ========================================
  Future<bool> deleteOrganization(String ownerId, String orgId) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
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

      print('✅ Organization deleted');
      return true;
    } catch (e) {
      print('❌ Error deleting organization: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Check if organization has complete bank info
  // ========================================
  Future<bool> hasCompleteBankInfo(String orgId) async {
    try {
      final org = await getOrganizationById(orgId);
      return org?.hasBankInfo ?? false;
    } catch (e) {
      print('❌ Error checking bank info: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Validate bank account number format
  // ========================================
  bool isValidBankAccountNumber(String accountNumber) {
    // Basic validation: 6-20 digits
    final regex = RegExp(r'^\d{6,20}$');
    return regex.hasMatch(accountNumber);
  }

  // ========================================
  // UTILITY - Validate tax code format (Vietnam)
  // ========================================
  bool isValidTaxCode(String taxCode) {
    // Vietnam tax code: 10-14 digits (can include hyphens)
    final regex = RegExp(r'^\d{10}(-\d{3})?$');
    return regex.hasMatch(taxCode.replaceAll('-', ''));
  }
}