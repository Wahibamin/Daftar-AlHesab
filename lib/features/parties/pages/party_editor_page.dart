import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';
import '../models/party_model.dart';
import '../repositories/parties_repository.dart';
import '../services/communication_service.dart';

/// Screen for creating and editing commercial parties (customers/suppliers).
class PartyEditorPage extends StatefulWidget {
  final PartyModel? partyToEdit;
  final PartyType initialType;
  final PartiesRepository? repository;

  const PartyEditorPage({
    super.key,
    this.partyToEdit,
    this.initialType = PartyType.customer,
    this.repository,
  });

  @override
  State<PartyEditorPage> createState() => _PartyEditorPageState();
}

class _PartyEditorPageState extends State<PartyEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final PartiesRepository _repo;

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _openingBalanceController;

  late PartyType _selectedType;
  bool _isDebtorOpening =
      true; // By default opening balance is owed by party (مدين)
  bool _isSaving = false;

  bool get _isEditing => widget.partyToEdit != null;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqlitePartiesRepository();

    final p = widget.partyToEdit;
    _selectedType = p?.type ?? widget.initialType;

    _nameController = TextEditingController(text: p?.name ?? '');
    _phoneController = TextEditingController(
      text: p != null ? PhoneNumberFormatter.formatSaudi(p.phone) : '',
    );
    _addressController = TextEditingController(text: p?.address ?? '');

    _creditLimitController = TextEditingController(
      text: p != null && !p.creditLimit.isZero
          ? ThousandsSeparatorInputFormatter.formatRawUnits(p.creditLimitInt)
          : '',
    );

    if (p != null) {
      _isDebtorOpening = p.isDebtor;
      _openingBalanceController = TextEditingController(
        text: p.currentBalance.isZero
            ? ''
            : ThousandsSeparatorInputFormatter.formatRawUnits(
                p.absoluteBalance.rawUnits,
              ),
      );
    } else {
      _openingBalanceController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _pickFromContacts() async {
    final result = await ContactPickerService.safePickContact();
    if (!mounted) return;

    if (!result.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ??
                'تم رفض إذن الوصول لجهات الاتصال. يمكنك كتابة الرقم يدوياً.',
          ),
          backgroundColor: RafColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final contact = result.contact;
    if (contact != null) {
      setState(() {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = contact.name;
        }
        _phoneController.text = PhoneNumberFormatter.formatSaudi(contact.phone);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم استيراد بيانات جهة الاتصال: ${contact.name}'),
          backgroundColor: RafColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveParty() async {
    if (!_formKey.currentState!.validate()) return;

    final rawPhone = PhoneNumberFormatter.cleanDigits(_phoneController.text);
    if (rawPhone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رقم جوال صحيح مكون من 9 أو 10 أرقام'),
          backgroundColor: RafColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final creditLimit = ThousandsSeparatorInputFormatter.extractMoney(
        _creditLimitController.text,
      );

      final enteredOpeningUnits =
          ThousandsSeparatorInputFormatter.extractRawUnits(
            _openingBalanceController.text,
          );

      // Debtor is negative (-), Creditor is positive (+)
      final openingBalance = _isDebtorOpening
          ? Money(-enteredOpeningUnits)
          : Money(enteredOpeningUnits);

      final now = DateTime.now();

      if (_isEditing) {
        final existing = widget.partyToEdit!;
        final updated = existing.copyWith(
          name: _nameController.text.trim(),
          phone: rawPhone,
          type: _selectedType,
          creditLimit: creditLimit,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          taxNumber: null,
          updatedAt: now,
        );

        await _repo.updateParty(updated);
      } else {
        final newParty = PartyModel(
          name: _nameController.text.trim(),
          phone: rawPhone,
          type: _selectedType,
          currentBalance: openingBalance,
          openingBalance: openingBalance,
          creditLimit: creditLimit,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          taxNumber: null,
          createdAt: now,
          updatedAt: now,
        );

        await _repo.insertParty(newParty);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء الحفظ: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing
        ? 'تعديل بيانات ${_selectedType.arabicLabel}'
        : 'إضافة ${_selectedType.arabicLabel} جديد';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveParty,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text(
              'حفظ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: RafSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(RafSpacing.md),
            children: [
              // 1. Party Type Switcher Card
              Container(
                padding: const EdgeInsets.all(RafSpacing.md),
                decoration: RafDecorations.cardFlat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('نوع الطرف التجاري', style: RafTypography.label),
                    const SizedBox(height: RafSpacing.sm),
                    SegmentedButton<PartyType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PartyType.customer,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('عميل'),
                          ),
                          icon: Icon(Icons.person_outline, size: 16),
                        ),
                        ButtonSegment(
                          value: PartyType.supplier,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('مورد'),
                          ),
                          icon: Icon(Icons.local_shipping_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: PartyType.both,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('عميل ومورد'),
                          ),
                          icon: Icon(Icons.sync_alt, size: 16),
                        ),
                      ],
                      selected: {_selectedType},
                      onSelectionChanged: (set) {
                        setState(() {
                          _selectedType = set.first;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: RafSpacing.md),

              // 2. Basic Information Card
              Container(
                padding: const EdgeInsets.all(RafSpacing.md),
                decoration: RafDecorations.cardFlat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'البيانات الأساسية',
                      style: RafTypography.titleMedium,
                    ),
                    const SizedBox(height: RafSpacing.md),

                    // Name
                    const Text(
                      'الاسم التجاري أو الشخصي *',
                      style: RafTypography.label,
                    ),
                    const SizedBox(height: RafSpacing.xs),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'مثال: مؤسسة النور / أحمد محمد',
                        prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'يرجى إدخال اسم الطرف';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: RafSpacing.md),

                    // Phone Number with Contact Picker Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'رقم الجوال *',
                            style: RafTypography.label,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickFromContacts,
                          icon: const Icon(Icons.contacts_outlined, size: 15),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'جهات الاتصال',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: RafSpacing.xs,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RafSpacing.xs),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [PhoneNumberFormatter()],
                      decoration: const InputDecoration(
                        hintText: '05X XXX XXXX',
                        prefixIcon: Icon(Icons.phone_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'يرجى إدخال رقم الجوال';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: RafSpacing.md),

                    // Address
                    const Text(
                      'العنوان / المدينة (اختياري)',
                      style: RafTypography.label,
                    ),
                    const SizedBox(height: RafSpacing.xs),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        hintText: 'مثال: الرياض - حي الملز',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: RafSpacing.md),

              // 3. Financial & Credit Limit Card
              Container(
                padding: const EdgeInsets.all(RafSpacing.md),
                decoration: RafDecorations.cardFlat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الضوابط المالية والائتمان',
                      style: RafTypography.titleMedium,
                    ),
                    const SizedBox(height: RafSpacing.md),

                    // Credit Limit
                    const Text(
                      'سقف الائتمان المسموح به',
                      style: RafTypography.label,
                    ),
                    const SizedBox(height: RafSpacing.xs),
                    TextFormField(
                      controller: _creditLimitController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        prefixIcon: Icon(Icons.credit_score_outlined, size: 20),
                      ),
                    ),

                    // Opening Balance (Only shown during creation)
                    if (!_isEditing) ...[
                      const SizedBox(height: RafSpacing.md),
                      const Text(
                        'الرصيد الافتتاحي',
                        style: RafTypography.label,
                      ),
                      const SizedBox(height: RafSpacing.xs),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale = MediaQuery.textScalerOf(
                            context,
                          ).scale(1.0);
                          final isNarrow =
                              constraints.maxWidth < 360 || textScale > 1.2;

                          final inputField = TextFormField(
                            controller: _openingBalanceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              ThousandsSeparatorInputFormatter(),
                            ],
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              prefixIcon: Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 20,
                              ),
                            ),
                          );

                          final toggle = SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: true,
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'مدين (عليه)',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              ButtonSegment(
                                value: false,
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'دائن (له)',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                            selected: {_isDebtorOpening},
                            onSelectionChanged: (set) {
                              setState(() {
                                _isDebtorOpening = set.first;
                              });
                            },
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                inputField,
                                const SizedBox(height: RafSpacing.sm),
                                toggle,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: inputField),
                              const SizedBox(width: RafSpacing.sm),
                              toggle,
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: RafSpacing.xl),

              // Save Action Button
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveParty,
                icon: const Icon(Icons.check, size: 20),
                label: Text(
                  _isEditing ? 'حفظ التعديلات' : 'إنشاء ملف الطرف',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
