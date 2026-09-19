import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/clinic_backup_service.dart';
import '../../../../core/security/app_lock_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/fade_slide_in.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../clinics/domain/entities/clinic.dart';
import '../../../clinics/presentation/providers/active_clinic_provider.dart';
import '../../../help/presentation/pages/help_guide_page.dart';
import '../../../legal/presentation/pages/privacy_policy_page.dart';
import '../../../legal/presentation/pages/terms_of_use_page.dart';
import '../../../reports/presentation/pages/monthly_report_page.dart';
import '../../../visits/presentation/pages/exam_template_settings_page.dart';
import 'activity_log_page.dart';

/// The "الإدارة" tab: everything a clinic owner needs to manage their own
/// account, the clinics registered on this device, and where the data
/// physically lives — three real sections instead of a single storage-path
/// form floating alone on the page.
class AdminHomePage extends ConsumerWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإدارة')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            StaggeredFadeSlideIn(
              spacing: AppSpacing.xl,
              children: [
                _AccountSection(),
                _HelpSection(),
                _UsersSection(),
                _SecuritySection(),
                _ClinicsSection(),
                _ExamFormSection(),
                _ReportsSection(),
                _ActivityLogSection(),
                _BackupSection(),
                _StorageSection(),
                _LegalSection(),
                _SupportSection(),
                _AboutFooter(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.aqua.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.aqua, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

// ============================== الحساب ==============================

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل الاسم'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    await ref.read(authProvider.notifier).updateName(result.trim());
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => const _ChangePasswordDialog(),
    );
  }

  /// Replaces this account's "forgot password" recovery code — the offline
  /// stand-in for a reset-link email — with a new one, in case the one
  /// shown at account creation was lost. Old code stops working immediately.
  Future<void> _regenerateRecoveryCode(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('توليد رمز استرداد جديد؟'),
        content: const Text(
          'سيتوقف الرمز الحالي (إن وُجد) عن العمل فورًا، ويظهر الرمز الجديد '
          'مرة واحدة فقط — احرصي على حفظه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('توليد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final code = await ref.read(authProvider.notifier).regenerateRecoveryCode();
    if (!context.mounted) return;

    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر توليد رمز استرداد جديد.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رمز الاسترداد الجديد'),
        content: SelectableText(
          code,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 2,
            color: AppColors.aquaDeep,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('تم الحفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.person_rounded,
          title: 'الحساب',
          subtitle: 'اسمك وكلمة المرور المستخدمة لتسجيل الدخول',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.aqua,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0] : '؟',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sky,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      user.isAdmin ? 'مدير' : 'ممرضة',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.aquaDeep,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editName(context, ref, user.name),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('تعديل الاسم'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _changePassword(context, ref),
                      icon: const Icon(Icons.lock_reset_rounded, size: 18),
                      label: const Text('كلمة المرور'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _regenerateRecoveryCode(context, ref),
                icon: const Icon(Icons.vpn_key_rounded, size: 18),
                label: const Text('توليد رمز استرداد جديد'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await ref
        .read(authProvider.notifier)
        .changePassword(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
        );

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentController,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _newController,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

// ============================== دليل الاستخدام ==============================

/// A direct link to the in-app help guide — the same content published as
/// a standalone web page, but reachable without leaving the app. Also
/// reachable from the dashboard header for staff who never see this page
/// (non-admin accounts).
class _HelpSection extends StatelessWidget {
  const _HelpSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.menu_book_rounded,
          title: 'دليل الاستخدام',
          subtitle: 'شرح تفصيلي لكل شاشة وميزة في التطبيق',
        ),
        _SectionCard(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HelpGuidePage())),
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: const Text('فتح دليل الاستخدام'),
          ),
        ),
      ],
    );
  }
}

// ============================== المستخدمون ==============================

/// Separate accounts per staff member instead of one shared login — lets
/// the clinic add nurses (or a second admin, e.g. a co-owner doctor)
/// without everyone using the same credentials, and gives an admin a way
/// to reset a colleague's forgotten password directly (see
/// AuthLocalDataSource.adminSetPassword) instead of that being a dead end.
class _UsersSection extends ConsumerStatefulWidget {
  const _UsersSection();

  @override
  ConsumerState<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends ConsumerState<_UsersSection> {
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await ref.read(authProvider.notifier).listClinicUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _addUser() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (result == true) _load();
  }

