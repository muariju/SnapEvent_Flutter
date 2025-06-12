import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
// ignore: unused_import
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceEmbeddingService {
  // ignore: constant_identifier_names
  static const MODEL_FILE = 'assets/models/facenet.tflite';
  late Interpreter _interpreter;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );

  Future<void> initialize() async {
    _interpreter = await Interpreter.fromAsset(MODEL_FILE);
  }

  Future<List<double>> extractEmbeddings(File imageFile) async {
    try {
      // 1. Detect and align face
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) throw Exception("No face detected");

      // 2. Preprocess image
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes)!;
      final processedImage = _preprocessImage(image, faces.first);

      // 3. Run inference
      final input = processedImage.reshape([1, 160, 160, 3]);
      final output = List.filled(128, 0.0).reshape([1, 128]);
      _interpreter.run(input, output);

      return _normalizeEmbeddings(output[0]);
    } finally {
      await _faceDetector.close();
    }
  }

  Float32List _preprocessImage(img.Image image, Face face) {
    // 1. Crop face using face.boundingBox
    final cropped = img.copyCrop(
      image,
      x: face.boundingBox.left.toInt(),
      y: face.boundingBox.top.toInt(),
      width: face.boundingBox.width.toInt(),
      height: face.boundingBox.height.toInt(),
    );

    // 2. Resize to 160x160 (Facenet requirement)
    final resized = img.copyResize(cropped, width: 160, height: 160);

    // 3. Convert to float32 array and normalize
    final pixels = Float32List(160 * 160 * 3);
    int pixelIndex = 0;
    for (var y = 0; y < 160; y++) {
      for (var x = 0; x < 160; x++) {
        final pixel = resized.getPixel(x, y);
        pixels[pixelIndex++] = (pixel.r - 127.5) / 128.0; // Normalize to [-1,1]
        pixels[pixelIndex++] = (pixel.g - 127.5) / 128.0;
        pixels[pixelIndex++] = (pixel.b - 127.5) / 128.0;
      }
    }
    return pixels;
  }

  List<double> _normalizeEmbeddings(List<double> embeddings) {
    double sum = embeddings.fold(0, (s, e) => s + e * e);
    final norm = math.sqrt(sum);
    return embeddings.map((e) => e / norm).toList();
  }

  void dispose() {
    _interpreter.close();
  }
}
