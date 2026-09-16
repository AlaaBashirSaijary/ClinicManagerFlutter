import 'package:equatable/equatable.dart';

/// One row of the clinic's own exam form — e.g. "ضغط الدم" for a general
/// clinic, or "Auto" for an eye clinic. Doctors define these themselves
/// (Admin > قوالب الفحص) instead of the app assuming any one specialty.
class ExamFieldTemplate extends Equatable {
  const ExamFieldTemplate({
    this.id,
    required this.label,
    this.hasSides = false,
    this.sortOrder = 0,
  });

  final int? id;
  final String label;

  /// True when this row records two readings (e.g. right/left eye, right/
  /// left ear) instead of one.
  final bool hasSides;

  final int sortOrder;

  ExamFieldTemplate copyWith({
    int? id,
    String? label,
    bool? hasSides,
    int? sortOrder,
  }) {
    return ExamFieldTemplate(
      id: id ?? this.id,
      label: label ?? this.label,
      hasSides: hasSides ?? this.hasSides,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, label, hasSides, sortOrder];
}