  Future<void> _resetPassword(AppUser user) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('كلمة مرور جديدة لـ ${user.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newPassword == null || newPassword.isEmpty || !mounted) return;

    final error = await ref
        .read(authProvider.notifier)
        .adminSetPassword(userId: user.id, newPassword: newPassword);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'تم تغيير كلمة مرور ${user.name}.')),
    );
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('حذف حساب ${user.name}؟'),
        content: const Text(
          'لن يعود بإمكان هذا الشخص تسجيل الدخول. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(authProvider.notifier)
        .deleteStaffUser(user.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authProvider).user?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.group_rounded,
          title: 'المستخدمون',
          subtitle: 'حساب مستقل لكل من يستخدم التطبيق بهذه العيادة',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                for (final user in _users) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.aqua,
                        child: Text(
                          user.name.isNotEmpty ? user.name[0] : '؟',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              user.email,
                              textDirection: TextDirection.ltr,
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
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.sky,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          user.isAdmin ? 'مدير' : 'ممرضة',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.aquaDeep,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إعادة تعيين كلمة المرور',
                        icon: const Icon(Icons.password_rounded, size: 18),
                        onPressed: () => _resetPassword(user),
                      ),
                      if (user.id != currentUserId)
                        IconButton(
                          tooltip: 'حذف الحساب',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          onPressed: () => _deleteUser(user),
                        ),
                    ],
                  ),
                  if (user != _users.last) const Divider(height: AppSpacing.lg),
                ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _addUser,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('إضافة مستخدم جديد'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog();

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isAdmin = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await ref
        .read(authProvider.notifier)
        .createStaffUser(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          isAdmin: _isAdmin,
        );

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مستخدم جديد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'كلمة المرور'),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('ممرضة'),
                selected: !_isAdmin,
                onSelected: (_) => setState(() => _isAdmin = false),
              ),
              ChoiceChip(
                label: const Text('مدير'),
                selected: _isAdmin,
                onSelected: (_) => setState(() => _isAdmin = true),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إنشاء'),
        ),
      ],
    );
  }
}

// ============================== الأمان ==============================

/// Optional PIN lock shown before the app's own content — off by default,
/// so it never gets in the way unless the clinic explicitly turns it on
/// here (see AppLockNotifier / PinLockPage).
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _SetPinDialog(),
    );
    if (pin == null) return;
    await ref.read(appLockProvider.notifier).enable(pin);
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final current = await _promptCurrentPin(context, title: 'الرمز الحالي');
    if (current == null || !context.mounted) return;

    final newPin = await showDialog<String>(
      context: context,
      builder: (_) => const _SetPinDialog(),
    );
    if (newPin == null || !context.mounted) return;

    final ok = await ref
        .read(appLockProvider.notifier)
        .changePin(currentPin: current, newPin: newPin);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'تم تغيير الرمز.' : 'الرمز الحالي غير صحيح.'),
      ),
    );
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final current = await _promptCurrentPin(
      context,
      title: 'أدخلي الرمز الحالي لإيقاف القفل',
    );
    if (current == null || !context.mounted) return;

    final ok = await ref.read(appLockProvider.notifier).disable(current);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الرمز الحالي غير صحيح.')));
    }
  }

  Future<String?> _promptCurrentPin(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'الرمز (4 أرقام)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.lock_outline_rounded,
          title: 'الأمان',
          subtitle: 'قفل اختياري برمز يظهر عند فتح التطبيق أو العودة إليه',
        ),
        _SectionCard(
          child: lock.enabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_rounded,
                          color: AppColors.ok,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Expanded(
                          child: Text(
                            'قفل التطبيق مفعّل',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _changePin(context, ref),
                            icon: const Icon(Icons.password_rounded, size: 18),
                            label: const Text('تغيير الرمز'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _disable(context, ref),
                            icon: const Icon(
                              Icons.lock_open_rounded,
                              size: 18,
                              color: AppColors.danger,
                            ),
                            label: const Text(
                              'إيقاف القفل',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: () => _enable(context, ref),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: const Text('تفعيل قفل التطبيق برمز'),
                ),
        ),
      ],
    );
  }
}

