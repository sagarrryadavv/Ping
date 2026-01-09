import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart'; // REQUIRED: To navigate to Login after signup

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- VALIDATION ---
  String? _validateInputs() {
    String email = _emailController.text.trim();
    String pass = _passwordController.text.trim();
    String confirmPass = _confirmPasswordController.text.trim();

    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty)
      return "Please enter your full name.";
    if (email.isEmpty || !email.contains('@') || !email.contains('.'))
      return "Please enter a valid email address.";
    if (pass.length < 8) return "Password must be at least 8 characters long.";
    if (pass != confirmPass) return "Passwords do not match.";
    return null;
  }

  // --- SIGN UP LOGIC ---
  Future<void> _handleSignUp() async {
    String? error = _validateInputs();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Create Auth User
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      String fullName =
          "${_firstNameController.text.trim()} ${_lastNameController.text.trim()}";
      await userCredential.user?.updateDisplayName(fullName);

      // 2. CREATE FIRESTORE DOCUMENT (Mark as NOT setup)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        "uid": userCredential.user!.uid,
        "email": _emailController.text.trim(),
        "displayName": fullName,
        "createdAt": DateTime.now(),
        "avatarSetupComplete": false, // <--- User must finish setup later
        "avatarUrl":
            "https://img.freepik.com/premium-vector/man-avatar-profile-picture-vector-illustration_268834-538.jpg",
      });

      // 3. Send Verification Email
      await userCredential.user?.sendEmailVerification();

      // 4. Success -> Send to Login
      if (mounted) _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? "Sign Up Failed"),
          backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.mark_email_read, color: Color(0xFFFFC0CB)),
                  const SizedBox(width: 10),
                  Text("Verify Email",
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                "We sent a verification link to ${_emailController.text}.\n\nPlease check your email, click the link, and then Log In.",
                style: GoogleFonts.poppins(color: Colors.grey[400]),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC0CB),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    // REDIRECT TO LOGIN
                    Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const LoginScreen()),
                        (route) => false);
                  },
                  child: const Text("Go to Login"),
                )
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            children: [
              Text("Create Account",
                  style: GoogleFonts.poppins(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 30),
              Row(children: [
                Expanded(
                    child: _buildTextField("First Name", _firstNameController)),
                const SizedBox(width: 15),
                Expanded(
                    child: _buildTextField("Last Name", _lastNameController))
              ]),
              const SizedBox(height: 15),
              _buildTextField("Email", _emailController),
              const SizedBox(height: 15),
              _buildTextField("Password", _passwordController,
                  isPassword: true),
              const SizedBox(height: 15),
              _buildTextField("Confirm Password", _confirmPasswordController,
                  isPassword: true),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: _isLoading ? null : _handleSignUp,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text("Sign Up",
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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
