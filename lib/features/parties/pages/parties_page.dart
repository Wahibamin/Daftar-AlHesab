import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/party_model.dart';
import '../repositories/parties_repository.dart';
import '../widgets/party_card.dart';
import 'account_statement_page.dart';
import 'party_editor_page.dart';

/// Central commercial parties directory screen (Customers & Suppliers) in RAF ERP.
class PartiesPage extends StatefulWidget {
  final PartiesRepository? repository;
  final List<PartyModel>? initialParties;

  const PartiesPage({super.key, this.repository, this.initialParties});

  @override
  State<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends State<PartiesPage>
    with SingleTickerProviderStateMixin {
  late final PartiesRepository _repo;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  static const int _pageSize = 30;
  List<PartyModel> _parties = [];
  bool _debtorOnly = false;
  bool _includeArchived = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SqlitePartiesRepository();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.initialParties != null) {
      _parties = List.of(widget.initialParties!);
      _isLoading = false;
      _hasMore = false;
    } else {
      _initAndLoad();
    }
  }

  Future<void> _initAndLoad() async {
    setState(() => _isLoading = true);
    await _repo.seedDefaultDataIfEmpty();
    await _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _hasMore = true;
    });

    try {
      final q = _searchController.text.trim();
      final parties = await _repo.getParties(
        includeArchived: _includeArchived,
        searchQuery: q.isEmpty ? null : q,
        debtorOnly: _debtorOnly ? true : null,
        limit: _pageSize,
        offset: 0,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          _parties = parties;
          _hasMore = parties.length >= _pageSize;
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
      final q = _searchController.text.trim();
      final nextParties = await _repo.getParties(
        includeArchived: _includeArchived,
        searchQuery: q.isEmpty ? null : q,
        debtorOnly: _debtorOnly ? true : null,
        limit: _pageSize,
        offset: _parties.length,
      );

      if (_searchToken != token) return;

      if (mounted) {
        setState(() {
          final existingIds = _parties.map((p) => p.id).toSet();
          final uniqueNew = nextParties
              .where((p) => !existingIds.contains(p.id))
              .toList();
          _parties.addAll(uniqueNew);
          _hasMore = nextParties.length >= _pageSize;
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

  Future<void> _openPartyEditor([PartyModel? party]) async {
    final defaultType = _tabController.index == 0
        ? PartyType.customer
        : PartyType.supplier;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PartyEditorPage(
          partyToEdit: party,
          initialType: party?.type ?? defaultType,
          repository: _repo,
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _openAccountStatement(PartyModel party) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AccountStatementPage(party: party, repository: _repo),
      ),
    );
    _loadData();
  }

  Future<void> _confirmDelete(PartyModel party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RafColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RafRadius.roundedMd,
          side: BorderSide(color: RafColors.border),
        ),
        title: const Text('أرشفة الطرف', style: RafTypography.titleMedium),
        content: Text('هل أنت متأكد من رغبتك في أرشفة ملف "${party.name}"؟'),
        actions: [
          IconButton(
            icon: Icon(
              _includeArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            tooltip: _includeArchived ? 'إخفاء المؤرشفين' : 'عرض المؤرشفين',
            onPressed: () {
              setState(() => _includeArchived = !_includeArchived);
              _loadData();
            },
          ),
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

    if (confirmed == true && party.id != null) {
      await _repo.deleteParty(party.id!);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت أرشفة الطرف بنجاح'),
            backgroundColor: RafColors.secondary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = _parties
        .where((p) => p.type == PartyType.customer || p.type == PartyType.both)
        .toList();
    final suppliers = _parties
        .where((p) => p.type == PartyType.supplier || p.type == PartyType.both)
        .toList();

    final debtorCount = _parties.where((p) => p.isDebtor).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دليل العملاء والموردين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadData,
          ),
          const SizedBox(width: RafSpacing.xs),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: RafColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: RafColors.primary,
              unselectedLabelColor: RafColors.textSecondary,
              indicatorColor: RafColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: RafTypography.fontFamily,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: RafTypography.fontFamily,
              ),
              tabs: [
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('العملاء'),
                        const SizedBox(width: RafSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _tabController.index == 0
                                ? RafColors.primarySubtle
                                : RafColors.surfaceSecondary,
                            borderRadius: RafRadius.roundedSm,
                          ),
                          child: Text(
                            '${customers.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _tabController.index == 0
                                  ? RafColors.primary
                                  : RafColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('الموردون'),
                        const SizedBox(width: RafSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _tabController.index == 1
                                ? RafColors.primarySubtle
                                : RafColors.surfaceSecondary,
                            borderRadius: RafRadius.roundedSm,
                          ),
                          child: Text(
                            '${suppliers.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _tabController.index == 1
                                  ? RafColors.primary
                                  : RafColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'parties_fab',
        onPressed: () => _openPartyEditor(),
        backgroundColor: RafColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
        label: Text(
          _tabController.index == 0 ? 'إضافة عميل' : 'إضافة مورد',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: RafTypography.fontFamily,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top White Header with Search & Filter
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
                  // Search Field
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الجوال...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadData();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RafSpacing.md,
                        vertical: RafSpacing.sm + 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: RafSpacing.sm),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: !_debtorOnly,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _debtorOnly = false);
                              _loadData();
                            }
                          },
                          backgroundColor: RafColors.surfaceSecondary,
                          selectedColor: RafColors.primarySubtle,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: !_debtorOnly
                                ? RafColors.primary
                                : RafColors.textSecondary,
                          ),
                          side: BorderSide(
                            color: !_debtorOnly
                                ? RafColors.primary
                                : RafColors.border,
                          ),
                        ),

                        const SizedBox(width: RafSpacing.xs),

                        FilterChip(
                          avatar: Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: _debtorOnly
                                ? RafColors.danger
                                : RafColors.textMuted,
                          ),
                          label: Text('عليهم مديونيات ($debtorCount)'),
                          selected: _debtorOnly,
                          onSelected: (selected) {
                            setState(() => _debtorOnly = selected);
                            _loadData();
                          },
                          backgroundColor: RafColors.surfaceSecondary,
                          selectedColor: RafColors.dangerSubtle,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _debtorOnly
                                ? RafColors.danger
                                : RafColors.textSecondary,
                          ),
                          side: BorderSide(
                            color: _debtorOnly
                                ? RafColors.dangerBorder
                                : RafColors.border,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar View
            Expanded(
              child: _isLoading && _parties.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: RafColors.primary,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPartiesList(customers, 'عميل'),
                        _buildPartiesList(suppliers, 'مورد'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartiesList(List<PartyModel> list, String roleName) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 56,
              color: RafColors.borderStrong,
            ),
            const SizedBox(height: RafSpacing.md),
            Text(
              'لا يوجد $roleName يطابق البحث',
              style: RafTypography.titleMedium,
            ),
            const SizedBox(height: RafSpacing.xs),
            Text(
              'اضغط على زر "إضافة $roleName" لإنشاء ملف جديد',
              style: RafTypography.bodySecondary,
            ),
            const SizedBox(height: RafSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => _openPartyEditor(),
              icon: const Icon(Icons.add, size: 16),
              label: Text('إضافة أول $roleName'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: RafColors.primary,
      onRefresh: _loadData,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >=
              scrollInfo.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            RafSpacing.md,
            RafSpacing.md,
            RafSpacing.md,
            80.0, // Floating button bottom clearance
          ),
          itemCount: list.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= list.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: RafSpacing.md),
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
            final party = list[index];
            return PartyCard(
              party: party,
              onOpenStatement: () => _openAccountStatement(party),
              onEdit: () => _openPartyEditor(party),
              onDelete: () => _confirmDelete(party),
            );
          },
        ),
      ),
    );
  }
}
