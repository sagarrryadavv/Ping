import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  // ℹ️ SECURITY NOTE:
  // To run this locally, generate a new Service Account Key from:
  // Firebase Console -> Project Settings -> Service Accounts
  // Then replace the 'YOUR_...' placeholders below.
  // NEVER upload real keys to GitHub.

  static final Map<String, dynamic> _serviceAccount = {
    "type": "service_account",
    "project_id": "YOUR_PROJECT_ID", // ⚠️ Replace locally
    "private_key_id": "YOUR_PRIVATE_KEY_ID", // ⚠️ Replace locally
    "private_key":
        "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n", // ⚠️ Replace locally
    "client_email": "YOUR_CLIENT_EMAIL", // ⚠️ Replace locally
    "client_id": "YOUR_CLIENT_ID",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "YOUR_CERT_URL",
    "universe_domain": "googleapis.com"
  };

  static final List<String> _scopes = [
    "https://www.googleapis.com/auth/firebase.messaging"
  ];

  static Future<String?> getAccessToken() async {
    try {
      final accountCredentials =
          ServiceAccountCredentials.fromJson(_serviceAccount);
      final client = await clientViaServiceAccount(accountCredentials, _scopes);
      final credentials = await client.credentials;
      client.close();
      return credentials.accessToken.data;
    } catch (e) {
      print("Error generating Access Token: $e");
      return null;
    }
  }

  static Future<void> sendGroupNotification(
      String groupId, String pingName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot groupSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      if (!groupSnap.exists) return;

      List<dynamic> members = groupSnap.get('members') ?? [];

      List<String> targetUids = members
          .map((e) => e.toString())
          .where((uid) => uid != user.uid)
          .toList();

      if (targetUids.isEmpty) return;

      // Processing in batches of 10 for Firestore 'in' query limit
      List<String> batchUids = targetUids.take(10).toList();
      QuerySnapshot userTokensSnap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batchUids)
          .get();

      List<String> tokens = [];
      for (var doc in userTokensSnap.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('fcmToken') && data['fcmToken'] != null) {
          tokens.add(data['fcmToken']);
        }
      }

      if (tokens.isEmpty) {
        print("No tokens found. Cannot send.");
        return;
      }

      String? accessToken = await getAccessToken();
      if (accessToken == null) {
        print("Failed to get Access Token. Check key format.");
        return;
      }

      for (String token in tokens) {
        // You might need to update the project ID in this URL if it changes
        final response = await http.post(
          Uri.parse(
              'https://fcm.googleapis.com/v1/projects/ping-rooms/messages:send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            "message": {
              "token": token,
              "notification": {
                "title": "Ping: ${groupSnap.get('name')}",
                "body":
                    "${user.displayName?.split(' ')[0] ?? 'Someone'} started: $pingName"
              },
              "data": {
                "groupId": groupId,
                "click_action": "FLUTTER_NOTIFICATION_CLICK"
              }
            }
          }),
        );

        if (response.statusCode == 200) {
          print("Notification sent successfully");
        } else {
          print("Failed to send: ${response.body}");
        }
      }
    } catch (e) {
      print("Failed to send notification: $e");
    }
  }
}
