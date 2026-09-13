import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/theme/app_theme.dart';

class HiMoney {
  static final NumberFormat _fmt = NumberFormat('#,##0');

  static String format(dynamic value, {String currency = 'TZS'}) {
    return '$currency ${_fmt.format(HomeInternetService.asMoney(value))}';
  }
}

class HiAccountStatement extends StatelessWidget {
  final Map<String, dynamic> statement;
  final String? accountName;
  final bool compact;
  final VoidCallback? onPayNow;

  const HiAccountStatement({
    super.key,
    required this.statement,
    this.accountName,
    this.compact = false,
    this.onPayNow,
  });

  @override
  Widget build(BuildContext context) {
    final currency = '${statement['currency'] ?? 'TZS'}';
    final thisMonth = HomeInternetService.asMoney(statement['this_month_bill']);
    final arrears = HomeInternetService.asMoney(statement['arrears']);
    final credit = HomeInternetService.asMoney(statement['credit']);
    final payNow = HomeInternetService.asMoney(statement['pay_now']);
    final outstanding = HomeInternetService.asMoney(statement['outstanding_amount']);
    final overdue = statement['overdue'] == true;
    final invoiceNo = statement['current_invoice_no']?.toString();
    final nextDue = statement['next_due_date'];
    final asOf = statement['as_of'];
    final aging = statement['aging'] is Map
        ? Map<String, dynamic>.from(statement['aging'] as Map)
        : const <String, dynamic>{};

    Color statusColor = AppTheme.successColor;
    String statusText = 'Settled';
    IconData statusIcon = Icons.verified_rounded;
    if (payNow > 0) {
      if (overdue) {
        statusColor = AppTheme.errorColor;
        statusText = 'Overdue';
        statusIcon = Icons.warning_amber_rounded;
      } else {
        statusColor = AppTheme.warningColor;
        statusText = 'Amount due';
        statusIcon = Icons.receipt_long_rounded;
      }
    } else if (credit > 0 || outstanding < 0) {
      statusColor = AppTheme.infoColor;
      statusText = 'Credit balance';
      statusIcon = Icons.account_balance_wallet_rounded;
    }

    return Card(
      elevation: compact ? 1 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: compact ? 18 : 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    compact ? 'Account statement' : 'Account statement',
                    style: TextStyle(
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (accountName != null && accountName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(accountName!, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
            if (invoiceNo != null && invoiceNo.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Invoice $invoiceNo',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (asOf is DateTime || nextDue is DateTime) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (asOf is DateTime) 'As of ${DateFormat('d MMM yyyy').format(asOf)}',
                  if (nextDue is DateTime) 'Next bill ${DateFormat('d MMM yyyy').format(nextDue)}',
                ].join('  ·  '),
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
              ),
            ],
            const Divider(height: 22),
            _line('This month\'s charges', HiMoney.format(thisMonth, currency: currency)),
            const SizedBox(height: 8),
            _line('Arrears', HiMoney.format(arrears, currency: currency),
                valueColor: arrears > 0 ? AppTheme.errorColor : null),
            const SizedBox(height: 8),
            _line('Account credit', HiMoney.format(credit, currency: currency),
                valueColor: credit > 0 ? AppTheme.infoColor : null),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: (payNow > 0 ? statusColor : AppTheme.successColor).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Amount due',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: payNow > 0 ? statusColor : AppTheme.successColor,
                      ),
                    ),
                  ),
                  Text(
                    HiMoney.format(payNow, currency: currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: payNow > 0 ? statusColor : AppTheme.successColor,
                    ),
                  ),
                ],
              ),
            ),
            if (!compact && aging.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Aging',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _agingChip('Current', aging['current']),
                  _agingChip('1–30', aging['days_1_30']),
                  _agingChip('31–60', aging['days_31_60']),
                  _agingChip('61–90', aging['days_61_90']),
                  _agingChip('90+', aging['days_90_plus']),
                ],
              ),
            ],
            if (onPayNow != null && payNow > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onPayNow,
                  icon: const Icon(Icons.payments_rounded),
                  label: Text('Pay ${HiMoney.format(payNow, currency: currency)}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _agingChip(String label, dynamic value) {
    final amount = HomeInternetService.asMoney(value);
    final active = amount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (active ? AppTheme.warningColor : AppTheme.textTertiary).withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label ${NumberFormat('#,##0').format(amount)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: active ? AppTheme.warningColor : AppTheme.textTertiary,
        ),
      ),
    );
  }
}
