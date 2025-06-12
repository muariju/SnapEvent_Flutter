import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'face_embedding_service.dart'; // Your existing service

class FaceUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> uploadImageWithFaceEmbeddings({
    required File imageFile,
    required String eventId,
    required BuildContext context,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar(context, 'You must be logged in to upload');
        return '';
      }

      // 1. Extract face embeddings
      final faceService = FaceEmbeddingService();
      await faceService.initialize();

      List<double> embeddings;
      try {
        embeddings = await faceService.extractEmbeddings(imageFile);
        debugPrint('Extracted embeddings: ${embeddings.length} numbers');
      } catch (e) {
        debugPrint("Face detection failed: $e");
        _showSnackBar(context, 'No face detected or invalid image');
        faceService.dispose();
        return '';
      } finally {
        faceService.dispose();
      }

      // 2. Upload to Firebase Storage
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = _storage.ref().child('events/$eventId/$fileName');
      await storageRef.putFile(imageFile);
      final downloadURL = await storageRef.getDownloadURL();

      // 3. Prepare Firestore data
      final firestoreData = {
        'url': downloadURL,
        'organizerId': user.uid,
        'uploadedAt': FieldValue.serverTimestamp(),
        'faces': [
          {
            'embedding': embeddings,
            'userId': user.uid,
          }
        ],
      };

      // 4. Save to Firestore
      await _firestore
          .collection('eventPhotos') // ✅ New collection
          .doc(eventId)
          .collection('photos') // Subcollection
          .add(firestoreData);

      return downloadURL;
    } catch (e) {
      debugPrint("Upload failed: $e");
      _showSnackBar(context, 'Upload failed: ${e.toString()}');
      return '';
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
