/// MoneyChat scan_receipt plugin public API.
///
/// Import this library to access the plugin's interfaces and domain models.
/// The host app is responsible for constructing [ObjectBoxReceiptRepository]
/// and wiring it with a [ReceiptCipher] and an ObjectBox [Store] — the plugin
/// does not open a second store.
library scan_receipt;

export 'src/scan_receipt_api.dart';
export 'src/domain/receipt_models.dart';
export 'src/domain/scan_receipt_config.dart';
export 'src/services/mlkit_receipt_capture.dart';
export 'src/services/ai_receipt_parser.dart';
export 'src/services/receipt_coordinator.dart';
