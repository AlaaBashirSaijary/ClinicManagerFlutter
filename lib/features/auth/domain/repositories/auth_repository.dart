import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/app_user.dart';

/// Mirrors Auth\LoginController — login/logout plus "who is signed in now",
/// backed by a locally-persisted session instead of a server cookie.
abstract class AuthRepository {
  Future<Either<Failure, AppUser>> login({
    required String email,
    required String password,
  });

  Future<void> logout();

  Future<AppUser?> currentUser();

  Future<Either<Failure, AppUser>> updateName(int userId, String name);

  Future<Either<Failure, Unit>> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  });

  /// Offline stand-in for a "forgot password" email link — resets the
  /// password if [recoveryCode] matches what was issued at account
  /// creation (or the last regenerate), without needing the old password.
  Future<Either<Failure, Unit>> resetPasswordWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  });

  /// Issues a fresh recovery code for a signed-in user, invalidating the
  /// previous one. Returns the plaintext code — the only time it's ever
  /// visible again after account creation.
  Future<Either<Failure, String>> regenerateRecoveryCode(int userId);
}
