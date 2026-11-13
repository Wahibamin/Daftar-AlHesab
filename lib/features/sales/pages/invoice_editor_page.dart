import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';
import '../../inventory/models/item_model.dart';
import '../../inventory/repositories/inventory_repository.dart';
import '../../parties/models/party_model.dart';
import '../../parties/repositories/parties_repository.dart';
import '../models/invoice_model.dart';
import '../repositories/invoices_repository.dart';
import '../widgets/invoice_item_tile.dart';
import '../widgets/invoice_summary_bottom_bar.dart';
import '../../../core/widgets/barcode_scanner_dialog.dart';
import '../../accounting/widgets/cheque_account_selector.dart';

/// Clean White UI POS & Invoice Editor Page for RAF ERP.
class InvoiceEditorPage extends StatefulWidget {
  final InvoicesRepository invoicesRepo;
  final InventoryRepository inventoryRepo;
  final PartiesRepository partiesRepo;
  final InvoiceModel? existingInvoice;
  final InvoiceType initialType;

  InvoiceEditorPage({
    super.key,
    InvoicesRepository? invoicesRepo,
    InventoryRepository? inventoryRepo,
    PartiesRepository? partiesRepo,
    this.existingInvoice,
    this.initialType = InvoiceType.sale,
  }) : invoicesRepo = invoicesRepo ?? SqliteInvoicesRepository(),
       inventoryRepo = inventoryRepo ?? SqliteInventoryRepository(),
       partiesRepo = partiesRepo ?? SqlitePartiesRepository();

  @override
  State<InvoiceEditorPage> createState() => _InvoiceEditorPageState();
}

class _InvoiceEditorPageState extends State<InvoiceEditorPage> {
  bool get _isReadOnly =>
      widget.existingInvoice != null && !widget.existingInvoice!.isDraft;
  late InvoiceType _invoiceType;
  late PaymentType _paymentType;
  late PaymentMethod _paymentMethod;
  TreasuryAccount _chequeAccount = TreasuryAccount.bank;
  int? _selectedPartyId;
  String? _selectedPartyName;
  DateTime _invoiceDate = DateTime.now();
  String _invoiceNumber = '';
  Money _additionalDiscount = Money.zero;
  Money _partialPaidAmount = Money.zero;
  String? _paymentInputError;

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _partialPaidController = TextEditingController();

  List<InvoiceItemModel> _items = [];
  List<ItemModel> _availableItems = [];
  Map<int, ItemModel> _itemsCache = {};

  int? _selectedCategoryId;
  String? _selectedCategoryName;

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _showItemPicker = false;
  int _itemSearchToken = 0;

