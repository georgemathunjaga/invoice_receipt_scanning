# scan_receipt

A Flutter plugin for capturing, parsing, storing, and linking receipts.  
Provides a pure-logic layer — no widgets, no screens — so any app can wire it
to its own UI and AI provider.

**Capabilities**

- Document scanner (up to N pages) or gallery image via ML Kit
- On-device OCR with ML Kit Latin (or any supported) text recognition
- Structured receipt parsing via your AI provider
- OCR text encrypted at rest; source images deleted after parsing by default
- Database-agnostic persistence layer (implement `ReceiptRepository` in your app)
- Transaction linking / unlinking
- Domain events for every state change

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  scan_receipt:
    path: ../plugin/scan_receipt   # adjust to your repo layout
```

---

## Android setup

### 1. Permissions (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The document scanner uses Google Play Services ML Kit and requires a device
running Android 5.0 (API 21) or higher.

### 2. Minimum SDK (`android/app/build.gradle.kts`)

```kotlin
android {
    defaultConfig {
        minSdk = 21
    }
}
```

---

## iOS setup

### 1. Usage descriptions (`ios/Runner/Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>Scan receipts to add purchase details.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Select receipt images for on-device text recognition.</string>
```

### 2. Minimum deployment target

Set the iOS deployment target to **14.0** or higher in Xcode or
`ios/Podfile`:

```ruby
platform :ios, '14.0'
```

---

## Step-by-step wiring

### Step 1 — Implement `ReceiptCipher`

The plugin encrypts OCR text at rest.  Supply your own cipher so you control
the key-management strategy.

```dart
import 'package:scan_receipt/scan_receipt.dart';

class MyReceiptCipher implements ReceiptCipher {
  // Example: AES-256-GCM using your app's master key.
  // mc-v2 uses ApiService.encryptPayload / decryptPayload.
  @override
  Future<String> encrypt(String plaintext) async {
    // return base64(aesEncrypt(masterKey, plaintext));
    throw UnimplementedError();
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    // return aesDecrypt(masterKey, base64Decode(ciphertext));
    throw UnimplementedError();
  }
}
```

> If you are integrating with **mc-v2**, delegate to
> `ApiService.generateDynamicReceiptPassword` /
> `ApiService.encryptPayload` — the same functions used by the existing
> `receipt_bottom_sheet.dart`.

---

### Step 2 — Implement `ReceiptRepository`

The plugin defines a database-agnostic `ReceiptRepository` interface. You must implement this in your host app (e.g. using ObjectBox or SQLite). 

Refer to [DETAILS.md](file:///d:/PersonalWorkSpace/moneychat-project/plugin/scan_receipt/DETAILS.md) for a copy-pasteable implementation template of **`ObjectBoxReceiptRepository`** and its corresponding entities.

```dart
import 'package:scan_receipt/scan_receipt.dart';
import 'package:my_app/data/objectbox_receipt_repository.dart'; // your implementation

final ReceiptRepository receiptRepository = ObjectBoxReceiptRepository(
  box: store.box<ReceiptRecordEntity>(),
  cipher: MyReceiptCipher(),
);
```

---

### Step 3 — Write your AI function

`AiReceiptParser` accepts any async function that takes OCR text and returns
a decoded `Map<String, dynamic>`.  Throw on failure — the plugin converts
throws to a retryable `ReceiptParseFailure`.

**Option A — delegate to your existing AI layer (mc-v2 style)**

```dart
import 'package:scan_receipt/scan_receipt.dart';
// import your app's existing AI call, e.g.:
// import 'package:my_app/ai/ai_api_call.dart';

Future<Map<String, dynamic>> myAiFunction(String ocrText) async {
  // mc-v2 equivalent:
  //   final result = await AiApiCall().parseReceiptFromOcr(ocrText);
  //   if (result == null) throw Exception(AiApiCall().lastReceiptParseError);
  //   return result;
  //
  // The provider is chosen at runtime from the user's setting:
  //   SharedPreferences key: 'cached_ai_focus_data_v1'  (mc-v2)
  //   Supported values: 'gemini', 'openai', 'openrouter', 'deepseek', 'anthropic'
  throw UnimplementedError();
}
```

**Option B — use the plugin's built-in prompt with any provider**

```dart
import 'dart:convert';
import 'package:scan_receipt/scan_receipt.dart';

Future<Map<String, dynamic>> myAiFunction(String ocrText) async {
  final response = await myProvider.complete(
    systemPrompt: AiReceiptParser.defaultSystemPrompt,
    userMessage: 'Parse this receipt:\n\n$ocrText',
  );
  return jsonDecode(response) as Map<String, dynamic>;
}
```

> Never log `ocrText` directly — it is financially sensitive.  The plugin
> itself never logs OCR content outside of `kDebugMode`.

---

### Step 4 — Assemble `ReceiptCoordinator`

```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:scan_receipt/scan_receipt.dart';

final config = ScanReceiptConfig(
  storageNamespace  : 'plugin.moneychat.scan_receipt', // mc-v2 value
  defaultPageLimit  : 3,                               // mc-v2 value
  fallbackCurrency  : 'KES',                           // mc-v2 value
  maxParseRetries   : 3,                               // mc-v2 value
  retainSourceImages: false,                           // mc-v2 value
  ocrRetentionWindow: const Duration(hours: 24),       // mc-v2 value
);

