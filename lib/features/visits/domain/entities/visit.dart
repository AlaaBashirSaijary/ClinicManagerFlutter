import 'package:equatable/equatable.dart';

/// A single exam visit — the digital equivalent of one filled-in page from
/// the clinic's paper "إضبارة" chart. A patient accumulates one of these
/// per visit rather than the chart having a single fixed exam section.
///
/// What's actually measured (Auto/Cycl/Myder for an eye clinic, blood
/// pressure/temperature for a general one, ...) isn't fixed here — see
/// [ExamFieldTemplate] and [VisitFieldValue] for the doctor-configurable
/// exam form this visit's readings are recorded against.
class Visit extends Equatable {
  const Visit({
    this.id,
    required this.patientId,
    required this.visitDate,
    this.notes,
    this.createdAt,
  });

  final int? id;
  final int patientId;
  final DateTime visitDate;
  final String? notes;
  final DateTime? createdAt;

  Visit copyWith({
    int? id,
    int? patientId,
    DateTime? visitDate,
    String? notes,
    DateTime? createdAt,
  }) {
    return Visit(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      visitDate: visitDate ?? this.visitDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, patientId, visitDate, notes];
}
