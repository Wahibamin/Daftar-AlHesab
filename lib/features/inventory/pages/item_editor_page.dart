import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/money.dart';
import '../data/inventory_repository.dart';
import '../models/item_model.dart';
import '../widgets/barcode_label_dialog.dart';
import '../../../core/services/barcode_generator_service.dart';
import '../../../core/widgets/barcode_scanner_dialog.dart';

/// Screen for creating a new product or editing an existing inventory item.
class ItemEditorPage extends StatefulWidget {
  final ItemModel? itemToEdit;
  final InventoryRepository? repository;
  final List<CategoryModel>? initialCategories;
  final List<UnitModel>? initialUnits;

  const ItemEditorPage({
    super.key,
    this.itemToEdit,
    this.repository,
    this.initialCategories,
    this.initialUnits,
  });

  @override
  State<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends State<ItemEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final InventoryRepository _repo;

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _initialStockController;
  late final TextEditingController _minAlertLimitController;

  List<CategoryModel> _categories = [];
  List<UnitModel> _units = [];

  int? _selectedCategoryId;
  int? _selectedUnitId;
  DateTime? _selectedExpiryDate;

  bool _isLoading = true;
  bool _isSaving = false;

  bool get _isEditing => widget.itemToEdit != null;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqliteInventoryRepository();

    final item = widget.itemToEdit;
    _nameController = TextEditingController(text: item?.name ?? '');
    _codeController = TextEditingController(text: item?.code ?? '');
    _costPriceController = TextEditingController(
      text: item != null
          ? ThousandsSeparatorInputFormatter.formatRawUnits(item.costPriceInt)
          : '',
    );
    _sellingPriceController = TextEditingController(
      text: item != null
          ? ThousandsSeparatorInputFormatter.formatRawUnits(
              item.sellingPriceInt,
            )
          : '',
    );
    _initialStockController = TextEditingController(
      text: item != null ? item.stockQuantity.toString() : '0',
    );
    _minAlertLimitController = TextEditingController(
      text: item != null ? item.minAlertLimit.toString() : '5',
    );

    _selectedCategoryId = item?.categoryId;
    _selectedUnitId = item?.unitId;
    _selectedExpiryDate = item?.expiryDate;

    if (widget.initialCategories != null && widget.initialUnits != null) {
      _categories = widget.initialCategories!;
      _units = widget.initialUnits!;
      _isLoading = false;
      if (_selectedUnitId == null && _units.isNotEmpty) {
        final activeUnits = _units.where((u) => !u.isArchived).toList();
        _selectedUnitId = activeUnits.isNotEmpty
            ? activeUnits.first.id
            : _units.first.id;
      }
      if (_selectedCategoryId == null && _categories.isNotEmpty) {
        final activeCats = _categories.where((c) => !c.isArchived).toList();
        _selectedCategoryId = activeCats.isNotEmpty
            ? activeCats.first.id
            : _categories.first.id;
      }
    } else {
      _loadMetadata();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _initialStockController.dispose();
    _minAlertLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final cats = await _repo.getCategories();
      final uns = await _repo.getUnits();

      if (mounted) {
        setState(() {
          _categories = cats;
          _units = uns;

          if (_selectedUnitId == null && uns.isNotEmpty) {
            final activeUnits = uns.where((u) => !u.isArchived).toList();
            _selectedUnitId = activeUnits.isNotEmpty
                ? activeUnits.first.id
                : uns.first.id;
          }
          if (_selectedCategoryId == null && cats.isNotEmpty) {
            final activeCats = cats.where((c) => !c.isArchived).toList();
            _selectedCategoryId = activeCats.isNotEmpty
                ? activeCats.first.id
                : cats.first.id;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateUniqueBarcode() async {
    final uniqueCode =
        await BarcodeGeneratorService.generateUniqueInternalBarcode(_repo);
    if (mounted) {
      setState(() {
        _codeController.text = uniqueCode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم توليد باركود داخلي فريد بنجاح'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _generateRandomBarcode() {
    _generateUniqueBarcode();
  }

  Future<void> _scanBarcode() async {
    final scannedCode = await BarcodeScannerDialog.scan(context);
    if (scannedCode == null || scannedCode.trim().isEmpty || !mounted) return;

    final trimmed = scannedCode.trim();

    // Check if this barcode already exists in the database
    final existing = await _repo.getItemByCode(trimmed);
    if (existing != null) {
      if (!_isEditing) {
        // Scanned an existing item while creating a new item
        if (!mounted) return;
        final openExisting = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'الباركود مستخدم مسبقاً',
              style: RafTypography.titleMedium,
            ),
            content: Text(
              'هذا الباركود ($trimmed) مسجل مسبقاً لصنف موجود:\n"${existing.name}"\n\nهل ترغب في فتح بيانات الصنف الحالي؟',
            ),
            actions: [
              TextButton(
                key: const Key('cancel_open_existing_item_button'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                key: const Key('open_existing_item_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RafColors.primary,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('فتح الصنف الموجود'),
              ),
            ],
          ),
        );

        if (openExisting == true && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ItemEditorPage(
                itemToEdit: existing,
                repository: _repo,
                initialCategories: _categories,
                initialUnits: _units,
              ),
            ),
          );
        }
        return;
      } else {
        // Editing an existing item - conflict if belongs to another item
        if (existing.id != widget.itemToEdit?.id) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'الباركود مستخدم بالفعل لصنف آخر: "${existing.name}"',
                ),
                backgroundColor: RafColors.danger,
              ),
            );
          }
          return;
        }
      }
    }

    // Set scanned code
    setState(() {
      _codeController.text = trimmed;
    });
  }

