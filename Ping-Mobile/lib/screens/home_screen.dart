import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart'; // Required for Clipboard
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'avatar_builder_screen.dart';
import 'find_group_screen.dart';
import 'settings_screen.dart';
import 'ping_room_screen.dart';
import '../services/notification_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController(viewportFraction: 0.93);

  // LOGIC: Use getter to ensure we always reference the current auth state
  User? get user => FirebaseAuth.instance.currentUser;

  Timer? _refreshTimer;
  StreamSubscription<DocumentSnapshot>? _muteListener;

  // STATE: Tracks if the user has globally muted notifications via Settings
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initializeLocalNotifications();
    _setupFCMListeners();
    _saveDeviceToken();

    // LOGIC: Listen to Firestore User Profile for "Mute" changes in real-time
    if (user != null) {
      _setupMuteListener(user!.uid);
    }

    // UI: Refresh every 30s to update "Time Left" displays without database reads
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _muteListener?.cancel();
    super.dispose();
  }

  // --- MUTE LISTENER (Connects Settings to Home) ---
  void _setupMuteListener(String uid) {
    _muteListener = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        // ACTION: Update local variable. If true, foreground notifications stop.
        setState(() {
          _isMuted = (snapshot.data() as Map)['muteAllNotifications'] ?? false;
        });
      }
    });
  }

  // --- NOTIFICATIONS ---
  void _initializeLocalNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _setupFCMListeners() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // LOGIC: The "Gatekeeper"
      // If user enabled "Pause All" in settings, we return immediately.
      // Note: This only stops FOREGROUND notifications. Background needs cloud function.
      if (_isMuted) return;

      String? body = message.notification?.body;
      String myName = user?.displayName?.split(' ')[0] ?? "User";

      // LOGIC: Don't notify me about my own actions
      if (body != null && body.startsWith(myName)) {
        return;
      }

      if (message.notification != null) {
        _showLocalNotification(
          message.notification!.title ?? "Ping",
          message.notification!.body ?? "New activity",
        );
      }
    });
  }

  Future<void> _saveDeviceToken() async {
    if (user == null) return;
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails('pings_channel', 'Pings',
            importance: Importance.max, priority: Priority.high);
    await flutterLocalNotificationsPlugin.show(
        0, title, body, const NotificationDetails(android: androidDetails));
  }

  // --- MAIN PING LOGIC ---

  void _handlePingTap(DocumentSnapshot pingDoc, String groupId) {
    Map<String, dynamic> data = pingDoc.data() as Map<String, dynamic>;
    List activeMembers = data['activeMembers'] ?? [];

    Timestamp? expiresAt = data['expiresAt'];
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This Ping has expired.")));
      return;
    }

    // ⚠️ STRICT RE-ENTRY FIX
    // We strictly check if the 'activeMembers' array contains my UID.
    // If I was kicked or left, I am NOT in this list, so I must "Knock" again.
    if (activeMembers.contains(user?.uid)) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => PingRoomScreen(
                  pingId: pingDoc.id,
                  groupId: groupId,
                  pingName: data['name'])));
    } else {
      _showJoinRequestDialog(context, data['name'], pingDoc.id, groupId);
    }
  }

  void _showJoinRequestDialog(
      BuildContext context, String pingName, String pingId, String groupId) {
    String myId = user?.uid ?? "";
    String myName = user?.displayName ?? "User";

    // ⚠️ BUG 2 FIX: System Message
    // We send a message with 'type: system' so it shows centered in chat.
    // We use 'senderId: myId' to pass Firestore Security Rules (sender must be auth user).
    FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('pings')
        .doc(pingId)
        .collection('messages')
        .add({
      "text": "Knock knock! $myName wants to join.",
      "type": "system",
      "senderId": myId,
      "senderName": "System",
      "timestamp": FieldValue.serverTimestamp(),
    });

    // Create the Request Document
    FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('pings')
        .doc(pingId)
        .collection('requests')
        .doc(myId)
        .set({
      "name": myName,
      "uid": myId,
      "status": "pending",
      "timestamp": FieldValue.serverTimestamp(),
      "votes": {}
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _JoinRequestPopup(
          pingName: pingName, pingId: pingId, groupId: groupId, myId: myId),
    ).then((result) {
      if (result == 'approved') {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => PingRoomScreen(
                    pingId: pingId, groupId: groupId, pingName: pingName)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Request Denied or Timed Out."),
            backgroundColor: Colors.red));
      }
    });
  }

  void _confirmLeaveGroup(String groupId, String groupName) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: const Text("Leave Group?",
                  style: TextStyle(color: Colors.white)),
              content: Text("Are you sure you want to leave '$groupName'?",
                  style: const TextStyle(color: Colors.grey)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('groups')
                        .doc(groupId)
                        .update({
                      "members": FieldValue.arrayRemove([user?.uid])
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Leave",
                      style: TextStyle(color: Colors.white)),
                )
              ],
            ));
  }

  // --- BUG 14 FIX: Navigation Safety ---
  // Prevents accidental app closure on Android
  Future<bool> _showExitConfirmDialog() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            title:
                const Text("Exit App?", style: TextStyle(color: Colors.white)),
            content: const Text("Do you want to close the app?",
                style: TextStyle(color: Colors.grey)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("No")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Yes")),
            ],
          ),
        ) ??
        false;
  }

  void _startPing(String groupId) {
    TextEditingController pingNameController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: Text("Start a Ping",
                  style: GoogleFonts.poppins(color: Colors.white)),
              content: TextField(
                controller: pingNameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Topic (e.g., Late Night Chat)",
                  hintStyle: TextStyle(color: Colors.grey[500]),
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
                      if (pingNameController.text.isNotEmpty) {
                        final navigator = Navigator.of(context);
                        navigator.pop();

                        String pingName = pingNameController.text.trim();

                        DocumentReference pingRef = await FirebaseFirestore
                            .instance
                            .collection('groups')
                            .doc(groupId)
                            .collection('pings')
                            .add({
                          "name": pingName,
                          "createdBy": user?.uid,
                          "creatorName": user?.displayName ?? "Unknown",
                          "createdAt": FieldValue.serverTimestamp(),
                          "expiresAt":
                              DateTime.now().add(const Duration(minutes: 10)),
                          "activeMembers": [user?.uid],
                          "isPublic": true,
                        });

                        FirebaseFirestore.instance
                            .collection('groups')
                            .doc(groupId)
                            .update(
                                {"lastPingAt": FieldValue.serverTimestamp()});

                        NotificationService.sendGroupNotification(
                            groupId, pingName);

                        navigator.push(MaterialPageRoute(
                            builder: (context) => PingRoomScreen(
                                pingId: pingRef.id,
                                groupId: groupId,
                                pingName: pingName)));
                      }
                    },
                    child: const Text("Start Now"))
              ],
            ));
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return false;
        }
        return await _showExitConfirmDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildHomeDashboard(),
              FindGroupScreen(
                  onGroupAdded: (val) => setState(() => _selectedIndex = 0)),
              _buildActivityFeed(),
              const SettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildHomeDashboard() {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildHeader(),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text("Hi ${user?.displayName?.split(' ')[0] ?? 'User'}",
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('groups')
                .where('members', arrayContains: user?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Center(
                    child: Text("Error loading groups",
                        style: TextStyle(color: Colors.red)));
              if (!snapshot.hasData)
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFC0CB)));

              var groups = snapshot.data!.docs;

              // Logic: Sort groups by most recent activity
              groups.sort((a, b) {
                Timestamp? tA = (a.data() as Map)['lastPingAt'];
                Timestamp? tB = (b.data() as Map)['lastPingAt'];
                if (tA == null) return 1;
                if (tB == null) return -1;
                return tB.compareTo(tA);
              });

              if (groups.isEmpty) {
                return Center(
                    child: TextButton(
                        onPressed: () => setState(() => _selectedIndex = 1),
                        child: const Text("No groups. Tap to search.",
                            style: TextStyle(color: Colors.grey))));
              }

              return PageView.builder(
                controller: _pageController,
                itemCount: groups.length,
                itemBuilder: (context, index) =>
                    _buildSuperGroupCard(groups[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuperGroupCard(DocumentSnapshot groupDoc) {
    Map<String, dynamic> groupData = groupDoc.data() as Map<String, dynamic>;
    // ⚠️ VISUAL FIX: Use 'inviteCode' field instead of Document ID
    String inviteCode = groupData['inviteCode'] ?? "N/A";

    return Padding(
      padding: const EdgeInsets.only(right: 15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(35)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(groupData['name'] ?? "Group",
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.exit_to_app,
                          color: Colors.redAccent),
                      onPressed: () => _confirmLeaveGroup(
                          groupDoc.id, groupData['name'] ?? "Group"),
                    ),
                  ],
                ),

                // ⚠️ UI FEATURE: Clickable "Copy Invite Code" chip
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Invite Code Copied!")));
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy, size: 12, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text("Invite Code: $inviteCode",
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 10)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25))),
                  onPressed: () => _startPing(groupDoc.id),
                  icon: const Icon(Icons.add, size: 20),
                  label: Text("Start Ping",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 10),
            child: Text("Active Pings",
                style: GoogleFonts.poppins(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(groupDoc.id)
                  .collection('pings')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                var pings = snapshot.data!.docs;

                var visiblePings = pings.where((doc) {
                  Map data = doc.data() as Map;
                  Timestamp? expires = data['expiresAt'];
                  bool isExpired = expires != null &&
                      expires.toDate().isBefore(DateTime.now());

                  bool isPublic = data['isPublic'] ?? true;
                  List activeMembers = data['activeMembers'] ?? [];
                  bool amIMember = activeMembers.contains(user?.uid);

                  return !isExpired && (isPublic || amIMember);
                }).toList();

                if (visiblePings.isEmpty)
                  return const Center(
                      child: Text("No active pings",
                          style: TextStyle(color: Colors.grey)));

                return ListView.builder(
                  itemCount: visiblePings.length,
                  itemBuilder: (context, i) {
                    var ping = visiblePings[i];
                    var data = ping.data() as Map<String, dynamic>;
                    List activeMembers = data['activeMembers'] ?? [];
                    bool isPublic = data['isPublic'] ?? true;

                    return GestureDetector(
                      onTap: () => _handlePingTap(ping, groupDoc.id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            // ⚠️ BUG 9 FIX: Horizontal Member List instead of Creator Name
                            SizedBox(
                              width: 80,
                              height: 40,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: activeMembers.length,
                                itemBuilder: (c, idx) => Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: UserAvatar(
                                      uid: activeMembers[idx], radius: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (!isPublic)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 5),
                                          child: Icon(Icons.lock,
                                              size: 14, color: Colors.grey),
                                        ),
                                      Text(data['name'],
                                          style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  Text("${activeMembers.length} joined",
                                      style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            PingTimerWidget(
                                expiresAt: data['expiresAt'],
                                onExpired: () => setState(() {})),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text("Live Activity",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('pings')
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFC0CB)));

              var allPings = snapshot.data!.docs;

              var activePings = allPings.where((doc) {
                Timestamp? expires = doc['expiresAt'];
                return expires != null &&
                    expires.toDate().isAfter(DateTime.now());
              }).toList();

              if (activePings.isEmpty)
                return const Center(
                    child: Text("No recent activity",
                        style: TextStyle(color: Colors.grey)));

              return ListView.builder(
                itemCount: activePings.length,
                itemBuilder: (context, index) {
                  var data = activePings[index].data() as Map<String, dynamic>;
                  var groupRef = activePings[index].reference.parent.parent;
                  String creatorId = data['createdBy'] ?? "";

                  return FutureBuilder<DocumentSnapshot>(
                    future: groupRef?.get(),
                    builder: (context, groupSnap) {
                      if (!groupSnap.hasData || !groupSnap.data!.exists)
                        return const SizedBox();
                      Map groupData = groupSnap.data!.data() as Map;
                      List members = groupData['members'] ?? [];
                      if (!members.contains(user?.uid)) return const SizedBox();

                      return ListTile(
                        leading: UserAvatar(uid: creatorId, radius: 20),
                        title: Text("${data['creatorName']} started a ping",
                            style: GoogleFonts.poppins(color: Colors.white)),
                        subtitle: Text("${data['name']} • ${groupData['name']}",
                            style: const TextStyle(color: Colors.grey)),
                        trailing: PingTimerWidget(
                            expiresAt: data['expiresAt'], onExpired: () {}),
                        onTap: () =>
                            _handlePingTap(activePings[index], groupRef!.id),
                      );
                    },
                  );
                },
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        children: [
          // ⚠️ BUG 3 FIX: Pass existing 'avatarConfig' to Builder
          GestureDetector(
            onTap: () async {
              // 1. Fetch current config from Firestore
              var doc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user!.uid)
                  .get();
              Map<String, dynamic>? savedConfig;
              if (doc.exists && doc.data()!.containsKey('avatarConfig')) {
                savedConfig = doc.data()!['avatarConfig'];
              }

              // 2. Open Builder with Pre-loaded Config
              if (mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            AvatarBuilderScreen(currentConfig: savedConfig)));
              }
            },
            child: UserAvatar(uid: user?.uid ?? "", radius: 26),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = 1),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(30)),
                child: Row(children: [
                  Text("Search groups...",
                      style: GoogleFonts.poppins(
                          color: Colors.grey[500], fontSize: 16)),
                  const Spacer(),
                  Icon(Icons.search, color: Colors.grey[500])
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(40)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_rounded, 0),
            _navItem(Icons.search, 1),
            _navItem(Icons.notifications_none_rounded, 2),
            _navItem(Icons.settings_outlined, 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(_selectedIndex == index ? 12 : 8),
        decoration: BoxDecoration(
            color: _selectedIndex == index
                ? const Color(0xFFFFC0CB)
                : Colors.transparent,
            shape: BoxShape.circle),
        child: Icon(icon,
            color: _selectedIndex == index ? Colors.black : Colors.grey),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  const UserAvatar({super.key, required this.uid, required this.radius});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        Widget avatar = CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey[800],
            child: Icon(Icons.person, color: Colors.white, size: radius));
        if (snapshot.hasData && snapshot.data!.exists) {
          Map data = snapshot.data!.data() as Map;
          if (data.containsKey('avatarData') && data['avatarData'] != null) {
            avatar = Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF3D2B5),
                border: Border.all(color: Colors.white24, width: 1),
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
            avatar = CircleAvatar(
                radius: radius,
                backgroundImage: NetworkImage(data['avatarUrl']));
          }
        }
        return avatar;
      },
    );
  }
}