/// Enter + confirm for a new 4-digit PIN — shared by "enable" and "change".
class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _error = 'أدخلي 4 أرقام.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'الرمزان غير متطابقين.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعيين رمز القفل'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(labelText: 'رمز من 4 أرقام'),
          ),
          TextField(
            controller: _confirmController,
            obscureText: true,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(labelText: 'تأكيد الرمز'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}

// ============================== العيادات ==============================

class _ClinicsSection extends ConsumerWidget {
  const _ClinicsSection();

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Clinic clinic,
  ) async {
    final controller = TextEditingController(text: clinic.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل اسم العيادة'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    await ref.read(activeClinicProvider.notifier).rename(clinic, result.trim());
  }

  Future<void> _addClinic(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عيادة جديدة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم العيادة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    await ref
        .read(activeClinicProvider.notifier)
        .createAndSwitch(result.trim());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeClinicProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.local_hospital_rounded,
          title: 'العيادات',
          subtitle: 'كل عيادة لها قاعدة بيانات منفصلة تمامًا عن الأخرى',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final clinic in state.clinics) ...[
                Row(
                  children: [
                    Icon(
                      clinic.id == state.active?.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: clinic.id == state.active?.id
                          ? AppColors.aqua
                          : AppColors.inkSoft,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        clinic.name,
                        style: TextStyle(
                          fontWeight: clinic.id == state.active?.id
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (clinic.id != state.active?.id)
                      TextButton(
                        onPressed: () => ref
                            .read(activeClinicProvider.notifier)
                            .switchTo(clinic),
                        child: const Text('تفعيل'),
                      ),
                    IconButton(
                      tooltip: 'تعديل الاسم',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _rename(context, ref, clinic),
                    ),
                  ],
                ),
                if (clinic != state.clinics.last)
                  const Divider(height: AppSpacing.lg),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _addClinic(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة عيادة جديدة'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================== نموذج الفحص ==============================

class _ExamFormSection extends StatelessWidget {
  const _ExamFormSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.assignment_outlined,
          title: 'نموذج الفحص',
          subtitle:
              'حقول زيارة الفحص التي تظهر لهذه العيادة — اجعليها مناسبة لتخصصك',
        ),
        _SectionCard(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ExamTemplateSettingsPage(),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('إعداد نموذج الفحص'),
          ),
        ),
      ],
    );
  }
}

// ============================== التقرير الشهري ==============================

class _ReportsSection extends StatelessWidget {
  const _ReportsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.bar_chart_rounded,
          title: 'التقرير الشهري',
          subtitle:
              'عدد الكشفيات المدفوعة والمتابعات المجانية والمرضى الجدد لكل شهر',
        ),
        _SectionCard(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MonthlyReportPage()),
            ),
            icon: const Icon(Icons.bar_chart_rounded, size: 18),
            label: const Text('عرض التقرير'),
          ),
        ),
      ],
    );
  }
}

// ============================== سجل النشاط ==============================

class _ActivityLogSection extends StatelessWidget {
  const _ActivityLogSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.history_rounded,
          title: 'سجل النشاط',
          subtitle: 'من فعل ماذا ومتى — لكل التغييرات في هذه العيادة',
        ),
        _SectionCard(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ActivityLogPage())),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('عرض سجل النشاط'),
          ),
        ),
      ],
    );
  }
}

// ============================== النسخ الاحتياطي ==============================

enum _RestoreChoice { newClinic, replace }

/// Lets the doctor choose, with the consequence of each spelled out
/// plainly, instead of the app only ever offering a full destructive
/// replace: restoring an old backup doesn't have to mean losing everything
/// entered since — it can become its own separate clinic instead, with the
/// active one left completely untouched.
class _RestoreChoiceDialog extends StatelessWidget {
  const _RestoreChoiceDialog({required this.backup, required this.dateFormat});