final coordinator = ReceiptCoordinator(
  config: config,

  capture: MlKitReceiptCapture(
    config   : config,
    ocrScript: TextRecognitionScript.latin,  // mc-v2 value
  ),

  parser: AiReceiptParser(
    runAiTask       : myAiFunction,          // from Step 3
    fallbackCurrency: 'KES',                 // mc-v2 value
    onParseError    : (msg) => myLogger.warn('receipt parse: $msg'),
  ),

  repository: receiptRepository,             // from Step 2

  onEvent: (name, payload) {
    // Forward to your event bus, analytics, or just log.
    // mc-v2 uses PluginEventBus.publish(name, payload).
    debugPrint('[$name] $payload');
  },
);
```

---

### Step 5 — Use in your UI

```dart
// Scan from document scanner
final record = await coordinator.scan(
  ReceiptCaptureRequest(
    source           : ReceiptCaptureSource.documentScanner,
    pageLimit        : 3,     // overrides config.defaultPageLimit if > 0
    retainSourceImages: false,
  ),
);

if (record != null) {
  final receipt = record.draft.parsed;
  print('${receipt?.merchantName} — ${receipt?.totalMinor} minor units');
}

// Scan from gallery
final record = await coordinator.scan(
  const ReceiptCaptureRequest(source: ReceiptCaptureSource.gallery),
);

// Link to a transaction
await coordinator.link(record!.draft.id, 'TXN-20260612-001');

// Unlink
await coordinator.unlink(record.draft.id);

// Watch all receipts (returns a live stream)
repository.watch(const ReceiptQuery()).listen((summaries) {
  for (final s in summaries) {
    print('${s.merchant} — ${s.parseState.name}');
  }
});

// Retry a failed parse
await repository.retry(receiptId);
```

---

## Configuration reference

| Property | Type | Default | mc-v2 value | Notes |
|---|---|---|---|---|
| `storageNamespace` | `String` | `'plugin.scan_receipt'` | `'plugin.moneychat.scan_receipt'` | Prefix for all SharedPreferences and ObjectBox keys owned by the plugin |
| `defaultPageLimit` | `int` | `3` | `3` | Max pages per document scan session |
| `fallbackCurrency` | `String` | `'KES'` | `'KES'` | ISO-4217 code when receipt omits currency |
| `maxParseRetries` | `int` | `3` | `3` | Max AI retry attempts before marking receipt as permanently failed |
| `retainSourceImages` | `bool` | `false` | `false` | Keep JPEG source files after OCR; set `true` only if your UI shows the original scan |
| `ocrRetentionWindow` | `Duration` | `24h` | `Duration(hours: 24)` | How long encrypted OCR text is kept after the retry window closes |

### `MlKitReceiptCapture` additional params

| Property | Type | Default | mc-v2 value |
|---|---|---|---|
| `ocrScript` | `TextRecognitionScript` | `latin` | `TextRecognitionScript.latin` |

### `AiReceiptParser` additional params

| Property | Type | Default | mc-v2 value |
|---|---|---|---|
| `fallbackCurrency` | `String` | `'KES'` | `'KES'` |
| `onParseError` | `void Function(String)?` | `null` | feeds `debugPrint` in debug mode |
| `AiReceiptParser.defaultSystemPrompt` | static `String` | built-in receipt prompt | `AiApiCall.composeReceiptParsingPrompt()` |

---

## Domain events

All events are delivered via the `onEvent` callback on `ReceiptCoordinator`.

| Event name | Payload keys | Emitted when |
|---|---|---|
| `receipt.saved.v1` | `receipt_id`, `transaction_id`, `parse_state`, `namespace` | After capture + save (success or parse failure) |
| `receipt.linked.v1` | `receipt_id`, `transaction_id` | After `coordinator.link()` |
| `receipt.unlinked.v1` | `receipt_id` | After `coordinator.unlink()` |
| `receipt.parse.failed.v1` | `receipt_id`, `code`, `retryable`, `namespace` | When AI parse fails |
| `receipt.sync.changed.v1` | _(reserved)_ | Future: remote sync state change |

Consumed events your app should forward to the coordinator:

| Event | Action |
|---|---|
| `transaction.deleted.v1` | call `repository.unlink(receiptId)` to keep the receipt without the transaction reference |
| `ai.provider.changed.v1` | optionally call `repository.retry(receiptId)` on pending receipts |

---

## Migrating from legacy `UserReceipt` (mc-v2 only)

If you are migrating legacy `UserReceipt` rows to the new repository, implement the helper `LegacyReceiptMigrator` in your host app (template available in [DETAILS.md](file:///d:/PersonalWorkSpace/moneychat-project/plugin/scan_receipt/DETAILS.md)) and call it:

```dart
import 'package:my_app/data/legacy_receipt_migrator.dart';

final migrator = LegacyReceiptMigrator(
  // Pass the raw rows from your old ObjectBox UserReceipt box:
  legacyRows: legacyBox.getAll().map((r) => {
    'id': r.id,
    'data': r.data,
    'transactionId': r.transactionId,
  }).toList(),
  target: receiptRepository,
);

final count = await migrator.migrate();
print('Migrated $count receipts');
```

Rows already present in the new store are skipped (idempotent).

---

## Running tests

```bash
flutter test test/src/receipt_coordinator_test.dart
```
#   i n v o i c e _ r e c e i p t _ s c a n n i n g  
 