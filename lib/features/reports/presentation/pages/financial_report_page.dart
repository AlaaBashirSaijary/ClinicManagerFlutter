import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../../patients/domain/usecases/get_new_patients_count.dart'
    show DateRangeParams;
import '../../../visits/domain/entities/financial_report.dart';
import '../../../visits/domain/usecases/get_financial_report.dart';
import '../pdf/financial_report_pdf_export.dart';

/// Real money in, real money out — actual fee/payment amounts entered per
/// visit, summed for a month, as opposed to MonthlyReportPage's count of
/// appointment types.
class FinancialReportPage extends ConsumerStatefulWidget {
  const FinancialReportPage({super.key});

  @override
  ConsumerState<FinancialReportPage> createState() =>
      _FinancialReportPageState();
}

class _FinancialReportPageState extends ConsumerState<FinancialReportPage> {
  static final _monthFormat = DateFormat('MMMM yyyy', 'ar');
  static final _dateFormat = DateFormat('yyyy/MM/dd');

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  FinancialReport _report = const FinancialReport();

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await sl<GetFinancialReport>().call(
      DateRangeParams(start: _month, end: _monthEnd),
    );

    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (report) => setState(() {
        _loading = false;
        _report = report;
      }),
    );
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await FinancialReportPdfExport.export(
        clinicName: ref.read(activeClinicProvider).active?.name ?? '',
        month: _month,
        report: _report,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر تصدير التقرير: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقرير المالي'),
        actions: [
          IconButton(
            tooltip: 'طباعة / تصدير PDF',
            onPressed: (_loading || _exporting) ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: ResponsiveBody(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _monthFormat.format(_month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (!_isCurrentMonth)
                          TextButton(
                            onPressed: () {
                              final now = DateTime.now();
                              setState(
                                () => _month = DateTime(now.year, now.month),
                              );
                              _load();
                            },
                            child: const Text(
                              'العودة للشهر الحالي',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: _MoneyTile(
                                icon: Icons.request_quote_rounded,
                                color: AppColors.aqua,
                                value: _report.totalFees,
                                label: 'إجمالي الكشفيات',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _MoneyTile(
                                icon: Icons.savings_rounded,
                                color: AppColors.ok,
                                value: _report.totalCollected,
                                label: 'المُحصَّل فعليًا',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _MoneyTile(
                                icon: Icons.pending_actions_rounded,
                                color: AppColors.danger,
                                value: _report.totalRemaining,
                                label: 'متبقٍّ غير محصَّل',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _MoneyTile(
                                icon: Icons.event_note_rounded,
                                color: AppColors.focus,
                                value: _report.pricedVisitCount.toDouble(),
                                label: 'زيارات مُسعَّرة',
                                isCount: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_report.rows.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.sky.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'لا توجد زيارات مُسعَّرة هذا الشهر. الكشفية '
                              'تُدخل يدويًا من نموذج الزيارة.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: AppShadows.card,
                            ),
                            child: Column(
                              children: [
                                for (final row in _report.rows)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.sm,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                row.patientName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                _dateFormat.format(
                                                  row.visitDate,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.inkSoft,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${row.amountPaid.toStringAsFixed(0)} '
                                          'ل.س',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: row.remaining > 0
                                                ? AppColors.danger
                                                : AppColors.ok,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  const _MoneyTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.isCount = false,
  });

  final IconData icon;
  final Color color;
  final double value;
  final String label;
  final bool isCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isCount
                ? value.toStringAsFixed(0)
                : '${value.toStringAsFixed(0)} ل.س',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
