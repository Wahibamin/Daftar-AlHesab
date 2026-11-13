import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../data/inventory_repository.dart';
import '../models/item_model.dart';
import '../widgets/item_card.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../widgets/barcode_label_dialog.dart';
import '../../../core/widgets/barcode_scanner_dialog.dart';
import 'item_editor_page.dart';

/// Central inventory and items catalog screen in RAF ERP.
class ItemsPage extends StatefulWidget {
  final InventoryRepository? repository;
  final List<ItemModel>? initialItems;
  final List<CategoryModel>? initialCategories;
  final List<UnitModel>? initialUnits;

  const ItemsPage({
    super.key,
    this.repository,
    this.initialItems,
    this.initialCategories,
    this.initialUnits,
  });

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  late final InventoryRepository _repo;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 30;
  List<ItemModel> _items = [];
  List<CategoryModel> _categories = [];
  Map<int, String> _unitSymbols = {};
  Map<int, String> _categoryNames = {};

  int? _selectedCategoryId;
  bool _showLowStockOnly = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqliteInventoryRepository();
    _scrollController.addListener(_onScroll);
    if (widget.initialItems != null) {
      _items = List.of(widget.initialItems!);
      _categories = widget.initialCategories ?? [];
      final units = widget.initialUnits ?? [];
      _unitSymbols = {
        for (final u in units)
          if (u.id != null) u.id!: u.symbol,
      };
      _categoryNames = {
        for (final c in _categories)
          if (c.id != null) c.id!: c.name,
      };
      _isLoading = false;
      _hasMore = false;
    } else {
      _initAndLoad();
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _initAndLoad() async {
    setState(() => _isLoading = true);
    await _loadData(reloadMeta: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool reloadMeta = false}) async {
    final token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _hasMore = true;
    });

