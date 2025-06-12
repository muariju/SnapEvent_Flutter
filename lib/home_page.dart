import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_event_page.dart';
import 'gallery_page.dart';
import 'profile_page.dart';
import 'fetch_event_page.dart'; // Add this import

void main() {
  runApp(SnapEventApp());
}

// ignore: use_key_in_widget_constructors
class SnapEventApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Mulish',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, String>> events = []; // Store both name and ID
  final TextEditingController _eventLinkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _saveFCMToken();
  }

Future<void> _saveFCMToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Get current token
  String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await _firestore.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    await _firestore.collection('users').doc(user.uid).update({
      'fcmToken': newToken,
    });
  });
}
  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Clear the previous events list to avoid duplication
      setState(() {
        events.clear();
      });

      // Fetch events where the organizerId matches the current user's UID
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('organizerId', isEqualTo: user.uid)
          .get();

      // Map the fetched documents into a list and update the state
      setState(() {
        events = snapshot.docs
            .map((doc) => {
                  'name': doc['name'] as String,
                  'id': doc.id,
                })
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading events: $e');

      // Optionally, show an error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load events')),
      );
    }
  }

  // ignore: unused_element
  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('events', events.map((e) => e['name']!).toList());
  }

  Future<void> _addEvent(String eventName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Convert event name to a valid document ID format
    final docId = eventName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .substring(0, min(20, eventName.length));

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(docId) // Set custom document ID
          .set({
        'name': eventName,
        'organizerId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _loadEvents();
    } catch (e) {
      debugPrint('Error creating event: $e');
    }
  }

  Future<void> _deleteEvent(int index) async {
    try {
      final eventId = events[index]['id'];

      // Delete the event from Firestore
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .delete();

      // Reload events after deletion (make sure this method is async and properly updates the state)
      await _loadEvents();

      // Optionally, show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event deleted successfully')),
      );
    } catch (e) {
      debugPrint('Error deleting event: $e');

      // Optionally, show an error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete event')),
      );
    }
  }

  // Update the QR scanning part in home_page.dart
  void _openQRScanner() async {
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => QRViewOverlay(
            onScanned: (result) => Navigator.pop(context, result),
          ),
        ),
      );

      if (result == null || result.isEmpty) {
        throw 'No QR code data found';
      }

      debugPrint('Raw QR Scanned Data: "$result"'); // Debug print

      // Improved validation
      if (!result.contains(':')) {
        throw 'Invalid QR format. Expected "eventId:searchKey"';
      }

      final parts = result.split(':');
      if (parts.length != 2) {
        throw 'QR code must contain exactly one colon (:)';
      }

      final eventId = parts[0].trim();
      final searchKey = parts[1].trim();

      if (eventId.isEmpty) {
        throw 'Missing event ID in QR code';
      }

      if (searchKey.isEmpty) {
        throw 'Missing search key in QR code';
      }

      debugPrint(
          'Parsed QR Data - EventID: "$eventId", SearchKey: "$searchKey"');

      // Navigate to event page
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FetchEventPage(
            eventId: eventId,
            searchKey: searchKey,
          ),
        ),
      );
    } catch (e) {
      debugPrint('QR Scan Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR Error: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'DEBUG',
              onPressed: () {
                debugPrint('--- QR SCAN DEBUG INFO ---');
                debugPrint('Error: $e');
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentDate = DateTime.now();
    final currentDay = DateFormat('d').format(currentDate);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section (unchanged)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 30),
                      const Text(
                        'Hi, Dear',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "What's up for today?",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 30, right: 5),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfilePage()),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/profile.png',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 45,
                              height: 45,
                              color: Colors.grey[300],
                              child: const Icon(Icons.person,
                                  color: Colors.grey, size: 30),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Event Link Input (unchanged)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _eventLinkController,
                decoration: InputDecoration(
                  hintText: "Enter event link",
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.link, color: Colors.blue),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.blue),
                    onPressed: _openQRScanner,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Calendar Section (unchanged)
            Container(
              height: MediaQuery.of(context).size.height * 0.15,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                itemBuilder: (context, index) {
                  final date = currentDate.add(Duration(days: index));
                  final dayNumber = DateFormat('d').format(date);
                  final weekDay = DateFormat('E').format(date);

                  return Container(
                    margin: const EdgeInsets.only(right: 15),
                    width: 60,
                    decoration: BoxDecoration(
                      color: dayNumber == currentDay
                          ? Colors.blue
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekDay,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: dayNumber == currentDay
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dayNumber,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: dayNumber == currentDay
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Event List Section (only changed the event access)
            Container(
              padding: const EdgeInsets.all(20),
              child: events.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 70),
                      child: Text(
                        "No events available. Just click on + button to create a new one.",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GalleryPage(
                                  eventId: events[index]['id']!,
                                  eventName: events[index]['name']!,
                                ),
                              ),
                            );
                          },
                          onLongPress: () {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Delete Event"),
                                content: const Text(
                                    "Are you sure you want to delete this event?"),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _deleteEvent(index);
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text("Delete"),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(25),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 239, 248, 255),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${index + 1}. ${events[index]['name']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const Icon(Icons.arrow_forward,
                                    color: Colors.blue),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Floating Button (unchanged)
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20.0, right: 20.0),
        child: FloatingActionButton(
          onPressed: () async {
            final newEvent = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEventPage()),
            );

            if (newEvent != null) {
              _loadEvents(); // Just reload, no need to create again
            }
          },
          backgroundColor: Colors.blue,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}

// QR SCANNER OVERLAY (unchanged)
class QRViewOverlay extends StatefulWidget {
  final Function(String) onScanned;

  const QRViewOverlay({super.key, required this.onScanned});

  @override
  State<QRViewOverlay> createState() => _QRViewOverlayState();
}

class _QRViewOverlayState extends State<QRViewOverlay> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  void dispose() {
    // ignore: deprecated_member_use
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        QRView(
          key: qrKey,
          onQRViewCreated: _onQRViewCreated,
          overlay: QrScannerOverlayShape(
            borderColor: Colors.blue,
            borderRadius: 10,
            borderLength: 20,
            borderWidth: 6,
            cutOutSize: 220,
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        )
      ],
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      controller.pauseCamera();
      widget.onScanned(scanData.code ?? '');
    });
  }
}
