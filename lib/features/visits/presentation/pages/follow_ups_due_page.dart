import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_theme.dart';
import '../../../patients/presentation/pages/patient_detail_page.dart';
import '../../domain/entities/follow_up_due.dart';
import '../providers/follow_ups_provider.dart';

/// Every active patient whose most recent visit is flagged as needing
/// follow-up — see VisitFormPage's "هذا المريض يحتاج متابعة" checkbox for
/// where these come from, and FollowUpDue's own doc comment for why a
/// patient never needs to be manually removed from this list.
class FollowUpsDuePage extends ConsumerWidget {
  const FollowUpsDuePage({super.key});

  static final _dateFormat = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(followUpsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('متابعات مستحقة')),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.read(followUpsProvider.notifier).refresh(),
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.items.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: const [_EmptyFollowUps()],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return _FollowUpCard(
                      item: item,
                      dateFormat: _dateFormat,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PatientDetailPage(patientId: item.patientId),
                          ),
                        );
                        ref.read(followUpsProvider.notifier).refresh();
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _EmptyFollowUps extends StatelessWidget {
  const _EmptyFollowUps();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.sky,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: AppColors.ok,
              size: 32,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'لا توجد متابعات مستحقة حاليًا',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'علّمي أي زيارة بـ"يحتاج متابعة" ليظهر مريضها هنا.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({
    required this.item,
    required this.dateFormat,
    required this.onTap,
  });

  final FollowUpDue item;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.isOverdue ? AppColors.danger : AppColors.focus;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(
                  item.patientName.isNotEmpty ? item.patientName[0] : '؟',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.patientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'آخر زيارة: ${dateFormat.format(item.visitDate)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.followUpBy == null
                      ? 'بلا تاريخ محدد'
                      : (item.isOverdue ? 'متأخرة — ' : 'بحلول ') +
                            dateFormat.format(item.followUpBy!),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
