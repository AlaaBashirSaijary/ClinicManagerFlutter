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

  /// Replaces every stored value for [visitId] with [values] — a visit's
  /// exam form is saved as a whole, not diffed field-by-field.
  Future<Either<Failure, void>> saveFieldValues(
    int visitId,
    List<VisitFieldValue> values,
  );
}
