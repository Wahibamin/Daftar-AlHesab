import 'package:flutter/material.dart';
import '../../../core/accounting/financial_accounts.dart';

class ChequeAccountSelector extends StatelessWidget {
  final TreasuryAccount value;
  final ValueChanged<TreasuryAccount>? onChanged;
  const ChequeAccountSelector({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<TreasuryAccount>(
      key: const Key('outgoing_cheque_account'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'حساب حجز الشيك الصادر',
        helperText: 'تُحجز القيمة من المتاح حتى تسوية الشيك.',
      ),
      items: TreasuryAccount.values
          .map((a) => DropdownMenuItem(value: a, child: Text(a.arabicLabel)))
          .toList(),
      onChanged: onChanged == null
          ? null
          : (a) {
              if (a != null) onChanged!(a);
            },
    ),
  );
}
