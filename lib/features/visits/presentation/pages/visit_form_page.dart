import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../appointments/domain/usecases/get_follow_up_days.dart';
import '../../../patients/domain/usecases/get_patient.dart';
import '../../domain/entities/exam_field_template.dart';
import '../../domain/entities/visit.dart';
import '../../domain/entities/visit_field_value.dart';
import '../../domain/entities/visit_photo.dart';
import '../../domain/entities/visit_type.dart';
import '../../domain/usecases/add_visit_photo.dart';
import '../../domain/usecases/delete_visit_photo.dart';
import '../../domain/usecases/get_exam_templates.dart';
import '../../domain/usecases/get_visit_field_values.dart';
import '../../domain/usecases/get_visit_photos.dart';
import '../../domain/usecases/get_visits.dart';
import '../../domain/usecases/save_visit.dart';
import '../../domain/usecases/save_visit_field_values.dart';
import 'exam_template_settings_page.dart';

/// A visit's photos live as BLOBs inside the clinic's own SQLite file (see
/// ClinicDataDatabase) — nothing prunes them, so an unbounded photo count
/// per visit is what actually grows that file large over years of use,
/// long before patient/visit *counts* alone would ever matter. Capping
/// here is cheap insurance against that, not a response to any real
/// clinic having hit it yet.
const _maxPhotosPerVisit = 8;

/// One exam visit's form — a digital copy of one filled page from the
/// clinic's paper "إضبارة" chart, except the rows themselves are the
/// clinic's own exam form (see ExamFieldTemplate) rather than a fixed
/// eye-exam chart, so any specialty can use this the same way.
class VisitFormPage extends StatefulWidget {
  const VisitFormPage({super.key, required this.patientId, this.visit});

  final int patientId;
  final Visit? visit;

  @override
  State<VisitFormPage> createState() => _VisitFormPageState();
}

class _VisitFormPageState extends State<VisitFormPage> {
  late DateTime _visitDate = widget.visit?.visitDate ?? DateTime.now();
  final _notesController = TextEditingController();
  final _examSummaryController = TextEditingController();
  late bool _needsFollowUp = widget.visit?.needsFollowUp ?? false;
  late DateTime? _followUpBy = widget.visit?.followUpBy;
  bool _followUpFromPlan = false;
  final _feeController = TextEditingController();
  final _paidController = TextEditingController();
  late VisitType _visitType = widget.visit?.visitType ?? VisitType.consultation;
  final _followUpOutcomeController = TextEditingController();

  bool _loadingTemplates = true;
  List<ExamFieldTemplate> _templates = [];
  final _singleControllers = <int, TextEditingController>{};
  final _rightControllers = <int, TextEditingController>{};
  final _leftControllers = <int, TextEditingController>{};

  /// Photos picked before the visit itself has been saved — a brand-new
  /// visit has no id yet for AddVisitPhoto to attach to, so these are held
  /// in memory and uploaded right after _submit() creates the visit row.
  final List<Uint8List> _pendingPhotos = [];

  bool _saving = false;

  bool get _isEdit => widget.visit != null;

  @override
  void initState() {
    super.initState();
    _notesController.text = widget.visit?.notes ?? '';
    _examSummaryController.text = widget.visit?.examSummary ?? '';
    _feeController.text = _formatAmount(widget.visit?.feeAmount);
    final visitPaid = widget.visit?.amountPaid;
    final visitFee = widget.visit?.feeAmount;
    _paidController.text = (visitPaid != null && visitPaid != visitFee)
        ? _formatAmount(visitPaid)
        : '';
    _followUpOutcomeController.text = widget.visit?.followUpOutcome ?? '';
    _load();
    if (!_isEdit) {
      _applyFollowUpPlanDefault();
      _suggestVisitType();
    }
  }

  /// Mirrors the appointments feature's own "متابعة مجانية" window (see
  /// GetFollowUpDays): a brand-new visit defaults to a full [VisitType.
  /// consultation] unless it falls within the clinic's follow-up-days
  /// window after the patient's last consultation, in which case it's
  /// suggested as a [VisitType.checkup] instead. The doctor can always
  /// override the chip either way before saving.
  Future<void> _suggestVisitType() async {
    final visitsResult = await sl<GetVisits>().call(widget.patientId);
    final visits = visitsResult.fold((_) => <Visit>[], (v) => v);
    final priorConsultations = visits.where(
      (v) => v.visitType == VisitType.consultation,
    );
    if (priorConsultations.isEmpty) return;
    final lastConsultation = priorConsultations.first;

    final daysResult = await sl<GetFollowUpDays>().call(const NoParams());
    final followUpDays = daysResult.fold((_) => 30, (d) => d);
    final daysSince = DateTime.now()
        .difference(lastConsultation.visitDate)
        .inDays;

    if (!mounted) return;
    if (daysSince <= followUpDays) {
      setState(() => _visitType = VisitType.checkup);
    }
  }

