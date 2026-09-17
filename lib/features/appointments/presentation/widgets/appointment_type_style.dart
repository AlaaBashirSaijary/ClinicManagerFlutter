import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/appointment.dart';

/// Icon + color for an [AppointmentType] — shared by every place the app
/// shows a type badge (the day list, the booking form, the monthly report)
/// so the three payment tiers read consistently everywhere instead of each
/// screen re-deriving its own two-way (paid/free) styling that can't
/// represent the half-price middle tier.
extension AppointmentTypeStyle on AppointmentType {
  IconData get icon => switch (this) {
    AppointmentType.consultation => Icons.payments_rounded,
    AppointmentType.halfConsultation => Icons.percent_rounded,
    AppointmentType.followUp => Icons.volunteer_activism_rounded,
  };

  Color get color => switch (this) {
    AppointmentType.consultation => AppColors.danger,
    AppointmentType.halfConsultation => AppColors.focus,
    AppointmentType.followUp => AppColors.ok,
  };
}
