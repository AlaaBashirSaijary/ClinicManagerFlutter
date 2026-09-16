import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/appointment.dart';
import '../../domain/repositories/appointment_repository.dart';
import '../datasources/appointment_local_datasource.dart';
import '../models/appointment_model.dart';

class AppointmentRepositoryImpl implements AppointmentRepository {
  const AppointmentRepositoryImpl(this._local);

  final AppointmentLocalDataSource _local;

  @override
  Future<Either<Failure, List<Appointment>>> listBetween(
    DateTime start,
    DateTime end,
  ) async {
    try {
      return Right(await _local.listBetween(start, end));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة المواعيد: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Appointment>>> listUpcoming({
    int limit = 20,
  }) async {
    try {
      return Right(await _local.listUpcoming(limit: limit));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة المواعيد القادمة: $e'));
    }
  }

  @override
  Future<Either<Failure, Appointment>> create(Appointment appointment) async {
    try {
      return Right(
        await _local.create(AppointmentModel.fromEntity(appointment)),
      );
    } catch (e) {
      return Left(StorageFailure('تعذّر حجز الموعد: $e'));
    }
  }

  @override
  Future<Either<Failure, Appointment>> update(Appointment appointment) async {
    try {
      return Right(
        await _local.update(AppointmentModel.fromEntity(appointment)),
      );
    } catch (e) {
      return Left(StorageFailure('تعذّر تحديث الموعد: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> delete(int id) async {
    try {
      await _local.delete(id);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حذف الموعد: $e'));
    }
  }

  @override
  Future<Either<Failure, DateTime?>> lastConsultationDate(int patientId) async {
    try {
      return Right(await _local.lastConsultationDate(patientId));
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة سجل الكشفيات: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> getFollowUpDays() async {
    try {
      return Right(await _local.getFollowUpDays());
    } catch (e) {
      return Left(StorageFailure('تعذّرت قراءة إعداد فترة المتابعة: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> setFollowUpDays(int days) async {
    try {
      await _local.setFollowUpDays(days);
      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('تعذّر حفظ إعداد فترة المتابعة: $e'));
    }
  }

  @override
  Future<Either<Failure, Map<AppointmentType, int>>> countByTypeBetween(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final raw = await _local.countByTypeBetween(start, end);
      return Right({
        for (final entry in raw.entries)
          AppointmentType.fromValue(entry.key): entry.value,
      });
    } catch (e) {
      return Left(StorageFailure('تعذّر حساب إحصاء المواعيد: $e'));
    }
  }
}
