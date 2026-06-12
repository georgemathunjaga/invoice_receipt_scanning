import '../domain/receipt_models.dart';
import '../scan_receipt_api.dart';

/// Parses a [RecognizedReceipt] into a structured [ParsedReceipt] using a
/// caller-supplied AI function.
///
/// ## Wiring
///
/// ```dart
/// AiReceiptParser(
///   runAiTask: (ocrText) async {
///     // Option A — delegate to your existing AI layer (e.g. mc-v2 AiApiCall):
///     final result = await AiApiCall().parseReceiptFromOcr(ocrText);
///     if (result == null) throw Exception('AI parse returned null');
///     return result;
///
///     // Option B — use the plugin's built-in prompt with your own provider:
///     // final response = await myProvider.complete(
///     //   AiReceiptParser.defaultSystemPrompt,
///     //   'Parse this receipt:\n\n$ocrText',
///     // );
///     // return jsonDecode(response) as Map<String, dynamic>;
///   },
///   fallbackCurrency: 'KES',          // mc-v2 value
///   onParseError: (msg) => log(msg),   // optional — redact before logging
/// )
/// ```
///
/// ## [runAiTask] contract
///
/// - Receives the raw OCR text.
/// - Must return a `Map<String, dynamic>` matching the receipt JSON schema
///   (see [defaultSystemPrompt]).
/// - Must **throw** on any error; the parser converts throws to
///   [ReceiptParseFailure] automatically.
/// - Never log the raw text inside this function — OCR text is
///   financially sensitive.
final class AiReceiptParser implements ReceiptParser {
  final Future<Map<String, dynamic>> Function(String ocrText) runAiTask;

  /// ISO-4217 currency code used when the AI response omits `currency`.
  /// mc-v2 value: `'KES'`
  final String fallbackCurrency;

  /// Called with a safe (non-sensitive) error message when parsing fails.
  /// Use this to feed your app's logger or crash reporter.
  final void Function(String safeMessage)? onParseError;

  AiReceiptParser({
    required this.runAiTask,
    this.fallbackCurrency = 'KES',
    this.onParseError,
  });

  // ---------------------------------------------------------------------------
  // Default system prompt
  // ---------------------------------------------------------------------------

  /// The built-in system / instruction prompt sent to the AI provider.
  ///
  /// Pass this to your AI provider when you don't have your own receipt-parsing
  /// prompt.  mc-v2 uses an equivalent prompt built by
  /// `AiApiCall.composeReceiptParsingPrompt()`.
  ///
  /// ```dart
  /// runAiTask: (ocrText) async {
  ///   final response = await myProvider.complete(
  ///     AiReceiptParser.defaultSystemPrompt,
  ///     'Parse this receipt:\n\n$ocrText',
  ///   );
  ///   return jsonDecode(response) as Map<String, dynamic>;
  /// },
  /// ```
  static const String defaultSystemPrompt = '''
You are an expert OCR receipt parsing AI.
Analyze the raw text extracted from a receipt and return a structured JSON object.
Extract information exactly as it appears — do NOT invent or calculate values.
If a field is absent, use null.

Return ONLY valid JSON with this exact structure:
{
  "merchant_info": {
    "name": "String | null",
    "branch": "String | null",
    "address": "String | null",
    "phone": "String | null"
  },
  "transaction_metadata": {
    "date": "YYYY-MM-DD | null",
    "time": "HH:MM:SS | null",
    "receipt_number": "String | null"
  },
  "financial_summary": {
    "subtotal": "double | null",
    "total": "double | null",
    "service_charge": "double | null",
    "discount_amount": "double | null",
    "currency": "ISO-4217 code | null"
  },
  "payment_details": {
    "method": "cash | card | mobile_money | null",
    "card_last_four": "String | null",
    "mobile_money_ref": "String | null"
  },
  "items": [
    {
      "sku": "String | null",
      "name": "String",
      "quantity": "String | null",
      "unit_price": "double | null",
      "total_price": "double | null",
      "discount": "double | null"
    }
  ],
  "additional_notes": "String | null"
}''';

  // ---------------------------------------------------------------------------
  // ReceiptParser implementation
  // ---------------------------------------------------------------------------

  @override
  Future<ReceiptParseResult> parse(RecognizedReceipt recognized) async {
    try {
      final raw = await runAiTask(recognized.ocrText);
      _validate(raw);
      return ReceiptParseSuccess(_fromJson(raw, fallbackCurrency));
    } on FormatException catch (e) {
      onParseError?.call(e.message);
      return ReceiptParseFailure(
        code: 'parse_invalid_schema',
        safeMessage: e.message,
        retryable: true,
      );
    } catch (e) {
      const msg = 'AI provider returned an unexpected response.';
      onParseError?.call(msg);
      return const ReceiptParseFailure(
        code: 'parse_provider_error',
        safeMessage: msg,
        retryable: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Validation and mapping
  // ---------------------------------------------------------------------------

  static void _validate(Map<String, dynamic> value) {
    final summary = value['financial_summary'];
    if (summary is! Map<String, dynamic>) {
      throw const FormatException('financial_summary is required.');
    }
    final items = value['items'];
    if (items != null && items is! List) {
      throw const FormatException('items must be a list.');
    }
  }

  static ParsedReceipt _fromJson(
    Map<String, dynamic> json,
    String fallbackCurrency,
  ) {
    final merchant = _map(json['merchant_info']);
    final metadata = _map(json['transaction_metadata']);
    final financial = _map(json['financial_summary']);
    final payment = _map(json['payment_details']);
    final rawItems = json['items'] as List<dynamic>? ?? const [];

    return ParsedReceipt(
      merchantName: merchant['name']?.toString(),
      branch: merchant['branch']?.toString(),
      address: merchant['address']?.toString(),
      phone: merchant['phone']?.toString(),
      occurredAt: DateTime.tryParse(
        '${metadata['date'] ?? ''} ${metadata['time'] ?? ''}'.trim(),
      ),
      receiptNumber: metadata['receipt_number']?.toString(),
      currency: financial['currency']?.toString() ?? fallbackCurrency,
      subtotalMinor: _minor(financial['subtotal']),
      totalMinor: _minor(financial['total']),
      serviceChargeMinor: _minor(financial['service_charge']),
      discountMinor: _minor(financial['discount_amount']),
      paymentMethod: payment['method']?.toString(),
      items: rawItems.whereType<Map>().map((raw) {
        final item = raw.cast<String, dynamic>();
        return ReceiptItem(
          sku: item['sku']?.toString(),
          name: item['name']?.toString().trim() ?? 'Unknown item',
          quantity: item['quantity']?.toString(),
          unitPriceMinor: _minor(item['unit_price']),
          totalPriceMinor: _minor(item['total_price']),
          discountMinor: _minor(item['discount']),
        );
      }).toList(growable: false),
      notes: json['additional_notes']?.toString(),
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  static int? _minor(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().replaceAll(',', '') ?? '');
    return amount == null ? null : (amount * 100).round();
  }
}
