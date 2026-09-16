import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../../visits/domain/usecases/get_today_visits_count.dart';
import '../../domain/entities/patient.dart';
import '../../domain/usecases/get_patient_stats.dart';
import 'patients_provider.dart';

class DashboardStats {
  const DashboardStats({
    this.patients = const PatientStats(),
    this.seenToday = 0,
    this.isLoading = true,
  });

  final PatientStats patients;
  final int seenToday;
  final bool isLoading;

  DashboardStats copyWith({
    PatientStats? patients,
    int? seenToday,
    bool? isLoading,
  }) {
    return DashboardStats(
      patients: patients ?? this.patients,
      seenToday: seenToday ?? this.seenToday,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// The dashboard header's stat cards (total/active/inactive patients,
/// distinct patients seen today) — refreshes whenever the patient list does
/// (so toggling a status or adding a patient updates the numbers) and
/// whenever the active clinic changes.
class DashboardStatsNotifier extends Notifier<DashboardStats> {
  late final GetPatientStats _getPatientStats;
  late final GetTodayVisitsCount _getTodayVisitsCount;

  @override
  DashboardStats build() {
    _getPatientStats = sl<GetPatientStats>();
    _getTodayVisitsCount = sl<GetTodayVisitsCount>();

    // Same numbers change whenever the patient list does (a status toggle,
    // a new patient, a switched clinic) — piggyback on that instead of
    // polling independently.
    ref.listen(patientsListProvider, (previous, next) {
      if (previous?.isLoading == true && next.isLoading == false) {
        refresh();
      }
    });

    if (ref.read(activeClinicProvider).isReady) {
      Future.microtask(refresh);
    }

    return const DashboardStats();
  }

  Future<void> refresh() async {
    if (!ref.read(activeClinicProvider).isReady) return;

    state = state.copyWith(isLoading: true);

    // Kicked off together (not `await`ed one at a time) so the two queries
    // run concurrently — Future.wait needs a single element type, which
    // Either<Failure, PatientStats> and Either<Failure, int> aren't.
    final statsFuture = _getPatientStats(const NoParams());
    final todayFuture = _getTodayVisitsCount(const NoParams());
    final statsResult = await statsFuture;
    final todayResult = await todayFuture;

    state = state.copyWith(
      patients: statsResult.fold((_) => state.patients, (s) => s),
      seenToday: todayResult.fold((_) => state.seenToday, (c) => c),
      isLoading: false,
    );
  }
}

final dashboardStatsProvider =
    NotifierProvider<DashboardStatsNotifier, DashboardStats>(
      DashboardStatsNotifier.new,
    );
