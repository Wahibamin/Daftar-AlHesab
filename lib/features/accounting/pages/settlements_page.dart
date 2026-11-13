import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/accounting/financial_accounts.dart';
import '../../../core/accounting/settlements_repository.dart';
import '../../../core/accounting/treasury_ledger.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/formatters.dart';

class SettlementsPage extends StatefulWidget {
  final SettlementsRepository repository;
  SettlementsPage({super.key, SettlementsRepository? repository})
    : repository = repository ?? SettlementsRepository();
  @override
  State<SettlementsPage> createState() => _SettlementsPageState();
}

class _SettlementsPageState extends State<SettlementsPage> {
  List<Map<String, Object?>> _cheques = [], _receipts = [], _allocations = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cheques = await widget.repository.getCheques();
      final receipts = await widget.repository.getReceipts();
      final allocations = await widget.repository.getAllocations();
      if (mounted) {
        setState(() {
          _cheques = cheques;
          _receipts = receipts;
          _allocations = allocations;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر قراءة السجلات. أعد المحاولة.';
        });
      }
    }
  }

  String _amount(Object? value) =>
      CurrencyFormatter.format(Money((value as int?) ?? 0));
  String _message(Object error) => switch (error) {
    ArgumentError() => error.message?.toString() ?? 'القيمة غير صحيحة',
    StateError() => error.message,
    InsufficientFundsException() => error.message,
    _ => 'تعذر إكمال الطلب. تحقق من السجل قبل إعادة المحاولة.',
  };
  void _notify(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<void> _chequeDialog(Map<String, Object?> row) async {
    final legacy = row['state'] == 'legacy_review';
    final outgoing = row['direction'] == -1;
    var cleared = !legacy;
    var account = TreasuryAccount.values.firstWhere(
      (a) => a.dbValue == (row['account'] ?? 'bank'),
    );
    var effective = DateTime.now();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            legacy
                ? 'مراجعة شيك قديم'
                : 'تأكيد ${outgoing ? 'تسوية' : 'تحصيل'} الشيك',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${row['number']} — ${_amount(row['amount_int'])}'),
                const Text(
                  'هذا الإجراء يحدّث السيولة فقط؛ لن يُرحّل مبلغًا آخر على حساب الطرف.',
                ),
                if (legacy) ...[
                  const Text(
                    'اختر الحقيقة بعد مراجعة السجل؛ لا يمكن استنتاج التحصيل من البيانات القديمة.',
                  ),
                  DropdownButtonFormField<bool>(
                    initialValue: cleared,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: false,
                        child: Text('ما زال قيد الانتظار'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text('سبق تحصيله / تسويته'),
                      ),
                    ],
                    onChanged: busy ? null : (v) => update(() => cleared = v!),
                  ),
                ],
                DropdownButtonFormField<TreasuryAccount>(
                  initialValue: account,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: outgoing
                        ? 'حساب الشيك الصادر'
                        : 'حساب استلام الحصيلة',
                  ),
                  items: TreasuryAccount.values
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(a.arabicLabel),
                        ),
                      )
                      .toList(),
                  onChanged: busy || (outgoing && !legacy)
                      ? null
                      : (a) => update(() => account = a!),
                ),
                if (cleared)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final day = await showDatePicker(
                              context: ctx,
                              initialDate: effective,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (day != null) update(() => effective = day);
                          },
                    child: Text(
                      'تاريخ التسوية: ${effective.year}/${effective.month}/${effective.day}',
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      try {
                        if (legacy) {
                          await widget.repository.reviewLegacyCheque(
                            row['id'] as int,
                            alreadyCleared: cleared,
                            account: account,
                            effectiveAt: effective,
                          );
                        } else {
                          await widget.repository.clearCheque(
                            row['id'] as int,
                            account: account,
                            effectiveAt: effective,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() {
                            busy = false;
                            error = _message(e);
                          });
                        }
                      }
                    },
              child: Text(
                busy
                    ? 'جارٍ الحفظ…'
                    : legacy
                    ? 'تأكيد المراجعة'
                    : 'تأكيد التسوية',
              ),
            ),
          ],
        ),
      ),
    );
    await _load();
  }

  Future<void> _allocate(Map<String, Object?> receipt) async {
    try {
      final invoices = await widget.repository.getOpenInvoices(
        receipt['party_id'] as int,
      );
      if (!mounted) return;
      if (invoices.isEmpty) {
        _notify(StateError('لا توجد فاتورة بيع معتمدة ذات متبقٍ لهذا العميل'));
        return;
      }
      int? invoiceId;
      final amount = TextEditingController();
      final random = Random.secure();
      final key =
          '${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      var busy = false;
      String? error;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text('تخصيص ${receipt['voucher_number']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'غير مخصص: ${_amount((receipt['amount_int'] as int) - (receipt['allocated_int'] as int))}',
                  ),
                  const Text(
                    'اختر الفاتورة يدويًا. لا يوجد تخصيص تلقائي للأقدم، ولن تُسجل حركة مال ثانية.',
                  ),
                  DropdownButtonFormField<int>(
                    key: const Key('allocation_invoice'),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'فاتورة البيع',
                    ),
                    items: invoices
                        .map(
                          (i) => DropdownMenuItem(
                            value: i['id'] as int,
                            child: Text(
                              '${i['invoice_number']} — متبقٍ ${_amount(i['effective_remaining_int'])}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => update(() => invoiceId = v),
                  ),
                  TextField(
                    key: const Key('allocation_amount'),
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المخصص',
                    ),
                  ),
                  const Text(
                    'سيُخصص هذا المبلغ فقط؛ أي بقية من السند ستبقى غير مخصصة.',
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final money = Money.tryParse(amount.text);
                        if (invoiceId == null ||
                            money == null ||
                            !money.isPositive) {
                          update(
                            () => error = 'اختر الفاتورة وأدخل مبلغًا موجبًا',
                          );
                          return;
                        }
                        update(() => busy = true);
                        try {
                          await widget.repository.allocateReceipt(
                            voucherId: receipt['id'] as int,
                            invoiceId: invoiceId!,
                            amount: money,
                            requestKey: key,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            update(() {
                              busy = false;
                              error = _message(e);
                            });
                          }
                        }
                      },
                child: Text(
                  busy ? 'جارٍ الحفظ…' : 'تخصيص المبلغ وإبقاء الباقي',
                ),
              ),
            ],
          ),
        ),
      );
      // The route transition may still hold the field for this frame.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      amount.dispose();
      await _load();
    } catch (e) {
      _notify(e);
    }
  }

  Future<void> _release(Map<String, Object?> allocation) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فك التخصيص؟'),
        content: const Text(
          'سيعود المبلغ غير مخصص في السند، وسيزداد متبقي الفاتورة. لا يتغير رصيد الطرف أو الخزينة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فك التخصيص'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await widget.repository.releaseAllocation(allocation['id'] as int);
        await _load();
      } catch (e) {
        _notify(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('الشيكات وتخصيص القبض'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'الشيكات'),
            Tab(text: 'تخصيص القبض'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'الشيكات المقبوضة قيد التحصيل ليست أموالًا متاحة. الشيك الصادر يحجز من حسابه حتى التسوية. الأثر على حساب الطرف عند قبول المستند.',
                    ),
                    if (_cheques.isEmpty)
                      const ListTile(title: Text('لا توجد شيكات')),
                    for (final c in _cheques)
                      Card(
                        child: ListTile(
                          title: Text(
                            '${c['number']} — ${_amount(c['amount_int'])}',
                          ),
                          subtitle: Text(
                            '${c['direction'] == 1 ? 'مقبوض' : 'صادر'} · ${switch (c['state']) {
                              'legacy_review' => 'يحتاج مراجعة',
                              'pending' => 'قيد الانتظار',
                              _ => 'تمت التسوية',
                            }}',
                          ),
                          trailing: c['state'] == 'cleared'
                              ? null
                              : TextButton(
                                  onPressed: () => _chequeDialog(c),
                                  child: Text(
                                    c['state'] == 'legacy_review'
                                        ? 'مراجعة'
                                        : 'تسوية',
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'رصيد العميل يشمل الافتتاحي والفواتير والمرتجعات وكل السندات. متبقي الفاتورة يشمل دفعة الإصدار والتخصيصات الفعالة فقط؛ القبض غير المخصص لا يخصم منها تلقائيًا.',
                    ),
                    for (final v in _receipts)
                      Card(
                        child: ListTile(
                          title: Text(
                            '${v['voucher_number']} — ${_amount(v['amount_int'])}',
                          ),
                          subtitle: Text(
                            'مخصص: ${_amount(v['allocated_int'])} · غير مخصص: ${_amount((v['amount_int'] as int) - (v['allocated_int'] as int))}',
                          ),
                          trailing:
                              (v['amount_int'] as int) >
                                  (v['allocated_int'] as int)
                              ? TextButton(
                                  onPressed: () => _allocate(v),
                                  child: const Text('تخصيص'),
                                )
                              : null,
                        ),
                      ),
                    const Divider(),
                    const Text('سجل التخصيصات'),
                    if (_allocations.isEmpty)
                      const ListTile(title: Text('لا توجد تخصيصات')),
                    for (final a in _allocations)
                      ListTile(
                        title: Text(
                          '${a['voucher_number']} ← ${a['invoice_number']}',
                        ),
                        subtitle: Text(
                          '${_amount(a['amount_int'])} · ${a['released_at'] != null
                              ? 'مفكوك'
                              : a['voucher_status'] == 'cancelled'
                              ? 'السند ملغى'
                              : 'فعال'}',
                        ),
                        trailing:
                            a['released_at'] == null &&
                                a['voucher_status'] != 'cancelled'
                            ? TextButton(
                                onPressed: () => _release(a),
                                child: const Text('فك التخصيص'),
                              )
                            : null,
                      ),
                  ],
                ),
              ],
            ),
    ),
  );
}
