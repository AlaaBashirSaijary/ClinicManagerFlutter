import 'package:equatable/equatable.dart';

/// The clinic's usual fee for each kind of visit, set once so the visit form
/// can pre-fill "الكشفية" instead of the doctor retyping it every time.
/// Null means "no default" — the field just starts empty, as before.
class FeeDefaults extends Equatable {
  const FeeDefaults({this.consultationFee, this.checkupFee});

  /// مراجعة — the full-price visit.
  final double? consultationFee;

  /// معاينة — usually half-price or free.
  final double? checkupFee;

  @override
  List<Object?> get props => [consultationFee, checkupFee];
}
