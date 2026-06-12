import 'package:flutter_test/flutter_test.dart';
import 'package:scan_receipt/scan_receipt.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

final _draft = ReceiptDraft(
  id: 'receipt_test_001',
  recognized: RecognizedReceipt(
    ocrText: 'Supermart\nTotal: 450.00',
    sourcePaths: const [],
    contentHash: 'abc123',
    capturedAt: DateTime.utc(2026, 6, 1, 10, 0),
  ),
  parseState: ReceiptParseState.ocrOnly,
  syncState: ReceiptSyncState.localOnly,
);

class _FakeCapture implements ReceiptCaptureCapability {
  final ReceiptDraft? result;
  _FakeCapture(this.result);

  @override
  Future<ReceiptDraft?> capture(ReceiptCaptureRequest _) async => result;
}

class _SuccessParser implements ReceiptParser {
  @override
  Future<ReceiptParseResult> parse(RecognizedReceipt _) async =>
      ReceiptParseSuccess(
        const ParsedReceipt(
          merchantName: 'Supermart',
          currency: 'KES',
          totalMinor: 45000,
        ),
      );
}

class _FailingParser implements ReceiptParser {
  @override
  Future<ReceiptParseResult> parse(RecognizedReceipt _) async =>
      const ReceiptParseFailure(
        code: 'parse_provider_error',
        safeMessage: 'AI unavailable.',
        retryable: true,
      );
}

class _FakeCipher implements ReceiptCipher {
  @override
  Future<String> encrypt(String p) async => 'enc:$p';
  @override
  Future<String> decrypt(String c) async => c.replaceFirst('enc:', '');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeReceiptRepository repository;

  setUp(() {
    repository = _FakeReceiptRepository();
  });

  group('ReceiptCoordinator.scan', () {
    test('returns null when capture returns null', () async {
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(null),
        parser: _SuccessParser(),
        repository: repository,
      );
      expect(await coordinator.scan(const ReceiptCaptureRequest(
        source: ReceiptCaptureSource.documentScanner,
      )), isNull);
      expect(repository.saved, isEmpty);
    });

    test('saves OCR-only draft before calling parser', () async {
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(_draft),
        parser: _SuccessParser(),
        repository: repository,
      );
      await coordinator.scan(const ReceiptCaptureRequest(
        source: ReceiptCaptureSource.documentScanner,
      ));
      expect(repository.saved.first.parseState, ReceiptParseState.ocrOnly);
    });

    test('final record has parsed state on success', () async {
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(_draft),
        parser: _SuccessParser(),
        repository: repository,
      );
      final record = await coordinator.scan(const ReceiptCaptureRequest(
        source: ReceiptCaptureSource.documentScanner,
      ));
      expect(record!.draft.parseState, ReceiptParseState.parsed);
      expect(record.draft.parsed?.merchantName, 'Supermart');
    });

    test('saves OCR draft before parser failure', () async {
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(_draft),
        parser: _FailingParser(),
        repository: repository,
      );
      final result = await coordinator.scan(const ReceiptCaptureRequest(
        source: ReceiptCaptureSource.documentScanner,
      ));
      expect(repository.saved.length, 2);
      expect(repository.saved.first.parseState, ReceiptParseState.ocrOnly);
      expect(result!.draft.parseState, ReceiptParseState.failed);
    });

    test('emits receipt.saved.v1 and receipt.parse.failed.v1 on failure',
        () async {
      final events = <String>[];
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(_draft),
        parser: _FailingParser(),
        repository: repository,
        onEvent: (name, _) => events.add(name),
      );
      await coordinator.scan(const ReceiptCaptureRequest(
        source: ReceiptCaptureSource.documentScanner,
      ));
      expect(events, containsAll(['receipt.saved.v1', 'receipt.parse.failed.v1']));
    });
  });

  group('ReceiptCoordinator link/unlink', () {
    test('emits receipt.linked.v1', () async {
      final events = <String>[];
      await repository.saveDraft(_draft);
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(null),
        parser: _FailingParser(),
        repository: repository,
        onEvent: (name, _) => events.add(name),
      );
      await coordinator.link(_draft.id, 'txn_001');
      expect(events, contains('receipt.linked.v1'));
    });

    test('emits receipt.unlinked.v1', () async {
      final events = <String>[];
      await repository.saveDraft(_draft);
      final coordinator = ReceiptCoordinator(
        capture: _FakeCapture(null),
        parser: _FailingParser(),
        repository: repository,
        onEvent: (name, _) => events.add(name),
      );
      await coordinator.unlink(_draft.id);
      expect(events, contains('receipt.unlinked.v1'));
    });
  });
}

// ---------------------------------------------------------------------------
// In-memory repository
// ---------------------------------------------------------------------------

class _FakeReceiptRepository implements ReceiptRepository {
  final List<ReceiptDraft> saved = [];
  final Map<String, ReceiptDraft> _store = {};

  @override
  Future<ReceiptRecord> saveDraft(ReceiptDraft draft) async {
    saved.add(draft);
    _store[draft.id] = draft;
    final now = DateTime.now().toUtc();
    return ReceiptRecord(draft: draft, createdAt: now, updatedAt: now);
  }

  @override
  Future<ReceiptRecord?> getById(String id) async {
    final draft = _store[id];
    if (draft == null) return null;
    final now = DateTime.now().toUtc();
    return ReceiptRecord(draft: draft, createdAt: now, updatedAt: now);
  }

  @override
  Future<ReceiptRecord?> getByTransactionId(String transactionId) async =>
      null;

  @override
  Stream<List<ReceiptSummary>> watch(ReceiptQuery query) => const Stream.empty();

  @override
  Future<void> link(String receiptId, String transactionId) async {
    final d = _store[receiptId];
    if (d != null) {
      _store[receiptId] = ReceiptDraft(
        id: d.id,
        recognized: d.recognized,
        parsed: d.parsed,
        parseState: d.parseState,
        syncState: d.syncState,
        linkedTransactionId: transactionId,
      );
    }
  }

  @override
  Future<void> unlink(String receiptId) async {
    final d = _store[receiptId];
    if (d != null) {
      _store[receiptId] = ReceiptDraft(
        id: d.id,
        recognized: d.recognized,
        parsed: d.parsed,
        parseState: d.parseState,
        syncState: d.syncState,
      );
    }
  }

  @override
  Future<void> delete(String receiptId) async => _store.remove(receiptId);

  @override
  Future<void> retry(String receiptId) async {}
}
