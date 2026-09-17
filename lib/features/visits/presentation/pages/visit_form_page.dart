import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/widgets/fade_slide_in.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../domain/entities/exam_field_template.dart';
import '../../domain/entities/visit.dart';
import '../../domain/entities/visit_field_value.dart';
import '../../domain/entities/visit_photo.dart';
import '../../domain/usecases/add_visit_photo.dart';
import '../../domain/usecases/delete_visit_photo.dart';
import '../../domain/usecases/get_exam_templates.dart';
import '../../domain/usecases/get_visit_field_values.dart';
import '../../domain/usecases/get_visit_photos.dart';
import '../../domain/usecases/save_visit.dart';
import '../../domain/usecases/save_visit_field_values.dart';
import 'exam_template_settings_page.dart';

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
    _load();
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

  @override
  void dispose() {
    _notesController.dispose();
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

    final visit = Visit(
      id: widget.visit?.id,
      patientId: widget.patientId,
      visitDate: _visitDate,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: widget.visit?.createdAt,
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

  @override
  Widget build(BuildContext context) {
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
      body: ResponsiveBody(
        maxWidth: 900,
        child: _loadingTemplates
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  StaggeredFadeSlideIn(
                    spacing: AppSpacing.md,
                    children: [
                      const _ExamHero(),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: AppShadows.card,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_rounded,
                                color: AppColors.aqua,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'تاريخ الزيارة: '
                                '${_visitDate.year}-${_visitDate.month.toString().padLeft(2, '0')}-${_visitDate.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.chevron_left_rounded,
                                color: AppColors.lens,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_templates.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.sky.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'لم يتم إعداد أي حقول للفحص بعد.',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton.icon(
                                onPressed: _openTemplateSettings,
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('إعداد نموذج الفحص'),
                              ),
                            ],
                          ),
                        )
                      else
                        _ExamTable(
                          templates: _templates,
                          singleControllers: _singleControllers,
                          rightControllers: _rightControllers,
                          leftControllers: _leftControllers,
                        ),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AppShadows.card,
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات إضافية',
                          ),
                        ),
                      ),
                      if (_isEdit)
                        _PhotosSection(visitId: widget.visit!.id!)
                      else
                        _PendingPhotosSection(
                          photos: _pendingPhotos,
                          onAdd: (bytes) =>
                              setState(() => _pendingPhotos.add(bytes)),
                          onRemove: (index) =>
                              setState(() => _pendingPhotos.removeAt(index)),
                        ),
                      _saving
                          ? const Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : GradientButton(
                              label: _isEdit ? 'حفظ التعديلات' : 'حفظ الزيارة',
                              icon: Icons.save_rounded,
                              onPressed: _submit,
                            ),
                    ],
                  ),
                ],
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
              const Expanded(
                child: Text(
                  'الصور المرفقة',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
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
                      onPressed: _showSourcePicker,
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: const Text('إضافة صورة'),
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
              const Expanded(
                child: Text(
                  'الصور المرفقة',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
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
                      onPressed: _showSourcePicker,
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: const Text('إضافة صورة'),
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
