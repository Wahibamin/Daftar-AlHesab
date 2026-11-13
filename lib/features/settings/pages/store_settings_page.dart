import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/business_data_wiper.dart';
import '../../../core/licensing/license_gate.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../inventory/data/inventory_repository.dart';

/// Store information model used across the app, invoices, and PDF generation.
class StoreSettingsModel {
  final String storeName;
  final String taxNumber;
  final String phone;
  final String address;
  final String invoiceFooterNote;

  const StoreSettingsModel({
    this.storeName = 'مؤسسة دفتر الحساب للتجارة والتوريدات',
    this.taxNumber = '',
    this.phone = '0501234567',
    this.address = 'المملكة العربية السعودية - الرياض',
    this.invoiceFooterNote =
        'شكراً لتعاملكم معنا. البضاعة المباعة ترد وتستبدل خلال 3 أيام بموجب الفاتورة.',
  });

  Map<String, String> toSettingsMap() => {
    'store_name': storeName,
    'tax_number': taxNumber,
    'phone': phone,
    'address': address,
    'invoice_footer_note': invoiceFooterNote,
  };

  factory StoreSettingsModel.fromSettingsMap(Map<String, String> map) {
    const defaults = StoreSettingsModel();
    return StoreSettingsModel(
      storeName: map['store_name'] ?? defaults.storeName,
      taxNumber: map['tax_number'] ?? defaults.taxNumber,
      phone: map['phone'] ?? defaults.phone,
      address: map['address'] ?? defaults.address,
      invoiceFooterNote:
          map['invoice_footer_note'] ?? defaults.invoiceFooterNote,
    );
  }

