import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'signup_page.dart'; // Import the SignupPage here
import 'package:introduction_screen/introduction_screen.dart';
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for Firebase
  await Firebase.initializeApp(); // Just this one line for basic connection
  runApp(const SnapEventApp());
}

final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void initializeNotifications() async {
  // Request permission
  await _firebaseMessaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Initialize local notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: DarwinInitializationSettings(),
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    showNotification(message);
  });

  // Handle when app is opened from notification
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationTap(message);
  });
}

void showNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'photo_uploads',
    'Photo Upload Notifications',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: DarwinNotificationDetails(),
  );

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title,
    message.notification?.body,
    platformChannelSpecifics,
  );
}

void _handleNotificationTap(RemoteMessage message) {
  final eventId = message.data['eventId'];
  if (eventId != null) {
    // Navigate to event gallery
    Navigator.of(context as BuildContext).pushNamed(
      '/gallery',
      arguments: {'eventId': eventId},
    );
  }
}

class SnapEventApp extends StatelessWidget {
  const SnapEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const OnboardingScreen(),
      theme: ThemeData(
        fontFamily: 'Mulish',
        scaffoldBackgroundColor: Colors.white,
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: "Welcome to SnapEvent",
          body: "Manage and retrieve event photos with ease.",
          image: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: const Alignment(0.0, 8.5),
              child: Image.asset('assets/welcome.png', fit: BoxFit.cover),
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(13, 71, 187, 1),
            ),
            titlePadding: EdgeInsets.only(top: 150, bottom: 20.0),
            bodyTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: Color.fromRGBO(102, 102, 102, 1),
            ),
          ),
        ),
        PageViewModel(
          title: "Core Features",
          body:
              "Enjoy AI-powered photo tagging, QR-based navigation, and secure photo access.",
          image: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: const Alignment(0.0, 8.5),
              child: Image.asset('assets/features.png', fit: BoxFit.cover),
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(13, 71, 187, 1),
            ),
            titlePadding: EdgeInsets.only(top: 150, bottom: 20.0),
            bodyTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: Color.fromRGBO(102, 102, 102, 1),
            ),
          ),
        ),
        PageViewModel(
          title: "Get Started",
          body: "Sign up now and make your event memories unforgettable!",
          image: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: const Alignment(0.0, 9.0),
              child: Image.asset('assets/get_started.png', fit: BoxFit.cover),
            ),
          ),
          decoration: const PageDecoration(
            titleTextStyle: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(13, 71, 187, 1),
            ),
            titlePadding: EdgeInsets.only(top: 150, bottom: 20.0),
            bodyTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: Color.fromRGBO(102, 102, 102, 1),
            ),
          ),
        ),
      ],
      onDone: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SignupPage()),
        );
      },
      onSkip: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SignupPage()),
        );
      },
      showSkipButton: true,
      skip: const Text(
        "Skip",
        style: TextStyle(
            fontWeight: FontWeight.bold, color: Color.fromRGBO(13, 71, 187, 1)),
      ),
      next: const Icon(Icons.arrow_forward,
          color: Color.fromRGBO(13, 71, 187, 1)),
      done: const Text("Start",
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(13, 71, 187, 1))),
    );
  }
}
