import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/widgets/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class OrganizationService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  final Uuid _uuid = Uuid();

  String _generateRawCode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  Future<void> migrateInviteCodesToNewCollection() async {
    final firestore = FirebaseFirestore.instance;
    logger.i('Migrating codes to invite_codes collection...');

    final orgs = await firestore.collection('organizations').get();
    final batch = firestore.batch();
    int count = 0;

    for (var orgDoc in orgs.docs) {
      final data = orgDoc.data();
      final String? code = data['inviteCode'];
      final String orgId = orgDoc.id;

      if (code != null && code.isNotEmpty) {
        final codeRef = firestore.collection('invite_codes').doc(code);
        batch.set(codeRef, {
          'organizationId': orgId,
          'claimedAt': FieldValue.serverTimestamp(),
        });
        count++;
      }
    }

    await batch.commit();
    logger.i('Successfully registered $count codes in the new collection.');
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
      final orgRef = _firestore.collection("organizations").doc();
      final membershipId = '${ownerId}_${orgRef.id}';
      final user = FirebaseAuth.instance.currentUser; 

      Organization? organization;

      while (true) {
        final inviteCode = _generateRawCode();

        try {
          await _firestore
              .collection('invite_codes')
              .doc(inviteCode)
              .set({
                'orgId': orgRef.id,
                'claimedAt': FieldValue.serverTimestamp()});
        } on FirebaseException catch (e) {
          if (e.code == 'already-exists') {
            logger.w('Invite code collision on $inviteCode, retrying...');
            continue;
          }
          rethrow;
        }

        organization = Organization(
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
          inviteCode: inviteCode,
        );

        final batch = _firestore.batch();

        batch.set(orgRef, organization.toMap());

        batch.set(
          _firestore.collection('memberships').doc(membershipId),
          Membership(
            id: membershipId,
            organizationId: orgRef.id,
            ownerId: ownerId,
            role: 'admin',
            status: 'active',
            joinedAt: DateTime.now(),
            displayName: user?.displayName ?? '', 
            email: user?.email ?? '',             
          ).toMap(),
        );

        await batch.commit();
        break;
      }

      logger.i('Organization created: ${organization.name}');
      return organization;
    } catch (e) {
      logger.e('Error creating organization', error: e);
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
      final membership = await getUserMembership(ownerId, orgId);

      if (membership == null || membership.role != 'admin') {
        logger.w('User is not admin');
        return false;
      }

      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (address != null) updates['address'] = address;
      if (phone != null) updates['phone'] = phone;
      if (email != null) updates['email'] = email;
      if (bankName != null) updates['bankName'] = bankName;
      if (bankAccountNumber != null) updates['bankAccountNumber'] = bankAccountNumber;
      if (bankAccountName != null) updates['bankAccountName'] = bankAccountName;
      if (taxCode != null) updates['taxCode'] = taxCode;

      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());

      if (updates.isEmpty || (updates.length == 1 && updates.containsKey('updatedAt'))) {
        logger.w('No updates provided');
        return false;
      }

      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update(updates);

      logger.i('Organization updated');
      return true;
    } catch (e) {
      logger.e('Error updating organization', error: e);
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
      final membership = await getUserMembership(ownerId, orgId);

      if (membership == null || membership.role != 'admin') {
        logger.w('User is not admin');
        return false;
      }

      final Map<String, dynamic> updates = {
        'bankName': bankName,
        'bankAccountNumber': bankAccountNumber,
        'bankAccountName': bankAccountName,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (taxCode != null) {
        updates['taxCode'] = taxCode;
      }

      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update(updates);

      logger.i('Bank information updated');
      return true;
    } catch (e) {
      logger.e('Error updating bank information', error: e);
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
      final membership = await getUserMembership(ownerId, orgId);

      if (membership == null || membership.role != 'admin') {
        logger.w('User is not admin');
        return false;
      }

      await _firestore
          .collection('organizations')
          .doc(orgId)
          .update({
        'bankName': null,
        'bankAccountNumber': null,
        'bankAccountName': null,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      logger.i('Bank information cleared');
      return true;
    } catch (e) {
      logger.e('Error clearing bank information', error: e);
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
        logger.w('Organization not found: $orgId');
        return null;
      }

      return Organization.fromMap(doc.id, doc.data()!);
    } catch (e) {
      logger.e('Error getting organization', error: e);
      return null;
    }
  }

  // ========================================
  // READ - Get user's membership in an organization
  // ========================================
  Future<Membership?> getUserMembership(String ownerId, String orgId) async {
    if (FirebaseAuth.instance.currentUser == null) return null;

    try {
      final membershipId = '${ownerId}_${orgId}';
      final doc = await _firestore.collection('memberships').doc(membershipId).get();

      if (!doc.exists) return null;

      return Membership.fromMap(doc.id, doc.data()!);
    } catch (e) {
      // FirebaseException path (most cases)
      if (e is FirebaseException && e.code == 'permission-denied') {
        logger.w('getUserMembership: permission-denied (FirebaseException), suppressing');
        return null;
      }
      // PlatformException path (logout race on some SDK versions)
      if (e is PlatformException && e.code == 'permission-denied') {
        logger.w('getUserMembership: permission-denied (PlatformException), suppressing');
        return null;
      }
      logger.e('Error getting membership', error: e);
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
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => Membership.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      logger.e('Error getting organization members', error: e);
      return [];
    }
  }

  // ========================================
  // READ - Get invite code
  // ========================================
  Future<String?> getInviteCode(String orgId) async {
    try {
      final org = await getOrganizationById(orgId);
      return org?.inviteCode;
    } catch (e) {
      logger.e('Error getting invite code', error: e);
      return null;
    }
  }

  Future<bool> refreshInviteCode(String adminId, String orgId) async {
    try {
      final membership = await getUserMembership(adminId, orgId);
      if (membership?.role != 'admin') return false;

      final org = await getOrganizationById(orgId);
      final oldCode = org?.inviteCode;

      while (true) {
        final newCode = _generateRawCode();

        try {
          await _firestore
              .collection('invite_codes')
              .doc(newCode)
              .set({
                'orgId': orgId,
                'claimedAt': FieldValue.serverTimestamp()});
        } on FirebaseException catch (e) {
          if (e.code == 'already-exists') {
            logger.w('Invite code collision on $newCode, retrying...');
            continue;
          }
          rethrow;
        }

        final batch = _firestore.batch();

        batch.update(
          _firestore.collection('organizations').doc(orgId),
          {
            'inviteCode': newCode,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          },
        );

        if (oldCode != null && oldCode.isNotEmpty) {
          batch.delete(_firestore.collection('invite_codes').doc(oldCode));
        }

        await batch.commit();
        logger.i('Invite code refreshed: $newCode');
        return true;
      }
    } catch (e) {
      logger.e('Error refreshing invite code', error: e);
      return false;
    }
  }

  // ========================================
  // READ - Get all organizations the current user is a member of
  // ========================================
  Future<List<Organization>> getUserOrganizations(String ownerId) async {
    if (FirebaseAuth.instance.currentUser == null) return [];

    try {
      final membershipsSnap = await _firestore
          .collection('memberships')
          .where('ownerId', isEqualTo: ownerId)
          .where('status', isEqualTo: 'active')
          .limit(100)
          .get();

      if (membershipsSnap.docs.isEmpty) {
        return [];
      }

      final orgIds = membershipsSnap.docs
          .map((doc) => doc.data()['organizationId'] as String)
          .toSet()
          .toList();

      final orgsSnap = await _firestore
          .collection('organizations')
          .where(FieldPath.documentId, whereIn: orgIds)
          .get();

      return orgsSnap.docs
          .map((doc) => Organization.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') return [];
      logger.e('Error fetching user organizations for $ownerId', error: e);
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
      final codeDoc = await _firestore
          .collection('invite_codes')
          .doc(inviteCode)
          .get();

      if (!codeDoc.exists) {
        logger.w('Invalid invite code');
        return false;
      }

      final orgId = codeDoc.data()!['orgId'] as String;

      final membershipId = '${ownerId}_$orgId';
      final alreadyMember = await _firestore
          .collection('memberships')
          .doc(membershipId)
          .get();

      if (alreadyMember.exists) {
        logger.w('Already a member');
        return false;
      }

      final user = FirebaseAuth.instance.currentUser; 

      final newMembership = Membership(
        id: membershipId,
        organizationId: orgId,
        ownerId: ownerId,
        role: 'member',
        status: 'active',
        joinedAt: DateTime.now(),
        displayName: user?.displayName ?? '', 
        email: user?.email ?? '',             
      );

      await _firestore
          .collection('memberships')
          .doc(membershipId)
          .set(newMembership.toMap());

      logger.i('User $ownerId joined organization $orgId');
      return true;
    } catch (e) {
      logger.e('Error joining organization', error: e);
      return false;
    }
  }

  // ========================================
  // LEAVE - Leave an organization
  // ========================================
  Future<bool> leaveOrganization(String ownerId, String orgId) async {
    try {
      final membershipId = '${ownerId}_${orgId}';

      final membership = await getUserMembership(ownerId, orgId);

      if (membership == null) {
        logger.w('User is not a member of this organization');
        return false;
      }

      if (membership.role == 'admin') {
        final members = await getOrganizationMembers(orgId);
        final adminCount = members.where((m) => m.role == 'admin').length;

        if (adminCount <= 1) {
          logger.w('Cannot leave: User is the last admin. Delete the organization instead or promote another member.');
          return false;
        }
      }

      await _firestore
          .collection('memberships')
          .doc(membershipId)
          .delete();

      logger.i('User left organization');
      return true;
    } catch (e) {
      logger.e('Error leaving organization', error: e);
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
      final currentAdminMembership = await getUserMembership(currentAdminId, orgId);

      if (currentAdminMembership == null || currentAdminMembership.role != 'admin') {
        logger.w('Only admins can promote members');
        return false;
      }

      final memberMembershipId = '${memberIdToPromote}_${orgId}';
      final memberDoc = await _firestore
          .collection('memberships')
          .doc(memberMembershipId)
          .get();

      if (!memberDoc.exists) {
        logger.w('Member not found in this organization');
        return false;
      }

      final memberMembership = Membership.fromMap(
        memberDoc.id,
        memberDoc.data()!,
      );

      if (memberMembership.role == 'admin') {
        logger.w('User is already an admin');
        return false;
      }

      if (memberMembership.status != 'active') {
        logger.w('Cannot promote inactive member');
        return false;
      }

      await _firestore
          .collection('memberships')
          .doc(memberMembershipId)
          .update({'role': 'admin'});

      logger.i('Member promoted to admin successfully');
      return true;
    } catch (e) {
      logger.e('Error promoting member to admin', error: e);
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
      final currentAdminMembership = await getUserMembership(currentAdminId, orgId);

      if (currentAdminMembership == null || currentAdminMembership.role != 'admin') {
        logger.w('Only admins can demote other admins');
        return false;
      }

      final members = await getOrganizationMembers(orgId);
      final adminCount = members.where((m) => m.role == 'admin').length;

      if (adminCount <= 1) {
        logger.w('Cannot demote: This is the last admin in the organization');
        return false;
      }

      final adminMembershipId = '${adminIdToDemote}_${orgId}';
      final adminDoc = await _firestore
          .collection('memberships')
          .doc(adminMembershipId)
          .get();

      if (!adminDoc.exists) {
        logger.w('Admin not found in this organization');
        return false;
      }

      final adminMembership = Membership.fromMap(
        adminDoc.id,
        adminDoc.data()!,
      );

      if (adminMembership.role != 'admin') {
        logger.w('User is not an admin');
        return false;
      }

      await _firestore
          .collection('memberships')
          .doc(adminMembershipId)
          .update({'role': 'member'});

      logger.i('Admin demoted to member successfully');
      return true;
    } catch (e) {
      logger.e('Error demoting admin', error: e);
      return false;
    }
  }

  // ========================================
  // DELETE - Delete an organization
  // ========================================
  Future<bool> deleteOrganization(String ownerId, String orgId, {Function(double)? onProgress}) async {
    try {
      final membership = await getUserMembership(ownerId, orgId);

      if (membership == null || membership.role != 'admin') {
        logger.w('User is not admin');
        return false;
      }

      logger.i('Fetching organization data...');
      onProgress?.call(0.1);

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

      logger.i('Found ${buildings.docs.length} buildings');
      onProgress?.call(0.2);

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

      logger.i('Found ${allRooms.length} rooms');
      onProgress?.call(0.35);

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

      logger.i('Found ${allTenants.length} tenants');
      onProgress?.call(0.50);

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

      logger.i('Found ${allPayments.length} payments');
      logger.i('Starting deletion process...');
      onProgress?.call(0.65);

      List<Future<void>> batchCommits = [];
      WriteBatch batch = _firestore.batch();
      int operationCount = 0;
      int totalOperations = allPayments.length + allTenants.length + allRooms.length + buildings.docs.length + memberships.docs.length + 1;

      void safeDelete(DocumentReference ref) {
        batch.delete(ref);
        operationCount++;
        if (operationCount >= 490) {
          batchCommits.add(batch.commit());
          batch = _firestore.batch();
          operationCount = 0;
        }
      }

      int deleted = 0;
      int yieldEvery = 20;
      void updateProgress() {
        if (totalOperations > 0) {
          double prog = 0.65 + (deleted / totalOperations) * 0.30;
          onProgress?.call(prog.clamp(0.0, 0.99));
        }
      }

      for (var doc in allPayments) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      logger.i('Queued ${allPayments.length} payment deletions');

      for (var doc in allTenants) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      logger.i('Queued ${allTenants.length} tenant deletions');

      for (var doc in allRooms) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      logger.i('Queued ${allRooms.length} room deletions');

      for (var doc in buildings.docs) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      logger.i('Queued ${buildings.docs.length} building deletions');

      for (var doc in memberships.docs) {
        safeDelete(doc.reference);
        deleted++;
        if (deleted % yieldEvery == 0) {
          updateProgress();
          await Future.delayed(Duration.zero);
        }
      }
      logger.i('Queued ${memberships.docs.length} membership deletions');

      safeDelete(_firestore.collection('organizations').doc(orgId));
      deleted++;
      updateProgress();
      logger.i('Queued organization deletion');

      if (operationCount > 0) {
        batchCommits.add(batch.commit());
      }

      logger.i('Committing ${batchCommits.length} batches...');
      for (var i = 0; i < batchCommits.length; i++) {
        await batchCommits[i];
        double progress = 0.65 + ((i + 1) / batchCommits.length) * 0.30;
        onProgress?.call(progress);
        if (i < batchCommits.length - 1) {
          await Future.delayed(Duration.zero);
        }
      }

      onProgress?.call(1.0);
      logger.i('Organization deleted successfully');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error deleting organization', error: e, stackTrace: stackTrace);
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
      logger.e('Error checking bank info', error: e);
      return false;
    }
  }

  // ========================================
  // UTILITY - Validate bank account number format
  // ========================================
  bool isValidBankAccountNumber(String accountNumber) {
    final regex = RegExp(r'^\d{6,20}$');
    return regex.hasMatch(accountNumber);
  }

  // ========================================
  // UTILITY - Validate tax code format (Vietnam)
  // ========================================
  bool isValidTaxCode(String taxCode) {
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
      onStatusUpdate?.call('Checking permissions...');
      final sourceMembership = await getUserMembership(ownerId, sourceOrgId);
      final targetMembership = await getUserMembership(ownerId, targetOrgId);

      if (sourceMembership == null || sourceMembership.role != 'admin') {
        logger.w('User is not admin in source organization');
        return false;
      }

      if (targetMembership == null || targetMembership.role != 'admin') {
        logger.w('User is not admin in target organization');
        return false;
      }

      final sourceOrg = await getOrganizationById(sourceOrgId);
      final targetOrg = await getOrganizationById(targetOrgId);

      if (sourceOrg == null || targetOrg == null) {
        logger.w('One or both organizations not found');
        return false;
      }

      logger.i('Starting migration from "${sourceOrg.name}" to "${targetOrg.name}"');
      onProgress?.call(0.05);

      // ============================================
      // STEP 1: Fetch all data from source
      // ============================================
      onStatusUpdate?.call('Fetching source data...');
      logger.i('Fetching all data from source organization...');

      final buildingsSnap = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: sourceOrgId)
          .get();

      final buildingIds = buildingsSnap.docs.map((doc) => doc.id).toList();
      logger.i('Found ${buildingsSnap.docs.length} buildings');
      onProgress?.call(0.10);

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
      logger.i('Found ${allRooms.length} rooms');
      onProgress?.call(0.20);

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
      logger.i('Found ${allTenants.length} tenants');
      onProgress?.call(0.30);

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
      logger.i('Found ${allPayments.length} payments');
      onProgress?.call(0.40);

      // ============================================
      // STEP 2: Create mappings for new IDs
      // ============================================
      onStatusUpdate?.call('Preparing migration mappings...');
      logger.i('Creating ID mappings...');

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
      logger.i('Starting data migration...');

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

        if (migratedCount % 20 == 0) {
          double progress = 0.45 + (migratedCount / totalOperations) * 0.45;
          onProgress?.call(progress.clamp(0.0, 0.90));
        }
      }

      for (var buildingDoc in buildingsSnap.docs) {
        final oldId = buildingDoc.id;
        final newId = buildingIdMap[oldId]!;
        final buildingData = buildingDoc.data();

        buildingData['organizationId'] = targetOrgId;

        final newBuildingRef = _firestore.collection('buildings').doc(newId);
        safeBatchOperation(newBuildingRef, buildingData);

        await Future.delayed(Duration.zero);
      }
      logger.i('Migrated ${buildingsSnap.docs.length} buildings');

      for (var roomDoc in allRooms) {
        final oldRoomId = roomDoc.id;
        final newRoomId = roomIdMap[oldRoomId]!;
        final roomData = roomDoc.data() as Map<String, dynamic>;

        final oldBuildingId = roomData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          roomData['buildingId'] = buildingIdMap[oldBuildingId];
        }

        final newRoomRef = _firestore.collection('rooms').doc(newRoomId);
        safeBatchOperation(newRoomRef, roomData);

        await Future.delayed(Duration.zero);
      }
      logger.i('Migrated ${allRooms.length} rooms');

      for (var tenantDoc in allTenants) {
        final oldTenantId = tenantDoc.id;
        final newTenantId = tenantIdMap[oldTenantId]!;
        final tenantData = tenantDoc.data() as Map<String, dynamic>;

        final oldRoomId = tenantData['roomId'];
        if (oldRoomId != null && roomIdMap.containsKey(oldRoomId)) {
          tenantData['roomId'] = roomIdMap[oldRoomId];
        }

        final oldBuildingId = tenantData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          tenantData['buildingId'] = buildingIdMap[oldBuildingId];
        }

        final newTenantRef = _firestore.collection('tenants').doc(newTenantId);
        safeBatchOperation(newTenantRef, tenantData);

        await Future.delayed(Duration.zero);
      }
      logger.i('Migrated ${allTenants.length} tenants');

      for (var paymentDoc in allPayments) {
        final paymentData = paymentDoc.data() as Map<String, dynamic>;

        final oldTenantId = paymentData['tenantId'];
        if (oldTenantId != null && tenantIdMap.containsKey(oldTenantId)) {
          paymentData['tenantId'] = tenantIdMap[oldTenantId];
        }

        final oldRoomId = paymentData['roomId'];
        if (oldRoomId != null && roomIdMap.containsKey(oldRoomId)) {
          paymentData['roomId'] = roomIdMap[oldRoomId];
        }

        final oldBuildingId = paymentData['buildingId'];
        if (oldBuildingId != null && buildingIdMap.containsKey(oldBuildingId)) {
          paymentData['buildingId'] = buildingIdMap[oldBuildingId];
        }

        final newPaymentRef = _firestore.collection('payments').doc();
        safeBatchOperation(newPaymentRef, paymentData);

        await Future.delayed(Duration.zero);
      }
      logger.i('Migrated ${allPayments.length} payments');

      if (operationCount > 0) {
        batchCommits.add(batch.commit());
      }

      // ============================================
      // STEP 4: Commit all batches
      // ============================================
      onStatusUpdate?.call('Finalizing migration...');
      logger.i('Committing ${batchCommits.length} batches...');

      for (var i = 0; i < batchCommits.length; i++) {
        await batchCommits[i];
        double progress = 0.90 + ((i + 1) / batchCommits.length) * 0.09;
        onProgress?.call(progress);
        await Future.delayed(Duration.zero);
      }

      onProgress?.call(1.0);
      onStatusUpdate?.call('Migration completed successfully!');
      logger.i('Migration completed successfully! '
          'Buildings: ${buildingsSnap.docs.length}, '
          'Rooms: ${allRooms.length}, '
          'Tenants: ${allTenants.length}, '
          'Payments: ${allPayments.length}');

      return true;
    } catch (e, stackTrace) {
      logger.e('Error during migration', error: e, stackTrace: stackTrace);
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
      onStatusUpdate?.call('Starting migration...');
      final migrationSuccess = await migrateOrganization(
        ownerId: ownerId,
        sourceOrgId: sourceOrgId,
        targetOrgId: targetOrgId,
        onProgress: (progress) => onProgress?.call(progress * 0.8),
        onStatusUpdate: onStatusUpdate,
      );

      if (!migrationSuccess) {
        logger.e('Migration failed, aborting delete');
        return false;
      }

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
        logger.i('Migration and deletion completed successfully');
        return true;
      } else {
        logger.w('Migration succeeded but deletion failed');
        onStatusUpdate?.call('Migration succeeded but deletion failed. Please delete manually.');
        return false;
      }
    } catch (e, stackTrace) {
      logger.e('Error during migrate and delete', error: e, stackTrace: stackTrace);
      onStatusUpdate?.call('Operation failed: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Get migration preview
  // ========================================
  Future<Map<String, int>> getMigrationPreview(String sourceOrgId) async {
    try {
      logger.i('Generating migration preview for org: $sourceOrgId');

      final buildingsSnap = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: sourceOrgId)
          .get();

      final buildingIds = buildingsSnap.docs.map((doc) => doc.id).toList();

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
      logger.e('Error generating migration preview', error: e);
      return {
        'buildings': 0,
        'rooms': 0,
        'tenants': 0,
        'payments': 0,
      };
    }
  }
}