import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isLoading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadProfileImage();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          setState(() {
            nameController.text = doc['name'] ?? '';
            emailController.text = doc['email'] ?? user.email ?? '';
            phoneController.text = doc['phone'] ?? '';
            _isLoading = false;
          });
        } else {
          // Create user document if it doesn't exist
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'phone': '',
          });
          setState(() {
            nameController.text = user.displayName ?? '';
            emailController.text = user.email ?? '';
            phoneController.text = '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error loading profile: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_path');

    if (imagePath != null) {
      setState(() {
        _imageFile = File(imagePath);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'name': nameController.text,
        'phone': phoneController.text,
      });

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error updating profile: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // Save to app directory
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = basename(pickedFile.path);
      final savedImage =
          await File(pickedFile.path).copy('${appDir.path}/$fileName');

      // Save path to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', savedImage.path);

      setState(() {
        _imageFile = savedImage;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      // Navigate to login screen or root
      Navigator.of(context as BuildContext)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error signing out: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _isLoading
                ? const CircularProgressIndicator()
                : IconButton(
                    onPressed: _saveProfile,
                    icon: const Text(
                      "Save",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.blue.shade100,
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!)
                            : const AssetImage('assets/SnapEventLogo.png')
                                as ImageProvider,
                        child: _imageFile == null
                            ? const Icon(Icons.camera_alt, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(controller: nameController, label: 'Name'),
                  _buildTextField(
                      controller: emailController,
                      label: 'Email',
                      enabled: false), // Email shouldn't be editable
                  _buildTextField(
                      controller: phoneController, label: 'Phone Number'),
                  const SizedBox(height: 50),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 25),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 239, 248, 255),
        borderRadius: BorderRadius.circular(50),
      ),
      margin: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color.fromRGBO(65, 65, 65, 1),
        ),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(
            fontFamily: 'Mulish',
            fontWeight: FontWeight.normal,
            color: Color.fromRGBO(110, 110, 110, 1),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
