import 'package:flutter/material.dart';
import '../../../core/theme/raf_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../models/party_model.dart';
import '../services/communication_service.dart';
import 'balance_badge.dart';

/// Clean minimalist card widget representing a commercial customer or supplier.
class PartyCard extends StatelessWidget {
  final PartyModel party;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenStatement;
  final void Function(String message)? onSendWhatsApp;

  const PartyCard({
    super.key,
    required this.party,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onOpenStatement,
    this.onSendWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final formattedPhone = PhoneNumberFormatter.formatSaudi(party.phone);

    return Container(
      margin: const EdgeInsets.only(bottom: RafSpacing.sm + 2),
      decoration: RafDecorations.cardFlat,
      child: Material(
        color: Colors.transparent,
        borderRadius: RafRadius.roundedMd,
        child: InkWell(
          borderRadius: RafRadius.roundedMd,
          onTap: onTap ?? onOpenStatement ?? onEdit,
          child: Padding(
            padding: const EdgeInsets.all(RafSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Name, Type Badge, and Popup Menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  party.name,
                                  style: RafTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: RafSpacing.xs),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: RafColors.surfaceSecondary,
                                    borderRadius: RafRadius.roundedSm,
                                    border: Border.all(color: RafColors.border),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      party.type.arabicLabel,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: RafColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: RafSpacing.xs),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: RafSpacing.xs,
                            runSpacing: 2,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.phone_outlined,
                                    size: 14,
                                    color: RafColors.textMuted,
                                  ),
                                  const SizedBox(width: RafSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      formattedPhone,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: RafTypography.fontFamily,
                                        color: RafColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (party.address != null &&
                                  party.address!.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '•',
                                      style: TextStyle(
                                        color: RafColors.borderStrong,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: RafSpacing.xs),
                                    Flexible(
                                      child: Text(
                                        party.address!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: RafTypography.fontFamily,
                                          color: RafColors.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: RafColors.secondary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 140),
                      elevation: 3,
                      shape: const RoundedRectangleBorder(
                        borderRadius: RafRadius.roundedMd,
                        side: BorderSide(color: RafColors.border),
                      ),
                      color: RafColors.surface,
                      onSelected: (val) {
                        if (val == 'statement') onOpenStatement?.call();
                        if (val == 'edit') onEdit?.call();
                        if (val == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'statement',
                          child: Row(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 16,
                                color: RafColors.primary,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'كشف الحساب',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: RafColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: RafColors.secondary,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'تعديل البيانات',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: RafColors.danger,
                              ),
                              SizedBox(width: RafSpacing.sm),
                              Text(
                                'أرشفة الطرف',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: RafColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(height: RafSpacing.lg, color: RafColors.border),

                // Middle Row: Balance Badge and Credit Limit Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(child: BalanceBadge(party: party)),
                    if (!party.creditLimit.isZero)
                      Flexible(
                        child: Text(
                          'سقف: ${party.creditLimit.format()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: RafTypography.fontFamily,
                            color: RafColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: RafSpacing.md),

                // Bottom Action Strip: Call, WhatsApp, Statement Quick Actions
                Row(
                  children: [
                    // Statement Action Button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: RafSpacing.xs + 2,
                          ),
                          side: const BorderSide(color: RafColors.border),
                          shape: const RoundedRectangleBorder(
                            borderRadius: RafRadius.roundedSm,
                          ),
                        ),
                        onPressed: onOpenStatement,
                        icon: const Icon(Icons.receipt_long_outlined, size: 15),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'كشف الحساب',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: RafSpacing.xs),

                    // WhatsApp Reminder Button
                    IconButton.outlined(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF25D366)),
                      ),
                      tooltip: 'إرسال تذكير بالرصيد عبر واتساب',
                      icon: const Icon(
                        Icons.chat_outlined,
                        size: 16,
                        color: Color(0xFF25D366),
                      ),
                      onPressed: () {
                        final msg = CommunicationService.formatBalanceMessage(
                          partyName: party.name,
                          balance: party.currentBalance,
                        );
                        if (onSendWhatsApp != null) {
                          onSendWhatsApp!(msg);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'معاينة فقط؛ لم يتم فتح واتساب أو إرسال الرسالة:\n$msg',
                              ),
                              backgroundColor: RafColors.secondary,
                            ),
                          );
                        }
                      },
                    ),

                    const SizedBox(width: RafSpacing.xs),

                    // Direct Phone Call Button
                    IconButton.outlined(
                      tooltip: 'اتصال هاتفي',
                      icon: const Icon(
                        Icons.phone_outlined,
                        size: 16,
                        color: RafColors.primary,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'الاتصال الهاتفي غير منفذ في هذه النسخة. الرقم: $formattedPhone',
                            ),
                            backgroundColor: RafColors.primary,
                          ),
                        );
                      },
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
}
