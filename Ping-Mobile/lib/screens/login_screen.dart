import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'avatar_builder_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- ⚠️ HELPER: CUSTOM STYLED POPUP (Matches your Theme) ---
  void _showStyledDialog(String title, String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        content: Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 14)),
        actions: [
          Center(
            child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK",
                    style: TextStyle(
                        color: Color(0xFFFFC0CB),
                        fontWeight: FontWeight.bold,
                        fontSize: 16))),
          )
        ],
      ),
    );
  }

  // --- ⚠️ BUG 2 FIX: SMART PASSWORD RESET ---
  Future<void> _handleForgotPassword() async {
    String email = _emailController.text.trim();

    if (email.isEmpty) {
      _showStyledDialog(
          "Missing Email", "Please enter your email address first.",
          isError: true);
      return;
    }

    try {
      // 1. CHECK DATABASE FIRST
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        // 2. NOT FOUND -> Custom Popup
        _showStyledDialog(
            "Not Registered", "This email is not registered with Ping.",
            isError: true);
        return;
      }

      // 3. FOUND -> Send Email
      await _auth.sendPasswordResetEmail(email: email);

      _showStyledDialog("Reset Link Sent",
          "Check your inbox at $email to reset your password.");
    } catch (e) {
      _showStyledDialog("Error", e.toString(), isError: true);
    }
  }

  // --- GOOGLE SIGN IN ---
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            "uid": user.uid,
            "email": user.email,
            "displayName": user.displayName,
            "createdAt": DateTime.now(),
            "avatarSetupComplete": false,
            "avatarUrl": user.photoURL ??
                "https://img.freepik.com/premium-vector/man-avatar-profile-picture-vector-illustration_268834-538.jpg",
          });
          if (mounted)
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        const AvatarBuilderScreen(isFirstTime: true)));
        } else {
          _checkAvatarStatus(user.uid);
        }
      }
    } catch (e) {
      _showStyledDialog("Sign In Failed", "Google Sign In could not complete.",
          isError: true);
      setState(() => _isLoading = false);
    }
  }

  // --- ⚠️ BUG 1 FIX: LOGIN WITH CUSTOM POPUPS ---
  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showStyledDialog("Incomplete", "Please enter both email and password.",
          isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null && !user.emailVerified) {
        await _auth.signOut();
        _showStyledDialog("Email Not Verified",
            "Please check your inbox and verify your email before logging in.");
        setState(() => _isLoading = false);
        return;
      }

      if (user != null) {
        _checkAvatarStatus(user.uid);
      }
    } on FirebaseAuthException catch (e) {
      // ⚠️ CUSTOM ERROR MESSAGES
      String errorTitle = "Login Failed";
      String errorMessage = "An error occurred. Please try again.";

      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        errorTitle = "Account Not Found";
        errorMessage = "No account found with this email. Please Sign Up.";
      } else if (e.code == 'wrong-password') {
        errorTitle = "Wrong Password";
        errorMessage = "The password you entered is incorrect.";
      } else if (e.code == 'invalid-email') {
        errorTitle = "Invalid Email";
        errorMessage = "Please enter a valid email address.";
      }

      _showStyledDialog(errorTitle, errorMessage, isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkAvatarStatus(String uid) async {
    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
        bool isSetupComplete = data?['avatarSetupComplete'] ?? false;

        if (mounted) {
          if (isSetupComplete) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (context) => const HomeScreen()));
          } else {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        const AvatarBuilderScreen(isFirstTime: true)));
          }
        }
      }
    } catch (e) {
      if (mounted)
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 40.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text("Ping.",
                  style: GoogleFonts.poppins(
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 60),
              _buildTextField("Email", _emailController),
              const SizedBox(height: 15),
              _buildTextField("Password", _passwordController,
                  isPassword: true),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleForgotPassword,
                  child: Text("Forgot Password?",
                      style: GoogleFonts.poppins(
                          color: Colors.grey[500], fontSize: 12)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text("Log In",
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C2C2C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text("Sign in with Google"),
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                ),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SignupScreen())),
                child: RichText(
                  text: TextSpan(
                    text: "Don't have an account? ",
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                    children: [
                      TextSpan(
                          text: "Sign Up",
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontWeight: FontWeight.bold))
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[500]),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none)),
    );
  }
}
