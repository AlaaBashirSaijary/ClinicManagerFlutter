import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../domain/entities/appointment.dart';
import '../../domain/usecases/delete_appointment.dart';
import '../../domain/usecases/get_appointments_for_day.dart';
import '../../domain/usecases/save_appointment.dart';

class AppointmentsState {
  const AppointmentsState({
    this.day,
    this.appointments = const [],
    this.isLoading = true,
    this.error,
  });

  final DateTime? day;
  final List<Appointment> appointments;
  final bool isLoading;
  final String? error;

  AppointmentsState copyWith({
    DateTime? day,
    List<Appointment>? appointments,
    bool? isLoading,
    String? error,
  }) {
    return AppointmentsState(
      day: day ?? this.day,
      appointments: appointments ?? this.appointments,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Backs the day-view appointments page — loads whichever [DateTime] (day
/// granularity) is currently selected, and re-loads automatically when the
/// active clinic switches (each clinic has its own appointments table, same
/// as patients/visits — see ClinicDataDatabase).
class AppointmentsNotifier extends Notifier<AppointmentsState> {
  late final GetAppointmentsForDay _getAppointmentsForDay;
  late final SaveAppointment _saveAppointment;
  late final DeleteAppointment _deleteAppointment;

  @override
  AppointmentsState build() {
    _getAppointmentsForDay = sl<GetAppointmentsForDay>();
    _saveAppointment = sl<SaveAppointment>();
    _deleteAppointment = sl<DeleteAppointment>();

    // Re-fetch whenever the active clinic changes — same reasoning as
    // PatientsListNotifier: its database file is a completely different
    // set of appointments.
    ref.listen(activeClinicProvider, (previous, next) {
      if (next.active != null && previous?.active?.id != next.active?.id) {
        final day = state.day;
        if (day != null) loadDay(day);
      }
    });

    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    if (ref.read(activeClinicProvider).isReady) {
      Future.microtask(() => loadDay(day));
    }
    return AppointmentsState(day: day);
  }

  Future<void> loadDay(DateTime day) async {
    if (!ref.read(activeClinicProvider).isReady) return;
    state = state.copyWith(day: day, isLoading: true);
    final result = await _getAppointmentsForDay(day);
    result.fold(
      (failure) =>
          state = state.copyWith(isLoading: false, error: failure.message),
      (appointments) => state = state.copyWith(
        appointments: appointments,
        isLoading: false,
        error: null,
      ),
    );
  }

  Future<String?> save(Appointment appointment) async {
    final result = await _saveAppointment(appointment);
    return result.fold((failure) => failure.message, (saved) {
      final day = state.day;
      if (day != null) loadDay(day);
      return null;
    });
  }

  Future<void> delete(int id) async {
    final result = await _deleteAppointment(id);
    result.fold((failure) => state = state.copyWith(error: failure.message), (
      _,
    ) {
      final day = state.day;
      if (day != null) loadDay(day);
    });
  }
}

final appointmentsProvider =
    NotifierProvider<AppointmentsNotifier, AppointmentsState>(
      AppointmentsNotifier.new,
    );
