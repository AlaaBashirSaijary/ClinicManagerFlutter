import '../../domain/entities/appointment.dart';

class AppointmentModel extends Appointment {
  const AppointmentModel({
    super.id,
    required super.patientId,
    required super.scheduledAt,
    super.status,
    super.type,
    super.notes,
    super.createdAt,
    super.patientName,
    super.patientPhone,
  });

  factory AppointmentModel.fromEntity(Appointment a) => AppointmentModel(
    id: a.id,
    patientId: a.patientId,
    scheduledAt: a.scheduledAt,
    status: a.status,
    type: a.type,
    notes: a.notes,
    createdAt: a.createdAt,
  );

  /// Expects a row from a query joined against `patients` (see
  /// AppointmentLocalDataSource) — `patient_name`/`patient_phone` come from
  /// that join and are null only if the caller queried `appointments` alone.
  factory AppointmentModel.fromMap(Map<String, Object?> map) =>
      AppointmentModel(
        id: map['id']! as int,
        patientId: map['patient_id']! as int,
        scheduledAt: DateTime.parse(map['scheduled_at']! as String),
        status: AppointmentStatus.fromValue(map['status']! as String),
        type: AppointmentType.fromValue(
          (map['type'] as String?) ?? AppointmentType.consultation.name,
        ),
        notes: map['notes'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at']! as String),
        patientName: map['patient_name'] as String?,
        patientPhone: map['patient_phone'] as String?,
      );

  Map<String, Object?> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'patient_id': patientId,
      'scheduled_at': scheduledAt.toIso8601String(),
      'status': status.name,
      'type': type.name,
      'notes': notes,
      'created_at': createdAt?.toIso8601String() ?? now,
      'updated_at': now,
    };
  }
}
