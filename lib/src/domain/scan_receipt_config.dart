/// Top-level configuration for the scan_receipt plugin.
///
/// Pass a [ScanReceiptConfig] to [ReceiptCoordinator] and
/// [MlKitReceiptCapture] to control behaviour without forking the plugin.
/// Every field has a safe default so only the values that differ from the
/// defaults need to be specified.
///
/// Example — MoneyChat (mc-v2) values:
/// ```dart
/// const ScanReceiptConfig(
///   storageNamespace : 'plugin.moneychat.scan_receipt',
///   defaultPageLimit : 3,
///   fallbackCurrency : 'KES',
///   maxParseRetries  : 3,
///   retainSourceImages  : false,
///   ocrRetentionWindow  : Duration(hours: 24),
/// )
/// ```
final class ScanReceiptConfig {
  /// SharedPreferences / ObjectBox key prefix used by the plugin.
  ///
  /// Change this if your app hosts multiple plugins that could collide.
  /// mc-v2 value: `'plugin.moneychat.scan_receipt'`
  final String storageNamespace;

  /// Maximum number of pages the document scanner will capture in one session.
  ///
  /// mc-v2 value: `3`
  final int defaultPageLimit;

  /// ISO-4217 currency code used when the receipt contains no currency field.
  ///
  /// mc-v2 value: `'KES'`
  final String fallbackCurrency;

  /// Maximum number of times the parse queue will retry a failed AI call
  /// before marking the receipt as permanently failed.
  ///
  /// mc-v2 value: `3`
  final int maxParseRetries;

  /// Whether JPEG source images are kept on-device after OCR succeeds.
  ///
  /// Keeping images increases storage usage.  Set to `true` only when your UI
  /// needs to show the original scan.
  /// mc-v2 value: `false`
  final bool retainSourceImages;

  /// How long encrypted OCR text is retained in the local store after the
  /// retry window closes.  After this window the raw text is deleted even if
  /// parsing never succeeded.
  ///
  /// mc-v2 value: `Duration(hours: 24)`
  final Duration ocrRetentionWindow;

  const ScanReceiptConfig({
    this.storageNamespace = 'plugin.scan_receipt',
    this.defaultPageLimit = 3,
    this.fallbackCurrency = 'KES',
    this.maxParseRetries = 3,
    this.retainSourceImages = false,
    this.ocrRetentionWindow = const Duration(hours: 24),
  });
}
