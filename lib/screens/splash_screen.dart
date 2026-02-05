import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:apartment_management_project_2/widgets/loading.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  // initState runs ONCE when this widget is first created
  // It's like the "start" or "setup" function
  @override
  void initState() {
    // Call the parent class's initState (required by Flutter)
    super.initState();

    // check if user is logged in
    _checkAuthStatus();
  }

  // This function checks if a user is logged in or not
  Future<void> _checkAuthStatus() async {
    
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 3));

    // Check if this widget is still on screen
    // If user closed the app durint the 2 seconds, don't continue
    // This prevent errors when trying to navigate after widget is gone
    if(!mounted) return;

    // Wait for Firebase Auth to finish checking persistence
    // This ensures we get the correct auth state
    // Get current auth state
    final user = FirebaseAuth.instance.currentUser;
    
    if (!mounted) return;
    
    // Get the currently logged-in user from Firebase
    // If someone is logged in, 'user' will have their info
    // If nobody is logged in, 'user' will be null
    // Firebase Auth stores login data LOCALLY on each device
    // When you login on your phone, only your phone remembers you
    // When your friend logs in on their phone, only their phone remembers them
    
    // Check if user exists (is logged in)
    if (user != null) {
      // User is logged in
      // Navigate to Dashboard and replace this splash screen
      Navigator.pushReplacementNamed(context, AppRouter.dashboardScreen);
    } else {
      // User is NOT logged in
      // Navigate to Login screen and replace this splash screen
      Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display an apartment icon
            Icon(
              Icons.apartment, // The icon type (building icon)
              size: 100,
              color: Theme.of(context).colorScheme.primary,
            ),

            const SizedBox(height: 24),

            // Display text
            const Text(
              'Phần Mền Quản Lý Căn Hộ', // The text to show
              style: TextStyle( // How the text should look
                fontSize: 24,
                fontWeight: FontWeight.bold, 
              )
            ),

            const SizedBox(height: 24),

            Loading(size: 50),
          ],
        ),
      ),
    );
  }
}