import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class OrganizationService {
  // Create instance of Firestore to interact with the database
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // UUID generator for creating unique invite codes
  final Uuid _uuid = Uuid();

  // Gemerate a unique 8-character inivite code
  String _generateInviteCode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  // Create a new organization
  Future<Organization?> createOrganization({
    required String name,
    required String ownerId,
  }) async {
    try {
      // Create a new document reference in 'organizations' collection
      final orgRef = _firestore.collection("organizations").doc();

      // Create an Organization object with the generated ID
      final organization = Organization(
        id: orgRef.id, // Use the auto-generated ID
        name: name, // Organization name from parameter
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

  // Get all organizations that a user is a member of
  Future<List<Organization>> getUserOrganizations(String ownerId) async {
    try {
      // Find all memberships where this user is a member
      final membershipsSnapshot  = await _firestore
        .collection('memberships') // Access memberships collection
        .where('ownerId', isEqualTo: ownerId) // Filter by user ID
        .where('status', isEqualTo: 'active') // Only get active member
        .get(); // Execute the quert and get results

      // Create ann empty list to store organizations
      List<Organization> organizations = [];

      // Loop through all membership documents
      for (var membershipDoc in membershipsSnapshot.docs) {
        // Convert the document data to a Membership object
        final membership = Membership.fromMap(
          membershipDoc.id, // Document ID
          membershipDoc.data(), // Document data
        );

        // Now get the organization document using the organizationId from membership
        final orgDoc = await _firestore
          .collection('organizations') // Access organizations collection
          .doc(membership.organizationId) // Get specific organization
          .get(); // Fetch the document
        
        // Check if the organization document exists
        if (orgDoc.exists) {
          // Convert the document to an Organization object and add to our list
          organizations.add(
            Organization.fromMap(
              orgDoc.id, // Document ID
              orgDoc.data()! // Document data
            )
          );
        }
      }

      return organizations;
    } catch(e) {
      print('❌ Error getting user organizations: $e');
      return [];
    }
  }

  // Get a single organization by its ID
  Future<Organization?> getOrganization(String orgId) async {
    try {
      // Get the organization document from firestore
      final doc = await _firestore
        .collection('organizations') // Access organizations collection
        .doc(orgId) // Get specific document by ID
        .get();
      
      // Check if document exists
      if (!doc.exists) return null;

      // Convert document to Organization object and return it
      return Organization.fromMap(
        doc.id, 
        doc.data()!,
      );
    } catch(e) {
      print('❌ Error getting organization: $e');
      return null;
    }
  }

  // Get a user's membership in a specific organization
  Future<Membership?> getUserMembership(String ownerId, String orgId) async {
    try {
      // Create the membership ID by combining user ID adn org ID
      final membershipId = '${ownerId}_${orgId}';

      // Try to get the membership document
      final doc = await _firestore
        .collection('memberships') // Access the memberships collection 
        .doc(membershipId) // Get document with our custom ID
        .get(); // Fethc the document
      
      // Check if the membership exist
      if (!doc.exists) return null;

      // Convert document to Membership obejct and return it
      return Membership.fromMap(
        doc.id, 
        doc.data()!
      );
    } catch (e) {
      // If anything goes wrong, log the error and return null
      print('❌ Error getting membership: $e');
      return null;
    }
  }

  // Join an organization using an invite code
  Future<bool> joinOrganization({
    required String ownerID,
    required String inviteCode,
  }) async {
    try {
      // We search in memberships beacuse each org has an invite code stored there
      final membershipSnapshot = await _firestore
        .collection('memberships') // Access memberships collection
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase()) // Find by inviteCode
        .limit(1) // We only need one result
        .get(); // Execute the query
      
      // Check if we found any membership with this invite code
      if (membershipSnapshot.docs.isEmpty) {
        print('❌ Invalid invite code');
        return false;
      }

      // Get the first (and only) membership document
      // This tells us which organization the invite code belongs to
      final existingMembership = Membership.fromMap(
        membershipSnapshot.docs.first.id, // Document ID 
        membershipSnapshot.docs.first.data(), // Document data
      );

      // Create the membership ID for this user + organization combo
      final userMembershipId = '${ownerID}_${existingMembership.organizationId}';

      // Try to get this membership document
      final existingUserMembership = await _firestore
        .collection('memberships') 
        .doc(userMembershipId)
        .get();
      
      // If this document already exists, user is already a member
      if (existingUserMembership.exists) {
        print('⚠️ User already a member of this organization');
        return false;
      }

      // Create a new membership for the user
      final newMembership = Membership(
        id: userMembershipId, // Unique ID for this membership
        organizationId: existingMembership.organizationId, // Link to organization
        ownerId: ownerID, // Link to user
        role: 'member', // New users join as regular members (not admin)
        inviteCode: existingMembership.inviteCode, // Same invite code as organization
        status: 'active', // Membership is active immediately
        joinedAt: DateTime.now(), // Store when they joined
      );

      // Save the new membership to Firestore
      await _firestore
          .collection('memberships') // Access memberships collection
          .doc(userMembershipId) // Use our custom ID
          .set(newMembership.toMap()); // Save the membership data
      
      // Log success
      print('✅ User joined organization');
      return true;
    } catch (e) {
      // If anything goes wrong, log the error and return false
      print('❌ Error joining organization: $e');
      return false;
    }
  }

  // Get the inviteCode for an organization
  // Only admins can get the invite code
  Future<String?> getInviteCode(String ownerId, String orgId) async {
    try {
      // Get the user's membership in this organization
      final membership = await getUserMembership(ownerId, orgId);

      // Check if membership exists and if user is an admin
      if (membership == null || membership.role != 'admin') {
        print('❌ User is not admin of this organization');
        return null;
      }

      // Return the invite code
      return membership.inviteCode;
    } catch (e) {
      // If anything goes wrong, log the error and return null
      print('❌ Error getting invite code: $e');
      return null;
    }
  }

  // Get all members of an organization
  Future<List<Membership>> getOrganizationMembers(String orgId) async {
    try {
      // Query all memberships for this organization
      final snapshot = await _firestore
          .collection('memberships') // Access memberships collection
          .where('organizationId', isEqualTo: orgId) // Filter by organization
          .where('status', isEqualTo: 'active') // Only get active members
          .get(); // Execute the query

      // Convert all documents to Membership objects and return as a list
      return snapshot.docs
          .map((doc) => Membership.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      // If anything goes wrong, log the error and return empty list
      print('❌ Error getting organization members: $e');
      return [];
    }
  }

  // Leave an organization
  Future<bool> leaveOrganization(String ownerId, String orgId) async {
    try {
      // Create the membership ID
      final membershipId = '${ownerId}_${orgId}';
      
      // Delete the membership document
      await _firestore
          .collection('memberships') // Access memberships collection
          .doc(membershipId) // Get specific membership
          .delete(); // Delete it
      
      // Log success
      print('✅ User left organization');
      return true;
    } catch (e) {
      // If anything goes wrong, log the error and return false
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

      // Delete all memberships for this organization
      // First, get all memberships
      final memberships = await _firestore
          .collection('memberships') // Access memberships collection
          .where('organizationId', isEqualTo: orgId) // Filter by organization
          .get(); // Get all documents

      // Loop through and delete each membership
      for (var doc in memberships.docs) {
        await doc.reference.delete(); // Delete the membership
      }

      // Delete the organization itself
      await _firestore
          .collection('organizations') // Access organizations collection
          .doc(orgId) // Get specific organization
          .delete(); // Delete it

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
}