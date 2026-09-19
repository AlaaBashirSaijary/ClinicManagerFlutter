import '../../domain/entities/visit.dart';

class VisitModel extends Visit {
  const VisitModel({
    super.id,
    required super.patientId,
    required super.visitDate,
    super.notes,
    super.needsFollowUp,
    super.followUpBy,
    super.createdAt,
  });

  factory VisitModel.fromEntity(Visit v) => VisitModel(
    id: v.id,
    patientId: v.patientId,
    visitDate: v.visitDate,
    notes: v.notes,
    needsFollowUp: v.needsFollowUp,
    followUpBy: v.followUpBy,
    createdAt: v.createdAt,
  );

  factory VisitModel.fromMap(Map<String, Object?> map) => VisitModel(
    id: map['id'] as int?,
    patientId: map['patient_id']! as int,
    visitDate: DateTime.parse(map['visit_date']! as String),
    notes: map['notes'] as String?,
    needsFollowUp: (map['needs_follow_up'] as int?) == 1,
    followUpBy: map['follow_up_by'] == null
        ? null
        : DateTime.parse(map['follow_up_by']! as String),
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
      'needs_follow_up': needsFollowUp ? 1 : 0,
      'follow_up_by': followUpBy?.toIso8601String().split('T').first,
      'created_at': createdAt?.toIso8601String() ?? now,
      'updated_at': now,
    };
  }
}
