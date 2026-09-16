import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login.dart';

/// Mirrors what `auth()->user()` gives every Blade view: null while
/// unresolved/signed-out, otherwise the signed-in AppUser. [needsOnboarding]
/// covers the one case the web app never had to (no users table row exists
/// yet at all) — the on-device equivalent of running ClinicSeeder once.
class AuthState {
  const AuthState({
    this.user,
    this.needsOnboarding = false,
    this.isLoading = true,
    this.error,
    this.pendingRecoveryCode,
  });

  final AppUser? user;
  final bool needsOnboarding;
  final bool isLoading;
  final String? error;

  /// Set right after onboarding creates the admin account, holding its
  /// one-time recovery code until AuthGate shows RecoveryCodePage and the
  /// admin confirms they saved it — see [AuthNotifier.acknowledgeRecoveryCode].
  final String? pendingRecoveryCode;

  bool get isSignedIn => user != null;

  AuthState copyWith({
    AppUser? user,
    bool? needsOnboarding,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? pendingRecoveryCode,
    bool clearPendingRecoveryCode = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pendingRecoveryCode: clearPendingRecoveryCode
          ? null
          : (pendingRecoveryCode ?? this.pendingRecoveryCode),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repository;
  late final AuthLocalDataSource _local;
  late final Login _login;

  @override
  AuthState build() {
    _repository = sl<AuthRepository>();
    _local = sl<AuthLocalDataSource>();
    _login = sl<Login>();
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    if (!await _local.hasAnyUser()) {
      state = state.copyWith(needsOnboarding: true, isLoading: false);
      return;
    }

    final user = await _repository.currentUser();
    state = state.copyWith(user: user, isLoading: false);
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final result = await _login(LoginParams(email: email, password: password));

    return result.fold(
      (failure) {
        state = state.copyWith(isLoading: false, error: failure.message);
        return false;
      },
      (user) {
        state = state.copyWith(user: user, isLoading: false, clearError: true);
        return true;
      },
    );
  }

  Future<void> signOut() async {
    await _repository.logout();
    state = state.copyWith(user: null);
    state = AuthState(isLoading: false, needsOnboarding: false, user: null);
  }

  Future<void> completeOnboarding({
    required String clinicName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final account = await _local.createClinicAndAdmin(
      clinicName: clinicName,
      adminName: adminName,
      email: email,
      password: password,
    );
    await _local.rememberSession(account.user.id);

    state = AuthState(
      user: account.user,
      isLoading: false,
      needsOnboarding: false,
      pendingRecoveryCode: account.recoveryCode,
    );
  }

  /// Dismisses the post-onboarding recovery-code screen once the admin has
  /// confirmed they saved it, letting AuthGate proceed into the app.
  void acknowledgeRecoveryCode() {
    state = state.copyWith(clearPendingRecoveryCode: true);
  }

  Future<bool> updateName(String name) async {
    final userId = state.user?.id;
    if (userId == null) return false;

    final result = await _repository.updateName(userId, name);
    return result.fold(
      (failure) {
        state = state.copyWith(error: failure.message);
        return false;
      },
      (user) {
        state = state.copyWith(user: user, clearError: true);
        return true;
      },
    );
  }

  /// Returns the failure message on error (shown inline in the dialog
  /// rather than replacing the whole page's error banner), or null on
  /// success.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final userId = state.user?.id;
    if (userId == null) return 'لا يوجد مستخدم مسجّل الدخول.';

    final result = await _repository.changePassword(
      userId: userId,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    return result.fold((failure) => failure.message, (_) => null);
  }

  /// Offline "forgot password": returns the failure message on error
  /// (shown inline on the form), or null on success — the caller then
  /// routes back to the login page to sign in with the new password.
  Future<String?> resetPasswordWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    final result = await _repository.resetPasswordWithRecoveryCode(
      email: email,
      recoveryCode: recoveryCode,
      newPassword: newPassword,
    );
    return result.fold((failure) => failure.message, (_) => null);
  }

  /// Issues the signed-in user a fresh recovery code (from the Admin page,
  /// in case the original was lost) — returns it once, or null on failure.
  Future<String?> regenerateRecoveryCode() async {
    final userId = state.user?.id;
    if (userId == null) return null;

    final result = await _repository.regenerateRecoveryCode(userId);
    return result.fold((failure) => null, (code) => code);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
