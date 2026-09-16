import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/appointment.dart';

abstract class AppointmentRepository {
  Future<Either<Failure, List<Appointment>>> listBetween(
    DateTime start,
    DateTime end,
  );

  Future<Either<Failure, List<Appointment>>> listUpcoming({int limit});

  Future<Either<Failure, Appointment>> create(Appointment appointment);

  Future<Either<Failure, Appointment>> update(Appointment appointment);

  Future<Either<Failure, void>> delete(int id);

  /// Most recent consultation date for [patientId], or null if none —
  /// used to suggest whether a new booking should default to "متابعة"
  /// (inside the follow-up window) or "كشفية" (outside it / first visit).
  Future<Either<Failure, DateTime?>> lastConsultationDate(int patientId);

  /// The clinic's current free-follow-up window, in days.
  Future<Either<Failure, int>> getFollowUpDays();

  /// Changes the clinic's free-follow-up window — a day-to-day nurse call,
  /// not locked behind Admin.
  Future<Either<Failure, void>> setFollowUpDays(int days);

  /// Non-cancelled appointment counts by [AppointmentType] within
  /// [start, end) — backs the monthly report.
  Future<Either<Failure, Map<AppointmentType, int>>> countByTypeBetween(
    DateTime start,
    DateTime end,
  );
}
