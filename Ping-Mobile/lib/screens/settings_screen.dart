import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // ⚠️ REQUIRED FOR BRAND ICONS

import 'login_screen.dart';
import 'avatar_builder_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  // --- LOGOUT ---
  Future<void> _handleLogout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false);
    }
  }

  // --- LAUNCHER ---
  Future<void> _launchLink(String url) async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            title: const Text("Open Website?",
                style: TextStyle(color: Colors.white)),
            content: Text("Do you want to open $url?",
                style: const TextStyle(color: Colors.grey)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Open")),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Could not launch $url")));
        }
      }
    }
  }

  // --- EDIT NAME ---
  void _showEditNameDialog() {
    final TextEditingController nameController =
        TextEditingController(text: user?.displayName);
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: Text("Change Name",
                  style: GoogleFonts.poppins(color: Colors.white)),
              content: TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC0CB),
                        foregroundColor: Colors.black),
                    onPressed: () async {
                      if (nameController.text.isNotEmpty) {
                        await user
                            ?.updateDisplayName(nameController.text.trim());
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .update(
                                {"displayName": nameController.text.trim()});
                        if (mounted) {
                          Navigator.pop(context);
                          setState(() {});
                        }
                      }
                    },
                    child: const Text("Save"))
              ],
            ));
  }

  // --- RESET PASSWORD ---
  void _sendPasswordReset() async {
    if (user?.email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Password reset link sent to your email!"),
            backgroundColor: Colors.green));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // --- MUTE OPTIONS ---
  void _showMuteOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Mute Specific Groups",
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Select groups to mute:",
                style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .where('members', arrayContains: user?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  var groups = snapshot.data!.docs;

                  return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user?.uid)
                          .snapshots(),
                      builder: (context, userSnap) {
                        List mutedGroups = [];
                        if (userSnap.hasData && userSnap.data!.exists) {
                          mutedGroups =
                              (userSnap.data!.data() as Map)['mutedGroups'] ??
                                  [];
                        }

                        return ListView.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            var group = groups[index];
                            bool isMuted = mutedGroups.contains(group.id);
                            return SwitchListTile(
                              title: Text(group['name'],
                                  style: const TextStyle(color: Colors.white)),
                              value: isMuted,
                              activeColor: const Color(0xFFFFC0CB),
                              onChanged: (val) async {
                                if (val) {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user?.uid)
                                      .update({
                                    "mutedGroups":
                                        FieldValue.arrayUnion([group.id])
                                  });
                                } else {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user?.uid)
                                      .update({
                                    "mutedGroups":
                                        FieldValue.arrayRemove([group.id])
                                  });
                                }
                              },
                            );
                          },
                        );
                      });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- FEEDBACK ---
  void _showFeedbackDialog(String type) {
    TextEditingController msgController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: Text(type,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Support Email:",
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  const Text("sagarrryadavv@gmail.com@gmail.com",
                      style: TextStyle(
                          color: Color(0xFFFFC0CB),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: msgController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Type your message here...",
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black),
                  onPressed: () async {
                    if (msgController.text.isNotEmpty) {
                      await FirebaseFirestore.instance
                          .collection('feedback')
                          .add({
                        "email": user?.email ?? "Anonymous",
                        "message": msgController.text.trim(),
                        "timestamp": FieldValue.serverTimestamp(),
                        "type": type,
                        "userId": user?.uid,
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Feedback Sent!")));
                    }
                  },
                  child: const Text("Submit"),
                )
              ],
            ));
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title:
            const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(
            "Privacy Policy for Ping App\n\n"
            "1. Information We Collect\nWe collect your email, username, and profile avatar data to provide the service.\n\n"
            "2. How We Use Information\nYour data is used solely for the functionality of the app.\n\n"
            "3. Contact Us\nIf you have questions, contact sagarrryadavv@gmail.com.",
            style: TextStyle(color: Colors.grey[300]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text("Settings",
                  style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 30),

              // --- PROFILE CARD ---
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AvatarBuilderScreen())),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          Widget avatarWidget = const CircleAvatar(
                              radius: 30, backgroundColor: Colors.grey);
                          if (snapshot.hasData && snapshot.data!.exists) {
                            Map data = snapshot.data!.data() as Map;
                            if (data.containsKey('avatarData') &&
                                data['avatarData'] != null) {
                              avatarWidget = Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFF3D2B5),
                                  border: Border.all(
                                      color: const Color(0xFFFFC0CB), width: 2),
                                ),
                                child: ClipOval(
                                  child: Transform.scale(
                                    scale: 1.35,
                                    alignment: Alignment.center,
                                    child: SvgPicture.string(data['avatarData'],
                                        fit: BoxFit.contain),
                                  ),
                                ),
                              );
                            } else if (data['avatarUrl'] != null) {
                              avatarWidget = CircleAvatar(
                                  radius: 30,
                                  backgroundImage:
                                      NetworkImage(data['avatarUrl']));
                            }
                          }
                          return avatarWidget;
                        },
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.displayName ?? "User",
                                style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(height: 4),
                            Text("Edit Avatar & Profile",
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: const Color(0xFFFFC0CB),
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.grey, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- GENERAL ---
              Text("General",
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500])),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(25)),
                child: Column(
                  children: [
                    StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          bool isMuted = false;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            isMuted = (snapshot.data!.data()
                                    as Map)['muteAllNotifications'] ??
                                false;
                          }
                          return SwitchListTile(
                            title: Text("Pause All Notifications",
                                style: GoogleFonts.poppins(
                                    color: Colors.white, fontSize: 15)),
                            value: isMuted,
                            activeColor: const Color(0xFFFFC0CB),
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.notifications_paused_outlined,
                                  color: Colors.grey[400], size: 20),
                            ),
                            onChanged: (val) async {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user?.uid)
                                  .update({"muteAllNotifications": val});
                            },
                          );
                        }),
                    _buildDivider(),
                    _buildNavTile(
                        "Mute Specific Groups", Icons.group_off_outlined,
                        onTap: _showMuteOptions),
                    _buildDivider(),
                    _buildNavTile("Account Security", Icons.security_outlined,
                        onTap: () {
                      showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF1E1E1E),
                          builder: (context) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                      leading: const Icon(Icons.edit,
                                          color: Colors.white),
                                      title: const Text("Change Name",
                                          style:
                                              TextStyle(color: Colors.white)),
                                      onTap: _showEditNameDialog),
                                  ListTile(
                                      leading: const Icon(Icons.lock_reset,
                                          color: Colors.white),
                                      title: const Text("Reset Password",
                                          style:
                                              TextStyle(color: Colors.white)),
                                      onTap: _sendPasswordReset),
                                  const SizedBox(height: 20)
                                ],
                              ));
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // --- SUPPORT ---
              Text("Support",
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500])),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(25)),
                child: Column(
                  children: [
                    _buildNavTile("Contact Us", Icons.mail_outline,
                        onTap: () => _showFeedbackDialog("Contact Us")),
                    _buildDivider(),
                    _buildNavTile("Privacy Policy", Icons.privacy_tip_outlined,
                        onTap: _showPrivacyPolicy),
                    _buildDivider(),
                    _buildNavTile("Report a Bug", Icons.bug_report_outlined,
                        onTap: () => _showFeedbackDialog("Report a Bug")),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ⚠️ NEW: DEVELOPER INFO (With Brand Icons)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white10)),
                child: Column(
                  children: [
                    const Text("About Developer",
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 10),
                    Text("Sagar Yadav",
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                          "Passionate developer building cool apps.\nLove coding, coffee, and breaking things to fix them better.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                              fontStyle: FontStyle.italic)),
                    ),
                    const SizedBox(height: 20), // Spacing for icons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // INSTAGRAM
                        _socialButton(FontAwesomeIcons.instagram, "Instagram",
                            "https://www.instagram.com/sagarrryadavv/"),
                        const SizedBox(width: 15),

                        // LINKEDIN
                        _socialButton(FontAwesomeIcons.linkedin, "LinkedIn",
                            "https://www.linkedin.com/in/sagarrryadavv"),
                        const SizedBox(width: 15),

                        // GITHUB
                        _socialButton(FontAwesomeIcons.github, "GitHub",
                            "https://github.com/sagarrryadavv"),
                        const SizedBox(width: 15),

                        // WEBSITE
                        _socialButton(FontAwesomeIcons.globe, "Website",
                            "https://sagaryadav.site"),
                      ],
                    )
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // --- LOGOUT ---
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3E2C2C),
                      foregroundColor: const Color(0xFFFF5555),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: _handleLogout,
                  child: Text("Log Out",
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // Helper for Social Buttons
  Widget _socialButton(IconData icon, String label, String url) {
    return Column(
      children: [
        IconButton(
          onPressed: () => _launchLink(url),
          icon: Icon(icon,
              color: const Color(0xFFFFC0CB),
              size: 22), // ⚠️ Sized for FontAwesome
          style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.all(12)), // Slightly larger touch area
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9))
      ],
    );
  }

  Widget _buildNavTile(String title, IconData icon,
      {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.grey[400], size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 15))),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
        color: Colors.grey[800], height: 1, indent: 60, endIndent: 20);
  }
}
