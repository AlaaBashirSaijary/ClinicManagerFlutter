import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/fade_slide_in.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../../visits/domain/entities/visit.dart';
import '../../../visits/presentation/pages/photo_comparison_page.dart';
import '../../../visits/presentation/pages/visit_form_page.dart';
import '../../../visits/presentation/providers/follow_ups_provider.dart';
import '../../../visits/presentation/providers/visits_provider.dart';
import '../../domain/entities/patient.dart';
import '../../domain/usecases/get_patient.dart';
import '../../domain/usecases/toggle_patient_status.dart';
import '../../domain/usecases/update_patient.dart';
import '../pdf/patient_pdf_export.dart';
import 'patient_form_page.dart';

/// Mirrors resources/views/patients/show.blade.php.
class PatientDetailPage extends ConsumerStatefulWidget {
  const PatientDetailPage({super.key, required this.patientId});

  final int patientId;

  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage> {
  Patient? _patient;
  String? _error;
  bool _togglingStatus = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await sl<GetPatient>().call(
      GetPatientParams(id: widget.patientId),
    );

    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (patient) => setState(() => _patient = patient),
    );
  }

  /// Explicit, confirmed action — mirrors the reference design's separate
  /// "تعديل/إلغاء" action buttons instead of relying on a tappable status
  /// pill that wasn't discoverable as interactive.
  Future<void> _confirmToggleStatus() async {
    final patient = _patient;
    if (patient == null) return;

    final activating = !patient.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(activating ? 'تفعيل المريض؟' : 'إلغاء تفعيل المريض؟'),
        content: Text(
          activating
              ? 'سيظهر "${patient.fullName}" مجددًا ضمن قائمة المرضى النشطين.'
              : 'سيُنقل "${patient.fullName}" إلى قائمة غير النشطين، ويمكن تفعيله مجددًا في أي وقت.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(activating ? 'تفعيل' : 'إلغاء التفعيل'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _togglingStatus = true);
    final result = await sl<TogglePatientStatus>().call(
      TogglePatientStatusParams(id: widget.patientId),
    );

    if (!mounted) return;
    setState(() => _togglingStatus = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message))),
      (updated) => setState(() => _patient = updated),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patient = _patient;

    final clinicName = ref.watch(activeClinicProvider).active?.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(patient?.fullName ?? 'إضبارة'),
        actions: [
          if (patient != null) ...[
            IconButton(
              tooltip: 'مقارنة صور قبل/بعد',
              icon: const Icon(Icons.compare_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PhotoComparisonPage(
                    patientId: patient.id!,
                    patientName: patient.fullName,
                  ),
                ),
              ),
            ),
            PatientPdfExportButton(patient: patient, clinicName: clinicName),
          ],
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            )
          : patient == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                StaggeredFadeSlideIn(
                  spacing: AppSpacing.md,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    patient.fullName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.sky,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'رقم المريض',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkSoft,
                                        ),
                                      ),
                                      Text(
                                        patient.patientNumber ?? '—',
                                        textDirection: TextDirection.ltr,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.aqua,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Divider(height: 1),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: patient.isActive
                                        ? AppColors.ok.withValues(alpha: 0.1)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    patient.statusLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: patient.isActive
                                          ? AppColors.ok
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                _togglingStatus
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : TextButton.icon(
                                        onPressed: _confirmToggleStatus,
                                        icon: Icon(
                                          patient.isActive
                                              ? Icons.person_off_rounded
                                              : Icons.person_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          patient.isActive
                                              ? 'إلغاء التفعيل'
                                              : 'تفعيل المريض',
                                        ),
                                      ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.diagnosisGradient,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.aqua.withValues(alpha: 0.2),
                        ),
                        boxShadow: AppShadows.card,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: -30,
                            right: -20,
                            child: Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.aqua.withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'الشكاية',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.aqua,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'ماذا يعاني؟',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.inkSoft,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  patient.diagnosis ?? 'غير محدد بعد',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _InfoCard(
                      title: 'بيانات المريض',
                      rows: [
                        ('الجنس', patient.gender?.label),
                        ('الهاتف', patient.phone),
                        ('العنوان', patient.address),
                        (
                          'العمر',
                          patient.displayAge != null
                              ? '${patient.displayAge} سنة'
                              : null,
                        ),
                        (
                          'تاريخ الميلاد',
                          patient.birthDate == null
                              ? null
                              : '${patient.birthDate!.year}-${patient.birthDate!.month.toString().padLeft(2, '0')}-${patient.birthDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                    _InfoCard(
                      title: 'التاريخ الطبي والأدوية',
                      rows: [
                        ('الأدوية السابقة', patient.previousMedications),
                        ('الأدوية الحالية', patient.currentMedications),
                        ('الحساسية', patient.allergies),
                        ('التاريخ المرضي', patient.medicalHistory),
                        ('عمليات سابقة', patient.surgeriesHistory),
                        ('ملاحظات إضافية', patient.notes),
                      ],
                      stacked: true,
                    ),
                    _FollowUpPlanCard(
                      patient: patient,
                      onUpdated: (updated) =>
                          setState(() => _patient = updated),
                    ),
                    _VisitsSection(patientId: widget.patientId),
                    GradientButton(
                      label: 'تعديل الإضبارة',
                      icon: Icons.edit_rounded,
                      onPressed: () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => PatientFormPage(patient: patient),
                          ),
                        );
                        if (saved == true) _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Lets the doctor put a chronic-condition patient on a standing "check
/// every N months" plan instead of re-flagging "يحتاج متابعة" by hand on
/// every single visit — VisitFormPage reads [Patient.followUpPlanMonths]
/// and pre-fills the follow-up flag/date for a new visit accordingly.
class _FollowUpPlanCard extends StatefulWidget {
  const _FollowUpPlanCard({required this.patient, required this.onUpdated});

  final Patient patient;
  final ValueChanged<Patient> onUpdated;

  @override
  State<_FollowUpPlanCard> createState() => _FollowUpPlanCardState();
}

class _FollowUpPlanCardState extends State<_FollowUpPlanCard> {
  static const _options = [
    (null, 'إيقاف'),
    (1, 'كل شهر'),
    (3, 'كل ٣ أشهر'),
    (6, 'كل ٦ أشهر'),
    (12, 'كل سنة'),
  ];

  bool _saving = false;

  Future<void> _select(int? months) async {
    if (months == widget.patient.followUpPlanMonths) return;
    setState(() => _saving = true);
    final result = await sl<UpdatePatient>().call(
      widget.patient.copyWith(
        followUpPlanMonths: months,
        clearFollowUpPlanMonths: months == null,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message))),
      widget.onUpdated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.patient.followUpPlanMonths;
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
          Row(
            children: [
              const Icon(
                Icons.event_repeat_rounded,
                color: AppColors.aqua,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'خطة متابعة دورية',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (_saving) ...[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'لمريض يحتاج فحصًا دوريًا (مرض مزمن مثلًا) — كل زيارة جديدة له '
            'تُعلَّم تلقائيًا "يحتاج متابعة" بتاريخ مستهدف بعد المدة المحددة.',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (months, label) in _options)
                ChoiceChip(
                  label: Text(label),
                  selected: active == months,
                  onSelected: _saving ? null : (_) => _select(months),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.rows,
    this.stacked = false,
  });

  final String title;

  /// A null value means "never entered" — filtered out entirely rather
  /// than shown as a placeholder, so a mostly-empty section (e.g. no
  /// medical history recorded yet) doesn't pad the page with dashes.
  final List<(String, String?)> rows;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final filled = [
      for (final (label, value) in rows)
        if (value != null && value.isNotEmpty) (label, value),
    ];
    if (filled.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (label, value) in filled)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.aqua,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            style: const TextStyle(color: AppColors.ink),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          Text(
                            value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
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

/// Lists this patient's exam visits (each a filled OD/OS chart) and lets
/// staff add a new one or open/delete an existing one — the digital
/// equivalent of the doctor flipping to a fresh page in the paper chart.
/// Search (by date or notes) and pagination kick in once the list grows
/// past a page, so a long-running patient's chart doesn't turn into one
/// giant scroll.
class _VisitsSection extends ConsumerStatefulWidget {
  const _VisitsSection({required this.patientId});

  final int patientId;

  @override
  ConsumerState<_VisitsSection> createState() => _VisitsSectionState();
}

class _VisitsSectionState extends ConsumerState<_VisitsSection> {
  static const _perPage = 5;

  final _searchController = TextEditingController();
  String _query = '';
  int _page = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Visit> _filter(List<Visit> visits) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return visits;
    return visits.where((visit) {
      final date =
          '${visit.visitDate.year}-${visit.visitDate.month.toString().padLeft(2, '0')}-${visit.visitDate.day.toString().padLeft(2, '0')}';
      final notes = (visit.notes ?? '').toLowerCase();
      return date.contains(query) || notes.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(visitsProvider(widget.patientId));
    final notifier = ref.read(visitsProvider(widget.patientId).notifier);

    final filtered = _filter(state.visits);
    final lastPage = filtered.isEmpty ? 1 : (filtered.length / _perPage).ceil();
    final page = _page > lastPage ? lastPage : _page;
    final pageVisits = filtered
        .skip((page - 1) * _perPage)
        .take(_perPage)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => VisitFormPage(patientId: widget.patientId),
                  ),
                );
                if (saved == true) {
                  notifier.refresh();
                  ref.read(followUpsProvider.notifier).refresh();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'زيارات الفحص',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: AppColors.aqua,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'زيارة جديدة',
                      style: TextStyle(
                        color: AppColors.aqua,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (state.visits.length > _perPage) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _query = value;
                _page = 1;
              }),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ابحث بالتاريخ أو الملاحظات...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _query = '';
                          _page = 1;
                        }),
                      ),
              ),
            ),
          ],
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                state.visits.isEmpty
                    ? 'لا توجد زيارات مسجّلة بعد.'
                    : 'لا توجد زيارات مطابقة للبحث.',
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            )
          else ...[
            for (final visit in pageVisits)
              _VisitRow(
                visit: visit,
                onOpen: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => VisitFormPage(
                        patientId: widget.patientId,
                        visit: visit,
                      ),
                    ),
                  );
                  if (saved == true) {
                    notifier.refresh();
                    ref.read(followUpsProvider.notifier).refresh();
                  }
                },
                onDelete: () async {
                  await notifier.delete(visit.id!);
                  ref.read(followUpsProvider.notifier).refresh();
                },
              ),
            if (lastPage > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page > 1
                        ? () => setState(() => _page = page - 1)
                        : null,
                    child: const Text('السابق'),
                  ),
                  Text(
                    'صفحة $page من $lastPage',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: page < lastPage
                        ? () => setState(() => _page = page + 1)
                        : null,
                    child: const Text('التالي'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({
    required this.visit,
    required this.onOpen,
    required this.onDelete,
  });

  final Visit visit;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date =
        '${visit.visitDate.year}-${visit.visitDate.month.toString().padLeft(2, '0')}-${visit.visitDate.day.toString().padLeft(2, '0')}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.visibility_rounded,
              color: AppColors.aqua,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                date,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (visit.feeAmount != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: visit.remainingAmount != null
                      ? AppColors.danger.withValues(alpha: 0.1)
                      : AppColors.ok.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  visit.remainingAmount != null
                      ? 'متبقي ${visit.remainingAmount!.toStringAsFixed(0)}'
                      : '${visit.feeAmount!.toStringAsFixed(0)} ل.س',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: visit.remainingAmount != null
                        ? AppColors.danger
                        : AppColors.ok,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
                size: 20,
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف الزيارة؟'),
                    content: const Text('لا يمكن التراجع عن هذا الإجراء.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          'حذف',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
