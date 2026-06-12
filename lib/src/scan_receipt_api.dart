import 'domain/receipt_models.dart';

export 'domain/receipt_models.dart';

abstract interface class ReceiptCaptureCapability {
  Future<ReceiptDraft?> capture(ReceiptCaptureRequest request);
}

abstract interface class ReceiptRepository {
  Stream<List<ReceiptSummary>> watch(ReceiptQuery query);
  Future<ReceiptRecord?> getById(String id);
  Future<ReceiptRecord?> getByTransactionId(String transactionId);
  Future<ReceiptRecord> saveDraft(ReceiptDraft draft);
  Future<void> link(String receiptId, String transactionId);
  Future<void> unlink(String receiptId);
  Future<void> delete(String receiptId);
  Future<void> retry(String receiptId);
}

abstract interface class ReceiptParser {
  Future<ReceiptParseResult> parse(RecognizedReceipt recognized);
}

abstract interface class ReceiptCipher {
  Future<String> encrypt(String plaintext);
  Future<String> decrypt(String ciphertext);
}
