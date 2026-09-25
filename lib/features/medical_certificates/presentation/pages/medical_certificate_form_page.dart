import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../domain/entities/medical_certificate.dart';
import '../../domain/usecases/save_medical_certificate.dart';
import '../pdf/medical_certificate_pdf_export.dart';

class MedicalCertificateFormPage extends ConsumerStatefulWidget {
  const MedicalCertificateFormPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientAge,
  });

  final int patientId;
  final String patientName;
  final int? patientAge;

  @override
  ConsumerState<MedicalCertificateFormPage> createState() =>
      _MedicalCertificateFormPageState();
}

class _MedicalCertificateFormPageState
    extends ConsumerState<MedicalCertificateFormPage> {
  final _restDaysController = TextEditingController(text: '3');
  final _bodyController = TextEditingController();
  MedicalCertificateType _type = MedicalCertificateType.sickLeave;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _restDaysController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final isSickLeave = _type == MedicalCertificateType.sickLeave;
    if (!isSickLeave && _bodyController.text.trim().isEmpty) {
      setState(() => _error = 'أدخلي نص التقرير.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final certificate = MedicalCertificate(
      patientId: widget.patientId,
      type: _type,
      restDays: isSickLeave ? int.tryParse(_restDaysController.text) : null,
      body: _bodyController.text.trim(),
      createdAt: DateTime.now(),
    );

    final result = await sl<SaveMedicalCertificate>().call(certificate);
    if (!mounted) return;

    await result.fold(
      (failure) async => setState(() {
        _saving = false;
        _error = failure.message;
      }),
      (saved) async {
        await MedicalCertificatePdfExport.export(
          clinicName: ref.read(activeClinicProvider).active?.name ?? '',
          doctorName: ref.read(authProvider).user?.name ?? '',
          patientName: widget.patientName,
          patientAge: widget.patientAge,
          certificate: saved,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSickLeave = _type == MedicalCertificateType.sickLeave;

    return Scaffold(
      appBar: AppBar(title: const Text('تقرير طبي / إجازة مرضية')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 8,
              children: [
                for (final type in MedicalCertificateType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isSickLeave) ...[
              TextField(
                controller: _restDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'عدد أيام الإجازة',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _bodyController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'سبب الإجازة / ملاحظات إضافية (اختياري)',
                ),
              ),
            ] else
              TextField(
                controller: _bodyController,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'نص التقرير الطبي',
                  alignLabelWithHint: true,
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            _saving
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('حفظ وطباعة'),
                  ),
          ],
        ),
      ),
    );
  }
}
