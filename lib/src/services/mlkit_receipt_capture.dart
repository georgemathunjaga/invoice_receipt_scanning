import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/receipt_models.dart';
import '../domain/scan_receipt_config.dart';
import '../scan_receipt_api.dart';

/// ML Kit–backed implementation of [ReceiptCaptureCapability].
///
/// ## Wiring
///
/// ```dart
/// MlKitReceiptCapture(
///   config: ScanReceiptConfig(
///     defaultPageLimit  : 3,         // mc-v2 value
///     retainSourceImages: false,      // mc-v2 value
///   ),
///   ocrScript: TextRecognitionScript.latin,  // mc-v2 value
/// )
/// ```
///
/// All constructor parameters are optional; the defaults match mc-v2 behaviour.
final class MlKitReceiptCapture implements ReceiptCaptureCapability {
  final ScanReceiptConfig _config;

  /// Text recognition script used by ML Kit.
  ///
  /// Override when your receipts use a non-Latin script (e.g. Devanagari,
  /// Chinese, Korean).  mc-v2 value: [TextRecognitionScript.latin].
  final TextRecognitionScript ocrScript;

  final ImagePicker _imagePicker;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  MlKitReceiptCapture({
    ScanReceiptConfig? config,
    this.ocrScript = TextRecognitionScript.latin,
    ImagePicker? imagePicker,
    DateTime Function()? clock,
  })  : _config = config ?? const ScanReceiptConfig(),
        _imagePicker = imagePicker ?? ImagePicker(),
        _clock = clock ?? DateTime.now;

  @override
  Future<ReceiptDraft?> capture(ReceiptCaptureRequest request) async {
    // A per-call page limit overrides the config default when explicitly set.
    final pageLimit = request.pageLimit > 0
        ? request.pageLimit
        : _config.defaultPageLimit;

    final effectiveRequest = ReceiptCaptureRequest(
      source: request.source,
      pageLimit: pageLimit,
      retainSourceImages:
          request.retainSourceImages || _config.retainSourceImages,
    );

    return switch (request.source) {
      ReceiptCaptureSource.documentScanner =>
        await _fromDocumentScanner(effectiveRequest),
      ReceiptCaptureSource.gallery => await _fromGallery(effectiveRequest),
    };
  }

  Future<ReceiptDraft?> _fromDocumentScanner(
    ReceiptCaptureRequest request,
  ) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        isGalleryImport: false,
        pageLimit: request.pageLimit,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final paths = result.images;
      if (paths.isEmpty) return null;

      final ocrText = await _recognizeAll(paths);
      if (ocrText.trim().isEmpty) return null;

      return _buildDraft(ocrText, paths, request.retainSourceImages);
    } on Exception catch (e) {
      // User cancelled the scanner — treat as no-op.
      if (e.toString().toLowerCase().contains('cancel')) return null;
      rethrow;
    } finally {
      scanner.close();
    }
  }

  Future<ReceiptDraft?> _fromGallery(ReceiptCaptureRequest request) async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;

    final ocrText = await _recognize(image.path);
    if (ocrText.trim().isEmpty) return null;

    return _buildDraft(ocrText, [image.path], request.retainSourceImages);
  }

  Future<String> _recognizeAll(List<String> paths) async {
    final buffer = StringBuffer();
    for (final path in paths) {
      if (buffer.isNotEmpty) buffer.write('\n\n--- page ---\n\n');
      buffer.write(await _recognize(path));
    }
    return buffer.toString();
  }

  Future<String> _recognize(String path) async {
    final recognizer = TextRecognizer(script: ocrScript);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final result = await recognizer.processImage(inputImage);
      return result.blocks
          .map((b) => b.lines.map((l) => l.text).join('\n'))
          .join('\n\n');
    } finally {
      recognizer.close();
    }
  }

  ReceiptDraft _buildDraft(
    String ocrText,
    List<String> sourcePaths,
    bool retainImages,
  ) {
    final capturedAt = _clock().toUtc();
    final hash = sha256.convert(utf8.encode(ocrText)).toString();
    final id = 'receipt_${_uuid.v4()}';

    return ReceiptDraft(
      id: id,
      recognized: RecognizedReceipt(
        ocrText: ocrText,
        sourcePaths: retainImages ? sourcePaths : const [],
        contentHash: hash,
        capturedAt: capturedAt,
      ),
      parseState: ReceiptParseState.ocrOnly,
      syncState: ReceiptSyncState.localOnly,
    );
  }
}