  @override
  void initState() {
    super.initState();
    _invoiceType = widget.existingInvoice?.invoiceType ?? widget.initialType;
    _paymentType = widget.existingInvoice?.paymentType ?? PaymentType.cash;
    _paymentMethod =
        widget.existingInvoice?.paymentMethod ?? PaymentMethod.cash;
    _chequeAccount =
        widget.existingInvoice?.chequeAccount ?? TreasuryAccount.bank;
    _selectedPartyId = widget.existingInvoice?.partyId;

    if (widget.existingInvoice != null) {
      _invoiceNumber = widget.existingInvoice!.invoiceNumber;
      _invoiceDate = widget.existingInvoice!.invoiceDate;
      _items = List.of(widget.existingInvoice!.items ?? []);
      _notesController.text = widget.existingInvoice!.notes ?? '';
      final lineDiscount = _items.fold<Money>(
        Money.zero,
        (sum, item) => sum + item.discount,
      );
      _additionalDiscount = widget.existingInvoice!.discount - lineDiscount;
      _partialPaidAmount = widget.existingInvoice!.paidAmount;
      if (!_partialPaidAmount.isZero) {
        _partialPaidController.text = _partialPaidAmount.toDecimalString();
      }
    }

    _loadInitialData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _searchController.dispose();
    _partialPaidController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      if (_invoiceNumber.isEmpty) {
        _invoiceNumber = await widget.invoicesRepo.generateNextInvoiceNumber(
          _invoiceType,
        );
      }

      if (_selectedPartyId != null) {
        final party = await widget.partiesRepo.getPartyById(_selectedPartyId!);
        _selectedPartyName = party?.name;
      }

      final items = await widget.inventoryRepo.getItems(limit: 50);
      final cache = <int, ItemModel>{};
      for (final item in items) {
        if (item.id != null) {
          cache[item.id!] = item;
        }
      }

      if (mounted) {
        setState(() {
          _availableItems = items;
          _itemsCache = cache;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onTypeChanged(InvoiceType newType) async {
    if (newType == _invoiceType) return;

    final oldIsCustomer =
        (_invoiceType == InvoiceType.sale ||
        _invoiceType == InvoiceType.saleReturn);
    final newIsCustomer =
        (newType == InvoiceType.sale || newType == InvoiceType.saleReturn);

    setState(() {
      _invoiceType = newType;
      if (oldIsCustomer != newIsCustomer) {
        _selectedPartyId = null;
        _selectedPartyName = null;
      }
    });

    final num = await widget.invoicesRepo.generateNextInvoiceNumber(newType);

    if (mounted) {
      setState(() {
        _invoiceNumber = num;
      });
    }
  }

  Future<void> _openPartySearchSheet() async {
    final partyType =
        (_invoiceType == InvoiceType.sale ||
            _invoiceType == InvoiceType.saleReturn)
        ? PartyType.customer
        : PartyType.supplier;
    final isCustomer = partyType == PartyType.customer;

    final initialParties = await widget.partiesRepo.getParties(
      type: partyType,
      limit: 30,
    );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PartySearchModal(
          partiesRepo: widget.partiesRepo,
          partyType: partyType,
          isCustomer: isCustomer,
          selectedPartyId: _selectedPartyId,
          initialParties: initialParties,
          onSelectParty: (party) {
            setState(() {
              _selectedPartyId = party?.id;
              _selectedPartyName = party?.name;
            });
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  Future<void> _openCategoryFilterSheet() async {
    final categories = await widget.inventoryRepo.getCategories();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CategoryFilterModal(
          categories: categories,
          selectedCategoryId: _selectedCategoryId,
          onSelectCategory: (cat) {
            Navigator.of(ctx).pop();
            _filterByCategory(cat);
          },
        );
      },
    );
  }

  Future<void> _filterByCategory(CategoryModel? category) async {
    setState(() {
      _selectedCategoryId = category?.id;
      _selectedCategoryName = category?.name;
      _showItemPicker = true;
    });
    await _searchItems(_searchController.text);
  }

  Future<void> _searchItems(String query) async {
    final token = ++_itemSearchToken;
    try {
      final items = await widget.inventoryRepo.getItems(
        searchQuery: query.trim().isEmpty ? null : query.trim(),
        categoryId: _selectedCategoryId,
        limit: 50,
      );
      if (_itemSearchToken != token || !mounted) return;
      setState(() {
        _availableItems = items;
        for (final it in items) {
          if (it.id != null) {
            _itemsCache[it.id!] = it;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _scanBarcodeAndAddItem() async {
    final code = await BarcodeScannerDialog.scan(
      context,
      title: 'إضافة صنف بالباركود',
      prompt: 'وجّه الكاميرا نحو باركود السلعة لإضافتها مباشرة إلى الفاتورة',
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final trimmed = code.trim();
    final item = await widget.inventoryRepo.getItemByCode(trimmed);
    if (!mounted) return;

    if (item != null) {
      if (item.id != null) {
        _itemsCache[item.id!] = item;
      }
      _addItem(item);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة "${item.name}" إلى الفاتورة'),
          backgroundColor: RafColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يتم العثور على منتج بهذا الباركود ($trimmed)'),
          backgroundColor: RafColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _addItem(ItemModel item) {
    final defaultPrice =
        (_invoiceType == InvoiceType.purchase ||
            _invoiceType == InvoiceType.purchaseReturn)
        ? item.costPrice
        : item.sellingPrice;

    final existingIndex = _items.indexWhere((line) => line.itemId == item.id);
    if (existingIndex != -1) {
      final old = _items[existingIndex];
      final updated = InvoiceItemModel.create(
        id: old.id,
        invoiceId: old.invoiceId,
        itemId: old.itemId,
        quantity: old.quantity + 1,
        unitPrice: old.unitPrice,
        discount: old.discount,
        unitCost: item.costPrice,
      );
      setState(() {
        _items[existingIndex] = updated;
      });
    } else {
      final newLine = InvoiceItemModel.create(
        itemId: item.id!,
        quantity: 1,
        unitPrice: defaultPrice,
        unitCost: item.costPrice,
      );
      setState(() {
        _items.add(newLine);
        _itemsCache[item.id!] = item;
      });
    }
  }

  void _incrementItem(int index) {
    final old = _items[index];
    setState(() {
      _items[index] = InvoiceItemModel.create(
        id: old.id,
        invoiceId: old.invoiceId,
        itemId: old.itemId,
        quantity: old.quantity + 1,
        unitPrice: old.unitPrice,
        discount: old.discount,
        unitCost: old.unitCost,
      );
    });
  }

  void _decrementItem(int index) {
    final old = _items[index];
    if (old.quantity > 1) {
      setState(() {
        _items[index] = InvoiceItemModel.create(
          id: old.id,
          invoiceId: old.invoiceId,
          itemId: old.itemId,
          quantity: old.quantity - 1,
          unitPrice: old.unitPrice,
          discount: old.discount,
          unitCost: old.unitCost,
        );
      });
    } else {
      _removeItem(index);
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  InvoiceModel _buildCurrentInvoice({
    InvoiceStatus status = InvoiceStatus.draft,
  }) {
    if (_isReadOnly && widget.existingInvoice != null) {
      return widget.existingInvoice!.copyWith(items: _items);
    }
    final now = DateTime.now();

    final temp = InvoiceModel.buildWithItems(
      id: widget.existingInvoice?.id,
      invoiceNumber: _invoiceNumber,
      partyId: _selectedPartyId,
      invoiceType: _invoiceType,
      status: status,
      paymentType: _paymentType,
      paymentMethod: _paymentMethod,
      chequeAccount: _chequeAccount,
      items: _items,
      additionalDiscount: _additionalDiscount,
      paidAmount: Money.zero,
      invoiceDate: _invoiceDate,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: widget.existingInvoice?.createdAt ?? now,
      updatedAt: now,
    );

    final Money paid;
    if (_paymentType == PaymentType.cash) {
      paid = temp.total;
    } else if (_paymentType == PaymentType.credit) {
      paid = Money.zero;
    } else {
      paid = _partialPaidAmount;
    }

    return InvoiceModel.buildWithItems(
      id: widget.existingInvoice?.id,
      invoiceNumber: _invoiceNumber,
      partyId: _selectedPartyId,
      invoiceType: _invoiceType,
      status: status,
      paymentType: _paymentType,
      paymentMethod: _paymentMethod,
      chequeAccount: _chequeAccount,
      items: _items,
      additionalDiscount: _additionalDiscount,
      paidAmount: paid,
      invoiceDate: _invoiceDate,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: widget.existingInvoice?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _saveAsDraft() async {
    if (_isReadOnly || _isProcessing) return;
    if (_items.isEmpty) {
      _showWarning('يرجى إضافة صنف واحد على الأقل لحفظ الفاتورة');
      return;
    }

    if (!_validateFinancialInput()) return;

    setState(() => _isProcessing = true);
    try {
      final invoice = _buildCurrentInvoice(status: InvoiceStatus.draft);
      if (widget.existingInvoice?.id != null) {
        await widget.invoicesRepo.updateInvoice(invoice);
      } else {
        await widget.invoicesRepo.createInvoice(invoice);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الفاتورة كمسودة بنجاح'),
            backgroundColor: RafColors.primary,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showWarning('تعذر حفظ الفاتورة: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _finalizeInvoice() async {
    if (_isReadOnly || _isProcessing) return;
    if (_items.isEmpty) {
      _showWarning('يرجى إضافة صنف واحد على الأقل لترحيل الفاتورة');
      return;
    }

    if (_paymentType == PaymentType.credit && _selectedPartyId == null) {
      _showWarning('يجب تحديد العميل أو المورد للفواتير الآجلة');
      return;
    }

    if (!_validateFinancialInput()) return;
    final invoice = _buildCurrentInvoice(status: InvoiceStatus.approved);

    if (_paymentType == PaymentType.partial) {
      if (_selectedPartyId == null) {
        _showWarning('يجب تحديد العميل أو المورد للفواتير ذات السداد الجزئي');
        return;
      }
      if (invoice.paidAmount.isZero || invoice.paidAmount.isNegative) {
        _showWarning('يجب أن يكون المبلغ المدفوع أكبر من صفر في السداد الجزئي');
        return;
      }
      if (invoice.paidAmount >= invoice.total) {
        _showWarning(
          'يجب أن يكون المبلغ المدفوع أقل من إجمالي الفاتورة في السداد الجزئي (أو اختر السداد الكامل)',
        );
        return;
      }
    }

    setState(() => _isProcessing = true);
    try {
      await widget.invoicesRepo.saveAndFinalizeInvoice(invoice);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم اعتماد وترحيل الفاتورة وتحديث المخزون بنجاح'),
            backgroundColor: RafColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showWarning('تعذر اعتماد الفاتورة: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: RafColors.danger),
    );
  }

  bool _validateFinancialInput() {
    if ((_paymentType == PaymentType.partial ||
            _paymentType == PaymentType.transfer) &&
        _paymentInputError != null) {
      _showWarning(_paymentInputError!);
      return false;
    }
    try {
      _buildCurrentInvoice().validateAmounts();
      return true;
    } on ArgumentError catch (error) {
      _showWarning(error.message.toString());
      return false;
    }
  }

  Future<void> _showDiscountDialog() async {
    final controller = TextEditingController(
      text: _additionalDiscount.isZero
          ? ''
          : _additionalDiscount.toDecimalString(),
    );
    String? discountError;
    final result = await showDialog<Money>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: RafColors.surface,
          shape: RoundedRectangleBorder(borderRadius: RafRadius.roundedMd),
          title: const Text('خصم إضافي على الفاتورة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'قيمة الخصم',
                    errorText: discountError,
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RafColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final money = Money.tryParse(controller.text);
                final available = _items.fold<Money>(
                  Money.zero,
                  (sum, item) => sum + item.totalPrice,
                );
                if (money == null || money.isNegative || money > available) {
                  setDialogState(
                    () => discountError =
                        'أدخل خصماً صحيحاً بين صفر وقيمة الفاتورة',
                  );
                  return;
                }
                Navigator.of(ctx).pop(money);
              },
              child: const Text('تطبيق الخصم'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _additionalDiscount = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = _isReadOnly;
    final currentInvoice = isReadOnly
        ? widget.existingInvoice!
        : _buildCurrentInvoice();

    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existingInvoice != null
                  ? (isReadOnly ? 'عرض فاتورة' : 'تعديل فاتورة')
                  : 'نقطة البيع والفوترة',
              style: RafTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _invoiceNumber.isNotEmpty ? _invoiceNumber : 'فاتورة جديدة',
              style: RafTypography.labelSmall.copyWith(
                color: RafColors.textSecondary,
              ),
            ),
          ],
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        actions: [
          if (isReadOnly)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RafSpacing.md,
                vertical: 12,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: RafColors.successSubtle,
                  borderRadius: RafRadius.roundedPill,
                  border: Border.all(color: RafColors.successBorder),
                ),
                child: Text(
                  widget.existingInvoice!.status.arabicLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: RafColors.success,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RafColors.primary),
            )
          : Column(
              children: [
                // Header Settings Container (Type, Party, Payment Method)
                _buildInvoiceHeaderCard(isReadOnly, currentInvoice),

                if (isReadOnly && !currentInvoice.allocatedAmount.isZero)
                  ListTile(
                    dense: true,
                    title: Text(
                      'سداد مخصص من سندات القبض: ${CurrencyFormatter.format(currentInvoice.allocatedAmount)}',
                    ),
                    subtitle: Text(
                      'دفعة الإصدار: ${CurrencyFormatter.format(currentInvoice.paidAmount)} · المتبقي الفعلي: ${CurrencyFormatter.format(currentInvoice.remainingAmount)}',
                    ),
                  ),

                // Item Search and Category Filter Bar
                if (!isReadOnly) _buildItemSearchBar(),

                // Line Items List
                Expanded(child: _buildItemsList(isReadOnly)),

                // Floating Summary Bottom Bar
                InvoiceSummaryBottomBar(
                  subtotal: currentInvoice.subtotal,
                  discount: currentInvoice.discount,
                  netTotal: currentInvoice.total,
                  itemCount: _items.length,
                  onFinalize: _finalizeInvoice,
                  onSaveDraft: _saveAsDraft,
                  onEditDiscount: _showDiscountDialog,
                  isProcessing: _isProcessing,
                  isReadOnly: isReadOnly,
                ),
              ],
            ),
    );
  }

  Widget _buildInvoiceHeaderCard(bool isReadOnly, InvoiceModel currentInvoice) {
    final isShort = MediaQuery.sizeOf(context).height < 650;
    final isCustomer =
        (_invoiceType == InvoiceType.sale ||
        _invoiceType == InvoiceType.saleReturn);
    final partyLabel = _selectedPartyId == null
        ? (isCustomer ? 'عميل نقدي عام (افتراضي)' : 'مورد عام (نقدي)')
        : (_selectedPartyName ?? (isCustomer ? 'عميل محدد' : 'مورد محدد'));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: RafSpacing.md,
        vertical: isShort ? RafSpacing.xs : RafSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: RafColors.surface,
        border: Border(bottom: BorderSide(color: RafColors.border)),
      ),
      child: Column(
        children: [
          // Row 1: Invoice Type Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: InvoiceType.values.map((type) {
                final isSelected = _invoiceType == type;
                return Padding(
                  padding: const EdgeInsets.only(left: RafSpacing.xs),
                  child: ChoiceChip(
                    label: Text(type.arabicLabel),
                    selected: isSelected,
                    onSelected: isReadOnly ? null : (_) => _onTypeChanged(type),
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

          const SizedBox(height: RafSpacing.xs),

          // Row 2: Searchable Party Selector & Payment Switcher
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final isNarrow = constraints.maxWidth < 400 || textScale > 1.2;

              final partySelectorWidget = InkWell(
                key: const Key('invoice_party_selector'),
                onTap: isReadOnly ? null : _openPartySearchSheet,
                borderRadius: RafRadius.roundedSm,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: RafSpacing.sm,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: RafColors.surfaceSecondary,
                    borderRadius: RafRadius.roundedSm,
                    border: Border.all(color: RafColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCustomer
                            ? Icons.person_outline
                            : Icons.store_outlined,
                        size: 18,
                        color: RafColors.primary,
                      ),
                      const SizedBox(width: RafSpacing.xs),
                      Expanded(
                        child: Text(
                          partyLabel,
                          style: RafTypography.bodySmall.copyWith(
                            fontWeight: _selectedPartyId == null
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: _selectedPartyId == null
                                ? RafColors.textSecondary
                                : RafColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isReadOnly)
                        const Icon(
                          Icons.search,
                          size: 18,
                          color: RafColors.textMuted,
                        ),
                    ],
                  ),
                ),
              );

              final paymentSwitch = Container(
                decoration: BoxDecoration(
                  color: RafColors.surfaceSecondary,
                  borderRadius: RafRadius.roundedSm,
                  border: Border.all(color: RafColors.border),
                ),
                child: Row(
                  mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    isNarrow
                        ? Expanded(
                            child: _buildPaymentChip(
                              'كامل',
                              PaymentType.cash,
                              isReadOnly,
                            ),
                          )
                        : _buildPaymentChip(
                            'كامل',
                            PaymentType.cash,
                            isReadOnly,
                          ),
                    isNarrow
                        ? Expanded(
                            child: _buildPaymentChip(
                              'آجل',
                              PaymentType.credit,
                              isReadOnly,
                            ),
                          )
                        : _buildPaymentChip(
                            'آجل',
                            PaymentType.credit,
                            isReadOnly,
                          ),
                    isNarrow
                        ? Expanded(
                            child: _buildPaymentChip(
                              'جزئي',
                              PaymentType.partial,
                              isReadOnly,
                            ),
                          )
                        : _buildPaymentChip(
                            'جزئي',
                            PaymentType.partial,
                            isReadOnly,
                          ),
                    if (_paymentType != PaymentType.credit)
                      PopupMenuButton<PaymentMethod>(
                        key: const Key('invoice_payment_method'),
                        tooltip: 'وسيلة الدفع',
                        enabled: !isReadOnly,
                        onSelected: (method) =>
                            setState(() => _paymentMethod = method),
                        itemBuilder: (_) => PaymentMethod.values
                            .map(
                              (method) => PopupMenuItem(
                                value: method,
                                child: Text(method.arabicLabel),
                              ),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: SizedBox(
                            width: 72,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(_paymentMethod.arabicLabel),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    partySelectorWidget,
                    const SizedBox(height: RafSpacing.xs),
                    paymentSwitch,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 6, child: partySelectorWidget),
                  const SizedBox(width: RafSpacing.sm),
                  paymentSwitch,
                ],
              );
            },
          ),

          if (_paymentMethod == PaymentMethod.cheque &&
              _paymentType != PaymentType.credit)
            if (_invoiceType == InvoiceType.purchase ||
                _invoiceType == InvoiceType.saleReturn)
              ChequeAccountSelector(
                value: _chequeAccount,
                onChanged: isReadOnly
                    ? null
                    : (a) => setState(() => _chequeAccount = a),
              )
            else
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'قيمة الشيك ليست سيولة متاحة حتى تأكيد تحصيله من شاشة الشيكات.',
                ),
              ),

          // Row 3: Partial Payment Input & Remaining (Visible when partial is selected)
          if (_paymentType == PaymentType.partial ||
              _paymentType == PaymentType.transfer) ...[
            const SizedBox(height: RafSpacing.xs),
            Container(
              padding: const EdgeInsets.all(RafSpacing.sm),
              decoration: BoxDecoration(
                color: RafColors.surfaceSecondary,
                borderRadius: RafRadius.roundedSm,
                border: Border.all(color: RafColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      key: const Key('partial_paid_input'),
                      controller: _partialPaidController,
                      enabled: !isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'المبلغ المدفوع',
                        errorText: _paymentInputError,
                        hintText: '0.00',
                        prefixIcon: const Icon(
                          Icons.payments_outlined,
                          size: 18,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = Money.tryParse(val);
                        setState(() {
                          _paymentInputError =
                              parsed == null || parsed.isNegative
                              ? 'أدخل مبلغاً صحيحاً غير سالب'
                              : null;
                          if (parsed != null && !parsed.isNegative) {
                            _partialPaidAmount = parsed;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: RafSpacing.sm),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('المتبقي الآجل', style: RafTypography.labelSmall),
                        Text(
                          CurrencyFormatter.format(
                            currentInvoice.remainingAmount,
                          ),
                          style: RafTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: RafColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentChip(String label, PaymentType type, bool isReadOnly) {
    final isSelected = _paymentType == type;
    return InkWell(
      onTap: isReadOnly
          ? null
          : () {
              setState(() {
                _paymentType = type;
                if (type == PaymentType.cash) {
                  _partialPaidAmount = Money.zero;
                  _partialPaidController.clear();
                } else if (type == PaymentType.credit) {
                  _partialPaidAmount = Money.zero;
                  _partialPaidController.clear();
                }
              });
            },
      borderRadius: RafRadius.roundedSm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? RafColors.primary : Colors.transparent,
          borderRadius: RafRadius.roundedSm,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : RafColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildItemSearchBar() {
    return Container(
      color: RafColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: RafSpacing.md,
        vertical: RafSpacing.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: _selectedCategoryId != null
                  ? 'بحث في ${_selectedCategoryName ?? 'التصنيف'} بالاسم أو الكود...'
                  : 'ابحث عن صنف بالاسم أو الباركود للإضافة...',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: RafColors.textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _searchItems('');
                      },
                    ),
                  IconButton(
                    key: const Key('invoice_scan_barcode_button'),
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      color: RafColors.primary,
                      size: 20,
                    ),
                    tooltip: 'مسح الباركود بالكاميرا',
                    onPressed: _scanBarcodeAndAddItem,
                  ),
                  IconButton(
                    key: const Key('category_filter_button'),
                    icon: Icon(
                      Icons.expand_more,
                      color: _selectedCategoryId != null
                          ? RafColors.primary
                          : RafColors.textSecondary,
                    ),
                    tooltip: 'قائمة التصنيفات',
                    onPressed: _openCategoryFilterSheet,
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: RafRadius.roundedMd,
                borderSide: const BorderSide(color: RafColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: RafRadius.roundedMd,
                borderSide: const BorderSide(color: RafColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: RafRadius.roundedMd,
                borderSide: const BorderSide(color: RafColors.primary),
              ),
              fillColor: RafColors.surfaceSecondary,
              filled: true,
            ),
            onChanged: (val) {
              setState(() {
                _showItemPicker = true;
              });
              _searchItems(val);
            },
          ),
          if (_selectedCategoryId != null)
            Container(
              margin: const EdgeInsets.only(top: RafSpacing.xxs),
              child: Row(
                children: [
                  Chip(
                    key: const Key('active_category_chip'),
                    label: Text('التصنيف: $_selectedCategoryName'),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _filterByCategory(null),
                    backgroundColor: RafColors.primarySubtle,
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: RafColors.primary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          if (_showItemPicker) _buildFilteredItemsDropdown(),
        ],
      ),
    );
  }

  Widget _buildFilteredItemsDropdown() {
    if (_availableItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(RafSpacing.md),
        decoration: BoxDecoration(
          color: RafColors.surface,
          borderRadius: RafRadius.roundedMd,
          border: Border.all(color: RafColors.border),
        ),
        child: Text(
          _selectedCategoryId != null
              ? 'لا توجد أصناف في هذا التصنيف'
              : 'لم يتم العثور على أصناف مطابقة للبحث',
          style: const TextStyle(fontSize: 13, color: RafColors.textSecondary),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.only(top: RafSpacing.xs),
      decoration: BoxDecoration(
        color: RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(color: RafColors.border),
        boxShadow: RafShadows.subtle,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _availableItems.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: RafColors.border),
        itemBuilder: (ctx, i) {
          final item = _availableItems[i];
          final price =
              (_invoiceType == InvoiceType.purchase ||
                  _invoiceType == InvoiceType.purchaseReturn)
              ? item.costPrice
              : item.sellingPrice;

          return ListTile(
            dense: true,
            title: Text(
              item.name,
              style: RafTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'كود: ${item.code} | متاح: ${item.stockQuantity}',
              style: RafTypography.bodySmall.copyWith(
                color: RafColors.textSecondary,
              ),
            ),
            trailing: Text(
              CurrencyFormatter.format(price),
              style: RafTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: RafColors.primary,
              ),
            ),
            onTap: () => _addItem(item),
          );
        },
      ),
    );
  }

  Widget _buildItemsList(bool isReadOnly) {
    if (_items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: RafSpacing.lg,
            vertical: RafSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 44,
                color: RafColors.textMuted.withValues(alpha: 0.6),
              ),
              const SizedBox(height: RafSpacing.sm),
              Text(
                'الفاتورة فارغة',
                style: RafTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: RafColors.textSecondary,
                ),
              ),
              const SizedBox(height: RafSpacing.xs),
              Text(
                'ابحث عن صنف بالاسم أو الباركود لإضافته إلى الفاتورة',
                textAlign: TextAlign.center,
                style: RafTypography.bodySmall.copyWith(
                  color: RafColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(RafSpacing.md),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final line = _items[index];
        final cachedItem = _itemsCache[line.itemId];
        final name = cachedItem?.name ?? 'صنف #${line.itemId}';

        return InvoiceItemTile(
          item: line,
          itemName: name,
          onIncrement: isReadOnly ? null : () => _incrementItem(index),
          onDecrement: isReadOnly ? null : () => _decrementItem(index),
          onRemove: isReadOnly ? null : () => _removeItem(index),
        );
      },
    );
  }
}

/// Searchable Party Selection Modal Sheet for Live Search by Name or Phone
class _PartySearchModal extends StatefulWidget {
  final PartiesRepository partiesRepo;
  final PartyType partyType;
  final bool isCustomer;
  final int? selectedPartyId;
  final List<PartyModel> initialParties;
  final ValueChanged<PartyModel?> onSelectParty;

  const _PartySearchModal({
    required this.partiesRepo,
    required this.partyType,
    required this.isCustomer,
    required this.selectedPartyId,
    required this.initialParties,
    required this.onSelectParty,
  });

  @override
  State<_PartySearchModal> createState() => _PartySearchModalState();
}

class _PartySearchModalState extends State<_PartySearchModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<PartyModel> _results;
  bool _isLoading = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _results = widget.initialParties;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final token = ++_searchToken;
    setState(() => _isLoading = true);

    try {
      final list = await widget.partiesRepo.getParties(
        type: widget.partyType,
        searchQuery: query.trim().isEmpty ? null : query.trim(),
        limit: 30,
      );
      if (_searchToken != token || !mounted) return;
      setState(() {
        _results = list;
        _isLoading = false;
      });
    } catch (_) {
      if (_searchToken != token || !mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        height: mediaQuery.size.height * 0.75,
        decoration: const BoxDecoration(
          color: RafColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RafRadius.lg),
          ),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(
                top: RafSpacing.sm,
                bottom: RafSpacing.xs,
              ),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: RafColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header Title
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RafSpacing.md,
                vertical: RafSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isCustomer
                        ? Icons.person_search
                        : Icons.store_mall_directory_outlined,
                    color: RafColors.primary,
                  ),
                  const SizedBox(width: RafSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.isCustomer ? 'اختيار العميل' : 'اختيار المورد',
                      style: RafTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Search Input Field
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RafSpacing.md,
                vertical: RafSpacing.xs,
              ),
              child: TextField(
                key: const Key('party_search_field'),
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: widget.isCustomer
                      ? 'ابحث عن اسم العميل أو الهاتف...'
                      : 'ابحث عن اسم المورد أو الهاتف...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _performSearch('');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _performSearch,
              ),
            ),
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: RafColors.primary,
                backgroundColor: RafColors.surfaceSecondary,
              ),
            const Divider(height: 1, color: RafColors.border),
            // Cash Customer / General Supplier default tile
            ListTile(
              key: const Key('party_default_tile'),
              leading: CircleAvatar(
                backgroundColor: widget.selectedPartyId == null
                    ? RafColors.primarySubtle
                    : RafColors.surfaceSecondary,
                child: Icon(
                  Icons.person_outline,
                  color: widget.selectedPartyId == null
                      ? RafColors.primary
                      : RafColors.textSecondary,
                ),
              ),
              title: Text(
                widget.isCustomer
                    ? 'عميل نقدي عام (افتراضي)'
                    : 'مورد عام (نقدي)',
                style: TextStyle(
                  fontWeight: widget.selectedPartyId == null
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: widget.selectedPartyId == null
                      ? RafColors.primary
                      : RafColors.textPrimary,
                ),
              ),
              subtitle: const Text('معاملة نقدية غير مقيدة على حساب طرف'),
              trailing: widget.selectedPartyId == null
                  ? const Icon(Icons.check, color: RafColors.primary)
                  : null,
              onTap: () => widget.onSelectParty(null),
            ),
            const Divider(height: 1, color: RafColors.border),
            // Results list
            Expanded(
              child: _results.isEmpty && !_isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 40,
                            color: RafColors.textMuted,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          Text(
                            'لا توجد نتائج مطابقة للبحث',
                            style: RafTypography.bodySmall.copyWith(
                              color: RafColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: RafColors.border),
                      itemBuilder: (ctx, i) {
                        final party = _results[i];
                        final isSelected = party.id == widget.selectedPartyId;
                        return ListTile(
                          key: Key('party_tile_${party.id}'),
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? RafColors.primarySubtle
                                : RafColors.surfaceSecondary,
                            child: Text(
                              party.name.isNotEmpty
                                  ? party.name.characters.first
                                  : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? RafColors.primary
                                    : RafColors.textPrimary,
                              ),
                            ),
                          ),
                          title: Text(
                            party.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? RafColors.primary
                                  : RafColors.textPrimary,
                            ),
                          ),
                          subtitle: party.phone.isNotEmpty
                              ? Text(
                                  party.phone,
                                  style: RafTypography.bodySmall,
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (party.currentBalance != Money.zero)
                                Text(
                                  CurrencyFormatter.format(
                                    party.currentBalance,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: party.currentBalance.isNegative
                                        ? RafColors.danger
                                        : RafColors.success,
                                  ),
                                ),
                              if (isSelected) ...[
                                const SizedBox(width: RafSpacing.xs),
                                const Icon(
                                  Icons.check,
                                  color: RafColors.primary,
                                ),
                              ],
                            ],
                          ),
                          onTap: () => widget.onSelectParty(party),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category Selection Modal Sheet for Filtering Active Items by Category
class _CategoryFilterModal extends StatelessWidget {
  final List<CategoryModel> categories;
  final int? selectedCategoryId;
  final ValueChanged<CategoryModel?> onSelectCategory;

  const _CategoryFilterModal({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: RafColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(RafRadius.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(
              top: RafSpacing.sm,
              bottom: RafSpacing.xs,
            ),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: RafColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: RafSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(Icons.category_outlined, color: RafColors.primary),
                const SizedBox(width: RafSpacing.xs),
                Expanded(
                  child: Text(
                    'تصفية الأصناف حسب التصنيف',
                    style: RafTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RafColors.border),
          ListTile(
            key: const Key('all_categories_tile'),
            leading: Icon(
              Icons.apps,
              color: selectedCategoryId == null
                  ? RafColors.primary
                  : RafColors.textSecondary,
            ),
            title: Text(
              'جميع التصنيفات',
              style: TextStyle(
                fontWeight: selectedCategoryId == null
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selectedCategoryId == null
                    ? RafColors.primary
                    : RafColors.textPrimary,
              ),
            ),
            trailing: selectedCategoryId == null
                ? const Icon(Icons.check, color: RafColors.primary)
                : null,
            onTap: () => onSelectCategory(null),
          ),
          const Divider(height: 1, color: RafColors.border),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: categories.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: RafColors.border),
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                final isSelected = cat.id == selectedCategoryId;
                return ListTile(
                  key: Key('category_tile_${cat.id}'),
                  title: Text(
                    cat.name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? RafColors.primary
                          : RafColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: RafColors.primary)
                      : null,
                  onTap: () => onSelectCategory(cat),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
