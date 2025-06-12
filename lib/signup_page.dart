import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signin_page.dart';
import 'FaceCapturePage.dart'; // Import the FaceCapturePage

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  bool _obscurePassword = true;

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  Future<void> _signUp() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // Store user details in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'uid': credential.user!.uid,
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Navigate to FaceCapturePage after signup
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(); // close loading
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const FaceCapturePage()),
      );
    } on FirebaseAuthException catch (e) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(); // close loading

      String message = 'Signup failed. Please try again.';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already in use.';
      } else if (e.code == 'weak-password') {
        message = 'Password should be at least 6 characters.';
      }

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ));
    } catch (e) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('An unexpected error occurred.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(0, 255, 255, 255),
        elevation: 0,
        flexibleSpace: const Padding(
          padding: EdgeInsets.only(top: 26.0),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(left: 40.0, top: 40.0),
                child: Text(
                  'Signup',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Mulish',
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: const Text(
                  "Signup to get started!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Mulish',
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: nameController,
                label: "Enter Name",
              ),
              _buildTextField(
                controller: emailController,
                label: "Email",
              ),
              _buildTextField(
                controller: phoneController,
                label: "Phone Number",
              ),
              _buildPasswordField(),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Already have an account? ",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Color.fromRGBO(102, 102, 102, 1),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (context) => const SigninPage()),
                      );
                    },
                    child: const Text(
                      "Sign in",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: Colors.blue,
                ),
                child: ElevatedButton(
                  onPressed: _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool obscureText = false,
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
        obscureText: obscureText,
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

  Widget _buildPasswordField() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 25),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 239, 248, 255),
        borderRadius: BorderRadius.circular(50),
      ),
      margin: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color.fromARGB(255, 56, 56, 56),
        ),
        decoration: InputDecoration(
          hintText: "Password",
          hintStyle: const TextStyle(
            fontFamily: 'Mulish',
            fontWeight: FontWeight.normal,
            color: Color.fromRGBO(110, 110, 110, 1),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
            onPressed: _togglePasswordVisibility,
          ),
        ),
      ),
    );
  }
}
