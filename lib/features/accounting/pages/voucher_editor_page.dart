import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';
import '../../parties/models/party_model.dart';
import '../../parties/repositories/parties_repository.dart';
import '../models/voucher_model.dart';
import '../repositories/vouchers_repository.dart';
import '../widgets/cheque_account_selector.dart';

/// Clean White UI Voucher Editor Page (Receipt & Payment Vouchers with Live Thousands Formatting).
class VoucherEditorPage extends StatefulWidget {
  final VouchersRepository vouchersRepo;
  final PartiesRepository partiesRepo;
  final VoucherType initialType;
  final int? initialPartyId;
  final VoucherPurpose initialPurpose;

  VoucherEditorPage({
    super.key,
    VouchersRepository? vouchersRepo,
    PartiesRepository? partiesRepo,
    this.initialType = VoucherType.receipt,
    this.initialPartyId,
    this.initialPurpose = VoucherPurpose.general,
  }) : vouchersRepo = vouchersRepo ?? SqliteVouchersRepository(),
       partiesRepo = partiesRepo ?? SqlitePartiesRepository();

  @override
  State<VoucherEditorPage> createState() => _VoucherEditorPageState();
}

class _VoucherEditorPageState extends State<VoucherEditorPage> {
  late VoucherType _voucherType;
  late PaymentMethod _paymentMethod;
  TreasuryAccount _chequeAccount = TreasuryAccount.bank;
  late VoucherPurpose _purpose;
  bool get _isExpense => _purpose == VoucherPurpose.expense;
  int? _selectedPartyId;
  DateTime _voucherDate = DateTime.now();
  String _voucherNumber = '';

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _statementController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  List<PartyModel> _availableParties = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _purpose = widget.initialPurpose;
    _voucherType = _isExpense ? VoucherType.payment : widget.initialType;
    _paymentMethod = PaymentMethod.cash;
    _selectedPartyId = widget.initialPartyId;
    _loadInitialData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _statementController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final parties = _isExpense
          ? <PartyModel>[]
          : await widget.partiesRepo.getParties();
      final num = await widget.vouchersRepo.generateNextVoucherNumber(
        _voucherType,
      );