  /// A brand-new visit for a patient on a standing "خطة متابعة دورية"
  /// (see PatientDetailPage's _FollowUpPlanCard) starts pre-flagged
  /// "يحتاج متابعة" with a target date N months out, instead of the doctor
  /// re-entering the same follow-up by hand every time. Only applies while
  /// the doctor hasn't already touched these fields, so a fetch that
  /// resolves after manual edits never clobbers them.
  Future<void> _applyFollowUpPlanDefault() async {
    final result = await sl<GetPatient>().call(
      GetPatientParams(id: widget.patientId),
    );
    if (!mounted || _needsFollowUp || _followUpBy != null) return;
    result.fold((_) {}, (patient) {
      final months = patient.followUpPlanMonths;
      if (months == null) return;
      setState(() {
        _needsFollowUp = true;
        _followUpFromPlan = true;
        _followUpBy = DateTime(
          _visitDate.year,
          _visitDate.month + months,
          _visitDate.day,
        );
      });
    });
  }

  Future<void> _load() async {
    final templatesResult = await sl<GetExamTemplates>().call(const NoParams());
    final templates = templatesResult.fold(
      (_) => <ExamFieldTemplate>[],
      (t) => t,
    );

    for (final template in templates) {
      _singleControllers[template.id!] = TextEditingController();
      _rightControllers[template.id!] = TextEditingController();
      _leftControllers[template.id!] = TextEditingController();
    }

    if (_isEdit) {
      final valuesResult = await sl<GetVisitFieldValues>().call(
        widget.visit!.id!,
      );
      valuesResult.fold((_) {}, (values) {
        for (final value in values) {
          switch (value.side) {
            case FieldSide.single:
              _singleControllers[value.templateId]?.text = value.value ?? '';
            case FieldSide.right:
              _rightControllers[value.templateId]?.text = value.value ?? '';
            case FieldSide.left:
              _leftControllers[value.templateId]?.text = value.value ?? '';
          }
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loadingTemplates = false;
    });
  }

  static String _formatAmount(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static double? _parseAmount(String text) {
    final trimmed = text.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _examSummaryController.dispose();
    _feeController.dispose();
    _paidController.dispose();
    _followUpOutcomeController.dispose();
    for (final c in _singleControllers.values) {
      c.dispose();
    }
    for (final c in _rightControllers.values) {
      c.dispose();
    }
    for (final c in _leftControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _visitDate = picked);
  }

  Future<void> _pickFollowUpDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpBy ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _followUpBy = picked);
  }

  Future<void> _openTemplateSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExamTemplateSettingsPage()));
    if (!mounted) return;
    setState(() => _loadingTemplates = true);
    await _load();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);

    final fee = _parseAmount(_feeController.text);
    final enteredPaid = _parseAmount(_paidController.text);

    final visit = Visit(
      id: widget.visit?.id,
      patientId: widget.patientId,
      visitDate: _visitDate,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      examSummary: _examSummaryController.text.trim().isEmpty
          ? null
          : _examSummaryController.text.trim(),
      needsFollowUp: _needsFollowUp,
      followUpBy: _needsFollowUp ? _followUpBy : null,
      // No amount typed in "المدفوع فعليًا" means "دُفعت الكشفية كاملة" —
      // the common case — rather than making every visit type the same
      // number twice.
      feeAmount: fee,
      amountPaid: fee == null ? null : (enteredPaid ?? fee),
      createdAt: widget.visit?.createdAt,
      visitType: _visitType,
      followUpOutcome: _visitType == VisitType.checkup
          ? (_followUpOutcomeController.text.trim().isEmpty
                ? null
                : _followUpOutcomeController.text.trim())
          : null,
    );

    final result = await sl<SaveVisit>().call(visit);

    if (!mounted) return;

    final error = await result.fold((failure) async => failure.message, (
      saved,
    ) async {
      final values = <VisitFieldValue>[
        for (final template in _templates) ...[
          if (template.hasSides) ...[
            VisitFieldValue(
              visitId: saved.id!,
              templateId: template.id!,
              side: FieldSide.right,
              value: _rightControllers[template.id!]!.text.trim(),
            ),
            VisitFieldValue(
              visitId: saved.id!,
              templateId: template.id!,
              side: FieldSide.left,
              value: _leftControllers[template.id!]!.text.trim(),
            ),
          ] else
            VisitFieldValue(
              visitId: saved.id!,
              templateId: template.id!,
              side: FieldSide.single,
              value: _singleControllers[template.id!]!.text.trim(),
            ),
        ],
      ];

      final valuesResult = await sl<SaveVisitFieldValues>().call(
        SaveVisitFieldValuesParams(visitId: saved.id!, values: values),
      );
      final valuesError = valuesResult.fold(
        (failure) => failure.message,
        (_) => null,
      );
      if (valuesError != null) return valuesError;

      // A new visit's photos were only ever held in memory (see
      // _pendingPhotos) — now that it has an id, hand them to the same
      // usecase _PhotosSection uses once a visit already exists.
      for (final bytes in _pendingPhotos) {
        await sl<AddVisitPhoto>().call(
          AddVisitPhotoParams(visitId: saved.id!, imageData: bytes),
        );
      }
      return null;
    });

    if (!mounted) return;
    setState(() => _saving = false);

    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  String get _dateLabel =>
      '${_visitDate.year}-${_visitDate.month.toString().padLeft(2, '0')}-${_visitDate.day.toString().padLeft(2, '0')}';

  Widget _dateCard() => SurfaceCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: _pickDate,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.aqua.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event_rounded,
                color: AppColors.aquaDeep,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text(
              'تاريخ الزيارة',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
            ),
            const Spacer(),
            Text(
              _dateLabel,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more_rounded, color: AppColors.lens),
          ],
        ),
      ),
    ),
  );

  Widget _visitTypeCard() => SurfaceCard(
    title: 'نوع الزيارة',
    icon: Icons.local_hospital_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<VisitType>(
          showSelectedIcon: false,
          segments: [
            for (final type in VisitType.values)
              ButtonSegment(value: type, label: Text(type.label)),
          ],
          selected: {_visitType},
          onSelectionChanged: (s) => setState(() => _visitType = s.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.aqua,
            selectedForegroundColor: Colors.white,
            foregroundColor: AppColors.ink,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _visitType == VisitType.consultation
              ? 'كشفية كاملة — أول زيارة أو بعد انتهاء فترة المتابعة.'
              : 'ضمن فترة المتابعة — غالبًا نصف السعر أو مجانية.',
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
        ),
        if (_visitType == VisitType.checkup) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _followUpOutcomeController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'نتيجة المتابعة',
              hintText: 'مثلًا: الالتهاب راح، تحسنت الرؤية...',
            ),
          ),
        ],
      ],
    ),
  );

  Widget _examSection() {
    if (_templates.isEmpty) {
      return SurfaceCard(
        title: 'القياسات',
        icon: Icons.assignment_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'لم يتم إعداد أي حقول للفحص بعد.',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _openTemplateSettings,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('إعداد نموذج الفحص'),
            ),
          ],
        ),
      );
    }
    return _ExamTable(
      templates: _templates,
      singleControllers: _singleControllers,
      rightControllers: _rightControllers,
      leftControllers: _leftControllers,
    );
  }

  Widget _summaryCard() => SurfaceCard(
    title: 'الخلاصة والملاحظات',
    icon: Icons.fact_check_rounded,
    child: Column(
      children: [
        TextField(
          controller: _examSummaryController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'خلاصة الفحص'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'ملاحظات إضافية'),
        ),
      ],
    ),
  );

  Widget _billingCard() => SurfaceCard(
    title: 'الكشفية',
    icon: Icons.payments_rounded,
    child: Column(
      children: [
        TextField(
          controller: _feeController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ (اختياري)',
            suffixText: 'ل.س',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _paidController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المدفوع فعليًا',
            helperText: 'اتركه فارغًا إذا دُفعت الكشفية كاملة',
            suffixText: 'ل.س',
          ),
        ),
      ],
    ),
  );

  Widget _followUpCard() => SurfaceCard(
    title: 'المتابعة',
    icon: Icons.event_repeat_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: _needsFollowUp,
          onChanged: (v) => setState(() {
            _needsFollowUp = v ?? false;
            _followUpFromPlan = false;
          }),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'هذا المريض يحتاج متابعة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _followUpFromPlan
                ? 'مُقترح تلقائيًا حسب خطة المتابعة الدورية — يمكن تعديله'
                : 'يظهر ضمن "متابعات مستحقة" حتى تُسجَّل له زيارة جديدة',
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
        if (_needsFollowUp) ...[
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.field),
            onTap: _pickFollowUpDate,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.sky,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_rounded,
                    color: AppColors.aqua,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _followUpBy == null
                          ? 'تاريخ مستهدف للمتابعة (اختياري)'
                          : 'المتابعة بحلول: '
                                '${_followUpBy!.year}-'
                                '${_followUpBy!.month.toString().padLeft(2, '0')}-'
                                '${_followUpBy!.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_followUpBy != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _followUpBy = null),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _photosCard() => _isEdit
      ? _PhotosSection(visitId: widget.visit!.id!)
      : _PendingPhotosSection(
          photos: _pendingPhotos,
          onAdd: (bytes) => setState(() => _pendingPhotos.add(bytes)),
          onRemove: (index) => setState(() => _pendingPhotos.removeAt(index)),
        );

  Widget _saveButton() => _saving
      ? const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        )
      : GradientButton(
          label: _isEdit ? 'حفظ التعديلات' : 'حفظ الزيارة',
          icon: Icons.save_rounded,
          onPressed: _submit,
        );

  /// Two columns on tablets / wide windows — clinical content (type,
  /// measurements, conclusion) on one side, the administrative cards
  /// (fee, follow-up, photos) on the other — and a single stacked column
  /// on phones, so the same screen reads naturally at any width.
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const gap = AppSpacing.md;

    final clinical = <Widget>[_visitTypeCard(), _examSection(), _summaryCard()];
    final admin = <Widget>[_billingCard(), _followUpCard(), _photosCard()];

    Widget column(List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in items.indexed) ...[
          if (i > 0) const SizedBox(height: gap),
          w,
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل زيارة' : 'زيارة فحص جديدة'),
        actions: [
          IconButton(
            tooltip: 'إعداد نموذج الفحص',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openTemplateSettings,
          ),
        ],
      ),
      body: _loadingTemplates
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1180 : 720),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    const _ExamHero(),
                    const SizedBox(height: gap),
                    _dateCard(),
                    const SizedBox(height: gap),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: column(clinical)),
                          const SizedBox(width: gap),
                          Expanded(flex: 4, child: column(admin)),
                        ],
                      )
                    else
                      column([...clinical, ...admin]),
                    const SizedBox(height: AppSpacing.lg),
                    _saveButton(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A branded intro card — the same diagnosis-hero gradient treatment used
/// on the patient detail page — so this form reads as part of the same
/// product instead of the plain white form it started as.
class _ExamHero extends StatelessWidget {
  const _ExamHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.diagnosisGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.aqua.withValues(alpha: 0.2)),
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -30,
            left: -20,
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
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.card,
                  ),
                  child: const Icon(
                    Icons.assignment_rounded,
                    color: AppColors.aqua,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الفحص',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'القياسات المسجّلة لهذه الزيارة',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
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
    );
  }
}

