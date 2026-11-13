import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/database/business_data_wiper.dart';
import '../core/theme/raf_design_system.dart';
import 'accounting/repositories/vouchers_repository.dart';
import 'dashboard/pages/dashboard_page.dart';
import 'inventory/pages/items_page.dart';
import 'inventory/repositories/inventory_repository.dart';
import 'parties/pages/parties_page.dart';
import 'parties/repositories/parties_repository.dart';
import 'reports/pages/reports_hub_page.dart';
import 'reports/repositories/reports_repository.dart';
import 'sales/pages/invoices_list_page.dart';
import 'sales/repositories/invoices_repository.dart';

/// Main Application Shell housing the persistent bottom navigation bar
/// connecting all ERP & POS modules: Dashboard, Invoices, Items, Parties, and Reports.
class RafNavigationShell extends StatefulWidget {
  final int initialIndex;
  final ReportsRepository? reportsRepo;
  final InvoicesRepository? invoicesRepo;
  final InventoryRepository? inventoryRepo;
  final PartiesRepository? partiesRepo;
  final VouchersRepository? vouchersRepo;

  const RafNavigationShell({
    super.key,
    this.initialIndex = 0,
    this.reportsRepo,
    this.invoicesRepo,
    this.inventoryRepo,
    this.partiesRepo,
    this.vouchersRepo,
  });

  @override
  State<RafNavigationShell> createState() => _RafNavigationShellState();
}

class _RafNavigationShellState extends State<RafNavigationShell> {
  late int _currentIndex;
  int _resetCounter = 0;
  bool _isExitDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    BusinessDataNotifier.instance.addListener(_handleDataCleared);
  }

  void _handleDataCleared() {
    if (mounted) {
      setState(() {
        _resetCounter++;
      });
    }
  }

  @override
  void dispose() {
    BusinessDataNotifier.instance.removeListener(_handleDataCleared);
    super.dispose();
  }

  Future<bool?> _showExitConfirmationDialog() async {
    if (_isExitDialogShowing) return false;
    _isExitDialogShowing = true;
    try {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: RafRadius.roundedMd),
          title: const Text(
            'هل تريد الخروج من التطبيق؟',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text('هل أنت متأكد من أنك تريد إغلاق التطبيق؟'),
          actions: [
            TextButton(
              key: const Key('stay_in_app_button'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('البقاء في التطبيق'),
            ),
            FilledButton(
              key: const Key('exit_app_button'),
              style: FilledButton.styleFrom(backgroundColor: RafColors.danger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('خروج'),
            ),
          ],
        ),
      );
    } finally {
      _isExitDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        key: ValueKey('dash_$_resetCounter'),
        reportsRepo: widget.reportsRepo,
        invoicesRepo: widget.invoicesRepo,
        inventoryRepo: widget.inventoryRepo,
        partiesRepo: widget.partiesRepo,
        vouchersRepo: widget.vouchersRepo,
      ),
      InvoicesListPage(
        key: ValueKey('invs_$_resetCounter'),
        invoicesRepo: widget.invoicesRepo,
        inventoryRepo: widget.inventoryRepo,
        partiesRepo: widget.partiesRepo,
      ),
      ItemsPage(
        key: ValueKey('items_$_resetCounter'),
        repository: widget.inventoryRepo,
      ),
      PartiesPage(
        key: ValueKey('parties_$_resetCounter'),
        repository: widget.partiesRepo,
      ),
      ReportsHubPage(
        key: ValueKey('reports_$_resetCounter'),
        reportsRepo: widget.reportsRepo,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // If currently in a tab other than Home, navigate back to Home first
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // When already at Home root, confirm before exiting
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit == true && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: RafColors.surface,
            border: Border(
              top: BorderSide(color: RafColors.border, width: 1.0),
            ),
            boxShadow: RafShadows.subtle,
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: RafColors.surface,
            selectedItemColor: RafColors.primary,
            unselectedItemColor: RafColors.textSecondary,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'الرئيسية',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined),
                activeIcon: Icon(Icons.receipt_long_rounded),
                label: 'الفواتير',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2_outlined),
                activeIcon: Icon(Icons.inventory_2_rounded),
                label: 'المخزون',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline_rounded),
                activeIcon: Icon(Icons.people_rounded),
                label: 'الأطراف',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.analytics_outlined),
                activeIcon: Icon(Icons.analytics_rounded),
                label: 'التقارير',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
