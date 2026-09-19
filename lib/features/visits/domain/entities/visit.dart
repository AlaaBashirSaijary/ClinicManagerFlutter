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
    this.needsFollowUp = false,
    this.followUpBy,
    this.createdAt,
  });

  final int? id;
  final int patientId;
  final DateTime visitDate;
  final String? notes;

  /// The doctor's own judgment call at the time of this visit — "this
  /// patient needs to be checked on again" — independent of the clinic's
  /// automatic free/half-price follow-up windows (see AppointmentType),
  /// which are about billing, not clinical need. Backs the "متابعات
  /// مستحقة" list: a patient shows up there while this is their most
  /// recent visit and it's still flagged, and drops off automatically the
  /// moment they're seen again — no separate "resolved" step needed.
  final bool needsFollowUp;

  /// Optional target date the doctor has in mind for that follow-up — null
  /// means "needs to come back at some point" with no specific deadline.
  final DateTime? followUpBy;

  final DateTime? createdAt;

  Visit copyWith({
    int? id,
    int? patientId,
    DateTime? visitDate,
    String? notes,
    bool? needsFollowUp,
    DateTime? followUpBy,
    bool clearFollowUpBy = false,
    DateTime? createdAt,
  }) {
    return Visit(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      visitDate: visitDate ?? this.visitDate,
      notes: notes ?? this.notes,
      needsFollowUp: needsFollowUp ?? this.needsFollowUp,
      followUpBy: clearFollowUpBy ? null : (followUpBy ?? this.followUpBy),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    patientId,
    visitDate,
    notes,
    needsFollowUp,
    followUpBy,
  ];
}
