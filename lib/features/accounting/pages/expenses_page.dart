import 'package:flutter/material.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/raf_design_system.dart';
import '../models/voucher_model.dart';
import '../repositories/vouchers_repository.dart';
import 'voucher_editor_page.dart';

/// Expenses reuse the payment voucher transaction, so money is never posted twice.
class ExpensesPage extends StatefulWidget {
  final VouchersRepository repository;
  ExpensesPage({super.key, VouchersRepository? repository})
    : repository = repository ?? SqliteVouchersRepository();
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _search = TextEditingController();
  List<VoucherModel> _rows = [];
  Money _total = Money.zero;
  bool _loading = true, _more = true;
  int _token = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final token = ++_token;
    setState(() => _loading = true);
    try {
      final rows = await widget.repository.getVouchers(
        purpose: VoucherPurpose.expense,
        searchQuery: _search.text.trim(),
        limit: 30,
        offset: append ? _rows.length : 0,
      );
      final total = await widget.repository.getExpenseTotal();
      if (!mounted || token != _token) return;
      setState(() {
        _rows = append ? [..._rows, ...rows] : rows;
        _total = total;
        _more = rows.length == 30;
      });
    } catch (error) {
      if (mounted && token == _token) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تحميل المصروفات: $error')));
      }
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VoucherEditorPage(
          vouchersRepo: widget.repository,
          initialType: VoucherType.payment,
          initialPurpose: VoucherPurpose.expense,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _cancel(VoucherModel value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء المصروف'),
        content: const Text(
          'سيُعكس أثر المصروف من الرصيد والأرباح والخسائر. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء المصروف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteVoucher(value.id!);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إلغاء المصروف: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('دفتر المصروفات'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('مصروف جديد'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(RafSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إجمالي المصروفات المعتمدة: ${CurrencyFormatter.format(_total)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('expense_search'),
                controller: _search,
                onChanged: (_) => _load(),
                decoration: const InputDecoration(
                  labelText: 'بحث في المصروفات',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? const Center(child: Text('لا توجد مصروفات'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _rows.length + (_more ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _rows.length) {
                      return TextButton(
                        onPressed: _loading ? null : () => _load(append: true),
                        child: Text(
                          _loading ? 'جارٍ التحميل...' : 'تحميل المزيد',
                        ),
                      );
                    }
                    final value = _rows[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              value.statement ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${value.expenseCategory ?? 'أخرى'} • ${value.voucherDate.year}/${value.voucherDate.month}/${value.voucherDate.day} • ${value.paymentMethod.arabicLabel}',
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    CurrencyFormatter.format(value.amount),
                                    style: TextStyle(
                                      color: value.isCancelled
                                          ? RafColors.textMuted
                                          : RafColors.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (value.isCancelled)
                                  const Text('ملغى')
                                else
                                  IconButton(
                                    tooltip: 'إلغاء المصروف',
                                    onPressed: () => _cancel(value),
                                    icon: const Icon(Icons.undo),
                                  ),
                              ],
                            ),
                            Text(
                              value.voucherNumber,
                              style: const TextStyle(
                                fontSize: 11,
                                color: RafColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
