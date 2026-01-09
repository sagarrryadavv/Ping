import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';

class PingRoomScreen extends StatefulWidget {
  final String pingId;
  final String groupId;
  final String pingName;

  const PingRoomScreen(
      {super.key,
      required this.pingId,
      required this.groupId,
      required this.pingName});

  @override
  State<PingRoomScreen> createState() => _PingRoomScreenState();
}

class _PingRoomScreenState extends State<PingRoomScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _finalWordsController = TextEditingController();
  final TextEditingController _leaveMsgController = TextEditingController();

  final User? user = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _blinkController;

  Timer? _uiTicker;

  String _timeLeftStr = "10:00";

  // ⚠️ CRASH FIX: Safety Flag
  bool _isClosing = false;

  bool _isVotePopupOpen = false;

  // Checkpoint State
  bool _showCheckInOverlay = false;
  int _checkInSecondsDisplay = 60;
  Timestamp? _lastProcessedExpiry;

  @override
  void initState() {
    super.initState();
    _addMyAvatarToPing();

    // Universal Ticker
    _uiTicker = Timer.periodic(
        const Duration(seconds: 1), (t) => _syncWithServerTime());

    _blinkController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _blinkController.repeat(reverse: true);

    _listenForVotes();
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _msgController.dispose();
    _finalWordsController.dispose();
    _leaveMsgController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  // --- 1. SERVER-SIDE TIME SYNC ---

  void _syncWithServerTime() async {
    if (_isClosing) return;

    DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .get();

    if (!snap.exists) return;

    Timestamp? expiresAt = snap['expiresAt'];
    if (expiresAt == null) return;

    DateTime expiryDate = expiresAt.toDate();
    DateTime now = DateTime.now();
    Duration diff = expiryDate.difference(now);

    if (mounted) {
      setState(() {
        if (diff.isNegative) {
          _timeLeftStr = "00:00";
        } else {
          _timeLeftStr =
              "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
        }
      });
    }

    // CHECKPOINT LOGIC
    if (diff.inSeconds <= 0) {
      int secondsOverdue = now.difference(expiryDate).inSeconds;
      int kickCountdown = 60 - secondsOverdue;

      if (kickCountdown <= 0) {
        if (_showCheckInOverlay) {
          _sendMessage(
              specialText: "${user?.displayName} timed out (idle)",
              type: "system");
          _processExit();
        }
      } else {
        if (!_showCheckInOverlay) {
          if (mounted) setState(() => _showCheckInOverlay = true);
        }
        if (mounted) setState(() => _checkInSecondsDisplay = kickCountdown);
      }

      // Auto-Extend Server
      if (_lastProcessedExpiry != expiresAt) {
        _lastProcessedExpiry = expiresAt;
        DateTime newExpiry = expiryDate.add(const Duration(minutes: 10));
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('pings')
            .doc(widget.pingId)
            .update({"expiresAt": newExpiry});
      }
    } else {
      if (_showCheckInOverlay) {
        if (mounted) setState(() => _showCheckInOverlay = false);
      }
    }
  }

  void _handleCheckInAction(bool stay) {
    if (stay) {
      setState(() => _showCheckInOverlay = false);
    } else {
      if (_finalWordsController.text.isNotEmpty) {
        _sendMessage(
            specialText: "${user?.displayName}: ${_finalWordsController.text}",
            type: "text");
      }
      _sendMessage(
          specialText: "${user?.displayName} left at checkpoint",
          type: "system");
      _processExit();
    }
  }

  // --- 2. VOTE LISTENER (Crash Safe) ---

  void _listenForVotes() {
    FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .snapshots()
        .listen((snap) {
      // ⚠️ BUG 6 FIX: If manual exit started, ignore this stream update
      if (_isClosing) return;

      if (!snap.exists) {
        if (mounted) {
          // Server deleted the ping -> Close screen
          _isClosing = true;
          Navigator.of(context).pop();
        }
        return;
      }
      var data = snap.data() as Map<String, dynamic>;

      if (data.containsKey('currentVote') && data['currentVote'] != null) {
        Map voteData = data['currentVote'];
        Timestamp? createdAt = voteData['voteCreatedAt'];

        // Timeout
        if (createdAt != null &&
            DateTime.now().difference(createdAt.toDate()).inSeconds > 15) {
          FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('pings')
              .doc(widget.pingId)
              .update({"currentVote": null});

          if (_isVotePopupOpen && mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            _isVotePopupOpen = false;
          }
          return;
        }

        // Instant Fail
        Map votes = voteData['votes'] ?? {};
        int noVotes = votes.values.where((v) => v == false).length;
        if (noVotes > 0) {
          FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('pings')
              .doc(widget.pingId)
              .update({"currentVote": null});
          return;
        }

        if (!_isVotePopupOpen) _showPrivacyVoteDialog(voteData);
      } else {
        if (_isVotePopupOpen && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _isVotePopupOpen = false;
        }
      }
    });
  }

  // --- 3. ACTIONS ---

  Future<void> _addMyAvatarToPing() async {
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .update({
      "activeMembers": FieldValue.arrayUnion([user?.uid])
    });
    _sendMessage(
        specialText: "${user?.displayName?.split(' ')[0]} joined",
        type: "system");
  }

  Future<void> _sendMessage({String? specialText, String type = "text"}) async {
    String text = specialText ?? _msgController.text.trim();
    if (text.isEmpty) return;
    if (specialText == null) _msgController.clear();

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .collection('messages')
        .add({
      "text": text,
      "senderId": user?.uid,
      "senderName": user?.displayName?.split(' ')[0] ?? "User",
      "timestamp": FieldValue.serverTimestamp(),
      "type": type,
    });
    if (_scrollController.hasClients)
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _attemptLeave() {
    _leaveMsgController.clear();
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25)),
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("Leaving?",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _leaveMsgController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                        hintText: "Final words (optional)...",
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15))),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))),
                        onPressed: () async {
                          Navigator.pop(context);
                          if (_leaveMsgController.text.isNotEmpty) {
                            await _sendMessage(
                                specialText:
                                    "${user?.displayName}: ${_leaveMsgController.text}",
                                type: "text");
                          }
                          await _sendMessage(
                              specialText:
                                  "${user?.displayName?.split(' ')[0]} left",
                              type: "system");
                          _processExit();
                        },
                        child: const Text("Leave Ping",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel",
                          style: TextStyle(color: Colors.grey)))
                ]),
              ),
            ));
  }

  // ⚠️ BUG 6 FIX: Controlled Exit
  Future<void> _processExit() async {
    // Set flag immediately so stream listener ignores the deletion
    setState(() => _isClosing = true);

    DocumentReference pingRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(pingRef);
      if (!snapshot.exists) return;
      List members = List.from(snapshot['activeMembers']);

      if (members.length <= 2) {
        transaction.delete(pingRef);
      } else {
        members.remove(user?.uid);
        transaction.update(pingRef, {"activeMembers": members});
      }
    });

    if (mounted) Navigator.pop(context);
  }

  // --- 4. UI COMPONENTS ---

  void _showRequestsDialog(List<QueryDocumentSnapshot> requests) {
    showDialog(
      context: context,
      builder: (context) {
        var validRequests = requests.where((req) {
          Timestamp? ts = (req.data() as Map)['timestamp'];
          if (ts == null) return false;
          return DateTime.now().difference(ts.toDate()).inSeconds <= 15;
        }).toList();

        return Dialog(
          backgroundColor: const Color(0xFF2C2C2C),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Join Requests",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              if (validRequests.isEmpty)
                const Text("No active requests.",
                    style: TextStyle(color: Colors.grey)),
              ...validRequests.map((reqDoc) {
                var req = reqDoc.data() as Map<String, dynamic>;
                return _RequestItem(
                    name: req['name'],
                    reqId: reqDoc.id,
                    onVote: (vote) =>
                        _voteOnRequest(reqDoc.id, vote, req['name']));
              }).toList(),
              const SizedBox(height: 15),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child:
                      const Text("Close", style: TextStyle(color: Colors.grey)))
            ]),
          ),
        );
      },
    );
  }

  void _voteOnRequest(String reqId, bool vote, String name) async {
    DocumentReference reqRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .collection('requests')
        .doc(reqId);

    if (vote) {
      await reqRef.set({
        "votes": {user!.uid: true}
      }, SetOptions(merge: true));
      _sendMessage(
          specialText: "${user?.displayName} accepted $name", type: "system");

      DocumentSnapshot snap = await reqRef.get();
      Map votes = (snap.data() as Map)['votes'] ?? {};
      DocumentSnapshot pingSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('pings')
          .doc(widget.pingId)
          .get();
      List members = (pingSnap.data() as Map)['activeMembers'] ?? [];

      if (votes.length >= members.length) {
        int rejectCount = votes.values.where((v) => v == false).length;
        if (rejectCount == 0) {
          String newUid = (snap.data() as Map)['uid'];
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('pings')
              .doc(widget.pingId)
              .update({
            "activeMembers": FieldValue.arrayUnion([newUid]),
          });
          reqRef.update({"status": "approved"});
          _sendMessage(specialText: "$name joined the chat!", type: "system");
          if (mounted) Navigator.pop(context);
        } else {
          reqRef.update({"status": "rejected"});
        }
      }
    } else {
      await reqRef.update({"status": "rejected"});
      _sendMessage(
          specialText: "${user?.displayName} rejected $name", type: "system");
    }
  }

  void _initiatePrivacyToggle(bool targetState) async {
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .update({
      "currentVote": {
        "type": "privacy",
        "targetState": targetState,
        "voteCreatedAt": FieldValue.serverTimestamp(),
        "votes": {user!.uid: true}
      }
    });
    String text = targetState ? "Public" : "Private";
    _sendMessage(specialText: "Vote: Switch to $text?", type: "system");
  }

  void _castPrivacyVote(bool vote, String targetText) async {
    if (vote == false) {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('pings')
          .doc(widget.pingId)
          .update({"currentVote": null});
      _sendMessage(
          specialText: "${user?.displayName} rejected switch to $targetText",
          type: "system");
      return;
    }

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .set({
      "currentVote": {
        "votes": {user!.uid: true}
      }
    }, SetOptions(merge: true));

    _sendMessage(
        specialText: "${user?.displayName} accepted switch to $targetText",
        type: "system");

    DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('pings')
        .doc(widget.pingId)
        .get();
    Map voteData = snap['currentVote'];
    Map votes = voteData['votes'] ?? {};
    List members = snap['activeMembers'] ?? [];
    bool targetState = voteData['targetState'];

    if (votes.length >= members.length) {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('pings')
          .doc(widget.pingId)
          .update({"isPublic": targetState, "currentVote": null});
      _sendMessage(
          specialText:
              "Privacy Updated to ${targetState ? 'Public' : 'Private'}",
          type: "system");
    }
  }

  void _showPrivacyVoteDialog(Map voteData) {
    _isVotePopupOpen = true;
    bool targetState = voteData['targetState'];
    String targetText = targetState ? "Public" : "Private";

    DateTime voteStartTime =
        (voteData['voteCreatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime voteEndTime = voteStartTime.add(const Duration(seconds: 15));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _PrivacyVotePopup(
          groupId: widget.groupId,
          pingId: widget.pingId,
          targetText: targetText,
          voteEndTime: voteEndTime,
          currentUid: user!.uid,
          onCastVote: (v, t) => _castPrivacyVote(v, t),
        );
      },
    ).then((_) => _isVotePopupOpen = false);
  }

  void _showProfileDialog(String uid) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                UserAvatar(uid: uid, radius: 40),
                const SizedBox(height: 10),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (c, s) => Text(s.data?['displayName'] ?? "User",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                )
              ]),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _attemptLeave();
        return false;
      },
      child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('pings')
              .doc(widget.pingId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Scaffold(
                  backgroundColor: Color(0xFF151515),
                  body: Center(child: CircularProgressIndicator()));
            if (!snapshot.data!.exists) return const SizedBox();

            var pingData = snapshot.data!.data() as Map<String, dynamic>;
            bool isPublic = pingData['isPublic'] ?? true;

            // ⚠️ THEME CHANGE: Subtle Navy for Private
            Color bgColor =
                isPublic ? const Color(0xFF151515) : const Color(0xFF0B0D12);
            Color barColor =
                isPublic ? const Color(0xFF1E1E1E) : const Color(0xFF13161F);

            return Scaffold(
              backgroundColor: bgColor,
              appBar: AppBar(
                backgroundColor: barColor,
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _attemptLeave),
                title: Row(
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.pingName,
                                style: GoogleFonts.poppins(
                                    color: Colors.white, fontSize: 16)),
                            Text(_timeLeftStr,
                                style: GoogleFonts.robotoMono(
                                    color: const Color(0xFFFFC0CB),
                                    fontSize: 12)),
                          ]),
                    ),
                    Text("Current: ${isPublic ? 'Public' : 'Private'}",
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 12)),
                    Switch(
                        value: isPublic,
                        onChanged: (val) => _initiatePrivacyToggle(val),
                        activeColor: const Color(0xFFFFC0CB),
                        inactiveThumbColor: Colors.grey),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  Column(
                    children: [
                      _buildMemberList(pingData),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('groups')
                              .doc(widget.groupId)
                              .collection('pings')
                              .doc(widget.pingId)
                              .collection('messages')
                              .orderBy('timestamp', descending: true)
                              .snapshots(),
                          builder: (context, msgSnap) {
                            if (!msgSnap.hasData)
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFFFC0CB)));
                            var docs = msgSnap.data!.docs;
                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 20),
                              itemCount: docs.length,
                              itemBuilder: (context, index) =>
                                  _buildMessageBubble(docs[index].data()
                                      as Map<String, dynamic>),
                            );
                          },
                        ),
                      ),
                      _buildInputArea(),
                    ],
                  ),
                  if (_showCheckInOverlay)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.96),
                        child: Center(
                          child: Container(
                            width: 300,
                            padding: const EdgeInsets.all(25),
                            decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2C),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                    color: const Color(0xFFFFC0CB), width: 2)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_off,
                                    color: Colors.white, size: 40),
                                const SizedBox(height: 15),
                                Text("Checkpoint!",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                const Text(
                                    "10 minutes passed. Are you still here?",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 10),
                                Text("Auto-kick in $_checkInSecondsDisplay s",
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 20),
                                TextField(
                                  controller: _finalWordsController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                      hintText: "Final words (Optional)...",
                                      filled: true,
                                      fillColor: Colors.black26,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(15))),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFFFC0CB),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(15))),
                                    onPressed: () => _handleCheckInAction(true),
                                    child: const Text("Stay (+10m)"),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () => _handleCheckInAction(false),
                                  child: const Text("Leave Room",
                                      style:
                                          TextStyle(color: Colors.redAccent)),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
    );
  }

  Widget _buildMemberList(Map<String, dynamic> data) {
    List activeMembers = data['activeMembers'] ?? [];
    return Container(
      height: 60,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 15),
          StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('pings')
                  .doc(widget.pingId)
                  .collection('requests')
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, reqSnap) {
                int count = 0;
                if (reqSnap.hasData) {
                  count = reqSnap.data!.docs.where((req) {
                    Timestamp? ts = (req.data() as Map)['timestamp'];
                    return ts != null &&
                        DateTime.now().difference(ts.toDate()).inSeconds <= 15;
                  }).length;
                }

                return GestureDetector(
                  onTap: () => _showRequestsDialog(reqSnap.data?.docs ?? []),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.person_add,
                              color: Colors.grey, size: 20)),
                      if (count > 0)
                        Positioned(
                            right: -2,
                            top: -2,
                            child: FadeTransition(
                                opacity: _blinkController,
                                child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle),
                                    child: Text("$count",
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)))))
                    ],
                  ),
                );
              }),
          const SizedBox(width: 15),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: activeMembers.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _showProfileDialog(activeMembers[index]),
                  child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: UserAvatar(uid: activeMembers[index], radius: 18)),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    bool isMe = msg['senderId'] == user?.uid;
    String type = msg['type'] ?? 'text';
    if (type == 'system')
      return Center(
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(msg['text'],
                  style: GoogleFonts.poppins(
                      color: Colors.grey[500],
                      fontSize: 11,
                      fontStyle: FontStyle.italic))));

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isMe) ...[
          UserAvatar(uid: msg['senderId'] ?? "", radius: 16),
          const SizedBox(width: 8)
        ],
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.70),
          decoration: BoxDecoration(
              color: isMe ? const Color(0xFF3A3A3A) : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(15)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isMe)
              Text(msg['senderName'],
                  style: GoogleFonts.poppins(
                      color: const Color(0xFFFFC0CB), fontSize: 10)),
            Text(msg['text'],
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
          ]),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(
              child: Container(
                  height: 55,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(30)),
                  child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          hintText: "Type...", border: InputBorder.none)))),
          const SizedBox(width: 10),
          GestureDetector(
              onTap: () => _sendMessage(),
              child: Container(
                  height: 55,
                  width: 55,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFC0CB),
                      borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.arrow_upward, color: Colors.black)))
        ]));
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
                    border: Border.all(color: Colors.white24, width: 1)),
                child: ClipOval(
                    child: Transform.scale(
                        scale: 1.35,
                        alignment: Alignment.center,
                        child: SvgPicture.string(data['avatarData'],
                            fit: BoxFit.contain))));
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

