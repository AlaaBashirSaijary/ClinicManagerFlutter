import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/backup_reminder_service.dart';
import '../../../../core/database/clinic_backup_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../../core/widgets/fade_slide_in.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../../clinics/presentation/widgets/clinic_switcher.dart';
import '../../domain/entities/patient.dart';
import 'patient_detail_page.dart';
import 'patient_form_page.dart';
import '../providers/dashboard_stats_provider.dart';
import '../providers/patients_provider.dart';

/// Mirrors resources/views/home.blade.php: search + status filter + list,
/// scoped to the signed-in user's clinic — plus a real dashboard header
/// (stat cards, distinctive branding) instead of a plain AppBar title, and
/// a paginated table instead of an ever-growing scroll list once there are
/// more than a page's worth of patients.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  BackupReminder? _backupReminder;

  @override
  void initState() {
    super.initState();
    _checkBackupReminder();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkBackupReminder() async {
    final reminder = await BackupReminderService.instance.checkIfDue();
    if (!mounted) return;
    setState(() => _backupReminder = reminder);
  }

  Future<void> _backupNow() async {
    setState(() => _backupReminder = null);
    try {
      await ClinicBackupService.instance.createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إنشاء نسخة احتياطية.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر إنشاء نسخة احتياطية: $e')));
    }
  }

  Future<void> _snoozeBackupReminder() async {
    setState(() => _backupReminder = null);
    await BackupReminderService.instance.snooze();
  }

  /// Live search as you type, same as the web app — debounced so a fast
  /// typist doesn't fire a database query per keystroke.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => ref.read(patientsListProvider.notifier).search(query),
    );
  }

  Future<void> _addPatient() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PatientFormPage()));
    if (saved == true) {
      ref.read(patientsListProvider.notifier).refresh();
      ref.read(dashboardStatsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Each clinic has its own backup history, so re-check whenever the
    // active clinic changes instead of showing a stale (or wrongly absent)
    // reminder for whichever clinic was active on the previous check.
    ref.listen(activeClinicProvider, (previous, next) {
      if (next.active != null && previous?.active?.id != next.active?.id) {
        _checkBackupReminder();
      }
    });

    final list = ref.watch(patientsListProvider);
    final notifier = ref.read(patientsListProvider.notifier);
    final stats = ref.watch(dashboardStatsProvider);
    final userName = ref.watch(authProvider).user?.name;

    return Scaffold(
      body: Column(
        children: [
          _DashboardHeader(
            userName: userName,
            stats: stats,
            onAddPatient: _addPatient,
          ),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.9, -1),
                  radius: 1.4,
                  colors: [Color(0x2E1287A0), Colors.transparent],
                ),
              ),
              child: RefreshIndicator(
                onRefresh: () => Future.wait([
                  notifier.refresh(),
                  ref.read(dashboardStatsProvider.notifier).refresh(),
                ]),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    if (_backupReminder != null) ...[
                      FadeSlideIn(
                        child: _BackupReminderBanner(
                          reminder: _backupReminder!,
                          onBackupNow: _backupNow,
                          onSnooze: _snoozeBackupReminder,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    FadeSlideIn(
                      child: _SearchCard(
                        controller: _searchController,
                        status: list.status,
                        searched: list.searched,
                        onSearchChanged: _onSearchChanged,
                        onStatus: notifier.setStatus,
                        onClear: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          notifier.clearFilters();
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (list.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        ),
                      )
                    else if (list.items.isEmpty)
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: _EmptyState(searched: list.searched),
                      )
                    else
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 60),
                        child: _PatientsTable(
                          patients: list.items,
                          onToggleStatus: (id) async {
                            await notifier.toggleStatus(id);
                            ref.read(dashboardStatsProvider.notifier).refresh();
                          },
                          onOpen: (id) async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PatientDetailPage(patientId: id),
                              ),
                            );
                            notifier.refresh();
                            ref.read(dashboardStatsProvider.notifier).refresh();
                          },
                        ),
                      ),
                    if (!list.isLoading && list.items.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _PaginationBar(
                        page: list.page,
                        lastPage: list.lastPage,
                        total: list.total,
                        onPrevious: list.page > 1
                            ? () => notifier.goToPage(list.page - 1)
                            : null,
                        onNext: list.page < list.lastPage
                            ? () => notifier.goToPage(list.page + 1)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A real header instead of a plain AppBar title: brand mark, a greeting
/// with the active clinic named right underneath it (so it reads as "whose
/// data this is" instead of an unlabeled switcher floating on its own),
/// sign-out, and the stat cards row — "إضافة مريض جديد" sits immediately
/// beside the patients-total tile rather than floating separately.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.userName,
    required this.stats,
    required this.onAddPatient,
  });

  final String? userName;
  final DashboardStats stats;
  final VoidCallback onAddPatient;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.aquaGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const BrandMark(size: 34),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // The clinic switcher, placed right under the name
                        // so it reads as "this is whose data you're seeing
                        // and where to switch it" instead of an unlabeled
                        // control floating on its own elsewhere.
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: ClinicSwitcher(compact: true, onDark: true),
                        ),
                      ],
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) => IconButton(
                      tooltip: 'خروج',
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () =>
                          ref.read(authProvider.notifier).signOut(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.groups_rounded,
                      value: '${stats.patients.total}',
                      label: 'إجمالي المرضى',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _AddPatientTile(onTap: onAddPatient)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.favorite_rounded,
                      value: '${stats.patients.active}',
                      label: 'نشط',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.event_available_rounded,
                      value: '${stats.seenToday}',
                      label: 'شوهدوا اليوم',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Right beside the patients-total tile, per the redesign ask.
class _AddPatientTile extends StatelessWidget {
  const _AddPatientTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.add_circle_rounded, color: AppColors.focus, size: 18),
            SizedBox(height: 6),
            Text(
              'إضافة',
              style: TextStyle(
                color: AppColors.focus,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'مريض جديد',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.status,
    required this.searched,
    required this.onSearchChanged,
    required this.onStatus,
    required this.onClear,
  });

  final TextEditingController controller;
  final PatientStatusFilter status;
  final bool searched;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PatientStatusFilter> onStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سجلات المرضى',
            style: TextStyle(
              color: AppColors.aqua,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'بحث بالاسم أو رقم الهاتف أو رقم الملف',
              suffixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in PatientStatusFilter.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: status == s,
                  onSelected: (_) => onStatus(s),
                ),
              if (searched)
                TextButton(
                  onPressed: onClear,
                  child: const Text('مسح الفلاتر'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nudges toward a manual backup once it's been a while — backups here are
/// entirely manual (see ClinicBackupService), so nothing else would ever
/// notice a stale or missing one on its own.
class _BackupReminderBanner extends StatelessWidget {
  const _BackupReminderBanner({
    required this.reminder,
    required this.onBackupNow,
    required this.onSnooze,
  });

  final BackupReminder reminder;
  final VoidCallback onBackupNow;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final message = !reminder.hasAnyBackup
        ? 'لم يتم إنشاء أي نسخة احتياطية بعد لهذه العيادة.'
        : 'آخر نسخة احتياطية كانت منذ '
              '${DateTime.now().difference(reminder.lastBackup!).inDays} يوم.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.sky.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.aqua.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.backup_outlined, color: AppColors.aqua, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    TextButton(
                      onPressed: onSnooze,
                      child: const Text('تذكير لاحقًا'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton(
                      onPressed: onBackupNow,
                      child: const Text('نسخ احتياطي الآن'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searched});

  final bool searched;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            searched ? Icons.search_off_rounded : Icons.folder_open_rounded,
            size: 40,
            color: AppColors.lens,
          ),
          const SizedBox(height: 12),
          Text(
            searched ? 'لا توجد نتائج مطابقة.' : 'لا توجد سجلات بعد.',
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            searched ? 'جرّبي كلمة بحث أخرى.' : 'أضيفي أول مريض من الأعلى.',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Up to 20 rows at a time (see PatientsListState.perPage) in a real table
/// instead of an ever-growing scroll list, so 100+ patients stays usable.
class _PatientsTable extends StatelessWidget {
  const _PatientsTable({
    required this.patients,
    required this.onToggleStatus,
    required this.onOpen,
  });

  final List<Patient> patients;
  final void Function(int id) onToggleStatus;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 42,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppColors.aqua,
          ),
          columns: const [
            DataColumn(label: Text('الاسم')),
            DataColumn(label: Text('رقم الملف')),
            DataColumn(label: Text('الهاتف')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final patient in patients)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      patient.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => onOpen(patient.id!),
                  ),
                  DataCell(
                    Text(
                      patient.patientNumber ?? '—',
                      style: const TextStyle(
                        color: AppColors.aqua,
                        fontSize: 12,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    onTap: () => onOpen(patient.id!),
                  ),
                  DataCell(
                    Text(
                      patient.phone ?? '—',
                      style: const TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 12,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    onTap: () => onOpen(patient.id!),
                  ),
                  DataCell(
                    GestureDetector(
                      onTap: () => onToggleStatus(patient.id!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: patient.isActive
                              ? AppColors.ok.withValues(alpha: 0.1)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          patient.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: patient.isActive
                                ? AppColors.ok
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      tooltip: 'فتح الإضبارة',
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: AppColors.aqua,
                      ),
                      onPressed: () => onOpen(patient.id!),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int lastPage;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('السابق'),
          ),
          const Spacer(),
          Text(
            'صفحة $page من $lastPage — $total مريض',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('التالي'),
          ),
        ],
      ),
    );
  }
}
