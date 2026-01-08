import 'package:apartment_management_project_2/models/owner_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // get current user
  User? get currentUser => _auth.currentUser;

  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  // Auth state changes (listens for login/logout)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Login
  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      return result.user;
    } catch (e) {
      print('Login failed: ${e.toString()}');
      return null;
    }
  }

  // Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Get Owner Data
  Future<Owner?> getOwnerData(String uid) async {
    try {
      // Get the owner document from Firestore
      DocumentSnapshot doc = await _firestore.collection('owners').doc(uid).get();

      // If document doesn't exist, return null
      if (!doc.exists) {
        return null;
      }

      // Convert Firestore data to Owner model
      return Owner.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    } catch (e) {
      print('Error getting owner data: $e');
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
    try {
      // Create Firebase Auth user
      UserCredential result = await _auth.createUserWithEmailAndPassword(
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

      return newOwner;
    } catch (e) {
      print('Registration failed: ${e.toString()}');
      return null;
    }
  }
}