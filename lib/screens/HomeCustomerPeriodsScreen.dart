import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/models/home_customer.dart';
import '../theme/app_theme.dart';

class HomeCustomerPeriodsScreen extends StatefulWidget {
  final String customerId;
  final String? customerName;
  const HomeCustomerPeriodsScreen({super.key, required this.customerId, this.customerName});

  @override
  State<HomeCustomerPeriodsScreen> createState() => _HomeCustomerPeriodsScreenState();
}

class _HomeCustomerPeriodsScreenState extends State<HomeCustomerPeriodsScreen> {
  final _dateFmt = DateFormat('yyyy-MM-dd');
  List<PeriodPaymentStatus> _periods = [];
  HomeCustomer? _customer;
  bool _loading = true;
  String _filter = 'all'; // all, paid, partial, unpaid

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customer = await HomeInternetService.getCustomer(widget.customerId);
      List<PeriodPaymentStatus> periods = [];
      if (customer?.status != null && customer!.status!['periods'] != null) {
        final periodsList = customer.status!['periods'] as List;
        periods = periodsList.map((p) {
          final start = (p['start'] as Timestamp).toDate();
          final end = (p['end'] as Timestamp).toDate();
          final due = (p['due'] as Timestamp).toDate();
          final required = (p['required_amount'] as num).toDouble();
          final paid = (p['paid_amount'] as num).toDouble();
          final stateStr = p['state'] as String;
          final state = stateStr == 'paid' ? PeriodPayState.paid : 
                       (stateStr == 'partial' ? PeriodPayState.partial : PeriodPayState.unpaid);
          return PeriodPaymentStatus(
            start: start,
            end: end,
            due: due,
            requiredAmount: required,
            paidAmount: paid,
            state: state,
          );
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _periods = periods;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Billing Periods${widget.customerName != null ? ' • ${widget.customerName}' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_customer == null) {
      return const Center(child: Text('Customer not found'));
    }

    final plan = _customer!.planAmount;
    final filtered = _applyFilter(_periods, _filter);

    final paidCount = _periods.where((p) => p.state == PeriodPayState.paid).length;
    final partialCount = _periods.where((p) => p.state == PeriodPayState.partial).length;
    final unpaidCount = _periods.where((p) => p.state == PeriodPayState.unpaid).length;
    final totalPaid = _periods.fold<double>(0, (sum, p) => sum + p.paidAmount);
    final totalRequired = _periods.fold<double>(0, (sum, p) => sum + p.requiredAmount);
    final outstanding = (totalRequired - totalPaid);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan Amount: TZS ${NumberFormat('#,##0').format(plan)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _chipStat('Due', _periods.length, AppTheme.textSecondary),
                      _chipStat('Paid', paidCount, AppTheme.successColor),
                      _chipStat('Partial', partialCount, AppTheme.warningColor),
                      _chipStat('Unpaid', unpaidCount, AppTheme.errorColor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Outstanding: TZS ${NumberFormat('#,##0').format(outstanding)}',
                    style: TextStyle(
                      color: outstanding > 0 ? AppTheme.errorColor : AppTheme.successColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filters
          _buildFilters(),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No periods for this filter'),
            ))
          else
            ...filtered.map(_buildPeriodTile),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: _filter == 'all',
          onSelected: (_) => setState(() => _filter = 'all'),
        ),
        ChoiceChip(
          label: const Text('Paid'),
          selected: _filter == 'paid',
          onSelected: (_) => setState(() => _filter = 'paid'),
        ),
        ChoiceChip(
          label: const Text('Partial'),
          selected: _filter == 'partial',
          onSelected: (_) => setState(() => _filter = 'partial'),
        ),
        ChoiceChip(
          label: const Text('Unpaid'),
          selected: _filter == 'unpaid',
          onSelected: (_) => setState(() => _filter = 'unpaid'),
        ),
      ],
    );
  }

  List<PeriodPaymentStatus> _applyFilter(List<PeriodPaymentStatus> items, String filter) {
    switch (filter) {
      case 'paid':
        return items.where((e) => e.state == PeriodPayState.paid).toList();
      case 'partial':
        return items.where((e) => e.state == PeriodPayState.partial).toList();
      case 'unpaid':
        return items.where((e) => e.state == PeriodPayState.unpaid).toList();
      case 'all':
      default:
        return items;
    }
  }

  Widget _buildPeriodTile(PeriodPaymentStatus p) {
    final isPaid = p.state == PeriodPayState.paid;
    final isPartial = p.state == PeriodPayState.partial;
    final color = isPaid
        ? AppTheme.successColor
        : (isPartial ? AppTheme.warningColor : AppTheme.errorColor);
    final icon = isPaid
        ? Icons.check_circle_rounded
        : (isPartial ? Icons.hourglass_bottom_rounded : Icons.error_rounded);

    final requiredFmt = NumberFormat('#,##0').format(p.requiredAmount);
    final paidFmt = NumberFormat('#,##0').format(p.paidAmount);
    final ratio = p.requiredAmount > 0 ? (p.paidAmount / p.requiredAmount).clamp(0.0, 1.0) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_dateFmt.format(p.start)}  -  ${_dateFmt.format(p.end)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    p.state.name.toUpperCase(),
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 10),
                Text('$paidFmt / $requiredFmt'),
              ],
            ),
            const SizedBox(height: 6),
            Text('Due: ${_dateFmt.format(p.due)}', style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _chipStat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: $value', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
