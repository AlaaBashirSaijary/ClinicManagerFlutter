import 'package:equatable/equatable.dart';

/// Typed failures returned by the domain layer instead of throwing —
/// mirrors how the Laravel side returns validation errors / redirects
/// instead of letting exceptions bubble up to the user.
abstract class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// A local SQLite read/write failed (disk full, external drive unplugged,
/// permission denied, etc.) — the Flutter analogue of ClinicStorage's
/// "path not writable" checks on the Laravel side.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Field-level validation failed. [fieldErrors] mirrors Laravel's
/// `$errors->all()` / `@error('field')` shape so the presentation layer can
/// show the same per-field messages the Blade forms show.
class ValidationFailure extends Failure {
  const ValidationFailure(this.fieldErrors) : super('بيانات غير صحيحة.');

  final Map<String, String> fieldErrors;

  @override
  List<Object?> get props => [message, fieldErrors];
}

/// Login failed — wrong email/password.
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Attempted to touch a record outside the signed-in user's clinic — the
/// Flutter equivalent of PatientController::authorizeClinic() aborting 404.
class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('غير مصرح بالوصول لهذا السجل.');
}

/// A requested record does not exist.
class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}