class PingTimerWidget extends StatefulWidget {
  final Timestamp? expiresAt;
  final VoidCallback onExpired;
  const PingTimerWidget(
      {super.key, required this.expiresAt, required this.onExpired});
  @override
  State<PingTimerWidget> createState() => _PingTimerWidgetState();
}

class _PingTimerWidgetState extends State<PingTimerWidget> {
  late Timer _timer;
  String _timeStr = "";
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _updateTime());
    _updateTime();
  }

  void _updateTime() {
    if (widget.expiresAt == null) return;
    Duration diff = widget.expiresAt!.toDate().difference(DateTime.now());
    if (diff.isNegative) {
      if (mounted) setState(() => _timeStr = "Ended");
      widget.onExpired();
      _timer.cancel();
    } else {
      if (mounted)
        setState(() => _timeStr =
            "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}");
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_timeStr,
        style: GoogleFonts.robotoMono(
            color: const Color(0xFFFFC0CB),
            fontSize: 12,
            fontWeight: FontWeight.bold));
  }
}

class _JoinRequestPopup extends StatefulWidget {
  final String pingName, pingId, groupId, myId;
  const _JoinRequestPopup(
      {required this.pingName,
      required this.pingId,
      required this.groupId,
      required this.myId});
  @override
  State<_JoinRequestPopup> createState() => _JoinRequestPopupState();
}

class _JoinRequestPopupState extends State<_JoinRequestPopup> {
  late StreamSubscription sub;
  int timeLeft = 15;

  @override
  void initState() {
    super.initState();
    sub = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .collection('requests')
        .doc(widget.myId)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        String status = snap.data()?['status'] ?? "pending";
        if (status == 'approved') {
          if (mounted) Navigator.pop(context, 'approved');
        } else if (status == 'rejected') {
          if (mounted) Navigator.pop(context, 'rejected');
        }
      }
    });
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() => timeLeft--);
    if (timeLeft > 0)
      Future.delayed(const Duration(seconds: 1), _tick);
    else {
      // Timeout Logic
      FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('pings')
          .doc(widget.pingId)
          .collection('requests')
          .doc(widget.myId)
          .update({"status": "timeout"});
      Navigator.pop(context, 'timeout');
    }
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(
            value: timeLeft / 15, color: const Color(0xFFFFC0CB)),
        const SizedBox(height: 20),
        Text("Waiting for approval...",
            style: GoogleFonts.poppins(color: Colors.white)),
        Text("$timeLeft s", style: const TextStyle(color: Colors.grey))
      ]),
    );
  }
}