/// The exam form itself, built from the clinic's own field templates —
/// each row is either a single value, or a right/left pair, depending on
/// [ExamFieldTemplate.hasSides].
class _ExamTable extends StatelessWidget {
  const _ExamTable({
    required this.templates,
    required this.singleControllers,
    required this.rightControllers,
    required this.leftControllers,
  });

  final List<ExamFieldTemplate> templates;
  final Map<int, TextEditingController> singleControllers;
  final Map<int, TextEditingController> rightControllers;
  final Map<int, TextEditingController> leftControllers;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      title: 'القياسات',
      icon: Icons.assignment_rounded,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (final (index, template) in templates.indexed)
            Container(
              color: index.isEven
                  ? Colors.transparent
                  : AppColors.sky.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: template.hasSides
                  ? Row(
                      crossAxisAlignment: template.isLongText
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _SideField(
                            label: 'يسار',
                            controller: leftControllers[template.id!]!,
                            isLongText: template.isLongText,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _SideField(
                            label: 'يمين',
                            controller: rightControllers[template.id!]!,
                            isLongText: template.isLongText,
                          ),
                        ),
                        _RowLabel(
                          label: template.label,
                          topPadding: template.isLongText,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: template.isLongText
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: singleControllers[template.id!],
                            textDirection: TextDirection.ltr,
                            maxLines: template.isLongText ? 4 : 1,
                            minLines: template.isLongText ? 3 : 1,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        _RowLabel(
                          label: template.label,
                          topPadding: template.isLongText,
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// The row's own field name — kept as a separate small widget now that it
/// sits at the *end* of the row (see _ExamTable's reversed column order)
/// instead of leading it, with an optional top nudge so it lines up with a
/// multi-line long-text box instead of that box's vertical center.
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.label, required this.topPadding});

  final String label;
  final bool topPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding ? 10 : 0),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _SideField extends StatelessWidget {
  const _SideField({
    required this.label,
    required this.controller,
    this.isLongText = false,
  });

  final String label;
  final TextEditingController controller;
  final bool isLongText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: isLongText ? TextAlign.start : TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: isLongText ? 4 : 1,
      minLines: isLongText ? 3 : 1,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: InputBorder.none,
      ),
    );
  }
}