  void _openPrintBarcodeDialog() {
    final item = widget.itemToEdit;
    if (item == null) return;
    final unit = _units.where((u) => u.id == _selectedUnitId).firstOrNull;
    BarcodeLabelDialog.show(
      context,
      item: item.copyWith(
        code: _codeController.text.trim().isNotEmpty
            ? _codeController.text.trim()
            : item.code,
        name: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : item.name,
        sellingPrice: _currentSellingMoney,
      ),
      unitSymbol: unit?.cleanSymbol,
    );
  }

  Future<void> _showAddUnitDialog() async {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    final factorCtrl = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<UnitModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إضافة وحدة قياس جديدة',
          style: RafTypography.titleMedium,
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الوحدة *',
                  hintText: 'مثال: متر، باكت، كرتون',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'أدخل اسم الوحدة'
                    : null,
              ),
              const SizedBox(height: RafSpacing.sm),
              TextFormField(
                controller: symbolCtrl,
                decoration: const InputDecoration(
                  labelText: 'رمز / اختصار الوحدة *',
                  hintText: 'مثال: م، باكت، ctn',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'أدخل رمز الوحدة'
                    : null,
              ),
              const SizedBox(height: RafSpacing.sm),
              TextFormField(
                controller: factorCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'معامل التحويل',
                  hintText: '1',
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
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                final factor = int.tryParse(factorCtrl.text.trim()) ?? 1;
                final unit = UnitModel(
                  name: nameCtrl.text.trim(),
                  symbol: symbolCtrl.text.trim(),
                  conversionFactor: factor > 0 ? factor : 1,
                  createdAt: DateTime.now(),
                );
                Navigator.of(ctx).pop(unit);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (created != null) {
      try {
        final newId = await _repo.insertUnit(created);
        final uns = await _repo.getUnits();
        if (mounted) {
          setState(() {
            _units = uns;
            _selectedUnitId = newId;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت إضافة وحدة القياس "${created.name}" بنجاح'),
              backgroundColor: RafColors.success,
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<CategoryModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة تصنيف جديد', style: RafTypography.titleMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم التصنيف *',
                  hintText: 'مثال: بهارات، أدوات منزلية',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'أدخل اسم التصنيف'
                    : null,
              ),
              const SizedBox(height: RafSpacing.sm),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'الوصف (اختياري)',
                  hintText: 'وصف مختصر للتصنيف',
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
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                final cat = CategoryModel(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  createdAt: DateTime.now(),
                );
                Navigator.of(ctx).pop(cat);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (created != null) {
      try {
        final newId = await _repo.insertCategory(created);
        final cats = await _repo.getCategories();
        if (mounted) {
          setState(() {
            _categories = cats;
            _selectedCategoryId = newId;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت إضافة التصنيف "${created.name}" بنجاح'),
              backgroundColor: RafColors.success,
            ),
          );
        }
      } catch (_) {}
    }
  }

  Money get _currentCostMoney =>
      ThousandsSeparatorInputFormatter.extractMoney(_costPriceController.text);

  Money get _currentSellingMoney =>
      ThousandsSeparatorInputFormatter.extractMoney(
        _sellingPriceController.text,
      );

  Money get _expectedMargin => _currentSellingMoney - _currentCostMoney;

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryDate ?? now.add(const Duration(days: 180)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 10)),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: RafColors.primary,
              onPrimary: Colors.white,
              surface: RafColors.surface,
              onSurface: RafColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedExpiryDate = picked);
    }
  }

  Future<void> _saveItem() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد وحدة القياس'),
          backgroundColor: RafColors.danger,
        ),
      );
      return;
    }

    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final costPrice = _currentCostMoney;
    final sellingPrice = _currentSellingMoney;
    final initialStock = ThousandsSeparatorInputFormatter.extractInteger(
      _initialStockController.text,
    );
    final minAlert = ThousandsSeparatorInputFormatter.extractInteger(
      _minAlertLimitController.text,
    );

    // Validate duplicate barcode on creation and edit
    final existing = await _repo.getItemByCode(code);
    if (existing != null) {
      final isConflict =
          !_isEditing ||
          (widget.itemToEdit != null && existing.id != widget.itemToEdit!.id);
      if (isConflict && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'الباركود مستخدم بالفعل لصنف آخر: "${existing.name}"',
            ),
            backgroundColor: RafColors.danger,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();

    try {
      if (_isEditing) {
        final updated = widget.itemToEdit!.copyWith(
          code: code,
          name: name,
          unitId: _selectedUnitId!,
          categoryId: _selectedCategoryId,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          minAlertLimit: minAlert,
          // Explicit null means the user cleared the date, not "keep old date".
          expiryDate: _selectedExpiryDate,
          updatedAt: now,
        );
        await _repo.updateItem(updated);
      } else {
        final newItem = ItemModel(
          code: code,
          name: name,
          unitId: _selectedUnitId!,
          categoryId: _selectedCategoryId,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          stockQuantity: initialStock,
          minAlertLimit: minAlert,
          expiryDate: _selectedExpiryDate,
          createdAt: now,
          updatedAt: now,
        );
        await _repo.insertItem(newItem, initialStock: initialStock);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء حفظ الصنف: $e'),
            backgroundColor: RafColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: RafColors.primary),
        ),
      );
    }

    final margin = _expectedMargin;
    final isLoss = margin.isNegative;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: RafSpacing.xs,
        title: Text(
          _isEditing ? 'تعديل بيانات الصنف' : 'إضافة صنف جديد',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isEditing && widget.itemToEdit != null)
            IconButton(
              key: const Key('appbar_print_barcode_button'),
              icon: const Icon(Icons.print_outlined),
              tooltip: 'طباعة ملصق الباركود',
              onPressed: _openPrintBarcodeDialog,
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: RafSpacing.sm),
            child: _isSaving
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: RafSpacing.sm),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RafColors.primary,
                        ),
                      ),
                    ),
                  )
                : FilledButton.tonalIcon(
                    key: const Key('appbar_save_item_button'),
                    onPressed: _isSaving ? null : _saveItem,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('حفظ'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(RafSpacing.lg),
          children: [
            // 1. Basic Identification Section
            Container(
              padding: const EdgeInsets.all(RafSpacing.lg),
              decoration: RafDecorations.cardFlat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المعلومات الأساسية والترميز',
                    style: RafTypography.titleMedium,
                  ),
                  const SizedBox(height: RafSpacing.md),

                  // Item Name
                  const Text('اسم الصنف *', style: RafTypography.label),
                  const SizedBox(height: RafSpacing.xs),
                  TextFormField(
                    key: const Key('item_name_field'),
                    controller: _nameController,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'يرجى إدخال اسم الصنف';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      hintText: 'مثال: أرز بسمتي هندي 5 كجم',
                    ),
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Barcode & Generator Button
                  const Text(
                    'الباركود / الكود التعريفي *',
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

                      final barcodeField = TextFormField(
                        key: const Key('item_code_field'),
                        controller: _codeController,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'يرجى إدخال كود الصنف';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'أدخل الباركود أو امسح بالكاميرا',
                          prefixIcon: const Icon(Icons.qr_code, size: 20),
                          suffixIcon: IconButton(
                            key: const Key('barcode_field_scan_icon_button'),
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: RafColors.primary,
                              size: 20,
                            ),
                            tooltip: 'مسح الباركود بالكاميرا',
                            onPressed: _scanBarcode,
                          ),
                        ),
                      );

                      final scanBtn = OutlinedButton.icon(
                        key: const Key('scan_barcode_button'),
                        onPressed: _scanBarcode,
                        icon: const Icon(Icons.qr_code_scanner, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('مسح بالكاميرا'),
                        ),
                      );

                      final generateBtn = OutlinedButton.icon(
                        key: const Key('generate_code_button'),
                        onPressed: _generateRandomBarcode,
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('توليد كود'),
                        ),
                      );

                      final printBtn = (_isEditing && widget.itemToEdit != null)
                          ? OutlinedButton.icon(
                              key: const Key('print_barcode_button'),
                              onPressed: _openPrintBarcodeDialog,
                              icon: const Icon(Icons.print_outlined, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('طباعة الملصق'),
                              ),
                            )
                          : null;

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            barcodeField,
                            const SizedBox(height: RafSpacing.xs),
                            Wrap(
                              spacing: RafSpacing.xs,
                              runSpacing: RafSpacing.xs,
                              children: [scanBtn, generateBtn, ?printBtn],
                            ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          barcodeField,
                          const SizedBox(height: RafSpacing.xs),
                          Row(
                            children: [
                              Expanded(child: scanBtn),
                              const SizedBox(width: RafSpacing.xs),
                              Expanded(child: generateBtn),
                              if (printBtn != null) ...[
                                const SizedBox(width: RafSpacing.xs),
                                Expanded(child: printBtn),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Unit & Category Controls
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow =
                          constraints.maxWidth < 440 ||
                          MediaQuery.textScalerOf(context).scale(1.0) > 1.2;

                      final unitWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Flexible(
                                child: Text(
                                  'وحدة القياس *',
                                  style: RafTypography.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: RafSpacing.xs),
                              Flexible(
                                child: InkWell(
                                  onTap: _showAddUnitDialog,
                                  borderRadius: RafRadius.roundedSm,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add_circle_outline,
                                            size: 14,
                                            color: RafColors.primary,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'وحدة جديدة',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: RafColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          Builder(
                            builder: (context) {
                              final selectableUnits = _isEditing
                                  ? _units
                                        .where(
                                          (u) =>
                                              !u.isArchived ||
                                              u.id == _selectedUnitId,
                                        )
                                        .toList()
                                  : _units.where((u) => !u.isArchived).toList();
                              return DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue:
                                    selectableUnits.any(
                                      (u) => u.id == _selectedUnitId,
                                    )
                                    ? _selectedUnitId
                                    : null,
                                items: selectableUnits.map((u) {
                                  final label = u.isArchived
                                      ? '${u.cleanName} (${u.cleanSymbol}) [مؤرشف]'
                                      : '${u.cleanName} (${u.cleanSymbol})';
                                  return DropdownMenuItem<int>(
                                    value: u.id,
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedUnitId = val);
                                },
                                decoration: const InputDecoration(),
                              );
                            },
                          ),
                        ],
                      );

                      final categoryWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Flexible(
                                child: Text(
                                  'التصنيف',
                                  style: RafTypography.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: RafSpacing.xs),
                              Flexible(
                                child: InkWell(
                                  onTap: _showAddCategoryDialog,
                                  borderRadius: RafRadius.roundedSm,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add_circle_outline,
                                            size: 14,
                                            color: RafColors.primary,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'تصنيف جديد',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: RafColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          Builder(
                            builder: (context) {
                              final selectableCategories = _isEditing
                                  ? _categories
                                        .where(
                                          (c) =>
                                              !c.isArchived ||
                                              c.id == _selectedCategoryId,
                                        )
                                        .toList()
                                  : _categories
                                        .where((c) => !c.isArchived)
                                        .toList();
                              return DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue:
                                    selectableCategories.any(
                                      (c) => c.id == _selectedCategoryId,
                                    )
                                    ? _selectedCategoryId
                                    : null,
                                items: selectableCategories.map((c) {
                                  final label = c.isArchived
                                      ? '${c.cleanName} [مؤرشف]'
                                      : c.cleanName;
                                  return DropdownMenuItem<int>(
                                    value: c.id,
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedCategoryId = val);
                                },
                                decoration: const InputDecoration(),
                              );
                            },
                          ),
                        ],
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            unitWidget,
                            const SizedBox(height: RafSpacing.md),
                            categoryWidget,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: unitWidget),
                          const SizedBox(width: RafSpacing.md),
                          Expanded(child: categoryWidget),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: RafSpacing.lg),

            // 2. Financial Pricing Section (Strict Integer Formatters)
            Container(
              padding: const EdgeInsets.all(RafSpacing.lg),
              decoration: RafDecorations.cardFlat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'التسعير والحساب المالي',
                    style: RafTypography.titleMedium,
                  ),
                  const SizedBox(height: RafSpacing.md),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 340;

                      final costWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'سعر التكلفة *',
                            style: RafTypography.label,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          TextFormField(
                            key: const Key('item_cost_field'),
                            controller: _costPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              ThousandsSeparatorInputFormatter(),
                            ],
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'أدخل التكلفة';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(hintText: '0.00'),
                          ),
                        ],
                      );

                      final sellingWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('سعر البيع *', style: RafTypography.label),
                          const SizedBox(height: RafSpacing.xs),
                          TextFormField(
                            key: const Key('item_selling_field'),
                            controller: _sellingPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              ThousandsSeparatorInputFormatter(),
                            ],
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'أدخل سعر البيع';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(hintText: '0.00'),
                          ),
                        ],
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            costWidget,
                            const SizedBox(height: RafSpacing.md),
                            sellingWidget,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: costWidget),
                          const SizedBox(width: RafSpacing.md),
                          Expanded(child: sellingWidget),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Real-time Margin Preview Strip
                  Container(
                    padding: const EdgeInsets.all(RafSpacing.md),
                    decoration: BoxDecoration(
                      color: isLoss
                          ? RafColors.dangerSubtle
                          : RafColors.surfaceSecondary,
                      borderRadius: RafRadius.roundedMd,
                      border: Border.all(
                        color: isLoss
                            ? RafColors.dangerBorder
                            : RafColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isLoss
                                ? 'تحذير: البيع بأقل من التكلفة (خسارة)'
                                : 'هامش الربح المتوقع للوحدة:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isLoss
                                  ? RafColors.danger
                                  : RafColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: RafSpacing.sm),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            margin.format(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isLoss
                                  ? RafColors.danger
                                  : RafColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: RafSpacing.lg),

            // 3. Inventory & Expiry Controls
            Container(
              padding: const EdgeInsets.all(RafSpacing.lg),
              decoration: RafDecorations.cardFlat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المخزون والصلاحية',
                    style: RafTypography.titleMedium,
                  ),
                  const SizedBox(height: RafSpacing.md),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 340;

                      final initialStockWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'الرصيد الحالي' : 'الرصيد الافتتاحي',
                            style: RafTypography.label,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          TextFormField(
                            key: const Key('item_initial_stock_field'),
                            controller: _initialStockController,
                            enabled: !_isEditing,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              ThousandsSeparatorInputFormatter.integerOnly(),
                            ],
                            decoration: InputDecoration(
                              hintText: '0',
                              helperText: _isEditing
                                  ? 'للتعديل استخدم التسوية الجردية'
                                  : null,
                            ),
                          ),
                        ],
                      );

                      final reorderWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'حد إعادة الطلب',
                            style: RafTypography.label,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          TextFormField(
                            controller: _minAlertLimitController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              ThousandsSeparatorInputFormatter.integerOnly(),
                            ],
                            decoration: const InputDecoration(hintText: '5'),
                          ),
                        ],
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            initialStockWidget,
                            const SizedBox(height: RafSpacing.md),
                            reorderWidget,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: initialStockWidget),
                          const SizedBox(width: RafSpacing.md),
                          Expanded(child: reorderWidget),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: RafSpacing.md),

                  // Expiry Date Picker
                  const Text(
                    'تاريخ الصلاحية (اختياري)',
                    style: RafTypography.label,
                  ),
                  const SizedBox(height: RafSpacing.xs),
                  InkWell(
                    onTap: _pickExpiryDate,
                    borderRadius: RafRadius.roundedMd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RafSpacing.lg,
                        vertical: RafSpacing.md + 2,
                      ),
                      decoration: BoxDecoration(
                        color: RafColors.surface,
                        borderRadius: RafRadius.roundedMd,
                        border: Border.all(color: RafColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedExpiryDate != null
                                  ? '${_selectedExpiryDate!.year}/${_selectedExpiryDate!.month.toString().padLeft(2, '0')}/${_selectedExpiryDate!.day.toString().padLeft(2, '0')}'
                                  : 'حدد تاريخ الصلاحية إن وجد',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedExpiryDate != null
                                    ? RafColors.textPrimary
                                    : RafColors.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: RafSpacing.xs),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_selectedExpiryDate != null)
                                IconButton(
                                  key: const Key('clear_expiry_date'),
                                  tooltip: 'حذف تاريخ الصلاحية',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(
                                    () => _selectedExpiryDate = null,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              const SizedBox(width: RafSpacing.xs),
                              const Icon(
                                Icons.calendar_month_outlined,
                                size: 20,
                                color: RafColors.secondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(RafSpacing.md),
          decoration: BoxDecoration(
            color: RafColors.surface,
            border: const Border(
              top: BorderSide(color: RafColors.border, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('save_item_button'),
              onPressed: _isSaving ? null : _saveItem,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 20),
              label: Text(
                _isSaving
                    ? 'جاري الحفظ...'
                    : (_isEditing ? 'حفظ تعديلات الصنف' : 'حفظ الصنف الجديد'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: RafColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: RafRadius.roundedMd,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
