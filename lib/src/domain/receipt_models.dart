enum ReceiptCaptureSource { documentScanner, gallery }

enum ReceiptParseState { ocrOnly, parsing, parsed, failed }

enum ReceiptSyncState { localOnly, pending, synced, failed }

final class ReceiptCaptureRequest {
  final ReceiptCaptureSource source;
  final int pageLimit;
  final bool retainSourceImages;

  const ReceiptCaptureRequest({
    required this.source,
    this.pageLimit = 3,
    this.retainSourceImages = false,
  });
}

final class RecognizedReceipt {
  final String ocrText;
  final List<String> sourcePaths;
  final String contentHash;
  final DateTime capturedAt;

  const RecognizedReceipt({
    required this.ocrText,
    required this.sourcePaths,
    required this.contentHash,
    required this.capturedAt,
  });
}

final class ReceiptItem {
  final String? sku;
  final String name;
  final String? quantity;
  final int? unitPriceMinor;
  final int? totalPriceMinor;
  final int? discountMinor;

  const ReceiptItem({
    this.sku,
    required this.name,
    this.quantity,
    this.unitPriceMinor,
    this.totalPriceMinor,
    this.discountMinor,
  });
}

final class ParsedReceipt {
  final String? merchantName;
  final String? branch;
  final String? address;
  final String? phone;
  final DateTime? occurredAt;
  final String? receiptNumber;
  final String currency;
  final int? subtotalMinor;
  final int? totalMinor;
  final int? serviceChargeMinor;
  final int? discountMinor;
  final String? paymentMethod;
  final List<ReceiptItem> items;
  final String? notes;

  const ParsedReceipt({
    this.merchantName,
    this.branch,
    this.address,
    this.phone,
    this.occurredAt,
    this.receiptNumber,
    required this.currency,
    this.subtotalMinor,
    this.totalMinor,
    this.serviceChargeMinor,
    this.discountMinor,
    this.paymentMethod,
    this.items = const [],
    this.notes,
  });
}

sealed class ReceiptParseResult {
  const ReceiptParseResult();
}

final class ReceiptParseSuccess extends ReceiptParseResult {
  final ParsedReceipt receipt;
  const ReceiptParseSuccess(this.receipt);
}

final class ReceiptParseFailure extends ReceiptParseResult {
  final String code;
  final String safeMessage;
  final bool retryable;

  const ReceiptParseFailure({
    required this.code,
    required this.safeMessage,
    required this.retryable,
  });
}

final class ReceiptDraft {
  final String id;
  final RecognizedReceipt recognized;
  final ParsedReceipt? parsed;
  final ReceiptParseState parseState;
  final ReceiptSyncState syncState;
  final String? linkedTransactionId;

  const ReceiptDraft({
    required this.id,
    required this.recognized,
    this.parsed,
    required this.parseState,
    required this.syncState,
    this.linkedTransactionId,
  });
}

final class ReceiptRecord {
  final ReceiptDraft draft;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReceiptRecord({
    required this.draft,
    required this.createdAt,
    required this.updatedAt,
  });
}

final class ReceiptSummary {
  final String id;
  final String merchant;
  final int? totalMinor;
  final String currency;
  final DateTime capturedAt;
  final String? linkedTransactionId;
  final ReceiptParseState parseState;
  final ReceiptSyncState syncState;

  const ReceiptSummary({
    required this.id,
    required this.merchant,
    required this.totalMinor,
    required this.currency,
    required this.capturedAt,
    required this.linkedTransactionId,
    required this.parseState,
    required this.syncState,
  });
}

final class ReceiptQuery {
  final String? transactionId;
  final bool includeUnlinked;
  final int limit;

  const ReceiptQuery({
    this.transactionId,
    this.includeUnlinked = true,
    this.limit = 100,
  });
}
