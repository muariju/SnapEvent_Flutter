import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;

class FetchEventPage extends StatefulWidget {
  final String eventId;
  final String searchKey;

  const FetchEventPage(
      {super.key, required this.eventId, required this.searchKey});

  @override
  _FetchEventPageState createState() => _FetchEventPageState();
}

class _FetchEventPageState extends State<FetchEventPage> {
  StreamSubscription<QuerySnapshot>? _imagesSubscription;
  List<Map<String, dynamic>> _allPhotos = [];
  List<Map<String, dynamic>> _filteredPhotos = [];
  List<int> selectedIndexes = [];
  bool isRemoveMode = false;
  int selectedCount = 0;
  bool _isLoading = true;
  List<double>? _userEmbeddings;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyEventAccess().then((_) {
        if (mounted) {
          _loadUserData();
          _loadEventPhotos();
          _setupRealTimeListener();
        }
      });
    });
  }

  void _setupRealTimeListener() {
    _imagesSubscription = FirebaseFirestore.instance
        .collection('eventPhotos') // ✅ Correct collection
        .doc(widget.eventId) // Uses the event ID from widget
        .collection('photos') // ✅ Correct subcollection
        .orderBy('uploadedAt', descending: true) // Optional: Newest first
        .snapshots() // Real-time updates
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _allPhotos = snapshot.docs.map((doc) => doc.data()).toList();
          _filterPhotos(); // Re-filter when new data arrives
        });
        debugPrint('Updated ${_allPhotos.length} photos in real-time'); // Debug
      }
    });
  }

  @override
  void dispose() {
    _imagesSubscription?.cancel(); // Stop listening when page closes
    super.dispose();
  }

  Future<void> _verifyEventAccess() async {
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (!eventDoc.exists) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event not found')),
          );
        }
        return;
      }

      if ((eventDoc['searchKey'] as String?) != widget.searchKey) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid event access')),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error verifying event: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data()?['faceEmbeddings'] != null) {
        final embeddings = List<double>.from(doc['faceEmbeddings']);

        if (embeddings.length >= 128) {
          // Ensure we have complete embeddings
          setState(() {
            _userEmbeddings = embeddings;
          });
          _filterPhotos(); // Re-filter photos when embeddings load
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadEventPhotos() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('eventPhotos')
        .doc(widget.eventId)
        .collection('photos')
        .orderBy('uploadedAt', descending: true) // Critical for consistency
        .get(const GetOptions(source: Source.server));

    debugPrint('=== PHOTO VERIFICATION ===');
    debugPrint('Found ${snapshot.docs.length} photos');
    debugPrint('Fetched ${snapshot.docs.length} photos directly from server');

    if (snapshot.docs.isNotEmpty) {
      final firstPhoto = snapshot.docs.first.data();
      debugPrint('First photo faces: ${firstPhoto['faces']?.length ?? 0}');
      debugPrint('First photo URL: ${firstPhoto['url']}');
    }
    setState(() {
      _allPhotos = snapshot.docs.map((doc) => doc.data()).toList();
      _filterPhotos();
      _isLoading = false;
    });
  }

  // Update the _filterPhotos method to properly handle face embeddings
  void _filterPhotos() {
    if (_userEmbeddings == null || _userEmbeddings!.isEmpty) {
      setState(() {
        _filteredPhotos = _allPhotos;
      });
      return;
    }

    // Convert user embeddings to List<double> if they aren't already
    // ignore: unused_local_variable
    final userEmbeddings = _userEmbeddings!.map((e) => e.toDouble()).toList();

    setState(() {
      _filteredPhotos = _allPhotos.where((photo) {
        try {
          final faces = photo['faces'] as List? ?? [];
          debugPrint('Checking photo with ${faces.length} faces');

          for (var face in faces.cast<Map>()) {
            final faceEmbedding = List<double>.from(face['embedding'] ?? []);
            if (faceEmbedding.length != 128) continue;

            final similarity =
                _cosineSimilarity(_userEmbeddings!, faceEmbedding);
            debugPrint('Similarity score: $similarity');

            if (similarity > 0.7) {
              // Lowered threshold from 0.6
              return true;
            }
          }
          return false;
        } catch (e) {
          debugPrint('Face matching error: $e');
          return false;
        }
      }).toList();
    });
  }

// Update cosine similarity calculation for better precision
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom > 0 ? dot / denom : 0.0;
  }

  void _onImageLongPress(int index) {
    setState(() {
      isRemoveMode = true;
      if (!selectedIndexes.contains(index)) {
        selectedIndexes.add(index);
        selectedCount++;
      }
    });
  }

  void _toggleSelection(int index) {
    if (isRemoveMode) {
      setState(() {
        if (selectedIndexes.contains(index)) {
          selectedIndexes.remove(index);
          selectedCount--;
        } else {
          selectedIndexes.add(index);
          selectedCount++;
        }
      });
    } else {
      _viewImage(_filteredPhotos[index]['url']);
    }
  }

  void _viewImage(String imageUrl) {
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

  void _downloadImages() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading Selected Images')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: Text(
            'Your Event Photos',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.blue),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPhotos.isEmpty
                      ? Center(
                          child: Text(
                            "No matching photos found",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        )
                      : GridView.builder(
                          itemCount: _filteredPhotos.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onLongPress: () => _onImageLongPress(index),
                              onTap: () => _toggleSelection(index),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: _filteredPhotos[index]['url'],
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: Colors.grey[200],
                                      ),
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.error),
                                    ),
                                  ),
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
            onPressed: selectedCount > 0 ? _downloadImages : null,
            backgroundColor: Colors.blue,
            shape: const CircleBorder(),
            child: const Icon(
              Icons.download,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
