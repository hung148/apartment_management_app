import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/loading.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late AnimationController _progressController; 

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _progressController.forward();

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _animController.forward();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _animController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // Fade out before navigating
    await _animController.reverse();
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;

    if (user != null) {
      Navigator.pushReplacementNamed(context, AppRouter.dashboardScreen);
    } else {
      Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Image(
        image: const AssetImage('assets/image/background_image.jpg'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame == null) {
            return const SizedBox.expand(
              child: ColoredBox(color: Colors.black),
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              // Dark overlay for better text readability
              Container(
                color: Colors.black.withValues(alpha: 0.35),
              ),
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Stack(
                      children: [
                        // ── Center content ──────────────────────────
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // App icon — rounded square like a real app icon
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1A56DB).withValues(alpha: 0.5),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    'assets/icon/apartment_management_app_icon.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // App name with blue accent on first letter
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'P',
                                      style: TextStyle(
                                        fontSize: 52,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4D8EFF),
                                        letterSpacing: -1.5,
                                        height: 1.0,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'ropy',
                                      style: TextStyle(
                                        fontSize: 52,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -1.5,
                                        height: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Subtitle
                              Text(
                                AppTranslations.of(context).text('app_title'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.6),
                                  letterSpacing: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        // ── Progress bar pinned to bottom ───────────
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 48,
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _progressController,
                                builder: (context, _) => Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 80),
                                  child: LinearProgressIndicator(
                                    value: _progressController.value,
                                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                    minHeight: 3,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}