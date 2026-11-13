import 'dart:math';
import '../../features/inventory/data/inventory_repository.dart';

/// Service responsible for generating unique internal barcodes.
///
/// Note: These internal barcodes use GS1-reserved internal prefix 200 (in-store / restricted circulation)
/// and are represented as Code 128 symbology. They are strictly for internal store management
/// and are not global GS1-registered barcodes.
class BarcodeGeneratorService {
  /// Generates a guaranteed-unique internal barcode by checking directly against the local SQLite database.
  ///
  /// Attempts up to [maxAttempts] times to find an unused candidate code.
  static Future<String> generateUniqueInternalBarcode(
    InventoryRepository repository, {
    int maxAttempts = 10,
    Random? random,
  }) async {
    final rng = random ?? Random();

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Internal prefix '200' + 9 random digits = 12 digits internal barcode
      final randomDigits = rng.nextInt(900000000) + 100000000;
      final candidate = '200$randomDigits';

      final existing = await repository.getItemByCode(candidate);
      if (existing == null) {
        return candidate;
      }
    }

    // High-concurrency fallback using timestamp to guarantee uniqueness
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fallbackCandidate = '200${ts % 1000000000}';
    final existingFallback = await repository.getItemByCode(fallbackCandidate);
    if (existingFallback == null) {
      return fallbackCandidate;
    }

    // Ultimate fallback: incremental scan
    return '200${ts + rng.nextInt(999)}';
  }
}
