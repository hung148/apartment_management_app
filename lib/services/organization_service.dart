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
  Future<bool> deleteOrganization(String ownerId, String orgId, {Function(double)? onProgress}) async {
    try {
      // Check if user is admin
      final membership = await getUserMembership(ownerId, orgId);
      
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin');
        return false;
      }

      // Fetch all data first in parallel to avoid nested queries
      print('📊 Fetching organization data...');
      onProgress?.call(0.1); // 10% - fetching data
      
      final results = await Future.wait([
        _firestore
            .collection('memberships')
            .where('organizationId', isEqualTo: orgId)
            .get(),
        _firestore
            .collection('buildings')
            .where('organizationId', isEqualTo: orgId)
            .get(),
      ]);

      final memberships = results[0];
      final buildings = results[1];
      
      final buildingIds = buildings.docs.map((doc) => doc.id).toList();
      
      print('📊 Found ${buildings.docs.length} buildings');
      onProgress?.call(0.2); // 20% - fetched main collections

      // Fetch all rooms for all buildings in parallel
      List<QuerySnapshot> roomSnapshots = [];
      if (buildingIds.isNotEmpty) {
        // Split into chunks of 10 for 'whereIn' limit
        for (int i = 0; i < buildingIds.length; i += 10) {
          final chunk = buildingIds.skip(i).take(10).toList();
          final roomSnap = await _firestore
              .collection('rooms')
              .where('buildingId', whereIn: chunk)
              .get();
          roomSnapshots.add(roomSnap);
          // Yield to event loop every chunk
          await Future.delayed(Duration.zero);
        }
      }
      
      final allRooms = roomSnapshots.expand((snap) => snap.docs).toList();
      final roomIds = allRooms.map((doc) => doc.id).toList();
      
      print('📊 Found ${allRooms.length} rooms');
      onProgress?.call(0.35); // 35% - fetched rooms

      // Fetch all tenants for all rooms in parallel
      List<QuerySnapshot> tenantSnapshots = [];
      if (roomIds.isNotEmpty) {
        for (int i = 0; i < roomIds.length; i += 10) {
          final chunk = roomIds.skip(i).take(10).toList();
          final tenantSnap = await _firestore
              .collection('tenants')
              .where('roomId', whereIn: chunk)
              .get();
          tenantSnapshots.add(tenantSnap);
          // Yield to event loop
          await Future.delayed(Duration.zero);
        }
      }
      
      final allTenants = tenantSnapshots.expand((snap) => snap.docs).toList();
      final tenantIds = allTenants.map((doc) => doc.id).toList();
      
      print('📊 Found ${allTenants.length} tenants');
      onProgress?.call(0.50); // 50% - fetched tenants

      // Fetch all payments for all tenants in parallel
      List<QuerySnapshot> paymentSnapshots = [];
      if (tenantIds.isNotEmpty) {
        for (int i = 0; i < tenantIds.length; i += 10) {
          final chunk = tenantIds.skip(i).take(10).toList();
          final paymentSnap = await _firestore
              .collection('payments')
              .where('tenantId', whereIn: chunk)
              .get();
          paymentSnapshots.add(paymentSnap);
          // Yield to event loop
          await Future.delayed(Duration.zero);
        }
      }
      
      final allPayments = paymentSnapshots.expand((snap) => snap.docs).toList();
      
      print('📊 Found ${allPayments.length} payments');
      print('🗑️ Starting deletion process...');
      onProgress?.call(0.65); // 65% - fetched all data, starting deletion

      // Collect all batch commits we need to do
      List<Future<void>> batchCommits = [];
      WriteBatch batch = _firestore.batch();
      int operationCount = 0;
      int totalOperations = allPayments.length + allTenants.length + allRooms.length + buildings.docs.length + memberships.docs.length + 1;

      // Helper to add delete operation safely
      void safeDelete(DocumentReference ref) {
        batch.delete(ref);
        operationCount++;
        if (operationCount >= 490) {
          // Store the current batch commit
          batchCommits.add(batch.commit());
          // Create a new batch
          batch = _firestore.batch();
          operationCount = 0;
        }
      }


      // Helper for yielding and progress
      int deleted = 0;
      int yieldEvery = 20;
      void updateProgress() {
        if (totalOperations > 0) {
          double prog = 0.65 + (deleted / totalOperations) * 0.30;
          onProgress?.call(prog.clamp(0.0, 0.99));
        }
      }

      // Delete all payments
      for (var doc in allPayments) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      print('🗑️ Queued ${allPayments.length} payment deletions');

      // Delete all tenants
      for (var doc in allTenants) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      print('🗑️ Queued ${allTenants.length} tenant deletions');

      // Delete all rooms
      for (var doc in allRooms) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      print('🗑️ Queued ${allRooms.length} room deletions');

      // Delete all buildings
      for (var doc in buildings.docs) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      print('🗑️ Queued ${buildings.docs.length} building deletions');

      // Delete all memberships
      for (var doc in memberships.docs) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      print('🗑️ Queued ${memberships.docs.length} membership deletions');

      // Delete the organization itself
      safeDelete(_firestore.collection('organizations').doc(orgId));
      deleted++;
      updateProgress();
      print('🗑️ Queued organization deletion');

      // Commit remaining operations in the current batch
      if (operationCount > 0) {
        batchCommits.add(batch.commit());
      }

      // Wait for all batches to complete with periodic yields to event loop
      print('⏳ Committing ${batchCommits.length} batches...');
      for (var i = 0; i < batchCommits.length; i++) {
        await batchCommits[i];
        // Update progress: 65% to 95%
        double progress = 0.65 + ((i + 1) / batchCommits.length) * 0.30;
        onProgress?.call(progress);
        // Yield to event loop after each batch commit
        if (i < batchCommits.length - 1) {
          await Future.delayed(Duration.zero);
        }
      }

      onProgress?.call(1.0); // 100% - completed
      print('✅ Organization deleted successfully');
      return true;
    } catch (e, stackTrace) {
      print('❌ Error deleting organization: $e');
      print('Stack trace: $stackTrace');
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

  // ========================================
  // MIGRATE - Migrate all data from one organization to another
  // ========================================
  Future<bool> migrateOrganization({
    required String ownerId,
    required String sourceOrgId,
    required String targetOrgId,
    Function(double)? onProgress,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      // Verify user is admin in BOTH organizations
      onStatusUpdate?.call('Checking permissions...');
      final sourceMembership = await getUserMembership(ownerId, sourceOrgId);
      final targetMembership = await getUserMembership(ownerId, targetOrgId);
      
      if (sourceMembership == null || sourceMembership.role != 'admin') {
        print('❌ User is not admin in source organization');
        return false;
      }
      
      if (targetMembership == null || targetMembership.role != 'admin') {
        print('❌ User is not admin in target organization');
        return false;
      }

      // Verify both organizations exist
      final sourceOrg = await getOrganizationById(sourceOrgId);
      final targetOrg = await getOrganizationById(targetOrgId);
      
      if (sourceOrg == null || targetOrg == null) {
        print('❌ One or both organizations not found');
        return false;
      }

      print('🔄 Starting migration from "${sourceOrg.name}" to "${targetOrg.name}"');
      onProgress?.call(0.05);

      // ============================================
      // STEP 1: Fetch all data from source
      // ============================================
      onStatusUpdate?.call('Fetching source data...');
      print('📊 Fetching all data from source organization...');
      
      final buildingsSnap = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: sourceOrgId)
          .get();
      
      final buildingIds = buildingsSnap.docs.map((doc) => doc.id).toList();
      print('📊 Found ${buildingsSnap.docs.length} buildings');
      onProgress?.call(0.10);

      // Fetch all rooms
      List<QuerySnapshot> roomSnapshots = [];
      if (buildingIds.isNotEmpty) {
        for (int i = 0; i < buildingIds.length; i += 10) {
          final chunk = buildingIds.skip(i).take(10).toList();
          final roomSnap = await _firestore
              .collection('rooms')
              .where('buildingId', whereIn: chunk)
              .get();
          roomSnapshots.add(roomSnap);
          await Future.delayed(Duration.zero);
        }
      }
      
      final allRooms = roomSnapshots.expand((snap) => snap.docs).toList();
      final roomIds = allRooms.map((doc) => doc.id).toList();
      print('📊 Found ${allRooms.length} rooms');
      onProgress?.call(0.20);

      // Fetch all tenants
      List<QuerySnapshot> tenantSnapshots = [];
      if (roomIds.isNotEmpty) {
        for (int i = 0; i < roomIds.length; i += 10) {
          final chunk = roomIds.skip(i).take(10).toList();
          final tenantSnap = await _firestore
              .collection('tenants')
              .where('roomId', whereIn: chunk)
              .get();
          tenantSnapshots.add(tenantSnap);
          await Future.delayed(Duration.zero);
        }
      }
      
      final allTenants = tenantSnapshots.expand((snap) => snap.docs).toList();
      final tenantIds = allTenants.map((doc) => doc.id).toList();
      print('📊 Found ${allTenants.length} tenants');
      onProgress?.call(0.30);

      // Fetch all payments
      List<QuerySnapshot> paymentSnapshots = [];
      if (tenantIds.isNotEmpty) {
        for (int i = 0; i < tenantIds.length; i += 10) {
          final chunk = tenantIds.skip(i).take(10).toList();
          final paymentSnap = await _firestore
              .collection('payments')
              .where('tenantId', whereIn: chunk)
              .get();
          paymentSnapshots.add(paymentSnap);
          await Future.delayed(Duration.zero);
        }
      }
      
      final allPayments = paymentSnapshots.expand((snap) => snap.docs).toList();
      print('📊 Found ${allPayments.length} payments');
      onProgress?.call(0.40);

      // ============================================
      // STEP 2: Create mappings for new IDs
      // ============================================
      onStatusUpdate?.call('Preparing migration mappings...');
      print('🗺️ Creating ID mappings...');
      
      // Map old building IDs to new building IDs
      final Map<String, String> buildingIdMap = {};
      final Map<String, String> roomIdMap = {};
      final Map<String, String> tenantIdMap = {};
      
      for (var buildingDoc in buildingsSnap.docs) {
        final newBuildingRef = _firestore.collection('buildings').doc();
        buildingIdMap[buildingDoc.id] = newBuildingRef.id;
      }
      
      for (var roomDoc in allRooms) {
        final newRoomRef = _firestore.collection('rooms').doc();
        roomIdMap[roomDoc.id] = newRoomRef.id;
      }
      
      for (var tenantDoc in allTenants) {
        final newTenantRef = _firestore.collection('tenants').doc();
        tenantIdMap[tenantDoc.id] = newTenantRef.id;
      }
      
      onProgress?.call(0.45);

      // ============================================
      // STEP 3: Migrate data with new IDs
      // ============================================
      onStatusUpdate?.call('Migrating data to target organization...');
      print('🔄 Starting data migration...');
      
      List<Future<void>> batchCommits = [];
      WriteBatch batch = _firestore.batch();
      int operationCount = 0;
      int totalOperations = buildingsSnap.docs.length + allRooms.length + 
                          allTenants.length + allPayments.length;
      int migratedCount = 0;

      void safeBatchOperation(DocumentReference ref, Map<String, dynamic> data) {
        batch.set(ref, data);
        operationCount++;
        migratedCount++;
        
        if (operationCount >= 490) {
          batchCommits.add(batch.commit());
          batch = _firestore.batch();
          operationCount = 0;
        }
        
        // Update progress periodically
        if (migratedCount % 20 == 0) {
          double progress = 0.45 + (migratedCount / totalOperations) * 0.45;
          onProgress?.call(progress.clamp(0.0, 0.90));
        }
      }

      // Migrate buildings
      for (var buildingDoc in buildingsSnap.docs) {
        final oldId = buildingDoc.id;
        final newId = buildingIdMap[oldId]!;
        final buildingData = buildingDoc.data();
        
        // Update organization ID
        buildingData['organizationId'] = targetOrgId;
        
        final newBuildingRef = _firestore.collection('buildings').doc(newId);
        safeBatchOperation(newBuildingRef, buildingData);
        
        await Future.delayed(Duration.zero);
      }
      print('✅ Migrated ${buildingsSnap.docs.length} buildings');

      // Migrate rooms
      for (var roomDoc in allRooms) {
        final oldRoomId = roomDoc.id;
        final newRoomId = roomIdMap[oldRoomId]!;
        final roomData = roomDoc.data() as Map<String, dynamic>;
        
        // Update building ID reference
        final oldBuildingId = roomData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          roomData['buildingId'] = buildingIdMap[oldBuildingId];
        }
        
        final newRoomRef = _firestore.collection('rooms').doc(newRoomId);
        safeBatchOperation(newRoomRef, roomData);
        
        await Future.delayed(Duration.zero);
      }
      print('✅ Migrated ${allRooms.length} rooms');

      // Migrate tenants
      for (var tenantDoc in allTenants) {
        final oldTenantId = tenantDoc.id;
        final newTenantId = tenantIdMap[oldTenantId]!;
        final tenantData = tenantDoc.data() as Map<String, dynamic>;
        
        // Update room ID reference
        final oldRoomId = tenantData['roomId'];
        if (oldRoomId != null && roomIdMap.containsKey(oldRoomId)) {
          tenantData['roomId'] = roomIdMap[oldRoomId];
        }
        
        // Update building ID reference (if exists)
        final oldBuildingId = tenantData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          tenantData['buildingId'] = buildingIdMap[oldBuildingId];
        }
        
        final newTenantRef = _firestore.collection('tenants').doc(newTenantId);
        safeBatchOperation(newTenantRef, tenantData);
        
        await Future.delayed(Duration.zero);
      }
      print('✅ Migrated ${allTenants.length} tenants');

      // Migrate payments
      for (var paymentDoc in allPayments) {
        final paymentData = paymentDoc.data() as Map<String, dynamic>;
        
        // Update tenant ID reference
        final oldTenantId = paymentData['tenantId'];
        if (oldTenantId != null && tenantIdMap.containsKey(oldTenantId)) {
          paymentData['tenantId'] = tenantIdMap[oldTenantId];
        }
        
        // Update room ID reference (if exists)
        final oldRoomId = paymentData['roomId'];
        if (oldRoomId != null && roomIdMap.containsKey(oldRoomId)) {
          paymentData['roomId'] = roomIdMap[oldRoomId];
        }
        
        // Update building ID reference (if exists)
        final oldBuildingId = paymentData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          paymentData['buildingId'] = buildingIdMap[oldBuildingId];
        }
        
        // Generate new payment ID
        final newPaymentRef = _firestore.collection('payments').doc();
        safeBatchOperation(newPaymentRef, paymentData);
        
        await Future.delayed(Duration.zero);
      }
      print('✅ Migrated ${allPayments.length} payments');

      // Commit remaining operations
      if (operationCount > 0) {
        batchCommits.add(batch.commit());
      }

      // ============================================
      // STEP 4: Commit all batches
      // ============================================
      onStatusUpdate?.call('Finalizing migration...');
      print('⏳ Committing ${batchCommits.length} batches...');
      
      for (var i = 0; i < batchCommits.length; i++) {
        await batchCommits[i];
        double progress = 0.90 + ((i + 1) / batchCommits.length) * 0.09;
        onProgress?.call(progress);
        await Future.delayed(Duration.zero);
      }

      onProgress?.call(1.0);
      onStatusUpdate?.call('Migration completed successfully!');
      print('✅ Migration completed successfully!');
      print('📊 Summary:');
      print('   - Buildings: ${buildingsSnap.docs.length}');
      print('   - Rooms: ${allRooms.length}');
      print('   - Tenants: ${allTenants.length}');
      print('   - Payments: ${allPayments.length}');
      
      return true;
    } catch (e, stackTrace) {
      print('❌ Error during migration: $e');
      print('Stack trace: $stackTrace');
      onStatusUpdate?.call('Migration failed: $e');
      return false;
    }
  }

  // ========================================
  // MIGRATE - Migrate and DELETE source organization
  // ========================================
  Future<bool> migrateAndDeleteOrganization({
    required String ownerId,
    required String sourceOrgId,
    required String targetOrgId,
    Function(double)? onProgress,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      // Step 1: Migrate data (0% - 80%)
      onStatusUpdate?.call('Starting migration...');
      final migrationSuccess = await migrateOrganization(
        ownerId: ownerId,
        sourceOrgId: sourceOrgId,
        targetOrgId: targetOrgId,
        onProgress: (progress) => onProgress?.call(progress * 0.8),
        onStatusUpdate: onStatusUpdate,
      );

      if (!migrationSuccess) {
        print('❌ Migration failed, aborting delete');
        return false;
      }

      // Step 2: Delete source organization (80% - 100%)
      onStatusUpdate?.call('Deleting source organization...');
      onProgress?.call(0.80);
      
      final deleteSuccess = await deleteOrganization(
        ownerId,
        sourceOrgId,
        onProgress: (progress) => onProgress?.call(0.80 + (progress * 0.2)),
      );

      if (deleteSuccess) {
        onProgress?.call(1.0);
        onStatusUpdate?.call('Migration and cleanup completed!');
        print('✅ Migration and deletion completed successfully');
        return true;
      } else {
        print('⚠️ Migration succeeded but deletion failed');
        onStatusUpdate?.call('Migration succeeded but deletion failed. Please delete manually.');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ Error during migrate and delete: $e');
      print('Stack trace: $stackTrace');
      onStatusUpdate?.call('Operation failed: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Get migration preview
  // ========================================
  Future<Map<String, int>> getMigrationPreview(String sourceOrgId) async {
    try {
      print('📊 Generating migration preview for org: $sourceOrgId');
      
      final buildingsSnap = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: sourceOrgId)
          .get();
      
      final buildingIds = buildingsSnap.docs.map((doc) => doc.id).toList();
      
      // Count rooms
      int roomCount = 0;
      if (buildingIds.isNotEmpty) {
        for (int i = 0; i < buildingIds.length; i += 10) {
          final chunk = buildingIds.skip(i).take(10).toList();
          final roomSnap = await _firestore
              .collection('rooms')
              .where('buildingId', whereIn: chunk)
              .get();
          roomCount += roomSnap.docs.length;
        }
      }
      
      // Get room IDs for tenant count
      List<String> roomIds = [];
      if (buildingIds.isNotEmpty) {
        for (int i = 0; i < buildingIds.length; i += 10) {
          final chunk = buildingIds.skip(i).take(10).toList();
          final roomSnap = await _firestore
              .collection('rooms')
              .where('buildingId', whereIn: chunk)
              .get();
          roomIds.addAll(roomSnap.docs.map((doc) => doc.id));
        }
      }
      
      // Count tenants
      int tenantCount = 0;
      if (roomIds.isNotEmpty) {
        for (int i = 0; i < roomIds.length; i += 10) {
          final chunk = roomIds.skip(i).take(10).toList();
          final tenantSnap = await _firestore
              .collection('tenants')
              .where('roomId', whereIn: chunk)
              .get();
          tenantCount += tenantSnap.docs.length;
        }
      }
      
      // Get tenant IDs for payment count
      List<String> tenantIds = [];
      if (roomIds.isNotEmpty) {
        for (int i = 0; i < roomIds.length; i += 10) {
          final chunk = roomIds.skip(i).take(10).toList();
          final tenantSnap = await _firestore
              .collection('tenants')
              .where('roomId', whereIn: chunk)
              .get();
          tenantIds.addAll(tenantSnap.docs.map((doc) => doc.id));
        }
      }
      
      // Count payments
      int paymentCount = 0;
      if (tenantIds.isNotEmpty) {
        for (int i = 0; i < tenantIds.length; i += 10) {
          final chunk = tenantIds.skip(i).take(10).toList();
          final paymentSnap = await _firestore
              .collection('payments')
              .where('tenantId', whereIn: chunk)
              .get();
          paymentCount += paymentSnap.docs.length;
        }
      }
      
      return {
        'buildings': buildingsSnap.docs.length,
        'rooms': roomCount,
        'tenants': tenantCount,
        'payments': paymentCount,
      };
    } catch (e) {
      print('❌ Error generating migration preview: $e');
      return {
        'buildings': 0,
        'rooms': 0,
        'tenants': 0,
        'payments': 0,
      };
    }
  }
}