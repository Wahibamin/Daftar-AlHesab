import 'package:flutter/material.dart';
import '../../../core/accounting/financial_accounts.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/raf_design_system.dart';

class TreasuryAccountsCard extends StatelessWidget {
  final TreasurySnapshot snapshot;
  final bool showFlows;
  const TreasuryAccountsCard({
    super.key,
    required this.snapshot,
    this.showFlows = false,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(RafSpacing.md),
    child: Padding(
      padding: const EdgeInsets.all(RafSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الأرصدة المتاحة حسب الحساب',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final account in TreasuryAccount.values) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(account.arabicLabel)),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      CurrencyFormatter.format(
                        snapshot.forAccount(account).available,
                      ),
                      key: ValueKey('balance_${account.dbValue}'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            if (!snapshot.forAccount(account).reserved.isZero)
              Text(
                'رصيد محصل: ${CurrencyFormatter.format(snapshot.forAccount(account).balance)} · محجوز: ${CurrencyFormatter.format(snapshot.forAccount(account).reserved)}',
              ),
            if (showFlows)
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'مقبوضات: ${CurrencyFormatter.format(snapshot.forAccount(account).receipts)}',
                  ),
                  Text(
                    'مدفوعات: ${CurrencyFormatter.format(snapshot.forAccount(account).payments)}',
                  ),
                  Text(
                    'صافي الفترة: ${CurrencyFormatter.format(snapshot.forAccount(account).net)}',
                  ),
                ],
              ),
          ],
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('إجمالي المتاح للصرف')),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    CurrencyFormatter.format(snapshot.total.available),
                  ),
                ),
              ),
            ],
          ),
          Text(
            'شيكات مقبوضة قيد التحصيل: ${CurrencyFormatter.format(snapshot.pendingCheques)}',
          ),
          if (snapshot.legacyReviewCount > 0)
            Text(
              'شيكات قديمة تحتاج مراجعة: ${snapshot.legacyReviewCount}. لا نفترض أنها محصلة.',
            ),
        ],
      ),
    ),
  );
}
