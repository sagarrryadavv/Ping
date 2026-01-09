import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // [New Import]
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

// [New: Top-level handler for background messages]
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling background message: ${message.messageId}");
  // You would typically handle displaying the notification here.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // [New: Set background handler]
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // [New: Setup foreground notification display on Android]
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: SplashScreen()),
  );
}

// [New: Function to handle permissions and save token]
void _setupFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request notification permissions
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    String? token = await messaging.getToken();
    User? user = FirebaseAuth.instance.currentUser;

    if (token != null && user != null) {
      // Save the token to the user's document for Cloud Functions to use
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    }
  }

  // Handle messages when app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // You can show a local snackbar or toast here if you want an in-app alert
    print('Got a message whilst in the foreground!');
  });
}
