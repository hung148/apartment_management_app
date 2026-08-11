import 'package:phan_mem_quan_ly_can_ho/models/owner_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown by [AuthService.deleteAccount] when Firebase requires the user
/// to have signed in recently before a sensitive operation (like account
/// deletion) can proceed. Callers should re-prompt for the password and
/// call [AuthService.reauthenticateWithPassword] before retrying.
class ReauthenticationRequiredException implements Exception {
  const ReauthenticationRequiredException();
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final OrganizationService _organizationService = OrganizationService();

  // get current user
  User? get currentUser => _auth.currentUser;

  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  // Auth state changes (listens for login/logout)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Login
  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      logger.i('Login successful');
      return result.user;
    } catch (e) {
      logger.e('Login failed', error: e);
      return null;
    }
  }

  // Logout
  Future<void> signOut() async {
    await _auth.signOut();
    logger.i('User signed out');
  }

  // Get Owner Data
  Future<Owner?> getOwnerData(String uid) async {

    try {
      // Get the owner document from Firestore
      DocumentSnapshot doc = await _firestore.collection('owners').doc(uid).get();

      // If document doesn't exist, return null
      if (!doc.exists) {
        logger.w('Owner document not found');
        return null;
      }

      // Convert Firestore data to Owner model
      return Owner.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    } catch (e) {
      logger.e('Error getting owner data', error: e);
      return null;
    }
  }

  // get current owner (combines Firebase User with owner model)
  Future<Owner?> getCurrentOwner() async {
    // Check if some is logged in
    final user = currentUser;
    if(user == null) return null;

    // Then get their Owner data from Firestore
    return await getOwnerData(user.uid);
  }

  // Register a new owner
  Future<Owner?> registerWithEmailPassword({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
  }) async {
    UserCredential? result;
    try {
      // Create Firebase Auth user
      result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create Owner model
      Owner newOwner = Owner(
        id: result.user!.uid,
        email: email,
        name: name,
        createdAt: DateTime.now(),
        invitedBy: null,
      );

      await _firestore.collection('owners').doc(newOwner.id).set(newOwner.toMap());
      logger.i('New Owner registered');

      return newOwner;
    } catch (e) {
      // Clean up orphaned Auth account if Firestore write failed
      // Only delete the Auth account if it was just created (Firestore write failed)
      if (result != null) {
        await result.user?.delete();
        logger.w('Orphaned Auth account deleted');
      }
      logger.e('Registration failed', error: e);
      return null;
    }
  }

  // Re-authenticate the current user with their password.
  // Required by Firebase before sensitive operations (like account deletion)
  // if the user's last sign-in isn't recent enough.
  Future<bool> reauthenticateWithPassword(String password) async {
    final user = currentUser;
    if (user == null || user.email == null) return false;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      logger.i('Reauthentication successful');
      return true;
    } catch (e) {
      logger.e('Reauthentication failed', error: e);
      return false;
    }
  }

  // ========================================
  // DELETE ACCOUNT - Permanently delete the signed-in user's account
  // ========================================
  //
  // This satisfies App Store Guideline 5.1.1(v): it fully removes the
  // account, not just disables it. It cascades through the user's data:
  //   - Organizations where the user is the *sole* admin are deleted
  //     entirely (including their buildings/rooms/tenants/payments).
  //   - Memberships in organizations the user shares with other admins
  //     are simply removed (the org and its data survive for the others).
  //   - The owner profile document is deleted.
  //   - Finally the Firebase Auth user itself is deleted.
  //
  // Throws [ReauthenticationRequiredException] if Firebase rejects the
  // deletion because the sign-in is stale (`requires-recent-login`).
  // Callers should collect the user's password and call
  // [reauthenticateWithPassword] before retrying.
  Future<bool> deleteAccount({Function(String)? onStatusUpdate}) async {
    final user = currentUser;
    if (user == null) return false;
    final uid = user.uid;

    try {
      onStatusUpdate?.call('Checking organizations...');

      final membershipsSnap = await _firestore
          .collection('memberships')
          .where('ownerId', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .limit(100)
          .get();

      for (final doc in membershipsSnap.docs) {
        final orgId = doc.data()['organizationId'] as String?;
        final role = doc.data()['role'] as String?;
        if (orgId == null) continue;

        if (role == 'admin') {
          final members = await _organizationService.getOrganizationMembers(orgId);
          final adminCount = members.where((m) => m.role == 'admin').length;

          if (adminCount <= 1) {
            // Sole admin: the organization and all of its data belong
            // only to this account, so it must be deleted too.
            onStatusUpdate?.call('Deleting organization data...');
            final deleted = await _organizationService.deleteOrganization(uid, orgId);
            if (!deleted) {
              logger.e('Failed to delete organization $orgId during account deletion');
              return false;
            }
            continue;
          }
        }

        // Shared organization (or a plain member): just remove this
        // user's membership, leaving the organization intact for others.
        await _firestore.collection('memberships').doc(doc.id).delete();
      }

      onStatusUpdate?.call('Deleting profile...');
      await _firestore.collection('owners').doc(uid).delete();

      onStatusUpdate?.call('Deleting account...');
      await user.delete();

      logger.i('Account deleted successfully');
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        logger.w('Account deletion requires reauthentication');
        throw const ReauthenticationRequiredException();
      }
      logger.e('Error deleting account', error: e);
      return false;
    } catch (e, stackTrace) {
      logger.e('Error deleting account', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}