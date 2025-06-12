import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/face_embedding_service.dart';
import 'home_page.dart';

class FaceCapturePage extends StatefulWidget {
  const FaceCapturePage({super.key});

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  final FaceEmbeddingService _embeddingService = FaceEmbeddingService();
  File? _imageFile;
  bool _isUploading = false;
  bool _isFaceDetected = false;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  // Initialize the model when the page loads
  Future<void> _initializeModel() async {
    await _embeddingService.initialize();
  }

  Future<void> _capturePhoto() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final imageFile = File(pickedFile.path);

        // Call extractEmbeddings and check for face detection
        try {
          await _embeddingService.extractEmbeddings(
              imageFile); // Detect face and process embeddings

          setState(() {
            _imageFile = imageFile;
            _isFaceDetected = true;
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No face detected. Please try again.')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _uploadAndSave() async {
    if (_imageFile == null || !_isFaceDetected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a valid face photo')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not logged in");
      }
      // Extract face embeddings from the image
      final embeddings = await _embeddingService.extractEmbeddings(_imageFile!);

      final storageRef =
          FirebaseStorage.instance.ref().child('user_faces/${user.uid}.jpg');

      await storageRef.putFile(_imageFile!);
      final imageUrl = await storageRef.getDownloadURL();

      // Store the face image URL and embeddings in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'faceImageUrl': imageUrl,
        'faceEmbeddings': embeddings,
        'faceVerified': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    _embeddingService.dispose(); // Properly dispose the embedding service
    _imageFile?.delete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Padding(
          padding: EdgeInsets.only(top: 26.0),
          child: Text(
            'Face Verification',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontFamily: 'Mulish',
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text(
              "Verify Your Identity",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Position your face within the circle",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),

            // Face Preview Container
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isFaceDetected ? Colors.green : Colors.blue,
                  width: 3,
                ),
              ),
              child: _imageFile != null
                  ? ClipOval(
                      child: Image.file(
                        _imageFile!,
                        width: 180,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.face,
                        size: 50,
                        color: Colors.blue,
                      ),
                    ),
            ),
            const SizedBox(height: 30),

            if (_isFaceDetected)
              const Text(
                "Face Verified!",
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _capturePhoto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Capture Face',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isFaceDetected)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
