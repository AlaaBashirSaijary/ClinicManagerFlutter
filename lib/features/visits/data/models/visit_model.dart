import '../../domain/entities/visit.dart';

class VisitModel extends Visit {
  const VisitModel({
    super.id,
    required super.patientId,
    required super.visitDate,
    super.notes,
    super.createdAt,
  });

  factory VisitModel.fromEntity(Visit v) => VisitModel(
    id: v.id,
    patientId: v.patientId,
    visitDate: v.visitDate,
    notes: v.notes,
    createdAt: v.createdAt,
  );

  factory VisitModel.fromMap(Map<String, Object?> map) => VisitModel(
    id: map['id'] as int?,
    patientId: map['patient_id']! as int,
    visitDate: DateTime.parse(map['visit_date']! as String),
    notes: map['notes'] as String?,
    createdAt: map['created_at'] == null
        ? null
        : DateTime.parse(map['created_at']! as String),
  );

  Map<String, Object?> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'patient_id': patientId,
      'visit_date': visitDate.toIso8601String().split('T').first,
      'notes': notes,
      'created_at': createdAt?.toIso8601String() ?? now,
      'updated_at': now,
    };
  }
}
