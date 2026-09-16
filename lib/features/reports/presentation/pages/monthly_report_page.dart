import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../appointments/domain/entities/appointment.dart';
import '../../../appointments/domain/usecases/get_monthly_appointment_counts.dart';
import '../../../patients/domain/usecases/get_new_patients_count.dart';

/// A per-month snapshot for the clinic owner: how many paid consultations
/// and free follow-ups happened, and how many new patients came in — all
/// derived from data already recorded (appointment type, patient
/// created_at), no separate bookkeeping needed.
class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  static final _monthFormat = DateFormat('MMMM yyyy', 'ar');

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  int _consultations = 0;
  int _followUps = 0;
  int _newPatients = 0;
  String? _error;

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

    final appointmentsResult = await sl<GetMonthlyAppointmentCounts>().call(
      MonthRangeParams(start: _month, end: _monthEnd),
    );
    final patientsResult = await sl<GetNewPatientsCount>().call(
      DateRangeParams(start: _month, end: _monthEnd),
    );

    if (!mounted) return;

    final appointmentsError = appointmentsResult.fold(
      (failure) => failure.message,
      (_) => null,
    );
    final patientsError = patientsResult.fold(
      (failure) => failure.message,
      (_) => null,
    );

    setState(() {
      _loading = false;
      _error = appointmentsError ?? patientsError;
      appointmentsResult.fold((_) {}, (counts) {
        _consultations = counts[AppointmentType.consultation] ?? 0;
        _followUps = counts[AppointmentType.followUp] ?? 0;
      });
      patientsResult.fold((_) {}, (count) => _newPatients = count);
    });
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الشهري')),
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
                              child: _ReportTile(
                                icon: Icons.payments_rounded,
                                color: AppColors.danger,
                                value: _consultations,
                                label: 'كشفيات مدفوعة',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _ReportTile(
                                icon: Icons.volunteer_activism_rounded,
                                color: AppColors.ok,
                                value: _followUps,
                                label: 'متابعات مجانية',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _ReportTile(
                                icon: Icons.groups_rounded,
                                color: AppColors.aqua,
                                value: _newPatients,
                                label: 'مرضى جدد',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _ReportTile(
                                icon: Icons.event_note_rounded,
                                color: AppColors.focus,
                                value: _consultations + _followUps,
                                label: 'إجمالي المواعيد',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.sky.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'لا تشمل هذه الأرقام المواعيد الملغاة. الكشفيات '
                            'والمتابعات محسوبة حسب نوع الموعد وقت الحجز.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                            ),
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

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

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
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
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