/// Photos attached to this visit (eye photos, old prescriptions) — only
/// shown once the visit itself has an id, since a photo needs a visit row
/// to attach to (see AddVisitPhoto).
class _PhotosSection extends StatefulWidget {
  const _PhotosSection({required this.visitId});

  final int visitId;

  @override
  State<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends State<_PhotosSection> {
  List<VisitPhoto> _photos = [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await sl<GetVisitPhotos>().call(widget.visitId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      result.fold((_) {}, (photos) => _photos = photos);
    });
  }

  Future<void> _pickAndAdd(ImageSource source) async {
    Navigator.of(context).pop(); // close the source-picker sheet
    if (_photos.length >= _maxPhotosPerVisit) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;

    setState(() => _adding = true);
    final bytes = await file.readAsBytes();
    final result = await sl<AddVisitPhoto>().call(
      AddVisitPhotoParams(visitId: widget.visitId, imageData: bytes),
    );
    if (!mounted) return;
    setState(() => _adding = false);

    result.fold(
      (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  Future<void> _showSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('التقاط صورة'),
              onTap: () => _pickAndAdd(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('اختيار من المعرض'),
              onTap: () => _pickAndAdd(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(VisitPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الصورة؟'),
        content: const Text('لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await sl<DeleteVisitPhoto>().call(photo.id!);
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  void _viewFullScreen(VisitPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.memory(photo.imageData)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.aqua.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  size: 16,
                  color: AppColors.aquaDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'الصور المرفقة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: _photos.length >= _maxPhotosPerVisit
                          ? null
                          : _showSourcePicker,
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: Text(
                        _photos.length >= _maxPhotosPerVisit
                            ? 'الحد الأقصى $_maxPhotosPerVisit صور'
                            : 'إضافة صورة',
                      ),
                    ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_photos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد صور مرفقة بعد.',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final photo in _photos)
                  GestureDetector(
                    onTap: () => _viewFullScreen(photo),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            photo.imageData,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            // Decodes straight to thumbnail size instead of
                            // the photo's full camera resolution — without
                            // this, a visit with several photos noticeably
                            // jank on first paint/scroll.
                            cacheWidth: 168,
                            cacheHeight: 168,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _delete(photo),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The create-mode counterpart to _PhotosSection: a brand-new visit has no
/// id yet for AddVisitPhoto to attach to, so photos picked here are held in
/// memory by the parent form (see _VisitFormPageState._pendingPhotos) and
/// only actually uploaded once _submit() has created the visit row.
class _PendingPhotosSection extends StatefulWidget {
  const _PendingPhotosSection({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Uint8List> photos;
  final ValueChanged<Uint8List> onAdd;
  final ValueChanged<int> onRemove;

  @override
  State<_PendingPhotosSection> createState() => _PendingPhotosSectionState();
}

class _PendingPhotosSectionState extends State<_PendingPhotosSection> {
  bool _picking = false;

  Future<void> _pickAndAdd(ImageSource source) async {
    Navigator.of(context).pop(); // close the source-picker sheet
    if (widget.photos.length >= _maxPhotosPerVisit) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;

    setState(() => _picking = true);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _picking = false);
    widget.onAdd(bytes);
  }

  Future<void> _showSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('التقاط صورة'),
              onTap: () => _pickAndAdd(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('اختيار من المعرض'),
              onTap: () => _pickAndAdd(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _viewFullScreen(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.aqua.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  size: 16,
                  color: AppColors.aquaDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'الصور المرفقة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _picking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: widget.photos.length >= _maxPhotosPerVisit
                          ? null
                          : _showSourcePicker,
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: Text(
                        widget.photos.length >= _maxPhotosPerVisit
                            ? 'الحد الأقصى $_maxPhotosPerVisit صور'
                            : 'إضافة صورة',
                      ),
                    ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (widget.photos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد صور مرفقة بعد.',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (index, bytes) in widget.photos.indexed)
                  GestureDetector(
                    onTap: () => _viewFullScreen(bytes),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            bytes,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            cacheWidth: 168,
                            cacheHeight: 168,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => widget.onRemove(index),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'سيتم حفظ الصور مع الزيارة عند الضغط على "حفظ الزيارة".',
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
