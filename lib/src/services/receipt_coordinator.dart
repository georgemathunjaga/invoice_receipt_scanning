import '../domain/receipt_models.dart';
import '../domain/scan_receipt_config.dart';
import '../scan_receipt_api.dart';

typedef OnReceiptEvent = void Function(
  String eventName,
  Map<String, dynamic> payload,
);

/// Orchestrates the full capture → parse → save flow and emits domain events.
///
/// ## Wiring
///
/// ```dart
/// ReceiptCoordinator(
///   config: ScanReceiptConfig(
///     storageNamespace : 'plugin.moneychat.scan_receipt', // mc-v2 value
///     fallbackCurrency : 'KES',                          // mc-v2 value
///     maxParseRetries  : 3,                              // mc-v2 value
///   ),
///   capture  : MlKitReceiptCapture(config: config),
///   parser   : AiReceiptParser(runAiTask: myAiFunction),
///   repository: ObjectBoxReceiptRepository(box: store.box(), cipher: myCipher),
///   onEvent  : (name, payload) => myEventBus.publish(name, payload),
/// )
/// ```
///
/// ## Events emitted via [onEvent]
///
/// | name | when |
/// |---|---|
/// | `receipt.saved.v1` | after every successful save (parse success or failure) |
/// | `receipt.linked.v1` | after [link] |
/// | `receipt.unlinked.v1` | after [unlink] |
/// | `receipt.parse.failed.v1` | when the AI parser fails |
/// | `receipt.sync.changed.v1` | reserved for future sync state changes |
final class ReceiptCoordinator {
  final ReceiptCaptureCapability capture;
  final ReceiptParser parser;
  final ReceiptRepository repository;
  final ScanReceiptConfig config;

  /// Optional event callback.  Supply this to integrate with your app's event
  /// bus or analytics layer without coupling the plugin to any framework.
  final OnReceiptEvent? onEvent;

  ReceiptCoordinator({
    required this.capture,
    required this.parser,
    required this.repository,
    ScanReceiptConfig? config,
    this.onEvent,
  }) : config = config ?? const ScanReceiptConfig();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Captures, parses, and saves a receipt.
  ///
  /// Returns `null` when the user cancels or no text is recognized.
  /// The OCR-only draft is persisted *before* the AI call so a crash or
  /// network failure does not lose captured data.
  Future<ReceiptRecord?> scan(ReceiptCaptureRequest request) async {
    final draft = await capture.capture(request);
    if (draft == null) return null;

    // Persist OCR-only draft immediately — crash-safe before AI call.
    await repository.saveDraft(draft);

    final parseResult = await parser.parse(draft.recognized);

    final completed = switch (parseResult) {
      ReceiptParseSuccess(:final receipt) => ReceiptDraft(
        id: draft.id,
        recognized: draft.recognized,
        parsed: receipt,
        parseState: ReceiptParseState.parsed,
        syncState: ReceiptSyncState.pending,
        linkedTransactionId: draft.linkedTransactionId,
      ),
      ReceiptParseFailure() => ReceiptDraft(
        id: draft.id,
        recognized: draft.recognized,
        parseState: ReceiptParseState.failed,
        syncState: ReceiptSyncState.localOnly,
        linkedTransactionId: draft.linkedTransactionId,
      ),
    };

    final record = await repository.saveDraft(completed);

    onEvent?.call('receipt.saved.v1', {
      'receipt_id': record.draft.id,
      'transaction_id': record.draft.linkedTransactionId,
      'parse_state': record.draft.parseState.name,
      'namespace': config.storageNamespace,
    });

    if (parseResult is ReceiptParseFailure) {
      onEvent?.call('receipt.parse.failed.v1', {
        'receipt_id': record.draft.id,
        'code': parseResult.code,
        'retryable': parseResult.retryable,
        'namespace': config.storageNamespace,
      });
    }

    return record;
  }

  /// Links a saved receipt to a transaction.
  Future<void> link(String receiptId, String transactionId) async {
    await repository.link(receiptId, transactionId);
    onEvent?.call('receipt.linked.v1', {
      'receipt_id': receiptId,
      'transaction_id': transactionId,
    });
  }

  /// Removes the transaction association from a receipt.
  Future<void> unlink(String receiptId) async {
    await repository.unlink(receiptId);
    onEvent?.call('receipt.unlinked.v1', {'receipt_id': receiptId});
  }
}
