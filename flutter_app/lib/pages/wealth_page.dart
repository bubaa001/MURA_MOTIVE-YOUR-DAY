import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../models.dart';
import '../refresh_bus.dart';

class WealthPage extends StatefulWidget {
  const WealthPage({super.key});

  @override
  State<WealthPage> createState() => _WealthPageState();
}

class _WealthPageState extends State<WealthPage> with AppRefreshListener {
  List<Habit> _habits = const <Habit>[];
  List<Goal> _goals = const <Goal>[];
  int? _strategicGoalId;
  WealthSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onAppRefresh() => _load();

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        ApiClient.instance.habits(),
        ApiClient.instance.listGoals(),
      ]);
      WealthSummary? summary;
      try {
        summary = await ApiClient.instance.wealthSummary();
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final savedGoalId = prefs.getInt('mura.wealth.strategic_goal_id');
      if (!mounted) return;
      setState(() {
        _habits = results[0] as List<Habit>;
        _goals = results[1] as List<Goal>;
        _summary = summary;
        _strategicGoalId = savedGoalId;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeGoals = _goals.where((item) => !item.isAchieved).toList();
    final goal =
        activeGoals.where((item) => item.id == _strategicGoalId).firstOrNull ??
            activeGoals.firstOrNull;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
            children: [
              Text(
                'Discipline compounds. Every decision shapes your financial architecture.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              _journeyCard(context, goal),
              const SizedBox(height: 16),
              _profitLossCard(context),
              const SizedBox(height: 16),
              _metricsCard(context),
              const SizedBox(height: 16),
              _metricCard(
                context,
                icon: Icons.account_balance_outlined,
                label: 'NET WORTH',
                title: _summary?.netWorth == null
                    ? 'Add net worth manually'
                    : '${_summary!.currency} ${_summary!.netWorth!.toStringAsFixed(2)}',
                subtitle: 'Optional manual snapshot; no card access required.',
                accent: scheme.tertiary,
              ),
              const SizedBox(height: 16),
              _metricCard(
                context,
                icon: Icons.trending_up_rounded,
                label: 'INCOME STREAMS',
                title: _summary == null
                    ? 'Add income manually'
                    : '${_summary!.currency} ${_summary!.monthlyIncome.toStringAsFixed(2)} / month',
                subtitle: _summary == null
                    ? 'No bank or card connection is required.'
                    : 'Recurring income currently tracked.',
                accent: scheme.primary,
              ),
              const SizedBox(height: 16),
              _ledgerCard(context),
              const SizedBox(height: 16),
              _goalCard(context, goal, activeGoals),
              const SizedBox(height: 22),
              Text(
                'DAILY DISCIPLINE',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_habits.isEmpty)
                _emptyCard(context, 'Create a habit to build daily discipline.')
              else
                ..._habits.take(4).map((habit) => _habitCard(context, habit)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  )),
            ],
          ),
          const SizedBox(height: 20),
          Text(title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              )),
        ],
      ),
    );
  }

  Widget _ledgerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final hasEntries = summary != null &&
        (summary.incomeStreams.isNotEmpty ||
            summary.profitEntries.isNotEmpty ||
            summary.netWorthHistory.isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text('MANUAL LEDGER',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasEntries)
            Text(
                'Your income, results, and net-worth snapshots will appear here.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
          else ...[
            ...summary.incomeStreams.take(4).map(
                  (stream) => _ledgerRow(
                    context,
                    icon: Icons.arrow_upward_rounded,
                    color: scheme.tertiary,
                    title: stream.name,
                    subtitle: '${stream.frequency} income',
                    amount:
                        '${summary.currency} ${stream.amount.toStringAsFixed(2)}',
                    onEdit: () => _editIncomeStream(context, stream),
                    onDelete: () => _deleteLedgerEntry(
                      context,
                      'income stream',
                      () => ApiClient.instance.deleteIncomeStream(stream.id),
                    ),
                  ),
                ),
            ...summary.profitEntries.take(8).map(
                  (entry) => _ledgerRow(
                    context,
                    icon: entry.type == 'loss'
                        ? Icons.arrow_downward_rounded
                        : Icons.trending_up_rounded,
                    color:
                        entry.type == 'loss' ? scheme.error : scheme.tertiary,
                    title: entry.type == 'loss' ? 'Loss' : 'Profit',
                    subtitle: entry.note.isEmpty
                        ? entry.date
                        : '${entry.date} · ${entry.note}',
                    amount:
                        '${summary.currency} ${entry.amount.toStringAsFixed(2)}',
                    onEdit: () => _editProfitEntry(context, entry),
                    onDelete: () => _deleteLedgerEntry(
                      context,
                      '${entry.type} entry',
                      () => ApiClient.instance.deleteProfitEntry(entry.id),
                    ),
                  ),
                ),
            ...summary.netWorthHistory.take(4).map(
                  (snapshot) => _ledgerRow(
                    context,
                    icon: Icons.account_balance_outlined,
                    color: scheme.primary,
                    title: 'Net worth',
                    subtitle: snapshot.asOf,
                    amount:
                        '${summary.currency} ${snapshot.amount.toStringAsFixed(2)}',
                    onEdit: () => _editNetWorthSnapshot(context, snapshot),
                    onDelete: () => _deleteLedgerEntry(
                      context,
                      'net-worth snapshot',
                      () => ApiClient.instance
                          .deleteNetWorthSnapshot(snapshot.id),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String amount,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Text(amount,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
          ),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLedgerEntry(
    BuildContext context,
    String label,
    Future<void> Function() delete,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $label?'),
        content: const Text('This manual entry will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await delete();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete $label.')),
        );
      }
    }
  }

  Future<Map<String, String>?> _entryForm(
    BuildContext context, {
    required String title,
    required Map<String, String> initial,
    required List<String> fields,
  }) async {
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field: TextEditingController(text: initial[field] ?? ''),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in fields)
                TextField(
                  controller: controllers[field],
                  keyboardType: field == 'name' || field == 'note'
                      ? TextInputType.text
                      : const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: field),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              <String, String>{
                for (final field in fields)
                  field: controllers[field]!.text.trim(),
              },
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _editIncomeStream(
      BuildContext context, IncomeStream stream) async {
    final values = await _entryForm(
      context,
      title: 'Edit income stream',
      initial: <String, String>{
        'name': stream.name,
        'amount': stream.amount.toStringAsFixed(2),
      },
      fields: const <String>['name', 'amount'],
    );
    final amount = double.tryParse(values?['amount'] ?? '');
    if (values == null ||
        values['name']!.isEmpty ||
        amount == null ||
        amount < 0) {
      return;
    }
    try {
      await ApiClient.instance.updateIncomeStream(
        stream.id,
        name: values['name']!,
        amount: amount,
        frequency: stream.frequency,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update income stream.')));
      }
    }
  }

  Future<void> _editProfitEntry(BuildContext context, ProfitEntry entry) async {
    final values = await _entryForm(
      context,
      title: 'Edit ${entry.type}',
      initial: <String, String>{
        'amount': entry.amount.toStringAsFixed(2),
        'date': entry.date,
        'note': entry.note,
      },
      fields: const <String>['amount', 'date', 'note'],
    );
    final amount = double.tryParse(values?['amount'] ?? '');
    if (values == null ||
        amount == null ||
        amount < 0 ||
        values['date']!.isEmpty) {
      return;
    }
    try {
      await ApiClient.instance.updateProfitEntry(
        entry.id,
        amount: amount,
        date: values['date']!,
        type: entry.type,
        note: values['note'] ?? '',
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update ledger entry.')));
      }
    }
  }

  Future<void> _editNetWorthSnapshot(
      BuildContext context, NetWorthSnapshot snapshot) async {
    final values = await _entryForm(
      context,
      title: 'Edit net-worth snapshot',
      initial: <String, String>{
        'amount': snapshot.amount.toStringAsFixed(2),
        'date': snapshot.asOf,
        'note': snapshot.note,
      },
      fields: const <String>['amount', 'date', 'note'],
    );
    final amount = double.tryParse(values?['amount'] ?? '');
    if (values == null || amount == null || values['date']!.isEmpty) return;
    try {
      await ApiClient.instance.updateNetWorthSnapshot(
        snapshot.id,
        amount: amount,
        asOf: values['date']!,
        note: values['note'] ?? '',
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update net-worth snapshot.')));
      }
    }
  }

  Widget _profitLossCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final profit = summary?.monthlySavings;
    final positive = (profit ?? 0) >= 0;
    final currency = summary?.currency ?? 'USD';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance_rounded,
                  color: positive ? scheme.tertiary : scheme.error),
              const SizedBox(width: 8),
              Text('MONTHLY PROFIT & LOSS',
                  style: TextStyle(
                    color: positive ? scheme.tertiary : scheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  )),
              const Spacer(),
              IconButton(
                tooltip: 'Update finances',
                onPressed: () => _showFinanceEditor(context),
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            summary == null
                ? 'No data yet'
                : '$currency ${profit!.toStringAsFixed(2)}',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary == null
                ? 'Enter income and expenses manually. We never request card details.'
                : '$currency ${summary.monthlyIncome.toStringAsFixed(2)} income - '
                    '$currency ${summary.monthlyExpenses.toStringAsFixed(2)} expenses '
                    '(${summary.savingsRate.toStringAsFixed(1)}% margin)',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _metricsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    String value(double? amount) => summary == null
        ? '--'
        : '${summary.currency} ${(amount ?? 0).toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PERFORMANCE METRICS',
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3)),
          const SizedBox(height: 14),
          Row(
            children: [
              _metricValue('AVG / MONTH', value(summary?.averageMonthlyProfit),
                  scheme.primary),
              _metricValue(
                  'NET MARGIN',
                  '${(summary?.netProfitMargin ?? 0).toStringAsFixed(1)}%',
                  scheme.tertiary),
              _metricValue(
                  'EXPENSE RATIO',
                  '${(summary?.expenseRatio ?? 0).toStringAsFixed(1)}%',
                  scheme.error),
            ],
          ),
          const SizedBox(height: 10),
          Text('Calculated from manual entries since your journey start date.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _metricValue(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _journeyCard(BuildContext context, Goal? goal) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final result = summary?.netResultSinceStart ?? 0;
    final positive = result >= 0;
    final since = summary?.journeyStartDate;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerLowest],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('WEALTH JOURNEY',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  )),
              const Spacer(),
              IconButton(
                tooltip: 'Set journey start date',
                onPressed: () => _pickJourneyStartDate(context),
                icon: const Icon(Icons.event_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('From commitment to results',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 14),
          Text(
            summary == null
                ? 'Set your start date and record results manually.'
                : '${summary.currency} ${result.toStringAsFixed(2)} '
                    '${positive ? 'generated' : 'down'} since ${since ?? 'starting'}',
            style: TextStyle(
              color: positive ? scheme.tertiary : scheme.error,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            goal == null
                ? 'Choose one definite chief aim below to keep the journey focused.'
                : 'Chief aim: ${goal.title}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _journeyStat(
                  'PROFIT', summary?.profitSinceStart ?? 0, scheme.tertiary),
              const SizedBox(width: 18),
              _journeyStat('LOSS', summary?.lossSinceStart ?? 0, scheme.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journeyStat(String label, double value, Color color) {
    final currency = _summary?.currency ?? 'USD';
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 3),
          Text('$currency ${value.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _pickJourneyStartDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'When did your Wealth Journey begin?',
    );
    if (picked == null || !mounted) return;
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    try {
      await ApiClient.instance.updateWealthProfile(
        monthlyExpenses: _summary?.monthlyExpenses,
        startDate: date,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save journey start date.')),
        );
      }
    }
  }

  Future<void> _showFinanceEditor(BuildContext context) async {
    final expenseController = TextEditingController(
      text: _summary?.monthlyExpenses.toStringAsFixed(2) ?? '',
    );
    final incomeNameController = TextEditingController();
    final incomeAmountController = TextEditingController();
    final netWorthController = TextEditingController();
    final profitController = TextEditingController();
    final lossController = TextEditingController();
    final previousCurrency = _summary?.currency ?? 'USD';
    String currency = previousCurrency;
    final form = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update Wealth Manually'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: const [
                    DropdownMenuItem(
                        value: 'USD', child: Text('USD - US Dollar')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR - Euro')),
                    DropdownMenuItem(
                        value: 'GBP', child: Text('GBP - Pound Sterling')),
                    DropdownMenuItem(
                        value: 'CAD', child: Text('CAD - Canadian Dollar')),
                    DropdownMenuItem(
                        value: 'AUD', child: Text('AUD - Australian Dollar')),
                    DropdownMenuItem(
                        value: 'JPY', child: Text('JPY - Japanese Yen')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => currency = value);
                  },
                ),
                TextField(
                  controller: expenseController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Monthly expenses'),
                ),
                TextField(
                  controller: incomeNameController,
                  decoration: const InputDecoration(labelText: 'Income name'),
                ),
                TextField(
                  controller: incomeAmountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Monthly income'),
                ),
                TextField(
                  controller: netWorthController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Current net worth'),
                ),
                TextField(
                  controller: profitController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Profit generated'),
                ),
                TextField(
                  controller: lossController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Loss recorded'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final expenses = double.tryParse(expenseController.text.trim());
    final income = double.tryParse(incomeAmountController.text.trim());
    final netWorth = double.tryParse(netWorthController.text.trim());
    final profit = double.tryParse(profitController.text.trim());
    final loss = double.tryParse(lossController.text.trim());
    final incomeName = incomeNameController.text.trim();
    if (form != 'save' || !mounted) return;
    try {
      if (expenses != null || currency != previousCurrency) {
        await ApiClient.instance.updateWealthProfile(
          monthlyExpenses: expenses,
          currency: currency,
        );
      }
      if (income != null && incomeName.isNotEmpty) {
        await ApiClient.instance.addIncomeStream(
          name: incomeName,
          amount: income,
        );
      }
      if (netWorth != null) {
        final now = DateTime.now();
        await ApiClient.instance.addNetWorthSnapshot(
          amount: netWorth,
          asOf:
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        );
      }
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (profit != null && profit > 0) {
        await ApiClient.instance.addProfitEntry(
          amount: profit,
          date: today,
          type: 'profit',
        );
      }
      if (loss != null && loss > 0) {
        await ApiClient.instance.addProfitEntry(
          amount: loss,
          date: today,
          type: 'loss',
        );
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save Wealth data.')),
        );
      }
    }
  }

  Widget _goalCard(BuildContext context, Goal? goal, List<Goal> activeGoals) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ((goal?.progress ?? 0).clamp(0, 100)) / 100;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.tertiary,
                ),
                Text('${goal?.progress ?? 0}%',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STRATEGIC GOAL',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(height: 5),
                Text(goal?.title ?? 'No goal selected',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Text(
                  goal == null
                      ? 'Create a goal in Plan to track it here.'
                      : (goal.description.isEmpty
                          ? 'Keep moving toward your target.'
                          : goal.description),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Set strategic goal',
            onPressed: activeGoals.isEmpty
                ? null
                : () => _selectStrategicGoal(context, activeGoals),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _selectStrategicGoal(
      BuildContext context, List<Goal> activeGoals) async {
    final selected = await showDialog<Goal>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set strategic goal'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: activeGoals
                .map(
                  (goal) => RadioListTile<int>(
                    value: goal.id,
                    groupValue: _strategicGoalId,
                    title: Text(goal.title),
                    subtitle: goal.description.isEmpty
                        ? null
                        : Text(goal.description,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    onChanged: (_) => Navigator.of(dialogContext).pop(goal),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mura.wealth.strategic_goal_id', selected.id);
    if (mounted) setState(() => _strategicGoalId = selected.id);
  }

  Widget _habitCard(BuildContext context, Habit habit) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(habit.name,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ))),
          Text('${habit.currentStreak} day streak',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _emptyCard(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}