  final ClinicBackup backup;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('استعادة نسخة ${dateFormat.format(backup.createdAt)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RestoreOptionTile(
            icon: Icons.library_add_rounded,
            color: AppColors.ok,
            title: 'استعادة كعيادة جديدة منفصلة',
            subtitle:
                'الخيار الأكثر أمانًا. لا يتغيّر أي شيء في بيانات العيادة '
                'الحالية إطلاقًا — تُضاف بيانات هذه النسخة كعيادة جديدة '
                'مستقلة تمامًا، يمكن التبديل إليها أو تعديل اسمها لاحقًا، '
                'بينما تبقى العيادة الحالية كما هي دون أي مساس.',
            onTap: () => Navigator.of(context).pop(_RestoreChoice.newClinic),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RestoreOptionTile(
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
            title: 'استبدال بيانات العيادة الحالية',
            subtitle:
                'يمسح كل بيانات العيادة الحالية ويستبدلها بالكامل بمحتوى '
                'هذه النسخة. يأخذ التطبيق نسخة احتياطية تلقائية من البيانات '
                'الحالية أولًا احتياطًا، لكن الاستبدال نفسه فوري داخل '
                'العيادة الحالية نفسها.',
            onTap: () => Navigator.of(context).pop(_RestoreChoice.replace),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}

class _RestoreOptionTile extends StatelessWidget {
  const _RestoreOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  List<ClinicBackup> _backups = [];
  bool _loading = true;
  bool _creating = false;
  String? _message;
  bool _messageIsError = false;

  static final _dateFormat = DateFormat('yyyy/MM/dd - HH:mm');

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _loading = true);
    final backups = await ClinicBackupService.instance.listBackups();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _loading = false;
    });
  }

  Future<void> _createBackup() async {
    setState(() {
      _creating = true;
      _message = null;
    });

    try {
      await ClinicBackupService.instance.createBackup();
      await _loadBackups();
      if (!mounted) return;
      setState(() {
        _message = 'تم إنشاء نسخة احتياطية بنجاح.';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'تعذّر إنشاء نسخة احتياطية: $e';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _restoreBackup(ClinicBackup backup) async {
    final choice = await showDialog<_RestoreChoice>(
      context: context,
      builder: (dialogContext) =>
          _RestoreChoiceDialog(backup: backup, dateFormat: _dateFormat),
    );
    if (choice == null) return;

    switch (choice) {
      case _RestoreChoice.newClinic:
        await _restoreAsNewClinic(backup);
      case _RestoreChoice.replace:
        await _replaceWithBackup(backup);
    }
  }

  /// The safe choice: the active clinic's data is never touched — this
  /// backup becomes its own separate clinic instead.
  Future<void> _restoreAsNewClinic(ClinicBackup backup) async {
    setState(() => _message = null);

    final currentName = ref.read(activeClinicProvider).active?.name ?? 'عيادة';
    final suggestedName =
        '$currentName (نسخة ${_dateFormat.format(backup.createdAt)})';

    final ok = await ref
        .read(activeClinicProvider.notifier)
        .restoreBackupAsNewClinic(backup, suggestedName);

    if (!mounted) return;
    setState(() {
      if (ok) {
        _message =
            'تمت الاستعادة كعيادة جديدة باسم "$suggestedName" — '
            'يمكن تعديل الاسم أو التبديل إليها من قسم "العيادات" أعلاه.';
        _messageIsError = false;
      } else {
        _message =
            ref.read(activeClinicProvider).error ??
            'تعذّرت الاستعادة كعيادة جديدة.';
        _messageIsError = true;
      }
    });
  }

  /// The destructive choice: overwrites the active clinic's current data.
  Future<void> _replaceWithBackup(ClinicBackup backup) async {
    setState(() => _message = null);
    try {
      await ClinicBackupService.instance.restoreBackup(backup);
      if (!mounted) return;
      setState(() {
        _message =
            'تمت استعادة النسخة الاحتياطية بنجاح (استبدال البيانات الحالية).';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'تعذّرت الاستعادة: $e';
        _messageIsError = true;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} ك.ب';
    return '${(kb / 1024).toStringAsFixed(1)} م.ب';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.backup_rounded,
          title: 'النسخ الاحتياطي',
          subtitle:
              'احتفظي بنسخة من بيانات العيادة الحالية يمكن استعادتها لاحقًا',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_message != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: (_messageIsError ? AppColors.danger : AppColors.ok)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError ? AppColors.danger : AppColors.ok,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _creating
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : GradientButton(
                      label: 'إنشاء نسخة احتياطية الآن',
                      icon: Icons.save_alt_rounded,
                      onPressed: _createBackup,
                    ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'النسخ المحفوظة',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'لا توجد نسخ احتياطية بعد.',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                  ),
                )
              else
                for (final backup in _backups) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppColors.inkSoft,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dateFormat.format(backup.createdAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _formatSize(backup.sizeBytes),
                              style: const TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _restoreBackup(backup),
                        child: const Text('استعادة'),
                      ),
                    ],
                  ),
                  if (backup != _backups.last)
                    const Divider(height: AppSpacing.lg),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ============================== التخزين ==============================

class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  String? _currentPath;
  bool _moving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final path = await AppDatabase.instance.currentPath();
    if (mounted) setState(() => _currentPath = path);
  }

  Future<void> _pickNewFolder() async {
    setState(() {
      _message = null;
      _messageIsError = false;
    });

    // Opens iOS/iPadOS's own folder picker — this is the screen where an
    // external drive plugged into the iPad (via the Files provider) shows
    // up as a selectable location, same as it would in the Files app.
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مكان حفظ قاعدة البيانات',
    );

    if (folder == null) return; // User cancelled.

    setState(() => _moving = true);

    try {
      await AppDatabase.instance.useCustomPath(folder);
      await _loadCurrentPath();
      setState(() {
        _message = 'تم نقل قاعدة البيانات بنجاح.';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = 'تعذّر النقل إلى هذا المسار: $e';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.sd_storage_rounded,
          title: 'مكان حفظ البيانات',
          subtitle: 'يمكن اختيار مجلد على قرص خارجي متصل بالآيباد',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'المسار الحالي',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                _currentPath ?? '...',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.md),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _message == null
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color:
                              (_messageIsError
                                      ? AppColors.danger
                                      : AppColors.ok)
                                  .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _messageIsError
                                ? AppColors.danger
                                : AppColors.ok,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              _moving
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : GradientButton(
                      label: 'اختيار مجلد جديد (مثلًا على قرص خارجي)',
                      icon: Icons.folder_open_rounded,
                      onPressed: _pickNewFolder,
                    ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.sky.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'ملاحظة: على آيباد، أول مرة تختارين فيها القرص الخارجي قد يطلب '
                  'النظام الإذن للوصول إليه. إن لم يظهر القرص بالقائمة تأكدي من '
                  'توصيله وأن تطبيق "الملفات" يقدر يشوفه.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================== قانوني ==============================

/// Links to the privacy policy and terms of use — both are still drafts
/// (see the warning banner at the top of each page) until reviewed by a
/// lawyer, but living here means they're always one tap away for a doctor
/// who wants to check what they agreed to, not just shown once during
/// onboarding and then forgotten.
class _LegalSection extends StatelessWidget {
  const _LegalSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.gavel_rounded,
          title: 'قانوني',
          subtitle: 'سياسة الخصوصية وشروط الاستخدام',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                ),
                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                label: const Text('سياسة الخصوصية'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsOfUsePage()),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('شروط الاستخدام'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================== حول ==============================

/// Required by the license of the onboarding illustrations
/// (assets/images/Doctor-pana.svg, Insurance-pana.svg — Storyset/Freepik,
/// "free for personal and commercial purpose with attribution").
// ============================== الدعم والإصدار ==============================

/// The technical side of "بيع مباشر + دعم شخصي": no in-app license key or
/// activation check (the relationship and the terms-of-use grant *are* the
/// license for this stage — see legal/terms_of_use_page.dart), just two
/// small, real conveniences that model actually needs — a one-tap channel
/// to the vendor, and a version number visible without digging through
/// device settings, so a support visit can confirm what's installed at a
/// glance before deciding whether to bring an update.
class _SupportSection extends StatefulWidget {
  const _SupportSection();

  @override
  State<_SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<_SupportSection> {
  static const _supportWhatsAppNumber = '963984668063';

  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _openSupport() async {
    final message = Uri.encodeComponent(
      'مرحبًا، بحاجة مساعدة بخصوص تطبيق عيادتي.',
    );
    final uri = Uri.parse(
      'https://wa.me/$_supportWhatsAppNumber?text=$message',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّر فتح واتساب.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.support_agent_rounded,
          title: 'الدعم والإصدار',
          subtitle: 'تواصل مباشر مع الدعم، ورقم إصدار التطبيق الحالي',
        ),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _openSupport,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('تواصل مع الدعم عبر واتساب'),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text(
                _info == null
                    ? 'جارٍ التحقق من رقم الإصدار...'
                    : 'الإصدار ${_info!.version} (رقم البناء ${_info!.buildNumber})',
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: Text(
          'رسومات الترحيب من storyset.com',
          style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}
