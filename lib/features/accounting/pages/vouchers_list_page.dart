import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../parties/repositories/parties_repository.dart';
import '../models/voucher_model.dart';
import '../repositories/vouchers_repository.dart';
import 'voucher_editor_page.dart';
import 'expenses_page.dart';
import 'settlements_page.dart';
import '../widgets/treasury_accounts_card.dart';

/// Clean White UI List Page displaying all financial vouchers (receipts, payments & expenses).
class VouchersListPage extends StatefulWidget {
  final VouchersRepository vouchersRepo;
  final PartiesRepository partiesRepo;

  VouchersListPage({
    super.key,
    VouchersRepository? vouchersRepo,
    PartiesRepository? partiesRepo,
  }) : vouchersRepo = vouchersRepo ?? SqliteVouchersRepository(),
       partiesRepo = partiesRepo ?? SqlitePartiesRepository();

  @override
  State<VouchersListPage> createState() => _VouchersListPageState();
}

class _VouchersListPageState extends State<VouchersListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 30;
  List<VoucherModel> _vouchers = [];
  Map<int, String> _partiesCache = {};
  TreasurySnapshot _treasuryBalances = const TreasurySnapshot();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tabController = TabController(length: 3, vsync: this);
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

  VoucherType? _getFilterForTab() {
    switch (_tabController.index) {
      case 1: // Receipts only
        return VoucherType.receipt;
      case 2: // Payments only
        return VoucherType.payment;
      case 0: // All
      default:
        return null;
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

      final filterType = _getFilterForTab();
      final q = _searchController.text.trim();
      final vouchers = await widget.vouchersRepo.getVouchers(
        type: filterType,
        searchQuery: q.isEmpty ? null : q,
        limit: _pageSize,
        offset: 0,
      );

      final balance = await widget.vouchersRepo.getTreasuryBalances();

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          _vouchers = vouchers;
          _treasuryBalances = balance;
          _hasMore = vouchers.length >= _pageSize;
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
      final filterType = _getFilterForTab();
      final q = _searchController.text.trim();
      final nextVouchers = await widget.vouchersRepo.getVouchers(
        type: filterType,
        searchQuery: q.isEmpty ? null : q,
        limit: _pageSize,
        offset: _vouchers.length,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          final existingIds = _vouchers.map((v) => v.id).toSet();
          final uniqueNew = nextVouchers
              .where((v) => !existingIds.contains(v.id))
              .toList();
          _vouchers.addAll(uniqueNew);
          _hasMore = nextVouchers.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && _searchToken == token) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _openEditor([VoucherType type = VoucherType.receipt]) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoucherEditorPage(
          vouchersRepo: widget.vouchersRepo,
          partiesRepo: widget.partiesRepo,
          initialType: type,
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _deleteVoucher(VoucherModel voucher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء السند'),
        content: Text(
          'هل أنت متأكد من إلغاء ${voucher.voucherType.arabicLabel} رقم ${voucher.voucherNumber}؟ سيتم عكس الأثر المالي فوراً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: RafColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );

    if (confirm == true && voucher.id != null) {
      try {
        await widget.vouchersRepo.deleteVoucher(voucher.id!);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RafColors.surfaceSecondary,
      appBar: AppBar(
        title: Text(
          'سجل السندات المالية والخزينة',
          style: RafTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: RafColors.surface,
        elevation: 0,
        actions: [
          if (widget.vouchersRepo is SqliteVouchersRepository)
            IconButton(
              tooltip: 'الشيكات وتخصيص القبض',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () async {
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => SettlementsPage()));
                if (mounted) await _loadData();
              },
            ),
          IconButton(
            tooltip: 'دفتر المصروفات',
            icon: const Icon(Icons.receipt_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExpensesPage(repository: widget.vouchersRepo),
                ),
              );
              if (mounted) await _loadData();
            },
          ),
        ],
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('سندات القبض'),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('سندات الصرف'),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(reloadParties: true),
        color: RafColors.primary,
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: 2 + _vouchers.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) return _buildTreasurySummaryCard();
            if (index == 1) {
              return Column(
                children: [
                  Container(
                    color: RafColors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: RafSpacing.md,
                      vertical: RafSpacing.xs,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث برقم السند أو البيان...',
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
                          borderSide: const BorderSide(
                            color: RafColors.primary,
                          ),
                        ),
                        fillColor: RafColors.surfaceSecondary,
                        filled: true,
                      ),
                      onChanged: (_) => _loadData(),
                      onSubmitted: (_) => _loadData(),
                    ),
                  ),
                  if (_vouchers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(RafSpacing.md),
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: RafColors.primary,
                              ),
                            )
                          : _buildEmptyState(),
                    ),
                ],
              );
            }
            final voucherIndex = index - 2;
            if (voucherIndex >= _vouchers.length) {
              return const Padding(
                padding: EdgeInsets.all(RafSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: RafSpacing.md),
              child: _buildVoucherCard(_vouchers[voucherIndex]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: RafColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add, size: 20),
        label: const Text(
          'سند جديد',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => _openEditor(
          _tabController.index == 2 ? VoucherType.payment : VoucherType.receipt,
        ),
      ),
    );
  }

  Widget _buildTreasurySummaryCard() =>
      TreasuryAccountsCard(snapshot: _treasuryBalances);

  Widget _buildVoucherCard(VoucherModel voucher) {
    final partyName = voucher.partyId != null
        ? (_partiesCache[voucher.partyId] ?? 'طرف #${voucher.partyId}')
        : voucher.isExpense
        ? 'مصروف تشغيلي (بدون طرف)'
        : voucher.isReceipt
        ? 'قبض عام (بدون طرف)'
        : 'صرف عام (بدون طرف)';

    final isReceipt = voucher.isReceipt;

    return Container(
      margin: const EdgeInsets.only(bottom: RafSpacing.sm),
      decoration: BoxDecoration(
        color: RafColors.surface,
        borderRadius: RafRadius.roundedMd,
        border: Border.all(color: RafColors.border),
        boxShadow: RafShadows.subtle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(RafSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Number, Badge, Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          voucher.voucherNumber,
                          style: RafTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                            color: RafColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: RafSpacing.xs),
                      _buildTypeBadge(voucher.voucherType),
                    ],
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${isReceipt ? '+' : '-'}${CurrencyFormatter.format(voucher.amount)}',
                      style: RafTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isReceipt ? RafColors.success : RafColors.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: RafSpacing.xs),

            // Middle: Party name & Payment Method
            Row(
              children: [
                Icon(
                  voucher.partyId != null
                      ? Icons.person_outline_rounded
                      : Icons.monetization_on_outlined,
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
                    voucher.paymentMethod.arabicLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: RafColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            if (voucher.statement != null && voucher.statement!.isNotEmpty) ...[
              const SizedBox(height: RafSpacing.xs),
              Text(
                voucher.statement!,
                style: RafTypography.bodySmall.copyWith(
                  color: RafColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: RafSpacing.sm),
            const Divider(height: 1, color: RafColors.border),
            const SizedBox(height: RafSpacing.xs),

            // Bottom: Date and Delete Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormatter.formatDate(voucher.voucherDate),
                  style: RafTypography.bodySmall.copyWith(
                    color: RafColors.textMuted,
                  ),
                ),
                if (voucher.isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: RafColors.dangerSubtle,
                      borderRadius: RafRadius.roundedXs,
                      border: Border.all(color: RafColors.dangerBorder),
                    ),
                    child: const Text(
                      'ملغى',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: RafColors.danger,
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: RafColors.textMuted,
                    tooltip: 'إلغاء السند وعكس الأثر',
                    onPressed: () => _deleteVoucher(voucher),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(VoucherType type) {
    final isReceipt = type == VoucherType.receipt;
    final fg = isReceipt ? RafColors.success : RafColors.danger;
    final bg = isReceipt ? RafColors.successSubtle : RafColors.dangerSubtle;
    final border = isReceipt ? RafColors.successBorder : RafColors.dangerBorder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: RafRadius.roundedXs,
        border: Border.all(color: border),
      ),
      child: Text(
        type.arabicLabel,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RafSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: RafColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: RafSpacing.md),
            Text(
              'لا توجد سندات مسجلة',
              style: RafTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: RafColors.textSecondary,
              ),
            ),
            const SizedBox(height: RafSpacing.xs),
            Text(
              'اضغط على "سند جديد" لتسجيل سند قبض أو صرف نقدي',
              style: RafTypography.bodySmall.copyWith(
                color: RafColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
