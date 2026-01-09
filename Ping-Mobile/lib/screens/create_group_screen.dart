import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math'; // For random ID generation

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  bool isPrivate = true;
  String? generatedID;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Create Group",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. NAME INPUT
              _buildLabel("Group Name"),
              _buildInput(_nameController, "e.g. Design Team Alpha"),
              const SizedBox(height: 25),

              // 2. CATEGORY INPUT
              _buildLabel("Category"),
              _buildInput(_categoryController, "e.g. Work, Study, Gaming"),
              const SizedBox(height: 25),

              // 3. PRIVACY TOGGLE
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPrivate ? "Private Group" : "Public Group",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isPrivate
                              ? "Requires invite ID to join"
                              : "Anyone can search and join",
                          style: GoogleFonts.poppins(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: isPrivate,
                      activeColor: const Color(0xFFFFC0CB),
                      activeTrackColor: const Color(
                        0xFFFFC0CB,
                      ).withOpacity(0.3),
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: Colors.black26,
                      onChanged: (val) => setState(() => isPrivate = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 4. CREATE BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC0CB),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    // GENERATE ID
                    String newID = "GRP-${Random().nextInt(9000) + 1000}";
                    setState(() {
                      generatedID = newID;
                    });

                    // SHOW SUCCESS DIALOG
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        title: Center(
                          child: Text(
                            "Group Created! 🎉",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Share this Invite ID:",
                              style: GoogleFonts.poppins(color: Colors.grey),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                newID,
                                style: GoogleFonts.robotoMono(
                                  color: const Color(0xFFFFC0CB),
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          Center(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC0CB),
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () {
                                // CLOSE DIALOG & RETURN DATA
                                Navigator.pop(context); // Close dialog

                                // Create the Group Data Object
                                final newGroupData = {
                                  "name": _nameController.text.isEmpty
                                      ? "New Group"
                                      : _nameController.text,
                                  "is_favorited": false,
                                  "pings": [
                                    {
                                      "name": "General",
                                      "icon": Icons.chat_bubble_outline,
                                    },
                                    {
                                      "name": "Announcements",
                                      "icon": Icons.campaign,
                                    },
                                  ],
                                };

                                Navigator.pop(
                                  context,
                                  newGroupData,
                                ); // Return to Find Group -> Home
                              },
                              child: const Text("Go to Home"),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(
                    "Generate Invite ID & Create",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(
        text,
        style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 14),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[700]),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }
}
