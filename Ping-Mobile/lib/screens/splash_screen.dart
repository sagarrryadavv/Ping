import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart'; // IMPORT AUTH
import 'onboarding_screen.dart';
import 'home_screen.dart'; // To navigate to Home

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pController;
  late AnimationController _ingController;
  late AnimationController _fadeController;

  late Animation<double> _pScaleAnimation;
  late Animation<Offset> _ingSlideAnimation;
  late Animation<double> _ingFadeAnimation;
  late Animation<double> _finalFadeAnimation;

  @override
  void initState() {
    super.initState();

    _pController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _pScaleAnimation =
        CurvedAnimation(parent: _pController, curve: Curves.easeOutBack);

    _ingController = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _ingSlideAnimation =
        Tween<Offset>(begin: const Offset(-0.5, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: _ingController, curve: Curves.easeOut));
    _ingFadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_ingController);

    _fadeController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _finalFadeAnimation =
        Tween<double>(begin: 1.0, end: 0.0).animate(_fadeController);

    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // 1. Play Animations
    await _pController.forward();
    await _ingController.forward();
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Check Logic BEFORE fading out
    User? user = FirebaseAuth.instance.currentUser;
    Widget nextScreen =
        (user != null) ? const HomeScreen() : const OnboardingScreen();

    await _fadeController.forward();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pController.dispose();
    _ingController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: FadeTransition(
          opacity: _finalFadeAnimation,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ScaleTransition(
                scale: _pScaleAnimation,
                child: Text("P",
                    style: GoogleFonts.poppins(
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.0)),
              ),
              SlideTransition(
                position: _ingSlideAnimation,
                child: FadeTransition(
                  opacity: _ingFadeAnimation,
                  child: Text("ing",
                      style: GoogleFonts.poppins(
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
