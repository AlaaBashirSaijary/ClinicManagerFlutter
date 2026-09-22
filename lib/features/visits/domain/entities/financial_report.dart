import 'package:equatable/equatable.dart';

/// One priced visit within a [FinancialReport]'s date range — a
/// denormalized join row (visit + the patient's name), same shape as
/// [FollowUpDue]: built directly in the datasource rather than through a
/// `fromMap` on the entity, so the domain layer stays persistence-agnostic.
class FinancialVisitRow extends Equatable {
  const FinancialVisitRow({
    required this.visitId,
    required this.patientId,
    required this.patientName,
    required this.visitDate,
    required this.feeAmount,
    required this.amountPaid,
  });

  final int visitId;
  final int patientId;
  final String patientName;
  final DateTime visitDate;
  final double feeAmount;
  final double amountPaid;

  double get remaining {
    final diff = feeAmount - amountPaid;
    return diff > 0 ? diff : 0;
  }

  @override
  List<Object?> get props => [visitId, patientId, visitDate];
}

/// Real money totals for a date range — what "تقرير مالي حقيقي بمبالغ"
/// means in this app: actual fee/payment amounts entered per visit, not a
/// count of appointment types.
class FinancialReport extends Equatable {
  const FinancialReport({this.rows = const []});

  final List<FinancialVisitRow> rows;

  double get totalFees => rows.fold(0, (sum, row) => sum + row.feeAmount);

  double get totalCollected => rows.fold(0, (sum, row) => sum + row.amountPaid);

  double get totalRemaining => totalFees - totalCollected;

  int get pricedVisitCount => rows.length;

  @override
  List<Object?> get props => [rows];
}