    try {
      if (reloadMeta || _categories.isEmpty || _unitSymbols.isEmpty) {
        final cats = await _repo.getCategories();
        final units = await _repo.getUnits();
        if (_searchToken != token) return;
        _categories = cats;
        _unitSymbols = {
          for (final u in units)
            if (u.id != null) u.id!: u.cleanSymbol,
        };
        _categoryNames = {
          for (final c in cats)
            if (c.id != null) c.id!: c.cleanName,
        };
      }

      final query = _searchController.text.trim();
      final items = await _repo.getItems(
        searchQuery: query.isEmpty ? null : query,
        categoryId: _selectedCategoryId,
        lowStockOnly: _showLowStockOnly ? true : null,
        limit: _pageSize,
        offset: 0,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          _items = items;
          _hasMore = items.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && _searchToken == token) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    final token = _searchToken;

    try {
      final query = _searchController.text.trim();
      final nextItems = await _repo.getItems(
        searchQuery: query.isEmpty ? null : query,
        categoryId: _selectedCategoryId,
        lowStockOnly: _showLowStockOnly ? true : null,
        limit: _pageSize,
        offset: _items.length,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          final existingIds = _items.map((i) => i.id).toSet();
          final uniqueNew = nextItems
              .where((i) => !existingIds.contains(i.id))
              .toList();
          _items.addAll(uniqueNew);
          _hasMore = nextItems.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && _searchToken == token) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _loadData();
  }

  Future<void> _scanBarcodeSearch() async {
    final code = await BarcodeScannerDialog.scan(
      context,
      title: 'البحث عن صنف بالباركود',
      prompt: 'وجّه الكاميرا نحو باركود الصنف لعرضه في المخزون',
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final trimmed = code.trim();
    _searchController.text = trimmed;
    await _loadData();

    final item = await _repo.getItemByCode(trimmed);
    if (!mounted) return;
    if (item != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم العثور على الصنف: "${item.name}"'),
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

  void _printBarcode(ItemModel item) {
    BarcodeLabelDialog.show(
      context,
      item: item,
      unitSymbol: _unitSymbols[item.unitId],
    );
  }

  Future<void> _openItemEditor([ItemModel? item]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            ItemEditorPage(itemToEdit: item, repository: _repo),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _openStockAdjustment(ItemModel item) async {
    final result = await StockAdjustmentDialog.show(
      context,
      item: item,
      repository: _repo,
    );

    if (result == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل التسوية الجردية للصنف "${item.name}" بنجاح',
            ),
            backgroundColor: RafColors.primary,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(ItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: const Text('أرشفة الصنف', style: RafTypography.titleMedium),
        content: Text('هل أنت متأكد من رغبتك في أرشفة الصنف "${item.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );

    if (confirmed == true && item.id != null) {
      await _repo.deleteItem(item.id!);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت أرشفة الصنف بنجاح'),
            backgroundColor: RafColors.secondary,
          ),
        );
      }
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: const Text('إضافة تصنيف جديد', style: RafTypography.titleMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('add_category_name_field'),
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم التصنيف *',
                  hintText: 'مثال: ألبان وأجبان',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'أدخل اسم التصنيف' : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('add_category_desc_field'),
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('save_category_button'),
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.primary),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final name = nameCtrl.text.trim();
              final desc = descCtrl.text.trim();
              try {
                await _repo.insertCategory(
                  CategoryModel(
                    name: name,
                    description: desc.isEmpty ? null : desc,
                    createdAt: DateTime.now(),
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceAll('StateError: ', ''),
                      ),
                      backgroundColor: RafColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ التصنيف'),
          ),
        ],
      ),
    );

    if (created == true) {
      await _loadData(reloadMeta: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة التصنيف "${nameCtrl.text.trim()}" بنجاح'),
            backgroundColor: RafColors.success,
          ),
        );
      }
    }
  }

  Future<void> _showEditCategoryDialog(CategoryModel category) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: category.cleanName);
    final descCtrl = TextEditingController(text: category.cleanDescription);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: const Text('تعديل التصنيف', style: RafTypography.titleMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('edit_category_name_field'),
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم التصنيف *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'أدخل اسم التصنيف' : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('edit_category_desc_field'),
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('update_category_button'),
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.primary),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final name = nameCtrl.text.trim();
              var desc = descCtrl.text.trim();
              if (category.isArchived) {
                desc = '[مؤرشف] $desc'.trim();
              }
              try {
                await _repo.updateCategory(
                  category.copyWith(
                    name: name,
                    description: desc.isEmpty ? null : desc,
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceAll('StateError: ', ''),
                      ),
                      backgroundColor: RafColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('تعديل'),
          ),
        ],
      ),
    );

    if (updated == true) {
      await _loadData(reloadMeta: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعديل التصنيف "${nameCtrl.text.trim()}" بنجاح'),
            backgroundColor: RafColors.primary,
          ),
        );
      }
    }
  }

  Future<void> _showManageCategoriesModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RafColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RafRadius.lg)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (scrollCtx, scrollController) {
                return FutureBuilder<List<CategoryModel>>(
                  future: _repo.getCategories(),
                  builder: (context, snapshot) {
                    final categories = snapshot.data ?? [];
                    return Column(
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: RafSpacing.sm,
                            ),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: RafColors.borderStrong,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RafSpacing.md,
                            vertical: RafSpacing.xs,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.category_rounded,
                                    size: 20,
                                    color: RafColors.primary,
                                  ),
                                  SizedBox(width: RafSpacing.sm),
                                  Text(
                                    'إدارة وتعديل التصنيفات',
                                    style: RafTypography.titleMedium,
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                key: const Key('modal_add_category_button'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: RafColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: RafSpacing.md,
                                    vertical: RafSpacing.xs + 2,
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text(
                                  'تصنيف جديد',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onPressed: () async {
                                  await _showAddCategoryDialog();
                                  setModalState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: RafColors.border),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Expanded(
                            child: Center(
                              child: CircularProgressIndicator(
                                color: RafColors.primary,
                              ),
                            ),
                          )
                        else if (categories.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text('لا توجد تصنيفات معرفة حالياً'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(RafSpacing.md),
                              itemCount: categories.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: RafSpacing.xs + 2),
                              itemBuilder: (context, index) {
                                final cat = categories[index];
                                return FutureBuilder<int>(
                                  future: _repo.getCategoryItemCount(cat.id!),
                                  builder: (context, countSnapshot) {
                                    final itemCount = countSnapshot.data ?? 0;
                                    return Container(
                                      padding: const EdgeInsets.all(
                                        RafSpacing.sm + 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cat.isArchived
                                            ? RafColors.surfaceSecondary
                                            : RafColors.surface,
                                        borderRadius: RafRadius.roundedMd,
                                        border: Border.all(
                                          color: cat.isArchived
                                              ? RafColors.warningBorder
                                              : RafColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        cat.cleanName,
                                                        style: RafTypography
                                                            .body
                                                            .copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (cat.isArchived) ...[
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: RafColors
                                                              .warningSubtle,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          border: Border.all(
                                                            color: RafColors
                                                                .warningBorder,
                                                          ),
                                                        ),
                                                        child: const Text(
                                                          'مؤرشف',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: RafColors
                                                                .warning,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      itemCount > 0
                                                          ? '$itemCount صنف'
                                                          : 'بدون أصناف',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: itemCount > 0
                                                            ? RafColors.primary
                                                            : RafColors
                                                                  .textMuted,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (cat
                                                        .cleanDescription
                                                        .isNotEmpty) ...[
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      const Text(
                                                        '•',
                                                        style: TextStyle(
                                                          color: RafColors
                                                              .borderStrong,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          cat.cleanDescription,
                                                          style: const TextStyle(
                                                            fontSize: 11,
                                                            color: RafColors
                                                                .textSecondary,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            key: Key('edit_category_${cat.id}'),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: RafColors.secondary,
                                            ),
                                            tooltip: 'تعديل',
                                            onPressed: () async {
                                              await _showEditCategoryDialog(
                                                cat,
                                              );
                                              setModalState(() {});
                                            },
                                          ),
                                          IconButton(
                                            key: Key(
                                              'archive_category_${cat.id}',
                                            ),
                                            icon: Icon(
                                              cat.isArchived
                                                  ? Icons.unarchive_outlined
                                                  : Icons.archive_outlined,
                                              size: 18,
                                              color: cat.isArchived
                                                  ? RafColors.success
                                                  : RafColors.warning,
                                            ),
                                            tooltip: cat.isArchived
                                                ? 'استعادة'
                                                : 'أرشفة',
                                            onPressed: () async {
                                              await _repo.archiveCategory(
                                                cat.id!,
                                                unarchive: cat.isArchived,
                                              );
                                              setModalState(() {});
                                              await _loadData(reloadMeta: true);
                                            },
                                          ),
                                          IconButton(
                                            key: Key(
                                              'delete_category_${cat.id}',
                                            ),
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: itemCount == 0
                                                  ? RafColors.danger
                                                  : RafColors.textMuted,
                                            ),
                                            tooltip: itemCount == 0
                                                ? 'حذف'
                                                : 'مرتبط بأصناف (أرشفة)',
                                            onPressed: () async {
                                              if (itemCount > 0) {
                                                await showDialog<void>(
                                                  context: modalCtx,
                                                  builder: (alertCtx) => AlertDialog(
                                                    title: const Text(
                                                      'تعذر حذف التصنيف',
                                                      style: RafTypography
                                                          .titleMedium,
                                                    ),
                                                    content: Text(
                                                      'لا يمكن حذف التصنيف "${cat.name}" لوجود $itemCount صنف مرتبط به، وذلك لحماية سلامة المخزون وحركات البيع والشراء السابقة.\n\nيمكنك أرشفة التصنيف بدلاً من حذفه.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop(),
                                                        child: const Text(
                                                          'إغلاق',
                                                        ),
                                                      ),
                                                      if (!cat.isArchived)
                                                        ElevatedButton(
                                                          style:
                                                              ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    RafColors
                                                                        .warning,
                                                              ),
                                                          onPressed: () async {
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop();
                                                            await _repo
                                                                .archiveCategory(
                                                                  cat.id!,
                                                                );
                                                            setModalState(
                                                              () {},
                                                            );
                                                            await _loadData(
                                                              reloadMeta: true,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'أرشفة الآن',
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              } else {
                                                final confirmed = await showDialog<bool>(
                                                  context: modalCtx,
                                                  builder: (alertCtx) => AlertDialog(
                                                    title: const Text(
                                                      'تأكيد الحذف',
                                                      style: RafTypography
                                                          .titleMedium,
                                                    ),
                                                    content: Text(
                                                      'هل أنت متأكد من حذف التصنيف "${cat.name}" نهائياً؟',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop(false),
                                                        child: const Text(
                                                          'إلغاء',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  RafColors
                                                                      .danger,
                                                            ),
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop(true),
                                                        child: const Text(
                                                          'حذف نهائي',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirmed == true) {
                                                  await _repo.deleteCategory(
                                                    cat.id!,
                                                  );
                                                  setModalState(() {});
                                                  await _loadData(
                                                    reloadMeta: true,
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );

    await _loadData(reloadMeta: true);
  }

  Future<void> _showAddUnitDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    final factorCtrl = TextEditingController(text: '1');

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
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
                key: const Key('add_unit_name_field'),
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم وحدة القياس *',
                  hintText: 'مثال: حبة، كرتون، كيلوجرام، متر',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل اسم وحدة القياس'
                    : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('add_unit_symbol_field'),
                controller: symbolCtrl,
                decoration: const InputDecoration(
                  labelText: 'رمز / اختصار وحدة القياس *',
                  hintText: 'مثال: حبة، ctn، كجم، م',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل رمز أو اختصار وحدة القياس'
                    : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('add_unit_factor_field'),
                controller: factorCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'معامل التحويل (الافتراضي 1)',
                  hintText: '1',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1) return 'أدخل رقماً صحيحاً موجباً';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('save_unit_button'),
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.primary),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final name = nameCtrl.text.trim();
              final symbol = symbolCtrl.text.trim();
              final factor = int.tryParse(factorCtrl.text.trim()) ?? 1;
              try {
                await _repo.insertUnit(
                  UnitModel(
                    name: name,
                    symbol: symbol,
                    conversionFactor: factor > 0 ? factor : 1,
                    createdAt: DateTime.now(),
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceAll('StateError: ', ''),
                      ),
                      backgroundColor: RafColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ وحدة القياس'),
          ),
        ],
      ),
    );

    if (created == true) {
      await _loadData(reloadMeta: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت إضافة وحدة القياس "${nameCtrl.text.trim()}" بنجاح',
            ),
            backgroundColor: RafColors.success,
          ),
        );
      }
    }
  }

  Future<void> _showEditUnitDialog(UnitModel unit) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: unit.cleanName);
    final symbolCtrl = TextEditingController(text: unit.cleanSymbol);
    final factorCtrl = TextEditingController(
      text: unit.conversionFactor.toString(),
    );

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: const Text(
          'تعديل وحدة القياس',
          style: RafTypography.titleMedium,
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('edit_unit_name_field'),
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم وحدة القياس *',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل اسم وحدة القياس'
                    : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('edit_unit_symbol_field'),
                controller: symbolCtrl,
                decoration: const InputDecoration(
                  labelText: 'رمز / اختصار وحدة القياس *',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل رمز أو اختصار وحدة القياس'
                    : null,
              ),
              const SizedBox(height: RafSpacing.md),
              TextFormField(
                key: const Key('edit_unit_factor_field'),
                controller: factorCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'معامل التحويل'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1) return 'أدخل رقماً صحيحاً موجباً';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('update_unit_button'),
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.primary),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              var name = nameCtrl.text.trim();
              final symbol = symbolCtrl.text.trim();
              final factor = int.tryParse(factorCtrl.text.trim()) ?? 1;
              if (unit.isArchived) {
                name = '[مؤرشف] $name'.trim();
              }
              try {
                await _repo.updateUnit(
                  unit.copyWith(
                    name: name,
                    symbol: symbol,
                    conversionFactor: factor > 0 ? factor : 1,
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceAll('StateError: ', ''),
                      ),
                      backgroundColor: RafColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('تعديل'),
          ),
        ],
      ),
    );

    if (updated == true) {
      await _loadData(reloadMeta: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تعديل وحدة القياس "${nameCtrl.text.trim()}" بنجاح',
            ),
            backgroundColor: RafColors.primary,
          ),
        );
      }
    }
  }

  Future<void> _showManageUnitsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RafColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RafRadius.lg)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (scrollCtx, scrollController) {
                return FutureBuilder<List<UnitModel>>(
                  future: _repo.getUnits(),
                  builder: (context, snapshot) {
                    final units = snapshot.data ?? [];
                    return Column(
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: RafSpacing.sm,
                            ),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: RafColors.borderStrong,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RafSpacing.md,
                            vertical: RafSpacing.xs,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.scale_rounded,
                                    size: 20,
                                    color: RafColors.primary,
                                  ),
                                  SizedBox(width: RafSpacing.sm),
                                  Text(
                                    'إدارة وحدات القياس',
                                    style: RafTypography.titleMedium,
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                key: const Key('modal_add_unit_button'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: RafColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: RafSpacing.md,
                                    vertical: RafSpacing.xs + 2,
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text(
                                  'وحدة قياس جديدة',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onPressed: () async {
                                  await _showAddUnitDialog();
                                  setModalState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: RafColors.border),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Expanded(
                            child: Center(
                              child: CircularProgressIndicator(
                                color: RafColors.primary,
                              ),
                            ),
                          )
                        else if (units.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text('لا توجد وحدات قياس معرفة حالياً'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(RafSpacing.md),
                              itemCount: units.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: RafSpacing.xs + 2),
                              itemBuilder: (context, index) {
                                final unit = units[index];
                                return FutureBuilder<int>(
                                  future: _repo.getUnitItemCount(unit.id!),
                                  builder: (context, countSnapshot) {
                                    final itemCount = countSnapshot.data ?? 0;
                                    return Container(
                                      padding: const EdgeInsets.all(
                                        RafSpacing.sm + 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: unit.isArchived
                                            ? RafColors.surfaceSecondary
                                            : RafColors.surface,
                                        borderRadius: RafRadius.roundedMd,
                                        border: Border.all(
                                          color: unit.isArchived
                                              ? RafColors.warningBorder
                                              : RafColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        '${unit.cleanName} (${unit.cleanSymbol})',
                                                        style: RafTypography
                                                            .body
                                                            .copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (unit.isArchived) ...[
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: RafColors
                                                              .warningSubtle,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          border: Border.all(
                                                            color: RafColors
                                                                .warningBorder,
                                                          ),
                                                        ),
                                                        child: const Text(
                                                          'مؤرشف',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: RafColors
                                                                .warning,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      itemCount > 0
                                                          ? '$itemCount صنف'
                                                          : 'بدون أصناف',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: itemCount > 0
                                                            ? RafColors.primary
                                                            : RafColors
                                                                  .textMuted,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (unit.conversionFactor >
                                                        1) ...[
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      const Text(
                                                        '•',
                                                        style: TextStyle(
                                                          color: RafColors
                                                              .borderStrong,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: RafSpacing.xs,
                                                      ),
                                                      Text(
                                                        'معامل: ${unit.conversionFactor}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: RafColors
                                                              .textSecondary,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            key: Key('edit_unit_${unit.id}'),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: RafColors.secondary,
                                            ),
                                            tooltip: 'تعديل',
                                            onPressed: () async {
                                              await _showEditUnitDialog(unit);
                                              setModalState(() {});
                                            },
                                          ),
                                          IconButton(
                                            key: Key('archive_unit_${unit.id}'),
                                            icon: Icon(
                                              unit.isArchived
                                                  ? Icons.unarchive_outlined
                                                  : Icons.archive_outlined,
                                              size: 18,
                                              color: unit.isArchived
                                                  ? RafColors.success
                                                  : RafColors.warning,
                                            ),
                                            tooltip: unit.isArchived
                                                ? 'استعادة'
                                                : 'أرشفة',
                                            onPressed: () async {
                                              await _repo.archiveUnit(
                                                unit.id!,
                                                unarchive: unit.isArchived,
                                              );
                                              setModalState(() {});
                                              await _loadData(reloadMeta: true);
                                            },
                                          ),
                                          IconButton(
                                            key: Key('delete_unit_${unit.id}'),
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: itemCount == 0
                                                  ? RafColors.danger
                                                  : RafColors.textMuted,
                                            ),
                                            tooltip: itemCount == 0
                                                ? 'حذف'
                                                : 'مرتبط بأصناف (أرشفة)',
                                            onPressed: () async {
                                              if (itemCount > 0) {
                                                await showDialog<void>(
                                                  context: modalCtx,
                                                  builder: (alertCtx) => AlertDialog(
                                                    title: const Text(
                                                      'تعذر حذف وحدة القياس',
                                                      style: RafTypography
                                                          .titleMedium,
                                                    ),
                                                    content: Text(
                                                      'لا يمكن حذف وحدة القياس "${unit.cleanName}" لوجود $itemCount صنف مرتبط بها، وذلك لحماية سلامة المخزون وسجلات البيع والشراء السابقة.\n\nيمكنك أرشفة وحدة القياس بدلاً من حذفها.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop(),
                                                        child: const Text(
                                                          'إغلاق',
                                                        ),
                                                      ),
                                                      if (!unit.isArchived)
                                                        ElevatedButton(
                                                          style:
                                                              ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    RafColors
                                                                        .warning,
                                                              ),
                                                          onPressed: () async {
                                                            Navigator.of(
                                                              alertCtx,
                                                            ).pop();
                                                            await _repo
                                                                .archiveUnit(
                                                                  unit.id!,
                                                                );
                                                            setModalState(
                                                              () {},
                                                            );
                                                            await _loadData(
                                                              reloadMeta: true,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'أرشفة وحدة القياس',
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                                return;
                                              }
                                              final confirmed = await showDialog<bool>(
                                                context: modalCtx,
                                                builder: (alertCtx) => AlertDialog(
                                                  title: const Text(
                                                    'تأكيد الحذف',
                                                    style: RafTypography
                                                        .titleMedium,
                                                  ),
                                                  content: Text(
                                                    'هل أنت متأكد من حذف وحدة القياس "${unit.cleanName}" نهائياً؟',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            alertCtx,
                                                          ).pop(false),
                                                      child: const Text(
                                                        'إلغاء',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style:
                                                          ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                RafColors
                                                                    .danger,
                                                          ),
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            alertCtx,
                                                          ).pop(true),
                                                      child: const Text('حذف'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmed == true) {
                                                try {
                                                  await _repo.deleteUnit(
                                                    unit.id!,
                                                  );
                                                  setModalState(() {});
                                                  await _loadData(
                                                    reloadMeta: true,
                                                  );
                                                } catch (e) {
                                                  if (modalCtx.mounted) {
                                                    ScaffoldMessenger.of(
                                                      modalCtx,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          e
                                                              .toString()
                                                              .replaceAll(
                                                                'StateError: ',
                                                                '',
                                                              ),
                                                        ),
                                                        backgroundColor:
                                                            RafColors.danger,
                                                      ),
                                                    );
                                                  }
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int lowStockCount = _items.where((i) => i.isLowStock).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دليل المخزون والأصناف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            key: const Key('items_page_more_menu'),
            icon: const Icon(Icons.more_vert),
            tooltip: 'خيارات إضافية',
            onSelected: (val) async {
              if (val == 'add_category') {
                await _showAddCategoryDialog();
              } else if (val == 'add_unit') {
                await _showAddUnitDialog();
              } else if (val == 'manage_categories') {
                await _showManageCategoriesModal();
              } else if (val == 'manage_units') {
                await _showManageUnitsModal();
              } else if (val == 'refresh') {
                final messenger = ScaffoldMessenger.of(context);
                await _loadData(reloadMeta: true);
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث قائمة الأصناف بنجاح'),
                    backgroundColor: RafColors.primary,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                key: Key('menu_add_category'),
                value: 'add_category',
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: RafColors.primary,
                    ),
                    SizedBox(width: RafSpacing.sm),
                    Expanded(
                      child: Text(
                        'إضافة تصنيف',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                key: Key('menu_add_unit'),
                value: 'add_unit',
                child: Row(
                  children: [
                    Icon(
                      Icons.add_box_outlined,
                      size: 18,
                      color: RafColors.primary,
                    ),
                    SizedBox(width: RafSpacing.sm),
                    Expanded(
                      child: Text(
                        'إضافة وحدة قياس',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                key: Key('menu_manage_categories'),
                value: 'manage_categories',
                child: Row(
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 18,
                      color: RafColors.secondary,
                    ),
                    SizedBox(width: RafSpacing.sm),
                    Expanded(
                      child: Text(
                        'تعديل تصنيف',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                key: Key('menu_manage_units'),
                value: 'manage_units',
                child: Row(
                  children: [
                    Icon(
                      Icons.scale_outlined,
                      size: 18,
                      color: RafColors.secondary,
                    ),
                    SizedBox(width: RafSpacing.sm),
                    Expanded(
                      child: Text(
                        'تعديل وحدة قياس',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                key: Key('menu_refresh'),
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 18,
                      color: RafColors.textSecondary,
                    ),
                    SizedBox(width: RafSpacing.sm),
                    Expanded(
                      child: Text(
                        'تحديث القائمة',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: RafSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'items_fab',
        onPressed: () => _openItemEditor(),
        backgroundColor: RafColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add, size: 20),
        label: const Text(
          'إضافة صنف',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: RafTypography.fontFamily,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top White Header with Search & Filter Strip
            Container(
              padding: const EdgeInsets.all(RafSpacing.md),
              decoration: const BoxDecoration(
                color: RafColors.surface,
                border: Border(
                  bottom: BorderSide(color: RafColors.border, width: 1.0),
                ),
              ),
              child: Column(
                children: [
                  // Search TextField
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الباركود...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadData();
                              },
                            ),
                          IconButton(
                            key: const Key('items_search_camera_button'),
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: RafColors.primary,
                              size: 20,
                            ),
                            tooltip: 'مسح الباركود بالكاميرا',
                            onPressed: _scanBarcodeSearch,
                          ),
                        ],
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RafSpacing.md,
                        vertical: RafSpacing.sm + 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: RafSpacing.sm),

                  // Horizontal Category Filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // All Filter
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected:
                              _selectedCategoryId == null && !_showLowStockOnly,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategoryId = null;
                                _showLowStockOnly = false;
                              });
                              _loadData();
                            }
                          },
                          backgroundColor: RafColors.surfaceSecondary,
                          selectedColor: RafColors.primarySubtle,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                (_selectedCategoryId == null &&
                                    !_showLowStockOnly)
                                ? RafColors.primary
                                : RafColors.textSecondary,
                          ),
                          side: BorderSide(
                            color:
                                (_selectedCategoryId == null &&
                                    !_showLowStockOnly)
                                ? RafColors.primary
                                : RafColors.border,
                          ),
                        ),

                        const SizedBox(width: RafSpacing.xs),

                        // Low Stock Alert Filter
                        FilterChip(
                          avatar: Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: _showLowStockOnly
                                ? RafColors.warning
                                : RafColors.textMuted,
                          ),
                          label: Text('نواقص ($lowStockCount)'),
                          selected: _showLowStockOnly,
                          onSelected: (selected) {
                            setState(() {
                              _showLowStockOnly = selected;
                              if (selected) _selectedCategoryId = null;
                            });
                            _loadData();
                          },
                          backgroundColor: RafColors.surfaceSecondary,
                          selectedColor: RafColors.warningSubtle,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _showLowStockOnly
                                ? RafColors.warning
                                : RafColors.textSecondary,
                          ),
                          side: BorderSide(
                            color: _showLowStockOnly
                                ? RafColors.warningBorder
                                : RafColors.border,
                          ),
                        ),

                        // Categories Chips
                        ..._categories.map((cat) {
                          final isSelected = _selectedCategoryId == cat.id;
                          return Padding(
                            padding: const EdgeInsets.only(
                              right: RafSpacing.xs,
                            ),
                            child: ChoiceChip(
                              label: Text(cat.name),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedCategoryId = selected
                                      ? cat.id
                                      : null;
                                  _showLowStockOnly = false;
                                });
                                _loadData();
                              },
                              backgroundColor: RafColors.surfaceSecondary,
                              selectedColor: RafColors.primarySubtle,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? RafColors.primary
                                    : RafColors.textSecondary,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? RafColors.primary
                                    : RafColors.border,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Items List / Empty View
            Expanded(
              child: _isLoading && _items.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: RafColors.primary,
                      ),
                    )
                  : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 56,
                            color: RafColors.borderStrong,
                          ),
                          const SizedBox(height: RafSpacing.md),
                          const Text(
                            'لا توجد أصناف تطابق هذا البحث',
                            style: RafTypography.titleMedium,
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          const Text(
                            'اضغط على زر "إضافة صنف" لتعريف صنف جديد بالمخزن',
                            style: RafTypography.bodySecondary,
                          ),
                          const SizedBox(height: RafSpacing.lg),
                          OutlinedButton.icon(
                            onPressed: () => _openItemEditor(),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('إضافة أول صنف'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: RafColors.primary,
                      onRefresh: () => _loadData(reloadMeta: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          RafSpacing.md,
                          RafSpacing.md,
                          RafSpacing.md,
                          80.0, // Floating button bottom spacing
                        ),
                        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: RafSpacing.md,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: RafColors.primary,
                                  ),
                                ),
                              ),
                            );
                          }
                          final item = _items[index];
                          return ItemCard(
                            item: item,
                            unitName: _unitSymbols[item.unitId],
                            categoryName: item.categoryId != null
                                ? _categoryNames[item.categoryId!]
                                : null,
                            onEdit: () => _openItemEditor(item),
                            onAdjustStock: () => _openStockAdjustment(item),
                            onPrintBarcode: () => _printBarcode(item),
                            onDelete: () => _confirmDelete(item),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
