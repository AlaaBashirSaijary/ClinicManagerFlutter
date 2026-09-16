import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/visit.dart';
import '../../domain/entities/visit_field_value.dart';
import '../../domain/entities/visit_photo.dart';
import '../../domain/repositories/visit_repository.dart';
import '../datasources/visit_local_datasource.dart';
import '../models/visit_field_value_model.dart';
import '../models/visit_model.dart';

class VisitRepositoryImpl implements VisitRepository {
  const VisitRepositoryImpl(this._local);

  final VisitLocalDataSource _local;

  @override
  Future<Either<Failure, List<Visit>>> listForPatient(int patientId) async {
    try {
      return Right(await _local.listForPatient(patientId));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة زيارات الفحص: $e'));
    }
  }

  @override
  Future<Either<Failure, Visit>> create(Visit visit) async {
    try {
      return Right(await _local.create(VisitModel.fromEntity(visit)));
    } catch (e) {
      return Left(StorageFailure('تعذّر حفظ زيارة الفحص: $e'));
    }
  }

  @override
  Future<Either<Failure, Visit>> update(Visit visit) async {
    try {
      return Right(await _local.update(VisitModel.fromEntity(visit)));
    } catch (e) {
      return Left(StorageFailure('تعذّر تحديث زيارة الفحص: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> delete(int id) async {
    try {
      await _local.delete(id);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حذف زيارة الفحص: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> countDistinctPatientsToday() async {
    try {
      return Right(await _local.countDistinctPatientsToday());
    } catch (e) {
      return Left(StorageFailure('تعذّر حساب مرضى اليوم: $e'));
    }
  }

  @override
  Future<Either<Failure, List<VisitPhoto>>> listPhotos(int visitId) async {
    try {
      return Right(await _local.listPhotos(visitId));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة صور الزيارة: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> addPhoto(
    int visitId,
    Uint8List imageData,
  ) async {
    try {
      await _local.addPhoto(visitId, imageData);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حفظ الصورة: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deletePhoto(int id) async {
    try {
      await _local.deletePhoto(id);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حذف الصورة: $e'));
    }
  }

  @override
  Future<Either<Failure, List<VisitFieldValue>>> listFieldValues(
    int visitId,
  ) async {
    try {
      return Right(await _local.listFieldValues(visitId));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة بيانات الفحص: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveFieldValues(
    int visitId,
    List<VisitFieldValue> values,
  ) async {
    try {
      await _local.saveFieldValues(visitId, [
        for (final value in values)
          VisitFieldValueModel(
            visitId: value.visitId,
            templateId: value.templateId,
            side: value.side,
            value: value.value,
          ),
      ]);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حفظ بيانات الفحص: $e'));
    }
  }
}
