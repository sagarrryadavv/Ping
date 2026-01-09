import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  List<Map<String, dynamic>> slides = [
    {
      "title": "Don't Lurk. Live.",
      "desc":
          "Real-time conversations only. No scrolling through old messages. Be there or miss out.",
      "icon": Icons.visibility_off_outlined,
    },
    {
      "title": "No History.",
      "desc":
          "Every message self-destructs. No screenshots allowed. Speak your mind freely.",
      "icon": Icons.local_fire_department_outlined,
    },
    {
      "title": "Your Face, Your Rules.",
      "desc":
          "Use 3D Avatars to express yourself without revealing your real identity.",
      "icon": Icons.face_retouching_natural,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Deep Black
      body: SafeArea(
        child: Column(
          children: [
            // SKIP BUTTON
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => _goToLogin(),
                child: Text(
                  "SKIP",
                  style: GoogleFonts.poppins(color: Colors.grey),
                ),
              ),
            ),

            // SWIPEABLE AREA
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: slides.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon Circle (Matte Grey with Pink Icon)
                        Container(
                          padding: const EdgeInsets.all(35),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2C2C2C), // Matte Grey
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slides[index]['icon'],
                            size: 70,
                            color: const Color(0xFFFFC0CB), // Pink Accent
                          ),
                        ),
                        const SizedBox(height: 50),

                        // Title
                        Text(
                          slides[index]['title'],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Description
                        Text(
                          slides[index]['desc'],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey[400],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // BOTTOM CONTROLS
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        height: 8,
                        width: _currentPage == index ? 30 : 8,
                        decoration: BoxDecoration(
                          // Active = Pink, Inactive = Dark Grey
                          color: _currentPage == index
                              ? const Color(0xFFFFC0CB)
                              : const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Button (Pink Squircle)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC0CB), // Pink
                        foregroundColor: Colors.black, // Black Text
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20), // Squircle
                        ),
                      ),
                      onPressed: () {
                        if (_currentPage == slides.length - 1) {
                          _goToLogin();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.ease,
                          );
                        }
                      },
                      child: Text(
                        _currentPage == slides.length - 1
                            ? "GET STARTED"
                            : "NEXT",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }
}