  StoreSettingsModel copyWith({
    String? storeName,
    String? taxNumber,
    String? phone,
    String? address,
    String? invoiceFooterNote,
  }) {
    return StoreSettingsModel(
      storeName: storeName ?? this.storeName,
      taxNumber: taxNumber ?? this.taxNumber,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      invoiceFooterNote: invoiceFooterNote ?? this.invoiceFooterNote,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreSettingsModel &&
          runtimeType == other.runtimeType &&
          storeName == other.storeName &&
          taxNumber == other.taxNumber &&
          phone == other.phone &&
          address == other.address &&
          invoiceFooterNote == other.invoiceFooterNote;

  @override
  int get hashCode =>
      Object.hash(storeName, taxNumber, phone, address, invoiceFooterNote);
}

/// Global settings manager instance for store profile with SQLite persistence.
class StoreSettingsManager {
  static StoreSettingsManager instance = StoreSettingsManager._internal();

  final AppDatabase _dbManager;
  StoreSettingsModel settings = const StoreSettingsModel();
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  StoreSettingsManager._internal({AppDatabase? dbManager})
    : _dbManager = dbManager ?? AppDatabase.instance;

  /// Resets instance for isolated unit tests.
  static void resetForTesting({AppDatabase? dbManager}) {
    instance = StoreSettingsManager._internal(dbManager: dbManager);
  }

  /// Loads settings from local SQLite storage.
  /// Falls back to defaults only for missing keys; preserves saved user data.
  Future<StoreSettingsModel> loadSettings() async {
    try {
      final db = await _dbManager.database;
      final rows = await db.query(AppTables.appSettings);
      if (rows.isNotEmpty) {
        final map = <String, String>{};
        for (final row in rows) {
          final k = row['key'] as String?;
          final v = row['value'] as String?;
          if (k != null && v != null) {
            map[k] = v;
          }
        }
        settings = StoreSettingsModel.fromSettingsMap(map);
      }
      _isLoaded = true;
    } catch (_) {
      // Retain in-memory settings if database is not yet opened
    }
    return settings;
  }

  /// Permanently saves settings into SQLite key-value store.
  Future<void> saveSettings(StoreSettingsModel newSettings) async {
    settings = newSettings;
    _isLoaded = true;
    try {
      final db = await _dbManager.database;
      final map = newSettings.toSettingsMap();
      await db.transaction((txn) async {
        for (final entry in map.entries) {
          await txn.insert(AppTables.appSettings, {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } on DatabaseException {
      rethrow;
    } catch (e) {
      // In headless widget testing without sqflite ffi binding
      if (e.toString().contains('MissingPluginException')) {
        return;
      }
      rethrow;
    }
  }
}

/// Store profile settings page for configuring branding, contact info, and invoice headers.
class StoreSettingsPage extends StatefulWidget {
  final InventoryRepository? inventoryRepo;
  final BusinessDataWiper? wiper;

  const StoreSettingsPage({super.key, this.inventoryRepo, this.wiper});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  late final InventoryRepository _repo;
  late final BusinessDataWiper _wiper;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _footerController;
  bool _isSeeding = false;
  bool _isSaving = false;
  bool _isWiping = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.inventoryRepo ?? SqliteInventoryRepository();
    _wiper = widget.wiper ?? BusinessDataWiper.instance;
    final current = StoreSettingsManager.instance.settings;
    _nameController = TextEditingController(text: current.storeName);
    _phoneController = TextEditingController(text: current.phone);
    _addressController = TextEditingController(text: current.address);
    _footerController = TextEditingController(text: current.invoiceFooterNote);

    if (!StoreSettingsManager.instance.isLoaded) {
      StoreSettingsManager.instance.loadSettings().then((loaded) {
        if (mounted) {
          setState(() {
            _nameController.text = loaded.storeName;
            _phoneController.text = loaded.phone;
            _addressController.text = loaded.address;
            _footerController.text = loaded.invoiceFooterNote;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final updated = StoreSettingsModel(
      storeName: _nameController.text.trim().isEmpty
          ? const StoreSettingsModel().storeName
          : _nameController.text.trim(),
      taxNumber: '',
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      invoiceFooterNote: _footerController.text.trim(),
    );

    try {
      await StoreSettingsManager.instance.saveSettings(updated);

      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ بيانات المنشأة بنجاح'),
          backgroundColor: RafColors.success,
        ),
      );

      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء حفظ بيانات المنشأة في قاعدة البيانات'),
          backgroundColor: RafColors.danger,
        ),
      );
    }
  }

  Future<void> _safeSeedData() async {
    setState(() => _isSeeding = true);
    try {
      final added = await _repo.safeSeedMasterData();
      if (mounted) {
        setState(() => _isSeeding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added > 0
                  ? 'تمت التهيئة الآمنة بنجاح: أُضيفت $added من الوحدات والتصنيفات القياسية دون المساس بسجلاتك.'
                  : 'البيانات الأساسية مكتملة بالفعل، لم يتم إجراء أي تعديل على بياناتك.',
            ),
            backgroundColor: RafColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSeeding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء التهيئة الآمنة للبيانات'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndClearBusinessData() async {
    if (_isWiping) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _ClearBusinessDataDialog(wiper: _wiper),
    );

    if (confirmed == true && mounted) {
      setState(() => _isWiping = true);
      try {
        await StoreSettingsManager.instance.loadSettings();
        if (!mounted) return;
        final loaded = StoreSettingsManager.instance.settings;
        setState(() {
          _nameController.text = loaded.storeName;
          _phoneController.text = loaded.phone;
          _addressController.text = loaded.address;
          _footerController.text = loaded.invoiceFooterNote;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم مسح جميع بيانات العمل بنجاح مع الحفاظ الكامل على إعدادات المنشأة.',
            ),
            backgroundColor: RafColors.success,
            duration: Duration(seconds: 4),
          ),
        );
      } finally {
        if (mounted) setState(() => _isWiping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          'بيانات وإعدادات المنشأة',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(RafSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TrialLicenseInfo(),
            Container(
              decoration: BoxDecoration(
                color: RafColors.surface,
                borderRadius: RafRadius.roundedMd,
                border: Border.all(color: RafColors.border),
                boxShadow: RafShadows.subtle,
              ),
              padding: const EdgeInsets.all(RafSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الهوية والبيانات الرسمية',
                    style: RafTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: RafColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: RafSpacing.md),

                  // Store Name
                  Text('اسم المتجر / المنشأة', style: RafTypography.bodySmall),
                  const SizedBox(height: RafSpacing.xxs),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'مثال: شركة رَفّ التجارية...',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Phone
                  Text('رقم الجوال / التواصل', style: RafTypography.bodySmall),
                  const SizedBox(height: RafSpacing.xxs),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneNumberFormatter(maxLength: 10)],
                    decoration: const InputDecoration(
                      hintText: '05XXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Address
                  Text('العنوان والمدينة', style: RafTypography.bodySmall),
                  const SizedBox(height: RafSpacing.xxs),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      hintText: 'المملكة العربية السعودية...',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Footer Notes on invoices
                  Text(
                    'ملاحظات وتذييل الفاتورة',
                    style: RafTypography.bodySmall,
                  ),
                  const SizedBox(height: RafSpacing.xxs),
                  TextField(
                    controller: _footerController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'سياسة الاستبدال والضمان...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: RafSpacing.lg),

            // Safe Master Data Seeding Card
            Container(
              decoration: BoxDecoration(
                color: RafColors.surface,
                borderRadius: RafRadius.roundedMd,
                border: Border.all(color: RafColors.border),
                boxShadow: RafShadows.subtle,
              ),
              padding: const EdgeInsets.all(RafSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.dataset_outlined,
                        color: RafColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: RafSpacing.xs),
                      Expanded(
                        child: Text(
                          'تهيئة البيانات الأساسية (وحدات وتصنيفات)',
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: RafColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RafSpacing.xs),
                  Text(
                    'تهيئة آمنة لوحدات القياس القياسية (قطعة، كرتون، كجم، لتر، متر، باكت...) وتصنيفات المنتجات بنقرة واحدة، دون حذف أو تعديل أي سجلات موجودة ودون إنشاء أي فواتير أو سندات وهمية.',
                    style: RafTypography.bodySmall.copyWith(
                      color: RafColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: RafSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSeeding ? null : _safeSeedData,
                      icon: _isSeeding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: RafColors.primary,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSeeding
                              ? 'جارِ فحص وتهيئة البيانات...'
                              : 'بدء التهيئة الآمنة للبيانات الأساسية',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RafColors.primary,
                        side: const BorderSide(color: RafColors.primary),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: RafRadius.roundedMd,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: RafSpacing.xl),

            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.check, size: 20),
              label: const Text(
                'حفظ التعديلات',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: RafColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: RafRadius.roundedMd,
                ),
              ),
            ),

            const SizedBox(height: RafSpacing.xxl),
            const Divider(color: RafColors.border),
            const SizedBox(height: RafSpacing.md),

            // Danger Zone Card: Safe Clearing of Local Business Data
            Container(
              decoration: BoxDecoration(
                color: RafColors.danger.withValues(alpha: 0.04),
                borderRadius: RafRadius.roundedMd,
                border: Border.all(
                  color: RafColors.danger.withValues(alpha: 0.3),
                ),
              ),
              padding: const EdgeInsets.all(RafSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: RafColors.danger,
                        size: 24,
                      ),
                      const SizedBox(width: RafSpacing.xs),
                      Expanded(
                        child: Text(
                          'منطقة العمليات الإدارية الحساسة',
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: RafColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RafSpacing.xs),
                  Text(
                    'مسح شامل لجميع بيانات العمل التشغيلية (الفواتير، السندات، الأصناف، الأطراف، وحركات المخزون) عند الرغبة في بدء دورة عمل جديدة، مع الحفاظ الكامل على إعدادات وهوية المنشأة والوحدات والتصنيفات القياسية ومخطط قاعدة البيانات.',
                    style: RafTypography.bodySmall.copyWith(
                      color: RafColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: RafSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('clear_business_data_button'),
                      onPressed: _isWiping
                          ? null
                          : _confirmAndClearBusinessData,
                      icon: _isWiping
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: RafColors.danger,
                              ),
                            )
                          : const Icon(Icons.delete_forever_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isWiping
                              ? 'جارِ مسح البيانات...'
                              : 'مسح جميع بيانات العمل المحلية',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RafColors.danger,
                        side: const BorderSide(color: RafColors.danger),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: RafRadius.roundedMd,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Double-confirmation dialog ensuring safe explicit confirmation by typing the phrase:
/// "مسح جميع البيانات" before triggering the wipe operation.
class _ClearBusinessDataDialog extends StatefulWidget {
  final BusinessDataWiper wiper;

  const _ClearBusinessDataDialog({required this.wiper});

  @override
  State<_ClearBusinessDataDialog> createState() =>
      _ClearBusinessDataDialogState();
}

class _ClearBusinessDataDialogState extends State<_ClearBusinessDataDialog> {
  late final TextEditingController _phraseController;
  bool _isExecuting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _phraseController = TextEditingController();
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  bool get _isPhraseValid =>
      _phraseController.text.trim() == BusinessDataWiper.confirmationPhrase;

  Future<void> _executeWipe() async {
    if (!_isPhraseValid || _isExecuting) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
    });

    try {
      await widget.wiper.clearAllBusinessData();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _errorMessage =
            'تعذر إتمام عملية المسح بسبب خطأ أثناء المعاملة. تم التراجع بالكامل عن أي تعديل لحماية بياناتك.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: RafRadius.roundedMd),
      titlePadding: const EdgeInsets.fromLTRB(
        RafSpacing.lg,
        RafSpacing.lg,
        RafSpacing.lg,
        RafSpacing.xs,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: RafSpacing.lg,
        vertical: RafSpacing.xs,
      ),
      actionsPadding: const EdgeInsets.all(RafSpacing.md),
      title: Row(
        children: [
          const Icon(Icons.warning_rounded, color: RafColors.danger, size: 28),
          const SizedBox(width: RafSpacing.xs),
          Expanded(
            child: Text(
              'مسح جميع بيانات العمل المحلية',
              style: RafTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
                color: RafColors.danger,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(RafSpacing.sm),
              decoration: BoxDecoration(
                color: RafColors.danger.withValues(alpha: 0.08),
                borderRadius: RafRadius.roundedSm,
                border: Border.all(
                  color: RafColors.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'تنبيه صارم: هذه العملية غير قابلة للتراجع! سيتم حذف كافة البيانات التشغيلية نهائياً من قاعدة البيانات المحلية ولن يمكن استعادتها من داخل التطبيق إلا عبر نسخة احتياطية خارجية.',
                style: RafTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: RafColors.danger,
                ),
              ),
            ),
            const SizedBox(height: RafSpacing.md),
            Text(
              'ما سيتم حذفه نهائياً:',
              style: RafTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RafSpacing.xxs),
            _buildBulletPoint(
              'كافة الفواتير (مبيعات، مشتريات، مردودات) وبنودها.',
            ),
            _buildBulletPoint(
              'كافة السندات المالية (قبض، صرف) وحركات الخزينة.',
            ),
            _buildBulletPoint(
              'كافة حركات المخزون والتسويات والأرصدة الافتتاحية.',
            ),
            _buildBulletPoint('كافة الأصناف والمنتجات والكميات المسجلة.'),
            _buildBulletPoint('كافة العملاء والموردين وأرصدتهم ومديونياتهم.'),
            _buildBulletPoint('كافة الوحدات والتصنيفات (القياسية والمخصصة).'),
            const SizedBox(height: RafSpacing.md),
            Text(
              'ما سيتم الحفاظ عليه بالكامل:',
              style: RafTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: RafColors.success,
              ),
            ),
            const SizedBox(height: RafSpacing.xxs),
            _buildBulletPoint(
              'إعدادات وهوية المنشأة (الاسم، الهاتف، العنوان، تذييل الفاتورة).',
            ),
            _buildBulletPoint(
              'مخطط وهيكل قاعدة البيانات والفهارس والإعدادات البرمجية.',
            ),
            const SizedBox(height: RafSpacing.md),
            const Divider(color: RafColors.border),
            const SizedBox(height: RafSpacing.xs),
            Text(
              'لتأكيد العملية، يرجى كتابة العبارة التالية نصاً:',
              style: RafTypography.bodySmall.copyWith(
                color: RafColors.textPrimary,
              ),
            ),
            const SizedBox(height: RafSpacing.xxs),
            Text(
              'مسح جميع البيانات',
              style: RafTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w800,
                color: RafColors.danger,
              ),
            ),
            const SizedBox(height: RafSpacing.xs),
            TextField(
              key: const Key('clear_business_data_phrase_field'),
              controller: _phraseController,
              enabled: !_isExecuting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'اكتب: مسح جميع البيانات',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: RafSpacing.sm),
              Text(
                _errorMessage!,
                style: RafTypography.bodySmall.copyWith(
                  color: RafColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_clear_button'),
          onPressed: _isExecuting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: RafColors.textSecondary),
          ),
        ),
        ElevatedButton(
          key: const Key('confirm_clear_button'),
          onPressed: (_isPhraseValid && !_isExecuting) ? _executeWipe : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: RafColors.danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: RafColors.danger.withValues(alpha: 0.3),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: RafRadius.roundedSm),
          ),
          child: _isExecuting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'تأكيد المسح النهائي',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.w800)),
          Expanded(
            child: Text(
              text,
              style: RafTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