class _RequestItem extends StatefulWidget {
  final String name, reqId;
  final Function(bool) onVote;
  const _RequestItem(
      {required this.name, required this.reqId, required this.onVote});
  @override
  State<_RequestItem> createState() => _RequestItemState();
}

class _RequestItemState extends State<_RequestItem> {
  int _state = 0;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(15)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(widget.name,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          if (_state == 0)
            Row(children: [
              IconButton(
                  icon:
                      const Icon(Icons.check_circle, color: Color(0xFFFFC0CB)),
                  onPressed: () {
                    setState(() => _state = 1);
                    widget.onVote(true);
                  }),
              IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  onPressed: () {
                    setState(() => _state = 2);
                    widget.onVote(false);
                  }),
            ])
          else if (_state == 1)
            const Text("Accepted",
                style:
                    TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          else
            const Text("Rejected",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold))
        ],
      ),
    );
  }
}

class _PrivacyVotePopup extends StatefulWidget {
  final String groupId, pingId, currentUid, targetText;
  final DateTime voteEndTime;
  final Function(bool, String) onCastVote;
  const _PrivacyVotePopup(
      {required this.groupId,
      required this.pingId,
      required this.targetText,
      required this.voteEndTime,
      required this.currentUid,
      required this.onCastVote});
  @override
  State<_PrivacyVotePopup> createState() => _PrivacyVotePopupState();
}

