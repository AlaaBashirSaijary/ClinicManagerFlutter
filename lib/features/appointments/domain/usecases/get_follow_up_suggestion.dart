import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/appointment.dart';
import '../repositories/appointment_repository.dart';

class FollowUpSuggestion {
  const FollowUpSuggestion({
    required this.suggestedType,
    required this.followUpDays,
    this.lastConsultationDate,
  });

  final AppointmentType suggestedType;
  final int followUpDays;
  final DateTime? lastConsultationDate;
}

/// Looks up a patient's last consultation and the clinic's follow-up
/// window, and suggests which type a new booking should default to —
/// staff can still override it in the form.
class GetFollowUpSuggestion implements UseCase<FollowUpSuggestion, int> {
  const GetFollowUpSuggestion(this._repository);

  final AppointmentRepository _repository;

  @override
  Future<Either<Failure, FollowUpSuggestion>> call(int patientId) async {
    final daysResult = await _repository.getFollowUpDays();
    return daysResult.fold((failure) => Future.value(Left(failure)), (
      days,
    ) async {
      final lastResult = await _repository.lastConsultationDate(patientId);
      return lastResult.fold(Left.new, (last) {
        final withinWindow =
            last != null && DateTime.now().difference(last).inDays <= days;
        return Right(
          FollowUpSuggestion(
            suggestedType: withinWindow
                ? AppointmentType.followUp
                : AppointmentType.consultation,
            followUpDays: days,
            lastConsultationDate: last,
          ),
        );
      });
    });
  }
}
