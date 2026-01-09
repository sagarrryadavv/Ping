import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';

class FindGroupScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onGroupAdded;
  const FindGroupScreen({super.key, required this.onGroupAdded});

  @override
  State<FindGroupScreen> createState() => _FindGroupScreenState();
}

class _FindGroupScreenState extends State<FindGroupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final User? user = FirebaseAuth.instance.currentUser;
  late TabController _tabController;

  Timer? _debounce;
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- SEARCH HANDLER ---
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _searchText = query;
        });
      }
    });
  }

  // --- HELPER: GENERATE ID ---
  String _generateSimpleId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    Random rnd = Random();
    String p1 = String.fromCharCodes(Iterable.generate(
        3, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    String p2 = String.fromCharCodes(Iterable.generate(
        3, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return "$p1-$p2";
  }

  // --- CREATE GROUP ---
  Future<void> _createGroup(String name, String desc, bool isPublic) async {
    if (user == null) return;
    String inviteCode = _generateSimpleId();

    try {
      DocumentReference ref =
          await FirebaseFirestore.instance.collection('groups').add({
        "name": name,
        "description": desc,
        "createdBy": user!.uid,
        "createdAt": FieldValue.serverTimestamp(),
        "members": [user!.uid],
        "isPublic": isPublic,
        "inviteCode": inviteCode,
      });

      if (mounted) {
        Navigator.pop(context);
        widget.onGroupAdded({'id': ref.id});
        _showGroupIdDialog(name, inviteCode);
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // --- ⚠️ UPDATED: SUBMIT PUBLIC REQUEST (Send to Admin Panel) ---
  Future<void> _submitPublicRequest(String reason) async {
    if (user == null) return;
    if (reason.trim().isEmpty) return;

    try {
      // ⚠️ FIX: Sending to 'feedback' collection so Admin Panel sees it
      await FirebaseFirestore.instance.collection('feedback').add({
        "type": "Public Group Request", // Matches Admin Tab
        "message": reason.trim(), // The text from the box
        "reason": reason.trim(), // Backup field
        "email": user!.email ?? "Unknown User",
        "uid": user!.uid,
        "timestamp": FieldValue.serverTimestamp(),
        "isRead": false,
        "isReplied": false,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Request sent! We will review it shortly.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- JOIN LOGIC ---
  void _quickJoin(String groupId) async {
    await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([user!.uid])
    });
    if (mounted) {
      widget.onGroupAdded({'id': groupId});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Joined!")));
    }
  }

  void _redirectToHome() {
    widget.onGroupAdded({});
  }

  Future<void> _joinByInviteCode(String code) async {
    if (user == null) return;
    try {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('groups')
          .where('inviteCode', isEqualTo: code.toUpperCase().trim())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        DocumentSnapshot doc = query.docs.first;
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(doc.id)
            .update({
          'members': FieldValue.arrayUnion([user!.uid])
        });
        if (mounted) {
          Navigator.pop(context);
          widget.onGroupAdded({'id': doc.id});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Joined ${(doc.data() as Map)['name']}!")));
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Invalid Code.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- POPUPS ---
  void _showPublicRequestDialog() {
    TextEditingController reasonCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("Restricted Access",
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Public groups are currently restricted.",
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  const Text("Contact us: sagarrryadavv@gmail.com",
                      style: TextStyle(
                          color: Color(0xFFFFC0CB),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  const Text("Or submit a request:",
                      style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                        hintText: "Why do you need a public group?",
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel",
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC0CB),
                        foregroundColor: Colors.black),
                    onPressed: () =>
                        _submitPublicRequest(reasonCtrl.text.trim()),
                    child: const Text("Submit Request"))
              ],
            ));
  }

  void _showGroupIdDialog(String name, String code) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("Group Created!",
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Invite ID:",
                      style: GoogleFonts.poppins(color: Colors.grey[400])),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Copied!")));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFC0CB))),
                      child: Text(code,
                          style: GoogleFonts.robotoMono(
                              color: const Color(0xFFFFC0CB),
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              letterSpacing: 2.0)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Done",
                        style: TextStyle(color: Colors.white)))
              ],
            ));
  }

  void _showCreateDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController descCtrl = TextEditingController();
    bool isPublic = false;

    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF2C2C2C),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text("Create Group",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          hintText: "Group Name",
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: descCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          hintText: "Description (Optional)",
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 15),
                    SwitchListTile(
                      title: const Text("Public Group",
                          style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                          isPublic ? "Visible in search" : "Hidden (Code Only)",
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12)),
                      activeColor: const Color(0xFFFFC0CB),
                      value: isPublic,
                      onChanged: (val) {
                        if (val == true) {
                          _showPublicRequestDialog();
                          // Don't switch the toggle if it's restricted
                        } else {
                          setState(() => isPublic = val);
                        }
                      },
                    )
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC0CB),
                        foregroundColor: Colors.black),
                    onPressed: () => _createGroup(
                        nameCtrl.text.trim(), descCtrl.text.trim(), isPublic),
                    child: const Text("Create"),
                  )
                ],
              );
            }));
  }

  void _showJoinByIdDialog() {
    TextEditingController idCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: const Text("Join by Code",
                  style: TextStyle(color: Colors.white)),
              content: TextField(
                controller: idCtrl,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, letterSpacing: 1.5),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                    hintText: "XXX-XXX",
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black),
                  onPressed: () => _joinByInviteCode(idCtrl.text.trim()),
                  child: const Text("Join"),
                )
              ],
            ));
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            labelStyle:
                GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
            indicatorColor: Colors.white,
            indicatorWeight: 3.0,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: "Search"), Tab(text: "Discover")],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildSearchTab(), _buildDiscoverTab()],
          ),
        )
      ],
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Find public groups...",
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _searchText.isEmpty
              ? _buildQuickOptions()
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .where('isPublic', isEqualTo: true)
                      .where('name', isGreaterThanOrEqualTo: _searchText)
                      .where('name', isLessThan: '$_searchText\uf8ff')
                      .limit(20)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: SelectableText(
                          "Database Error: ${snapshot.error}",
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFFFC0CB)));
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                          child: Text("No groups found.",
                              style: TextStyle(color: Colors.grey)));
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        var data = doc.data() as Map<String, dynamic>;
                        List members = data['members'] ?? [];
                        bool isMember = members.contains(user?.uid);

                        return ListTile(
                          title: Text(data['name'] ?? "Unknown",
                              style: const TextStyle(color: Colors.white)),
                          subtitle: data['description'] != null
                              ? Text(data['description'],
                                  maxLines: 1,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 12))
                              : null,
                          trailing: isMember
                              ? IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: _redirectToHome)
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFC0CB),
                                      foregroundColor: Colors.black),
                                  onPressed: () => _quickJoin(doc.id),
                                  child: const Text("Join"),
                                ),
                        );
                      },
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildDiscoverTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .where('isPublic', isEqualTo: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC0CB)));
        var docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var doc = docs[index];
            var data = doc.data() as Map<String, dynamic>;
            List members = data['members'] ?? [];
            bool isMember = members.contains(user?.uid);
            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(data['name'] ?? "Unknown",
                    style: const TextStyle(color: Colors.white)),
                subtitle: data['description'] != null
                    ? Text(data['description'],
                        maxLines: 1,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12))
                    : null,
                trailing: isMember
                    ? IconButton(
                        icon:
                            const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: _redirectToHome)
                    : IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: Color(0xFFFFC0CB)),
                        onPressed: () => _quickJoin(doc.id),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickOptions() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Text("Quick Actions",
            style: GoogleFonts.poppins(
                color: Colors.grey[600], fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _buildOptionTile(Icons.add_circle_outline, const Color(0xFFFFC0CB),
            "Create New Group", "Start your own community", _showCreateDialog),
        _buildOptionTile(Icons.qr_code, Colors.blueAccent, "Join by Code",
            "Have an invite code? Enter here.", _showJoinByIdDialog),
        _buildOptionTile(Icons.explore, Colors.orangeAccent, "Browse Discover",
            "See popular groups", () => _tabController.animateTo(1)),
      ],
    );
  }

  Widget _buildOptionTile(IconData icon, Color color, String title,
      String subtitle, VoidCallback onTap) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color)),
        title: Text(title,
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 12)),
        trailing:
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
        onTap: onTap,
      ),
    );
  }
}