      if (mounted) {
        setState(() {
          _availableParties = parties;
          _voucherNumber = num;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onTypeChanged(VoucherType newType) async {
    if (newType == _voucherType) return;
    setState(() {
      _voucherType = newType;
      if (newType == VoucherType.receipt) _purpose = VoucherPurpose.general;
    });

    final num = await widget.vouchersRepo.generateNextVoucherNumber(newType);
    if (mounted) {
      setState(() {
        _voucherNumber = num;
      });
    }
  }

  Future<void> _saveVoucher() async {
    if (_isSaving) return;
    if (_isExpense && _statementController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال بيان المصروف')));
      return;
    }
    final amount = Money.tryParse(_amountController.text.trim());
    if (amount == null || amount.isZero || amount.isNegative) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر'),
          backgroundColor: RafColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final voucher = VoucherModel(
        voucherNumber: _voucherNumber,
        voucherType: _voucherType,
        partyId: _isExpense ? null : _selectedPartyId,
        amount: amount,
        paymentMethod: _paymentMethod,
        chequeAccount: _chequeAccount,
        purpose: _purpose,
        expenseCategory:
            _isExpense && _categoryController.text.trim().isNotEmpty
            ? _categoryController.text.trim()
            : null,
        referenceNumber: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        statement: _statementController.text.trim().isEmpty
            ? null
            : _statementController.text.trim(),
        voucherDate: _voucherDate,
        createdAt: DateTime.now(),
      );

      await widget.vouchersRepo.createVoucher(voucher);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isExpense
                  ? 'تم تسجيل المصروف بنجاح'
                  : _voucherType == VoucherType.receipt
                  ? 'تم حفظ وترحيل سند القبض بنجاح'
                  : 'تم حفظ وترحيل سند الصرف بنجاح',
            ),
            backgroundColor: RafColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ السند: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          _isExpense
              ? 'تسجيل مصروف'
              : _voucherType == VoucherType.receipt
              ? 'سند قبض مالي'
              : 'سند صرف مالي',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RafColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(RafSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Type Toggle Tabs (سند قبض / سند صرف)
                  if (widget.initialPurpose != VoucherPurpose.expense)
                    Container(
                      decoration: BoxDecoration(
                        color: RafColors.surface,
                        borderRadius: RafRadius.roundedMd,
                        border: Border.all(color: RafColors.border),
                      ),
                      padding: const EdgeInsets.all(RafSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTypeButton(
                              title: 'سند قبض (توريد)',
                              icon: Icons.call_received_rounded,
                              type: VoucherType.receipt,
                              color: RafColors.success,
                            ),
                          ),
                          const SizedBox(width: RafSpacing.xs),
                          Expanded(
                            child: _buildTypeButton(
                              title: 'سند صرف (صرف)',
                              icon: Icons.call_made_rounded,
                              type: VoucherType.payment,
                              color: RafColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: RafSpacing.md),

                  // Amount Card with Thousands Separator Formatter
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'مبلغ السند',
                                style: RafTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: RafColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: RafSpacing.xs),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: RafColors.surfaceSecondary,
                                  borderRadius: RafRadius.roundedXs,
                                  border: Border.all(color: RafColors.border),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _voucherNumber,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: RafColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RafSpacing.md),
                        TextField(
                          controller: _amountController,
                          key: const ValueKey('voucher_amount'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter(
                              allowDecimals: true,
                              maxDecimalDigits: 2,
                            ),
                          ],
                          style: RafTypography.titleLarge.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _voucherType == VoucherType.receipt
                                ? RafColors.success
                                : RafColors.danger,
                          ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            border: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: BorderSide(
                                color: _voucherType == VoucherType.receipt
                                    ? RafColors.success
                                    : RafColors.danger,
                                width: 2,
                              ),
                            ),
                            fillColor: RafColors.surfaceSecondary,
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Details Card (Party, Payment Method, Statement, Reference)
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
                          'تفاصيل السند',
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: RafColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: RafSpacing.md),

                        if (_voucherType == VoucherType.payment &&
                            widget.initialPurpose !=
                                VoucherPurpose.expense) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('مصروف تشغيلي'),
                            subtitle: const Text(
                              'فعّل للمصروفات، واتركه مغلقاً للسداد أو الصرف العام',
                            ),
                            value: _isExpense,
                            onChanged: (value) => setState(() {
                              _purpose = value
                                  ? VoucherPurpose.expense
                                  : VoucherPurpose.general;
                              if (value) _selectedPartyId = null;
                            }),
                          ),
                        ],
                        if (!_isExpense) ...[
                          // Commercial Party Dropdown
                          Text(
                            'الطرف التجاري (اختياري للصرف العام)',
                            style: RafTypography.bodySmall.copyWith(
                              color: RafColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: RafSpacing.xxs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: RafSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              color: RafColors.surfaceSecondary,
                              borderRadius: RafRadius.roundedMd,
                              border: Border.all(color: RafColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: _selectedPartyId,
                                isExpanded: true,
                                hint: const Text('سند عام / بدون طرف محدد'),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('سند عام / بدون طرف'),
                                  ),
                                  ..._availableParties.map((p) {
                                    return DropdownMenuItem<int?>(
                                      value: p.id,
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '(${p.type.arabicLabel})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: RafColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  setState(() => _selectedPartyId = val);
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: RafSpacing.md),

                          // Payment Method Selector
                        ],
                        if (_isExpense) ...[
                          TextField(
                            key: const Key('expense_category'),
                            controller: _categoryController,
                            maxLength: 60,
                            decoration: const InputDecoration(
                              labelText: 'تصنيف المصروف (اختياري)',
                              hintText: 'إيجار، خدمات، نقل...',
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('expense_date'),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(
                              'تاريخ المصروف: ${_voucherDate.year}/${_voucherDate.month}/${_voucherDate.day}',
                            ),
                            onPressed: () async {
                              final chosen = await showDatePicker(
                                context: context,
                                initialDate: _voucherDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (chosen != null && mounted) {
                                setState(() => _voucherDate = chosen);
                              }
                            },
                          ),
                          const SizedBox(height: RafSpacing.sm),
                        ],
                        Text(
                          'طريقة الدفع',
                          style: RafTypography.bodySmall.copyWith(
                            color: RafColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: RafSpacing.xxs),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: PaymentMethod.values.map((method) {
                              final isSelected = _paymentMethod == method;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: RafSpacing.xs,
                                ),
                                child: ChoiceChip(
                                  label: Text(method.arabicLabel),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    setState(() => _paymentMethod = method);
                                  },
                                  selectedColor: RafColors.primarySubtle,
                                  backgroundColor: RafColors.surfaceSecondary,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? RafColors.primary
                                        : RafColors.textSecondary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: RafRadius.roundedSm,
                                    side: BorderSide(
                                      color: isSelected
                                          ? RafColors.primary
                                          : RafColors.border,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: RafSpacing.md),

                        if (_paymentMethod == PaymentMethod.cheque &&
                            _voucherType == VoucherType.payment)
                          ChequeAccountSelector(
                            value: _chequeAccount,
                            onChanged: (a) =>
                                setState(() => _chequeAccount = a),
                          ),
                        if (_paymentMethod == PaymentMethod.cheque &&
                            _voucherType == VoucherType.receipt)
                          const Text(
                            'الشيك قيد التحصيل ولا يزيد المتاح للصرف قبل تأكيد التحصيل من شاشة الشيكات.',
                          ),

                        // Statement / Notes Field (البيان)
                        Text(
                          'البيان / تفاصيل العملية',
                          style: RafTypography.bodySmall.copyWith(
                            color: RafColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: RafSpacing.xxs),
                        TextField(
                          key: const Key('voucher_statement'),
                          controller: _statementController,
                          decoration: InputDecoration(
                            hintText: _voucherType == VoucherType.receipt
                                ? 'مثال: دفعة تحت الحساب...'
                                : 'مثال: سداد دفعة مورد / مصاريف تشغيلية...',
                            border: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.primary,
                              ),
                            ),
                            fillColor: RafColors.surfaceSecondary,
                            filled: true,
                          ),
                        ),

                        const SizedBox(height: RafSpacing.md),

                        // Reference Number (رقم الحوالة أو الشيك)
                        Text(
                          'رقم المرجع / الحوالة (اختياري)',
                          style: RafTypography.bodySmall.copyWith(
                            color: RafColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: RafSpacing.xxs),
                        TextField(
                          controller: _referenceController,
                          decoration: InputDecoration(
                            hintText: 'رقم الإيصال أو مرجع التحويل...',
                            border: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: RafRadius.roundedMd,
                              borderSide: const BorderSide(
                                color: RafColors.primary,
                              ),
                            ),
                            fillColor: RafColors.surfaceSecondary,
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: RafSpacing.xl),

                  // Save & Post Button
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveVoucher,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                          ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isSaving ? 'جاري الترحيل...' : 'حفظ وترحيل السند',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _voucherType == VoucherType.receipt
                          ? RafColors.success
                          : RafColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: RafRadius.roundedMd,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTypeButton({
    required String title,
    required IconData icon,
    required VoucherType type,
    required Color color,
  }) {
    final isSelected = _voucherType == type;

    return InkWell(
      onTap: () => _onTypeChanged(type),
      borderRadius: RafRadius.roundedSm,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: RafRadius.roundedSm,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : RafColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isSelected ? Colors.white : RafColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
