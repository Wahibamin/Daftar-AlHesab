import '../../../core/utils/money.dart';

/// Commercial contact information picked or inputted.
class ContactInfo {
  final String name;
  final String phone;

  const ContactInfo({required this.name, required this.phone});
}

/// Represents the status of runtime permissions.
enum ContactPermissionStatus { granted, denied, permanentlyDenied }

/// Structured result of contact picker with permission state and graceful fallback.
class ContactPickResult {
  final bool isGranted;
  final ContactInfo? contact;
  final String? message;

  const ContactPickResult({
    required this.isGranted,
    this.contact,
    this.message,
  });

  bool get isSuccess => isGranted && contact != null;
}

/// Service providing direct phone, SMS, and WhatsApp communication hooks.
class CommunicationService {
  /// Strips any non-digit characters from the phone number.
  static String cleanPhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  /// Converts a local Saudi phone (e.g., '0501234567') to international format ('966501234567').
  static String toWhatsAppInternational(String phone) {
    final clean = cleanPhoneNumber(phone);
    if (clean.startsWith('05')) {
      return '966${clean.substring(1)}';
    } else if (clean.startsWith('5')) {
      return '966$clean';
    } else if (clean.startsWith('+')) {
      return clean.substring(1);
    }
    return clean;
  }

  /// Generates the standard official Arabic accounting balance reminder message.
  static String formatBalanceMessage({
    required String partyName,
    required Money balance,
    String storeName = 'دفتر الحساب',
  }) {
    final formattedAmount = balance.abs.format(includeSymbol: false);
    return 'أهلاً بك $partyName، نود تذكيرك بأن رصيدكم الحالي لدى [$storeName] هو: $formattedAmount.';
  }

  /// Builds a `tel:` direct dialer URI.
  static Uri buildCallUri(String phone) {
    final clean = cleanPhoneNumber(phone);
    return Uri(scheme: 'tel', path: clean);
  }

  /// Builds an `sms:` direct messaging URI with optional body.
  static Uri buildSmsUri(String phone, [String? message]) {
    final clean = cleanPhoneNumber(phone);
    if (message != null && message.isNotEmpty) {
      return Uri(
        scheme: 'sms',
        path: clean,
        queryParameters: {'body': message},
      );
    }
    return Uri(scheme: 'sms', path: clean);
  }

  /// Builds a direct WhatsApp web/app link with a pre-filled accounting statement message.
  static Uri buildWhatsAppUri(String phone, String message) {
    final intlPhone = toWhatsAppInternational(phone);
    return Uri.parse(
      'https://wa.me/$intlPhone?text=${Uri.encodeComponent(message)}',
    );
  }

  /// Validates whether a given URI scheme is supported by the OS intent query configuration.
  static bool isSupportedIntentScheme(Uri uri) {
    const supportedSchemes = {'tel', 'sms', 'https'};
    return supportedSchemes.contains(uri.scheme.toLowerCase());
  }
}

/// Contact picker service with graceful runtime permission checks.
class ContactPickerService {
  /// Optional mock/override delegate for runtime permission testing.
  static Future<bool> Function()? permissionDelegate;
  static Future<ContactInfo?> Function()? pickerDelegate;

  /// Flag to simulate permission denial in UI tests or previews.
  static bool simulatePermissionDenied = false;

  /// Checks and requests contact access permission gracefully.
  static Future<bool> checkAndRequestPermission() async {
    if (permissionDelegate != null) {
      return await permissionDelegate!();
    }
    if (simulatePermissionDenied) {
      return false;
    }
    // No native permission request is implemented without an injected delegate.
    return false;
  }

  /// Curated list of mock commercial contacts for testing and demonstration.
  static const List<ContactInfo> mockContacts = [
    ContactInfo(name: 'مؤسسة النور للتوريدات', phone: '0501112233'),
    ContactInfo(name: 'سوبرماركت الرياض الحديث', phone: '0552223344'),
    ContactInfo(name: 'شركة الوفاق للصناعات الغذائية', phone: '0563334455'),
    ContactInfo(name: 'مطعم ومقهى السعادة', phone: '0544445566'),
    ContactInfo(name: 'تموينات الفهد التجارية', phone: '0595556677'),
  ];

  /// Raw contact picker function.
  static Future<ContactInfo?> pickContact({
    Future<ContactInfo?> Function()? customPicker,
  }) async {
    if (customPicker != null) {
      return await customPicker();
    }
    if (pickerDelegate != null) return await pickerDelegate!();
    // There is no native contact picker in this version. Never auto-fill a
    // demonstration contact as if the user selected it from their phone.
    return null;
  }

  /// Safe contact picker pipeline that verifies permissions before launching,
  /// preventing app crashes and providing a graceful fallback.
  static Future<ContactPickResult> safePickContact({
    Future<ContactInfo?> Function()? customPicker,
  }) async {
    if (customPicker == null &&
        pickerDelegate == null &&
        permissionDelegate == null &&
        !simulatePermissionDenied) {
      return const ContactPickResult(
        isGranted: false,
        contact: null,
        message:
            'اختيار جهات اتصال الهاتف غير متاح في هذه النسخة. يمكنك إدخال الاسم والرقم يدوياً.',
      );
    }
    try {
      final granted = await checkAndRequestPermission();
      if (!granted) {
        return const ContactPickResult(
          isGranted: false,
          contact: null,
          message: 'تم رفض إذن الوصول لجهات الاتصال. يمكنك كتابة الرقم يدوياً.',
        );
      }
      final contact = await pickContact(customPicker: customPicker);
      return ContactPickResult(isGranted: true, contact: contact);
    } catch (e) {
      return ContactPickResult(
        isGranted: false,
        contact: null,
        message: 'تعذر الوصول إلى جهات الاتصال: $e. يمكنك إدخال الرقم يدوياً.',
      );
    }
  }
}
