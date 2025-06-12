// ignore_for_file: unused_import, duplicate_ignore

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
// ignore: unused_import
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:snapevent/services/face_embedding_service.dart';
import 'package:snapevent/services/face_upload_service.dart';

class GalleryPage extends StatefulWidget {
  final String eventName;
  final String eventId;

  const GalleryPage({
    super.key,
    required this.eventName,
    required this.eventId,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<String> images = [];
  List<int> selectedIndexes = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;

  bool isRemoveMode = false;
  bool _isUploading = false;
  final GlobalKey _qrKey = GlobalKey();
  StreamSubscription<QuerySnapshot>? _imagesSubscription;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _setupRealTimeListener();
  }

  @override
  void dispose() {
    _imagesSubscription?.cancel();
    super.dispose();
  }

  void _setupRealTimeListener() {
    setState(() => _isLoading = true); // Add this line
    _imagesSubscription = _firestore
        .collection('events')
        .doc(widget.eventId)
        .collection('images')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          images = snapshot.docs
              .map((doc) => doc['url'] as String?)
              .where((url) => url != null && url.isNotEmpty)
              .cast<String>()
              .toList();
          _isLoading = false; // Add this line
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() => _isLoading = false); // Add this line
      }
      debugPrint('Error loading images: $error');
    });
  }

  Future<bool> _checkStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();

      if (status.isPermanentlyDenied) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'Please enable storage permission in app settings to save QR codes',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return false;
      }
      return status.isGranted;
    }
    return true;
  }

  Future<void> _pickImages() async {
    try {
      final permissionStatus = await Permission.photos.request();
      if (!permissionStatus.isGranted || !mounted) return;

      final pickedImages = await _picker.pickMultiImage();
      // ignore: unnecessary_null_comparison
      if (pickedImages == null || !mounted) return;

      setState(() => _isUploading = true);

      final tempImages = pickedImages.map((xfile) => xfile.path).toList();
      setState(() => images.insertAll(0, tempImages));

      for (var image in pickedImages) {
        try {
          await _uploadImage(File(image.path));
        } catch (e) {
          debugPrint('Upload error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Failed to upload image: ${e.toString()}')),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<String> _uploadImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to upload')),
        );
        return '';
      }

      // 1. Upload image with face embeddings
      final faceUploadService = FaceUploadService();
      final imageUrl = await faceUploadService.uploadImageWithFaceEmbeddings(
        imageFile: file,
        eventId: widget.eventId,
        context: context,
      );

      // 2. Only proceed if upload was successful
      if (imageUrl.isNotEmpty) {
        // 3. Send notifications to participants
        await _notifyParticipantsAboutNewPhoto(imageUrl);
      }

      return imageUrl;
    } catch (e) {
      debugPrint("Upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${e.toString()}')),
      );
      return '';
    }
  }

  Future<void> _notifyParticipantsAboutNewPhoto(String imageUrl) async {
    try {
      // 1. Get event details
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();
      final eventName = eventDoc['name'] ?? 'the event';

      // 2. Get all participants (excluding the uploader)
      final currentUser = FirebaseAuth.instance.currentUser;
      final participants = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .collection('participants')
          .where(FieldPath.documentId, isNotEqualTo: currentUser?.uid ?? '')
          .get();

      // 3. Extract valid FCM tokens
      final tokens = participants.docs
          .map((doc) => doc['fcmToken'] as String?)
          .where((token) => token != null && token.isNotEmpty)
          .cast<String>()
          .toList();

      if (tokens.isEmpty) return;

      // 4. Prepare notification payload
      final payload = {
        'registration_ids':
            tokens, // This is where tokens are properly included
        'notification': {
          'title': 'New Photo in $eventName',
          'body': 'Check out the newly uploaded photo!',
          'image': imageUrl,
        },
        'data': {
          'type': 'new_photo',
          'eventId': widget.eventId,
          'imageUrl': imageUrl,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'priority': 'high',
      };

      // 5. Send via HTTP
      await _sendFcmNotification(payload);
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  Future<void> _sendFcmNotification(Map<String, dynamic> payload) async {
    const serverKey = 'YOUR_FIREBASE_SERVER_KEY';
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'key=$serverKey',
    };

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint('Notification failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('HTTP error: $e');
    }
  }

  void _onImageLongPress(int index) {
    setState(() {
      isRemoveMode = true;
      selectedIndexes.add(index);
    });
  }

  void _toggleSelection(int index) {
    if (isRemoveMode) {
      setState(() {
        if (selectedIndexes.contains(index)) {
          selectedIndexes.remove(index);
        } else {
          selectedIndexes.add(index);
        }
      });
    } else {
      _showFullScreenImage(images[index]);
    }
  }

  void _deleteSelectedImages() async {
    if (selectedIndexes.isEmpty) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content:
            const Text('Are you sure you want to delete the selected images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      for (var index in selectedIndexes) {
        String imageUrl = images[index];
        await _deleteImageFromStorage(imageUrl);
        await _deleteImageFromFirestore(imageUrl);
      }
      selectedIndexes.clear();
      setState(() {
        isRemoveMode = false;
      });
    }
  }

  Future<void> _sendPhotoUploadNotification() async {
    try {
      // 1. Get all participants for this event
      final participants = await _firestore
          .collection('events')
          .doc(widget.eventId)
          .collection('participants')
          .get();

      // 2. Get their FCM tokens
      final tokens = participants.docs
          .map((doc) => doc['fcmToken'] as String?)
          .where((token) => token != null)
          .cast<String>()
          .toList();

      if (tokens.isEmpty) return;

      // 3. Send notifications via HTTP API
      await _sendNotificationViaHttp(tokens);
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  Future<void> _sendNotificationViaHttp(List<String> tokens) async {
    const serverKey =
        'YOUR_FIREBASE_SERVER_KEY'; // From Firebase Console -> Project Settings -> Cloud Messaging

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'key=$serverKey',
    };

    final body = {
      'registration_ids': tokens,
      'notification': {
        'title': 'New Photos Uploaded!',
        'body': 'Check out new photos in ${widget.eventName}',
        'sound': 'default',
      },
      'data': {
        'eventId': widget.eventId,
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'priority': 'high',
    };

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to send notification: ${response.body}');
      }
    } catch (e) {
      debugPrint('HTTP error: $e');
    }
  }

  Future<void> _deleteImageFromStorage(String imageUrl) async {
    try {
      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('Error deleting image from storage: $e');
    }
  }

  Future<void> _deleteImageFromFirestore(String imageUrl) async {
    final snapshot = await _firestore
        .collection('events')
        .doc(widget.eventId)
        .collection('images')
        .where('url', isEqualTo: imageUrl)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  void _showQRPopup() async {
    // Get the event document
    final eventDoc =
        await _firestore.collection('events').doc(widget.eventId).get();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Event QR Code',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: QrImageView(
                  data: '${widget.eventId}:${eventDoc['searchKey']}',
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  errorStateBuilder: (ctx, err) {
                    return Center(
                      child: Text(
                        'QR Error: ${err.toString()}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () async {
                    final hasPermission = await _checkStoragePermission();
                    if (hasPermission) {
                      Navigator.pop(context);
                      await _downloadQRCode();
                    }
                  },
                  child: const Text("Download"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadQRCode() async {
    try {
      // Check storage permission
      final hasPermission = await Permission.storage.request();
      if (!hasPermission.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied')),
        );
        return;
      }

      // Capture QR as an image
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      // Save to gallery with unique filename
      final time = DateTime.now().millisecondsSinceEpoch;
      final result = await ImageGallerySaverPlus.saveImage(
        byteData.buffer.asUint8List(),
        name: "Event_${widget.eventName}_$time",
        quality: 100,
      );

      if (result['isSuccess'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code saved to gallery!')),
        );
      } else {
        throw Exception('Failed to save QR code');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(30, 50, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.eventName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    IconButton(
                      onPressed: _showQRPopup,
                      icon: const Icon(Icons.qr_code,
                          size: 28, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: images.isEmpty
                      ? Center(
                          child: Text(
                            "No photos added yet. Use the + button to add.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        )
                      : GridView.builder(
                          itemCount: images.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, index) {
                            final imageUrl = images[index];
                            return GestureDetector(
                              onLongPress: () => _onImageLongPress(index),
                              onTap: () => _toggleSelection(index),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: imageUrl.startsWith('/')
                                          ? Image.file(File(imageUrl),
                                              fit: BoxFit.cover)
                                          : CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                color: Colors.grey[200],
                                                child: Center(
                                                    child:
                                                        CircularProgressIndicator()),
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                color: Colors.grey[200],
                                                child: Icon(Icons.error,
                                                    color: Colors.red),
                                              ),
                                            )),
                                  if (selectedIndexes.contains(index))
                                    const Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.blue,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
          if (_isUploading) const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20.0, right: 20.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: isRemoveMode ? _deleteSelectedImages : _pickImages,
            backgroundColor: isRemoveMode ? Colors.red : Colors.blue,
            shape: const CircleBorder(),
            child: Icon(
              isRemoveMode ? Icons.remove : Icons.add,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
