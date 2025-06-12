import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddEventPage extends StatelessWidget {
  const AddEventPage({super.key});

  Future<void> _addEventToFirebase(String eventName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Create a more unique searchKey
    final searchKey =
        '${eventName.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';

    await FirebaseFirestore.instance.collection('events').add({
      'name': eventName.trim(),
      'organizerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'searchKey': searchKey,
    });
  }

  @override
  Widget build(BuildContext context) {
    TextEditingController eventController = TextEditingController();
    FocusNode focusNode = FocusNode();

    focusNode.addListener(() {
      if (!focusNode.hasFocus) return;
    });

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
                  'Enter Name',
                  style: TextStyle(
                    fontSize: 24,
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
                height: MediaQuery.of(context).size.height * 0.4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  image: DecorationImage(
                    image: AssetImage('assets/welcome.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Text(
                        'Please enter the name of the Event below here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Color.fromRGBO(102, 102, 102, 1),
                          fontFamily: 'Mulish',
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 25),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 239, 248, 255),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: TextField(
                        controller: eventController,
                        focusNode: focusNode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 56, 56, 56),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Event Name',
                          hintStyle: TextStyle(
                            fontFamily: 'Mulish',
                            fontWeight: FontWeight.normal,
                            color: Color.fromRGBO(65, 65, 65, 1),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 90),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: Colors.blue,
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          if (eventController.text.isNotEmpty) {
                            await _addEventToFirebase(eventController.text);
                            Navigator.pop(context, eventController.text);
                          }
                        },
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
            ],
          ),
        ),
      ),
    );
  }
}
