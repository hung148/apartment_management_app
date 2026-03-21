import 'package:apartment_management_project_2/models/owner_model.dart';
import 'package:apartment_management_project_2/widgets/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
}