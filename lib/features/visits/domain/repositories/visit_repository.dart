import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/visit.dart';
import '../entities/visit_field_value.dart';
import '../entities/visit_photo.dart';

abstract class VisitRepository {
  Future<Either<Failure, List<Visit>>> listForPatient(int patientId);

  Future<Either<Failure, Visit>> create(Visit visit);

  Future<Either<Failure, Visit>> update(Visit visit);

  Future<Either<Failure, void>> delete(int id);

  /// Distinct patients seen today — see AppointmentRepository for the
  /// future-looking counterpart (scheduled bookings, not yet seen).
  Future<Either<Failure, int>> countDistinctPatientsToday();

  Future<Either<Failure, List<VisitPhoto>>> listPhotos(int visitId);

  Future<Either<Failure, void>> addPhoto(int visitId, Uint8List imageData);

  Future<Either<Failure, void>> deletePhoto(int id);

  Future<Either<Failure, List<VisitFieldValue>>> listFieldValues(int visitId);

  /// Same as [listFieldValues], but for every visit in [visitIds] at once —
  /// one query instead of one per visit, for callers (like the patient PDF
  /// export) that need a whole patient's exam history in one go.
  Future<Either<Failure, Map<int, List<VisitFieldValue>>>>
  listFieldValuesForVisits(List<int> visitIds);

  /// Replaces every stored value for [visitId] with [values] — a visit's
  /// exam form is saved as a whole, not diffed field-by-field.
  Future<Either<Failure, void>> saveFieldValues(
    int visitId,
    List<VisitFieldValue> values,
  );
}
