import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../inventory/repositories/inventory_repository.dart';
import '../../parties/repositories/parties_repository.dart';
import '../models/invoice_model.dart';
import '../repositories/invoices_repository.dart';
import 'invoice_editor_page.dart';

/// Clean White UI List Page displaying all commercial invoices with tabs.
class InvoicesListPage extends StatefulWidget {
  final InvoicesRepository invoicesRepo;
  final InventoryRepository inventoryRepo;
  final PartiesRepository partiesRepo;

  InvoicesListPage({
    super.key,
    InvoicesRepository? invoicesRepo,
    InventoryRepository? inventoryRepo,
    PartiesRepository? partiesRepo,
  }) : invoicesRepo = invoicesRepo ?? SqliteInvoicesRepository(),
       inventoryRepo = inventoryRepo ?? SqliteInventoryRepository(),
       partiesRepo = partiesRepo ?? SqlitePartiesRepository();

  @override
  State<InvoicesListPage> createState() => _InvoicesListPageState();
}

class _InvoicesListPageState extends State<InvoicesListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 30;
  List<InvoiceModel> _invoices = [];
  Map<int, String> _partiesCache = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadData();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  (InvoiceType?, List<InvoiceType>?) _getFilterForTab() {
    switch (_tabController.index) {
      case 1: // Sales
        return (InvoiceType.sale, null);
      case 2: // Purchases
        return (InvoiceType.purchase, null);
      case 3: // Returns
        return (null, [InvoiceType.saleReturn, InvoiceType.purchaseReturn]);
      case 0: // All
      default:
        return (null, null);
    }
  }

  Future<void> _loadData({bool reloadParties = false}) async {
    final token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _hasMore = true;
    });

    try {
      if (reloadParties || _partiesCache.isEmpty) {
        final parties = await widget.partiesRepo.getParties();
        if (_searchToken != token) return;
        final cache = <int, String>{};
        for (final p in parties) {
          if (p.id != null) cache[p.id!] = p.name;
        }
        _partiesCache = cache;
      }

      final filter = _getFilterForTab();
      final q = _searchController.text.trim();
      final invoices = await widget.invoicesRepo.getInvoices(
        type: filter.$1,
        types: filter.$2,
        searchQuery: q.isEmpty ? null : q,
        includeItems: false,
        limit: _pageSize,
        offset: 0,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          _invoices = invoices;
          _hasMore = invoices.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (_) {
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
      final filter = _getFilterForTab();
      final q = _searchController.text.trim();
      final nextInvoices = await widget.invoicesRepo.getInvoices(
        type: filter.$1,
        types: filter.$2,
        searchQuery: q.isEmpty ? null : q,
        includeItems: false,
        limit: _pageSize,
        offset: _invoices.length,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          final existingIds = _invoices.map((i) => i.id).toSet();
          final uniqueNew = nextInvoices
              .where((i) => !existingIds.contains(i.id))
              .toList();
          _invoices.addAll(uniqueNew);
          _hasMore = nextInvoices.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && _searchToken == token) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _openEditor({
    InvoiceModel? existing,
    InvoiceType? initialType,
  }) async {
    if (existing?.id != null) {
      final saved = await widget.invoicesRepo.getInvoiceById(existing!.id!);
      if (!mounted) return;
      if (saved == null) {
        _loadData();
        return;
      }
      existing = saved;
    }
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceEditorPage(
          invoicesRepo: widget.invoicesRepo,
          inventoryRepo: widget.inventoryRepo,
          partiesRepo: widget.partiesRepo,
          existingInvoice: existing,
          initialType: initialType ?? InvoiceType.sale,
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          'سجل الفواتير والمبيعات',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: RafColors.primary,
          indicatorWeight: 2.5,
          labelColor: RafColors.primary,
          unselectedLabelColor: RafColors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('الكل')),
            ),
            Tab(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('المبيعات')),
            ),
            Tab(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('المشتريات')),
            ),
            Tab(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('المرتجعات')),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Field
          Container(
            color: RafColors.surface,
            padding: const EdgeInsets.symmetric(
              horizontal: RafSpacing.md,
              vertical: RafSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث برقم الفاتورة...',
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: RafColors.textMuted,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadData();
                        },
                      )
                    : null,
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
              onChanged: (_) => _loadData(),
              onSubmitted: (_) => _loadData(),
            ),
          ),

          // Invoices List
          Expanded(
            child: _isLoading && _invoices.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: RafColors.primary),
                  )
                : _invoices.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () => _loadData(reloadParties: true),
                    color: RafColors.primary,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(RafSpacing.md),
                      itemCount: _invoices.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _invoices.length) {
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
                        return _buildInvoiceCard(_invoices[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'invoices_fab',
        backgroundColor: RafColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
        label: const Text(
          'فاتورة جديدة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => _openEditor(initialType: _getInitialTypeFromTab()),
      ),
    );
  }

  InvoiceType _getInitialTypeFromTab() {
    switch (_tabController.index) {
      case 2:
        return InvoiceType.purchase;
      case 3:
        return InvoiceType.saleReturn;
      default:
        return InvoiceType.sale;
    }
  }

  Widget _buildInvoiceCard(InvoiceModel invoice) {
    final partyName = invoice.partyId != null
        ? (_partiesCache[invoice.partyId] ?? 'طرف #${invoice.partyId}')
        : 'عميل نقدي عام';

    return Container(
      margin: const EdgeInsets.only(bottom: RafSpacing.sm),
      decoration: BoxDecoration(
        color: RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(color: RafColors.border),
        boxShadow: RafShadows.subtle,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: RafRadius.roundedMd,
        child: InkWell(
          borderRadius: RafRadius.roundedMd,
          onTap: () => _openEditor(existing: invoice),
          child: Padding(
            padding: const EdgeInsets.all(RafSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Number, Type Chip, and Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              invoice.invoiceNumber,
                              style: RafTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.w800,
                                color: RafColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: RafSpacing.xs),
                          _buildTypeBadge(invoice.invoiceType),
                        ],
                      ),
                    ),
                    _buildStatusBadge(invoice.status),
                  ],
                ),

                const SizedBox(height: RafSpacing.xs),

                // Middle Row: Party Name and Payment Type
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: RafColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        partyName,
                        style: RafTypography.bodyMedium.copyWith(
                          color: RafColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: RafSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: RafColors.surfaceSecondary,
                        borderRadius: RafRadius.roundedXs,
                        border: Border.all(color: RafColors.border),
                      ),
                      child: Text(
                        invoice.paymentType.arabicLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: RafColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: RafSpacing.sm),
                const Divider(height: 1, color: RafColors.border),
                const SizedBox(height: RafSpacing.xs),

                // Bottom Row: Date and Total Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormatter.formatDate(invoice.invoiceDate),
                      style: RafTypography.bodySmall.copyWith(
                        color: RafColors.textMuted,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'الصافي: ',
                              style: RafTypography.bodySmall.copyWith(
                                color: RafColors.textSecondary,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(invoice.total),
                              style: RafTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: RafColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(InvoiceType type) {
    final Color color;
    switch (type) {
      case InvoiceType.sale:
        color = RafColors.primary;
        break;
      case InvoiceType.purchase:
        color = const Color(0xFF2563EB); // Royal Blue
        break;
      case InvoiceType.saleReturn:
      case InvoiceType.purchaseReturn:
        color = RafColors.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: RafRadius.roundedXs,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        type.arabicLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(InvoiceStatus status) {
    final String label;
    final Color fg;
    final Color bg;
    final Color border;

    switch (status) {
      case InvoiceStatus.approved:
        label = 'معتمدة';
        fg = RafColors.success;
        bg = RafColors.successSubtle;
        border = RafColors.successBorder;
        break;
      case InvoiceStatus.draft:
        label = 'مسودة';
        fg = RafColors.warning;
        bg = RafColors.warningSubtle;
        border = RafColors.warningBorder;
        break;
      case InvoiceStatus.cancelled:
        label = 'ملغاة';
        fg = RafColors.danger;
        bg = RafColors.dangerSubtle;
        border = RafColors.dangerBorder;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: RafRadius.roundedPill,
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RafSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: RafColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: RafSpacing.md),
            Text(
              'لا توجد فواتير مطابقة',
              style: RafTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: RafColors.textSecondary,
              ),
            ),
            const SizedBox(height: RafSpacing.xs),
            Text(
              'اضغط على "فاتورة جديدة" لإنشاء فاتورة مبيعات أو مشتريات',
              style: RafTypography.bodySmall.copyWith(
                color: RafColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
