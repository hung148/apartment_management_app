import 'app_functions.dart';
import 'device_session.dart';
import 'read_cache.dart';
import 'organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/models/owner_model.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Thrown by [AuthService.deleteSignIn] when Firebase requires the user
/// to have signed in recently before a sensitive operation (like account
/// deletion) can proceed. Callers should re-prompt for the password and
/// call [AuthService.reauthenticateWithPassword] before retrying.
class ReauthenticationRequiredException implements Exception {
  const ReauthenticationRequiredException();
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

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

  /// Google sign-in is offered on web and Android (R2, 2026-10-01). The iPhone
  /// app waits for Sign in with Apple (App Store rule); desktop builds have no
  /// Firebase provider flow.
  static bool get googleSignInAvailable =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Signs in with Google. Returns null when the person closed or cancelled the
  /// Google window. Throws [FirebaseAuthException] for real failures.
  /// The first Google sign-in creates the owners/{uid} profile.
  Future<User?> signInWithGoogle({String? languageCode}) async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    UserCredential result;
    try {
      if (languageCode != null) await _auth.setLanguageCode(languageCode);
      result = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (const {
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-cancelled',
        'web-context-canceled',
        'user-cancelled',
        'canceled',
      }.contains(e.code)) {
        return null;
      }
      rethrow;
    }
    final user = result.user;
    if (user == null) return null;
    try {
      await _ensureOwnerProfile(user);
    } catch (e) {
      // Without a profile the dashboard cannot load; sign out so a retry starts clean.
      logger.e('Could not create the profile after Google sign-in', error: e);
      await _auth.signOut();
      throw FirebaseAuthException(code: 'profile-create-failed');
    }
    logger.i('Google sign-in successful');
    return user;
  }

  Future<void> _ensureOwnerProfile(User user) async {
    final ref = _firestore.collection('owners').doc(user.uid);
    if ((await ref.get()).exists) return;
    final email = user.email ?? '';
    final display = user.displayName?.trim() ?? '';
    final name = display.isNotEmpty ? display : email.split('@').first;
    await ref.set(Owner(
      id: user.uid,
      email: email,
      name: name.length > 100 ? name.substring(0, 100) : name,
      createdAt: DateTime.now(),
      invitedBy: null,
    ).toMap());
  }

  /// "Remember this computer" (web, 2026-10-06). Runs just before signing in.
  /// Unticked (a shared computer): the sign-in ends when the browser closes
  /// and nothing is saved on the computer (the saved copy is wiped now).
  Future<void> applyRememberChoice(bool remember) async {
    if (!offerRememberThisDevice) return;
    setRememberThisDevice(remember);
    await _auth.setPersistence(
      remember ? Persistence.LOCAL : Persistence.SESSION,
    );
    if (!remember) await ReadCache.shared?.clear();
  }

  /// Ends every sign-in of this account on every device, then this one.
  Future<void> signOutEverywhere() async {
    await appCallable('accountSessions').call({'action': 'signOutEverywhere'});
    await signOut();
  }

  // Logout
  Future<void> signOut() async {
    OrganizationMoney.shared.clear();
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
      // Legacy organizations copy the sign-in display name into memberships.
      await setAuthDisplayName(name);
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

  /// Keeps the Firebase sign-in's display name in step with the profile name.
  /// Best effort: the profile itself is the source of truth.
  Future<void> setAuthDisplayName(String name) async {
    try {
      await currentUser?.updateDisplayName(name);
    } catch (e) {
      logger.w('Could not update the sign-in display name', error: e);
    }
  }

  Future<void> _reauthenticateOrThrow(String password) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
  }

  /// Checks the current password, then sets the new one. Throws
  /// [FirebaseAuthException] (wrong-password / invalid-credential,
  /// weak-password, too-many-requests, network-request-failed ...).
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _reauthenticateOrThrow(currentPassword);
    await currentUser!.updatePassword(newPassword);
    logger.i('Password changed');
  }

  /// Checks the password, then emails a confirmation link to [newEmail].
  /// The sign-in email only changes after the link is opened; the user then
  /// signs in again with the new address. Throws [FirebaseAuthException]
  /// (wrong-password / invalid-credential, email-already-in-use,
  /// invalid-email, too-many-requests ...).
  Future<void> requestEmailChange({required String password, required String newEmail}) async {
    await _reauthenticateOrThrow(password);
    await currentUser!.verifyBeforeUpdateEmail(newEmail.trim());
    logger.i('Email change link sent');
  }

  /// Emails a password reset link. An unknown email is treated as sent, so
  /// the screen never reveals whether an account exists. Throws
  /// [FirebaseAuthException] for invalid-email, too-many-requests and
  /// network-request-failed.
  Future<void> sendPasswordReset(String email, {String? languageCode}) async {
    try {
      if (languageCode != null) await _auth.setLanguageCode(languageCode);
      await _auth.sendPasswordResetEmail(email: email.trim());
      logger.i('Password reset email requested');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'user-disabled') return;
      rethrow;
    }
  }

  /// Forces a fresh ID token so the server sees the new sign-in time right
  /// after [reauthenticateWithPassword].
  Future<void> refreshIdToken() async {
    await currentUser?.getIdToken(true);
  }

  // ========================================
  // DELETE SIGN-IN - last step of account deletion
  // ========================================
  //
  // The server (deleteMyAccount) removes or hands over everything the
  // account owns first; this only removes the Firebase Auth user so the
  // email can no longer sign in. Satisfies App Store Guideline 5.1.1(v).
  //
  // Throws [ReauthenticationRequiredException] when Firebase wants a
  // recent sign-in (`requires-recent-login`).
  Future<void> deleteSignIn() async {
    final user = currentUser;
    if (user == null) return;
    try {
      await user.delete();
      logger.i('Sign-in deleted');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        logger.w('Deleting the sign-in requires reauthentication');
        throw const ReauthenticationRequiredException();
      }
      rethrow;
    }
  }
}