class _PrivacyVotePopupState extends State<_PrivacyVotePopup> {
  late Timer _timer;
  int _secondsLeft = 15;
  int _voteState = 0;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.voteEndTime.difference(DateTime.now()).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      int diff = widget.voteEndTime.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        _timer.cancel();
        if (mounted) Navigator.pop(context);
      } else if (mounted) setState(() => _secondsLeft = diff);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Vote: Switch to ${widget.targetText}?",
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 5),
            const Text("(All must agree to make changes)",
                style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 5),
            Text("Closing in $_secondsLeft s",
                style: const TextStyle(color: Color(0xFFFFC0CB))),
            const SizedBox(height: 20),
            if (_voteState == 0)
              Row(children: [
                Expanded(
                    child: TextButton(
                        onPressed: () {
                          setState(() => _voteState = 2);
                          widget.onCastVote(false, widget.targetText);
                        },
                        child: const Text("Reject",
                            style: TextStyle(color: Colors.redAccent)))),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC0CB),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        onPressed: () {
                          setState(() => _voteState = 1);
                          widget.onCastVote(true, widget.targetText);
                        },
                        child: const Text("Accept"))),
              ])
            else if (_voteState == 1)
              const Text("Accepted",
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold))
            else
              const Text("Rejected",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold))
          ]),
        ),
      ),
    );
  }
}
