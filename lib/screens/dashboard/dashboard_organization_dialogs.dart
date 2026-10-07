part of 'dashboard_screen.dart';

// Create, join, edit, leave, delete, and migrate organizations, plus their menu.
// These dialogs use the dashboard's existing services, locks, and refresh flow.
extension _DashboardOrganizationDialogs on _DashboardScreenState {
  Future<void> _showCreateOrganizationDialog() async {
    if (!_canCreateOrganization) return;
    final nameCtrl    = TextEditingController();
    final addressCtrl = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final emailCtrl   = TextEditingController();
    final taxCtrl     = TextEditingController();
    final formKey     = GlobalKey<FormState>();
    bool isSubmitting = false;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: _DS.primaryLight,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _DS.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_business, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('tooltip_create'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildField(nameCtrl, AppTranslations.of(ctx).text('org_name_required'),
                            hint: AppTranslations.of(ctx).text('org_name_example'),
                            icon: Icons.business, maxLength: 100,
                            autofocus: !_isSmallScreen(ctx),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? AppTranslations.of(ctx).text('please_enter_org_name')
                                : null),
                        const SizedBox(height: 14),
                        _buildField(addressCtrl, AppTranslations.of(ctx).text('address'),
                            hint: AppTranslations.of(ctx).text('address_example'),
                            icon: Icons.location_on, maxLength: 300, maxLines: 2,
                            textCapitalization: TextCapitalization.words,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 14),
                        _buildField(phoneCtrl, AppTranslations.of(ctx).text('phone'),
                            hint: AppTranslations.of(ctx).text('phone_example'),
                            icon: Icons.phone, maxLength: 20,
                            keyboardType: TextInputType.phone,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 14),
                        _buildField(emailCtrl, AppTranslations.of(ctx).text('email'),
                            hint: AppTranslations.of(ctx).text('email_example'),
                            icon: Icons.email, maxLength: 254,
                            keyboardType: TextInputType.emailAddress,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                if (!isValidEmail(v)) return AppTranslations.of(ctx).text('email_invalid');
                              }
                              return null;
                            }),
                        const SizedBox(height: 14),
                        _buildField(taxCtrl, AppTranslations.of(ctx).text('tax_code'),
                            hint: '0123456789 or 0123456789-001',
                            icon: Icons.receipt_long, maxLength: 14,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty && !_organizationService.isValidTaxCode(v)) {
                                return AppTranslations.of(ctx)['invalid_tax_code'];
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildInfoBanner(AppTranslations.of(ctx).text('contact_info_on_invoice')),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    StatefulBuilder(
                      builder: (ctx2, setButtonState) {
                        return FilledButton.icon(
                          onPressed: isSubmitting ? null : () async {
                            if (_createOrgLock.isLocked) return;
                            if (!formKey.currentState!.validate()) return;
                            setButtonState(() => isSubmitting = true);
                            await _createOrgLock.run(() async {
                              // Capture navigator from the dialog context before async
                              final dialogNav = Navigator.of(ctx);
                              final screenMessenger = ScaffoldMessenger.of(context);
                              _showTrackedDialog(
                                context: ctx,
                                barrierDismissible: false,
                                builder: (lctx) => _buildLoadingDialog(
                                  AppTranslations.of(lctx).text('create_action'),
                                ),
                              );
                              try {
                                final owner = await _authService.getCurrentOwner();
                                if (owner == null) {
                                  if (mounted) dialogNav.pop();
                                  return;
                                }
                                final created = await _organizationService.createOrganization(
                                  name: nameCtrl.text.trim(),
                                  ownerId: owner.id,
                                  address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                  email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                  taxCode: taxCtrl.text.trim().isEmpty ? null : taxCtrl.text.trim(),
                                );
                                if (created == null) throw StateError('org_create_failed');
                                if (!mounted) return;
                                dialogNav.pop(); // pop loader
                                dialogNav.pop(); // pop create dialog
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _showSuccessSnack(AppTranslations.of(context).text('org_created_success'));
                                    _updateDashboardState(() { _entryKey = UniqueKey(); });
                                  }
                                });
                              } catch (e) {
                                if (mounted) {
                                  dialogNav.pop(); // pop loader
                                  final reason = serverReason(e, const ['org_staff_account', 'org_create_limit', 'org_create_unavailable', 'org_invalid_email']);
                                  screenMessenger.showSnackBar(SnackBar(
                                    content: Text(AppTranslations.of(context).text(reason.isEmpty ? 'org_create_failed' : reason)),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            });
                            if (mounted) setButtonState(() => isSubmitting = false);
                          },
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(AppTranslations.of(ctx).text('create_action')),
                          style: FilledButton.styleFrom(backgroundColor: _DS.primary),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    taxCtrl.dispose();
  }

  Future<void> _showJoinOrganizationDialog() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (routeContext) => Scaffold(
      body: AccessRequestScreen(service: getIt<TeamService>(), onBack: () => Navigator.of(routeContext).pop()),
    )));
    final owner = await _authService.getCurrentOwner();
    if (mounted && owner != null) _refreshOrgs(owner.id);
  }

  Future<void> _showLeaveOrganizationDialog(Organization org, String ownerId) async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange[400]!, Colors.orange[700]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppTranslations.of(ctx).text('leave_org'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Text(
                    AppTranslations.of(ctx).textWithParams('leave_org_confirm', {'name': org.name}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  _buildWarningBanner(AppTranslations.of(ctx).text('lose_access_warning'), Colors.orange),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _DS.textSecondary,
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppTranslations.of(ctx).text('cancel'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.exit_to_app_rounded, size: 16),
                      label: Text(AppTranslations.of(ctx).text('leave_action'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      final nav       = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final successText = AppTranslations.of(context).text('left_org_success');
      final failText    = AppTranslations.of(context).text('cannot_leave_org');

      _leaveOrgLock.run(() async {
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (lctx) => _buildLoadingDialog(AppTranslations.of(lctx).text('leaving_org')),
        );
        final success = org.accessVersion == 2
            ? await _v2Action(() => _organizationSettings.leave(org.id))
            : await _organizationService.leaveOrganization(ownerId, org.id);
        if (!mounted) return;
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(success ? successText : failText),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
        if (success) _updateDashboardState(() { _entryKey = UniqueKey(); });
      });
    }
  }

  Future<void> _showDeleteOrganizationDialog(Organization org, String ownerId) async {
    final nameCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.delete_forever, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text('delete_org'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Version 2 closes now and deletes after 30 days: say that first.
                        if (org.accessVersion == 2) ...[
                          _buildWarningBanner(AppTranslations.of(ctx).text('close_org_v2_notice'), Colors.orange),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          AppTranslations.of(ctx).textWithParams('delete_org_warning', {'name': org.name}),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_buildings')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_rooms')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_tenants')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_payments')),
                        _buildDeleteWarningItem(AppTranslations.of(ctx).text('all_members')),
                        const SizedBox(height: 12),
                        _buildWarningBanner(AppTranslations.of(ctx).text('warning_cannot_undo'), Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          AppTranslations.of(ctx).text('confirm_enter_org_name'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: nameCtrl,
                          maxLength: 100,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: org.name,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.edit),
                          ),
                          validator: (v) => (v == null || v.trim() != org.name)
                              ? AppTranslations.of(ctx).text('name_mismatch')
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        nameCtrl.dispose();
                        Navigator.pop(ctx, false);
                      },
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: nameCtrl,
                      builder: (_, typed, _) => FilledButton(
                        // Disabled until the exact name is typed; the form check stays as a second guard.
                        onPressed: typed.text.trim() == org.name
                            ? () {
                                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
                              }
                            : null,
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        child: Text(AppTranslations.of(ctx).text('delete_permanently')),
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

    if (confirm == true && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      // Capture before async
      final nav       = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final successText = AppTranslations.of(context).text('deleted_org_success');
      final failText    = AppTranslations.of(context).text('cannot_delete_org');

      final progressNotifier = ValueNotifier<double>(0.0);
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: false,
            titleKey: 'deleting_org'),
      );
      final typedName = nameCtrl.text.trim();
      final success = org.accessVersion == 2
          // The server checks the typed name again; never send the saved name.
          ? await _v2Action(() => _organizationSettings.close(org.id, typedName))
          : await _organizationService.deleteOrganization(
              ownerId, org.id,
              onProgress: (p) => progressNotifier.value = p);
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Row(children: [
          Icon(success ? Icons.check_circle : Icons.error, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(success ? successText : failText)),
        ]),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      if (success) _updateDashboardState(() { _entryKey = UniqueKey(); });
    }
  }

  void _showOrganizationInfo(Organization org) {
    _showTrackedDialog(
      context: context,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_DS.primaryMid, _DS.primaryDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        org.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppTranslations.of(ctx).text('org_info'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          org.name,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 17,
                            fontWeight: FontWeight.w800, letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoTile(Icons.badge_outlined,
                          AppTranslations.of(ctx).text('id'), org.id, monospace: true),
                      _buildInfoTile(Icons.calendar_today_outlined,
                          AppTranslations.of(ctx).text('created_date'),
                          _formatDate(org.createdAt, ctx)),
                      if (org.updatedAt != null)
                        _buildInfoTile(Icons.update_rounded,
                            AppTranslations.of(ctx).text('last_updated'),
                            _formatDate(org.updatedAt!, ctx)),
                      if (org.address?.isNotEmpty == true)
                        _buildInfoTile(Icons.location_on_outlined,
                            AppTranslations.of(ctx).text('address_label'), org.address!),
                      if (org.phone?.isNotEmpty == true)
                        _buildInfoTile(Icons.phone_outlined,
                            AppTranslations.of(ctx).text('phone_label'), org.phone!),
                      if (org.email?.isNotEmpty == true)
                        _buildInfoTile(Icons.email_outlined,
                            AppTranslations.of(ctx).text('email_label'), org.email!),
                      if (org.bankName?.isNotEmpty == true)
                        _buildInfoTile(Icons.account_balance_outlined,
                            AppTranslations.of(ctx).text('bank_name'), org.bankName!),
                      if (org.bankAccountNumber?.isNotEmpty == true)
                        _buildInfoTile(Icons.credit_card_outlined,
                            AppTranslations.of(ctx).text('account_number'), org.bankAccountNumber!),
                      if (org.bankAccountName?.isNotEmpty == true)
                        _buildInfoTile(Icons.person_outline_rounded,
                            AppTranslations.of(ctx).text('account_holder'), org.bankAccountName!),
                      if (org.taxCode?.isNotEmpty == true)
                        _buildInfoTile(Icons.receipt_long_outlined,
                            AppTranslations.of(ctx).text('tax_code'), org.taxCode!),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _DS.textSecondary,
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppTranslations.of(ctx).text('close'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value,
      {bool monospace = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _DS.primaryLight, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 14, color: _DS.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _DS.textSecondary, letterSpacing: 0.3,
                    )),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: _DS.textPrimary,
                    fontFamily: monospace ? 'monospace' : null,
                    letterSpacing: monospace ? 0.5 : 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMigrateOrganizationDialog(
      Organization sourceOrg, String ownerId, bool deleteAfter) async {
    // Holds the chosen target's ID; filled only from the picker below.
    final targetCtrl = TextEditingController();
    final isV2 = sourceOrg.accessVersion == 2;
    // Only organizations this account can actually copy into: same kind as the
    // source, active membership with Owner/Administrator (legacy: admin), and
    // not the source. The server re-checks everything; this list is for choice.
    final targets = <Organization>[];
    try {
      final orgs = await (_orgsFuture ?? Future.value(<Organization>[]));
      for (final o in orgs) {
        if (o.id == sourceOrg.id || o.accessVersion != sourceOrg.accessVersion) continue;
        final m = await _membershipFutures.putIfAbsent(
            o.id, () => _organizationService.getUserMembership(ownerId, o.id));
        final allowed = m != null && m.status == 'active' &&
            (isV2 ? const {'owner', 'administrator'}.contains(m.role) : m.role == 'admin');
        if (allowed) targets.add(o);
      }
    } catch (e) {
      logger.e('Could not list copy targets', error: e);
    }
    if (!mounted) return;
    targets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // Copy & delete closes the source, so it needs the same typed confirmation.
    final confirmCtrl = TextEditingController();
    final needsName = isV2 && deleteAfter;
    // One copy operation per target, reused on retry so an interrupted copy
    // resumes instead of duplicating records.
    String? copyTarget;
    String? copyOperation;
    Map<String, int>? preview;
    String? status;
    bool statusIsError = false;
    bool loading = false;
    bool started = false;
    double progress = 0.0;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: !started,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _getDialogWidth(ctx),
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: deleteAfter
                          ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                          : [_DS.primaryMid, _DS.primaryDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        deleteAfter ? Icons.delete_sweep_rounded : Icons.compare_arrows_rounded,
                        color: Colors.white, size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      deleteAfter
                          ? AppTranslations.of(ctx).text('migrate_and_delete')
                          : AppTranslations.of(ctx).text('migrate_org_data'),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _DS.primaryLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _DS.primary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppTranslations.of(ctx).text('source_org_info'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 11,
                                    color: _DS.primary, letterSpacing: 0.5,
                                  )),
                              const SizedBox(height: 6),
                              Text(
                                AppTranslations.of(ctx).textWithParams('name_with_value', {'name': sourceOrg.name}),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: _DS.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppTranslations.of(ctx).textWithParams('id_with_value', {'id': sourceOrg.id}),
                                style: const TextStyle(fontSize: 12, color: _DS.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (targets.isEmpty)
                          _buildWarningBanner(
                              AppTranslations.of(ctx).text('copy_no_target_orgs'), Colors.orange)
                        else ...[
                          DropdownButtonFormField<String>(
                            initialValue: targetCtrl.text.isEmpty ? null : targetCtrl.text,
                            isExpanded: true,
                            items: [
                              for (final o in targets)
                                DropdownMenuItem(
                                  value: o.id,
                                  child: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            // A preview or error belongs to the previous choice, so clear it.
                            onChanged: started ? null : (id) => setDialogState(() {
                              targetCtrl.text = id ?? '';
                              preview = null;
                              status = null;
                              statusIsError = false;
                            }),
                            decoration: InputDecoration(
                              labelText: AppTranslations.of(ctx).text('copy_target_org'),
                              prefixIcon: const Icon(Icons.business_outlined),
                              filled: true,
                              fillColor: _DS.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: _DS.primary, width: 1.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(AppTranslations.of(ctx).text('copy_repeat_note'),
                              style: const TextStyle(fontSize: 12, color: _DS.textSecondary)),
                        ],
                        if (preview != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(Icons.preview_rounded, size: 15, color: Color(0xFF16A34A)),
                                  SizedBox(width: 6),
                                  Text(AppTranslations.of(ctx)['preview'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12, color: Color(0xFF16A34A),
                                      )),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                  AppTranslations.of(ctx).textWithParams('preview_stats', {
                                    'buildings': preview?['buildings'] ?? 0,
                                    'rooms': preview?['rooms'] ?? 0,
                                    'tenants': preview?['tenants'] ?? 0,
                                    'payments': preview?['payments'] ?? 0,
                                  }),
                                  style: const TextStyle(fontSize: 13, color: _DS.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (loading) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: deleteAfter ? const Color(0xFFFFEBEB) : _DS.primaryLight,
                              valueColor: AlwaysStoppedAnimation(deleteAfter ? Colors.red : _DS.primary),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: deleteAfter ? Colors.red : _DS.primary,
                            ),
                          ),
                        ],
                        if (deleteAfter && !started) ...[
                          const SizedBox(height: 14),
                          _buildWarningBanner(
                              AppTranslations.of(ctx).text(isV2 ? 'close_org_v2_notice' : 'warning_cannot_undo'),
                              isV2 ? Colors.orange : Colors.red),
                        ],
                        if (needsName && !started) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: confirmCtrl,
                            maxLength: 120,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: AppTranslations.of(ctx).text('type_name_to_confirm'),
                              hintText: sourceOrg.name,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.edit),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Outside the scroll area so the result is always visible.
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: statusIsError ? Colors.red.withValues(alpha: 0.07) : _DS.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusIsError
                            ? Colors.red.withValues(alpha: 0.35) : Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Text(status!,
                          style: TextStyle(fontSize: 13,
                              color: statusIsError ? Colors.red[700] : _DS.textSecondary,
                              fontWeight: statusIsError ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  ),
                if (!started) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(AppTranslations.of(ctx).text('cancel'),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: loading || targetCtrl.text.trim().isEmpty ? null : () async {
                          setDialogState(() { status = null; statusIsError = false; });
                          final id = targetCtrl.text.trim();
                          if (id.isEmpty) {
                            setDialogState(() {
                                statusIsError = true;
                                status = AppTranslations.of(ctx).text('please_enter_target_id');
                              });
                            return;
                          }
                          setDialogState(() {
                            loading = true;
                            statusIsError = false;
                            status = AppTranslations.of(ctx).text('fetching_preview');
                          });
                          try {
                            final result = isV2
                                ? await _organizationSettings.copyPreview(sourceOrg.id, id)
                                : await _organizationService.getMigrationPreview(sourceOrg.id);
                            setDialogState(() {
                              preview = result;
                              statusIsError = false;
                              status = AppTranslations.of(ctx).text('fetched_preview');
                            });
                          } catch (e) {
                            logger.e('Organization copy preview failed', error: e);
                            setDialogState(() {
                              statusIsError = true;
                              status = isV2
                                  ? AppTranslations.of(ctx).text(_copyErrorKey(e))
                                  : AppTranslations.of(ctx).textWithParams('preview_error', {'error': e});
                            });
                          }
                          setDialogState(() => loading = false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _DS.primary,
                          side: BorderSide(color: _DS.primary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppTranslations.of(ctx).text('preview'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          // Needs the target ID, and for copy & delete also the exact source name.
                          onPressed: loading || targetCtrl.text.trim().isEmpty ||
                                  (needsName && confirmCtrl.text.trim() != sourceOrg.name)
                              ? null : () async {
                            final targetId = targetCtrl.text.trim();
                            if (targetId.isEmpty) {
                              setDialogState(() {
                                  statusIsError = true;
                                  status = AppTranslations.of(ctx).text('please_enter_target_id');
                                });
                              return;
                            }
                            setDialogState(() {
                              loading  = true;
                              started  = true;
                              statusIsError = false;
                              status   = deleteAfter
                                  ? AppTranslations.of(ctx).text('migrating_and_deleting')
                                  : AppTranslations.of(ctx).text('migrating_data');
                              progress = 0.0;
                            });
                            // Capture before async
                            final dialogNav = Navigator.of(ctx);
                            bool success = false;
                            String? failKey;
                            try {
                              if (isV2) {
                                if (copyTarget != targetId) {
                                  copyTarget = targetId;
                                  copyOperation = _organizationSettings.newOperation();
                                }
                                setDialogState(() => progress = 0.3);
                                await _organizationSettings.copy(
                                    sourceOrg.id, targetId, operationId: copyOperation!);
                                setDialogState(() => progress = deleteAfter ? 0.8 : 1.0);
                                // Only the owner may close; the copy above is kept either way.
                                if (deleteAfter) {
                                  await _organizationSettings.close(sourceOrg.id, confirmCtrl.text.trim());
                                }
                                success = true;
                              } else if (deleteAfter) {
                                success = await _organizationService.migrateAndDeleteOrganization(
                                  ownerId: ownerId,
                                  sourceOrgId: sourceOrg.id,
                                  targetOrgId: targetId,
                                  onProgress: (p) => setDialogState(() => progress = p),
                                  onStatusUpdate: (msg) => setDialogState(() => status = msg),
                                );
                              } else {
                                success = await _organizationService.migrateOrganization(
                                  ownerId: ownerId,
                                  sourceOrgId: sourceOrg.id,
                                  targetOrgId: targetId,
                                  onProgress: (p) => setDialogState(() => progress = p),
                                  onStatusUpdate: (msg) => setDialogState(() => status = msg),
                                );
                              }
                            } catch (e) {
                              logger.e('Organization copy failed', error: e);
                              if (isV2) failKey = _copyErrorKey(e);
                            }
                            setDialogState(() { loading = false; started = false; });
                            if (success && mounted) {
                              dialogNav.pop();
                              _showSuccessSnack(deleteAfter
                                  ? AppTranslations.of(context).text('migrated_and_deleted_success')
                                  : AppTranslations.of(context).text('migrated_data_success'));
                              _updateDashboardState(() { _entryKey = UniqueKey(); });
                            } else {
                              setDialogState(() {
                                statusIsError = true;
                                status = AppTranslations.of(ctx).text(failKey ?? 'operation_failed');
                              });
                            }
                          },
                          icon: Icon(
                            deleteAfter ? Icons.delete_sweep_rounded : Icons.compare_arrows_rounded,
                            size: 16,
                          ),
                          label: Text(
                            deleteAfter
                                ? AppTranslations.of(ctx).text('migrate_and_delete_action')
                                : AppTranslations.of(ctx).text('migrate_action'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: deleteAfter ? Colors.red : _DS.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditOrganizationDialog(Organization org, String ownerId, {bool information = false}) async {
    final nameCtrl            = TextEditingController(text: org.name);
    final addressCtrl         = TextEditingController(text: org.address ?? '');
    final phoneCtrl           = TextEditingController(text: org.phone ?? '');
    final emailCtrl           = TextEditingController(text: org.email ?? '');
    final taxCtrl             = TextEditingController(text: org.taxCode ?? '');
    final bankNameCtrl        = TextEditingController(text: org.bankName ?? '');
    final bankAccountCtrl     = TextEditingController(text: org.bankAccountNumber ?? '');
    final bankAccountNameCtrl = TextEditingController(text: org.bankAccountName ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _getDialogWidth(ctx),
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppTranslations.of(ctx).text(information ? 'org_info' : 'edit_org'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionLabel(ctx, Icons.business_rounded,
                            AppTranslations.of(ctx).text('basic_info')),
                        const SizedBox(height: 10),
                        _buildField(nameCtrl, AppTranslations.of(ctx).text('org_name_required'),
                            hint: AppTranslations.of(ctx).text('org_name_example'),
                            icon: Icons.business, maxLength: 100,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? AppTranslations.of(ctx).text('please_enter_org_name')
                                : null),
                        const SizedBox(height: 12),
                        _buildField(addressCtrl, AppTranslations.of(ctx).text('address'),
                            hint: AppTranslations.of(ctx).text('address_example'),
                            icon: Icons.location_on, maxLength: 300, maxLines: 2,
                            textCapitalization: TextCapitalization.words,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(phoneCtrl, AppTranslations.of(ctx).text('phone'),
                            hint: AppTranslations.of(ctx).text('phone_example'),
                            icon: Icons.phone, maxLength: 20,
                            keyboardType: TextInputType.phone,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(emailCtrl, AppTranslations.of(ctx).text('email'),
                            hint: AppTranslations.of(ctx).text('email_example'),
                            icon: Icons.email, maxLength: 254,
                            keyboardType: TextInputType.emailAddress,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                if (!isValidEmail(v)) return AppTranslations.of(ctx).text('email_invalid');
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildField(taxCtrl, AppTranslations.of(ctx).text('tax_code'),
                            hint: '0123456789 or 0123456789-001',
                            icon: Icons.receipt_long, maxLength: 14,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty &&
                                  !_organizationService.isValidTaxCode(v)) {
                                return AppTranslations.of(ctx)['invalid_tax_code'];
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildSectionLabel(ctx, Icons.account_balance_rounded,
                            AppTranslations.of(ctx).text('bank_info')),
                        const SizedBox(height: 10),
                        _buildField(bankNameCtrl, AppTranslations.of(ctx).text('bank_name'),
                            hint: 'Vietcombank, Techcombank...',
                            icon: Icons.account_balance, maxLength: 100,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildField(bankAccountCtrl, AppTranslations.of(ctx).text('account_number'),
                            hint: '1234567890',
                            icon: Icons.credit_card, maxLength: 20,
                            keyboardType: TextInputType.number,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice'),
                            validator: (v) {
                              if (v != null && v.isNotEmpty &&
                                  !_organizationService.isValidBankAccountNumber(v)) {
                                return AppTranslations.of(ctx).text('invalid_bank_account');
                              }
                              return null;
                            }),
                        const SizedBox(height: 12),
                        _buildField(bankAccountNameCtrl, AppTranslations.of(ctx).text('account_holder'),
                            hint: 'NGUYEN VAN A',
                            icon: Icons.person, maxLength: 100,
                            textCapitalization: TextCapitalization.characters,
                            helper: AppTranslations.of(ctx).text('optional_on_invoice')),
                        const SizedBox(height: 12),
                        _buildInfoBanner(AppTranslations.of(ctx).text('contact_info_on_invoice')),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppTranslations.of(ctx).text('cancel')),
                    ),
                    const SizedBox(width: 8),
                    StatefulBuilder(
                      builder: (ctx2, setButtonState) {
                        return FilledButton.icon(
                          onPressed: isSubmitting ? null : () async {
                            if (!formKey.currentState!.validate()) return;
                            setButtonState(() => isSubmitting = true);
                            // Capture before async
                            final dialogNav      = Navigator.of(ctx);
                            final screenMessenger = ScaffoldMessenger.of(context);
                            _showTrackedDialog(
                              context: ctx,
                              barrierDismissible: false,
                              builder: (lctx) =>
                                  _buildLoadingDialog(AppTranslations.of(lctx).text('saving')),
                            );
                            try {
                              final success = org.accessVersion == 2
                                  ? await _v2Action(() => _organizationSettings.update(org.id, {
                                      'name': nameCtrl.text,
                                      'address': addressCtrl.text,
                                      'phone': phoneCtrl.text,
                                      'email': emailCtrl.text,
                                      'taxCode': taxCtrl.text,
                                      'bankName': bankNameCtrl.text,
                                      'bankAccountNumber': bankAccountCtrl.text,
                                      'bankAccountName': bankAccountNameCtrl.text,
                                    }))
                                  : await _organizationService.updateOrganization(
                                ownerId: ownerId,
                                orgId: org.id,
                                name: nameCtrl.text.trim(),
                                address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                                email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                                taxCode: taxCtrl.text.trim().isEmpty ? null : taxCtrl.text.trim(),
                                bankName: bankNameCtrl.text.trim().isEmpty ? null : bankNameCtrl.text.trim(),
                                bankAccountNumber: bankAccountCtrl.text.trim().isEmpty
                                    ? null : bankAccountCtrl.text.trim(),
                                bankAccountName: bankAccountNameCtrl.text.trim().isEmpty
                                    ? null : bankAccountNameCtrl.text.trim(),
                              );
                              if (!mounted) return;
                              dialogNav.pop(); // pop loader
                              if (success) {
                                dialogNav.pop(); // pop edit dialog
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _showSuccessSnack(AppTranslations.of(context).text('org_updated_success'));
                                    _updateDashboardState(() { _entryKey = UniqueKey(); });
                                  }
                                });
                              } else {
                                screenMessenger.showSnackBar(SnackBar(
                                  content: Text(AppTranslations.of(context).text('update_failed')),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            } catch (e) {
                              if (mounted) {
                                dialogNav.pop(); // pop loader
                                screenMessenger.showSnackBar(SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            }
                            if (mounted) setButtonState(() => isSubmitting = false);
                          },
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(AppTranslations.of(ctx).text('save')),
                          style: FilledButton.styleFrom(backgroundColor: Colors.green[600]),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    taxCtrl.dispose();
    bankNameCtrl.dispose();
    bankAccountCtrl.dispose();
    bankAccountNameCtrl.dispose();
  }

  Widget _buildSectionLabel(BuildContext ctx, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _DS.primary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _DS.primary, letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: _DS.primary.withValues(alpha: 0.2))),
      ],
    );
  }

  void _showOrganizationOptions(Organization org, String ownerId, bool isAdmin, String role,
      {String? roleName, bool waitingMember = false}) {
    final isV2 = org.accessVersion == 2;
    // Legacy: admins cannot leave. Version 2: only the owner cannot leave.
    final canLeave = isV2 ? role != 'owner' : !isAdmin;
    // Waiting members can only leave; there is nothing else they may open yet.
    final waiting = isV2 && (waitingMember || (!TeamPolicy.isTemplate(role) && !role.startsWith('r_')));
    if (isV2 && !waiting) _prefetchV2Settings(org);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLarge = screenWidth >= 600;
    final gradient = _DS.orgGradient(org.id);

    Widget sheetHeader = Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            if (isLarge)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  padding: EdgeInsets.zero,
                ),
              ),
            if (!isLarge) ...[
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
              ),
              child: Center(
                child: Text(
                  org.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              org.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            _buildRoleBadgeLight(isAdmin,
                label: !isV2 ? null : !waiting
                    ? _v2RoleLabel(role, roleName)
                    : AppTranslations.of(context).text('team_waiting_role')),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );

    List<Widget> menuItems = [
      if (!waiting) ...[
      _buildOptionTile(
        icon: Icons.open_in_new_rounded,
        iconColor: _DS.primary,
        title: AppTranslations.of(context).text('open_org'),
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, AppRouter.oranizationScreen,
              arguments: {'organization': org});
        },
      ),
      _buildOptionTile(
        icon: Icons.info_outline_rounded,
        iconColor: AppThemePalette.primary,
        title: AppTranslations.of(context).text('view_org_info'),
        subtitle: AppTranslations.of(context).text('org_details_and_id'),
        onTap: () {
          Navigator.pop(context);
          if (isV2) {
            _openV2Settings(org, (s) => _showOrganizationInfo(s.organization));
          } else {
            _showOrganizationInfo(org);
          }
        },
      ),
      ],
      if (isAdmin) ...[
        _buildOptionTile(
          icon: Icons.edit_rounded,
          iconColor: Colors.green[600]!,
          title: AppTranslations.of(context).text('edit_org'),
          subtitle: AppTranslations.of(context).text('edit_org_details'),
          onTap: () {
            Navigator.pop(context);
            if (isV2) {
              _openV2Settings(org, (s) => _showEditOrganizationDialog(s.organization, ownerId));
            } else {
              _showEditOrganizationDialog(org, ownerId);
            }
          },
        ),
        // Version 2 copies on the server; closing the source needs the owner.
        _buildOptionTile(
          icon: Icons.compare_arrows_rounded,
          iconColor: AppThemePalette.primary,
          title: AppTranslations.of(context).text('migrate_to_other_org'),
          subtitle: AppTranslations.of(context).text('copy_all_data'),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, false);
          },
        ),
        if (!isV2 || role == 'owner')
        _buildOptionTile(
          icon: Icons.delete_sweep_rounded,
          iconColor: Colors.red[600]!,
          title: AppTranslations.of(context).text('migrate_and_delete_org'),
          subtitle: AppTranslations.of(context).text('transfer_and_delete'),
          onTap: () {
            Navigator.pop(context);
            _showMigrateOrganizationDialog(org, ownerId, true);
          },
        ),
        if (!isV2 || role == 'owner')
        _buildOptionTile(
          icon: Icons.delete_forever_rounded,
          iconColor: Colors.red[700]!,
          title: AppTranslations.of(context).text('delete_org_action'),
          subtitle: AppTranslations.of(context).text('delete_org_permanently'),
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _showDeleteOrganizationDialog(org, ownerId);
          },
        ),
      ],
      if (canLeave) ...[
        _buildOptionTile(
          icon: Icons.exit_to_app_rounded,
          iconColor: Colors.orange[700]!,
          title: AppTranslations.of(context).text('leave_org_action'),
          subtitle: AppTranslations.of(context).text('will_lose_access'),
          onTap: () {
            Navigator.pop(context);
            _showLeaveOrganizationDialog(org, ownerId);
          },
        ),
      ],
      const SizedBox(height: 8),
    ];

    if (isLarge) {
      _showTrackedDialog(
        context: context,
        builder: (ctx) => AppDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 420,
            child: SafeArea(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    sheetHeader,
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: menuItems),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      _showTrackedBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              sheetHeader,
              Flexible(
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: menuItems),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Version-2 organization helpers ──────────────────────────
  /// True when a version-2 membership has no supported role yet: status
  /// assignmentRequired, or a role that no longer exists (e.g. viewer).
  bool _isWaitingMember(Membership? m) =>
      m != null &&
      (m.status == 'assignmentRequired' ||
          (m.status == 'active' && !TeamPolicy.isTemplate(m.role) && !m.hasRoleGrants));

  void _showWaitingForRole(Organization org) {
    _showTrackedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_rounded),
        title: Text(org.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Text(AppTranslations.of(ctx).text('org_waiting_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.of(ctx).text('close')),
          ),
        ],
      ),
    );
  }

  /// Organizations this account closed in the last 30 days, with Restore.
  Future<void> _showRecentlyDeletedDialog() => _dialogLock.run(() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final t = AppTranslations.of(context);
    final ownerId = FirebaseAuth.instance.currentUser?.uid;
    if (ownerId == null) return;
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildLoadingDialog(t.text('loading')),
    );
    List<ClosedOrganization>? items;
    try {
      items = await _organizationSettings.closedList();
    } catch (e) {
      logger.e('Could not load closed organizations', error: e);
    }
    if (!mounted) return;
    nav.pop();
    if (items == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.text('org_settings_load_failed')), backgroundColor: Colors.red));
      return;
    }
    final list = items;
    String? restoring; // one restore at a time
    await _showTrackedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx), maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(children: [
                  Icon(Icons.restore_from_trash_rounded, color: _DS.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.text('recently_deleted_orgs'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _DS.textPrimary))),
                  IconButton(
                    tooltip: t.text('close'),
                    onPressed: restoring == null ? () => Navigator.pop(ctx) : null,
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t.text('recently_deleted_empty'), textAlign: TextAlign.center,
                            style: const TextStyle(color: _DS.textSecondary)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final org = list[i];
                          return ListTile(
                            leading: const Icon(Icons.apartment_outlined),
                            title: Text(org.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(t.textWithParams('restore_days_left',
                                {'days': org.daysLeft(DateTime.now().toUtc())})),
                            trailing: restoring == org.id
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : FilledButton(
                                    onPressed: restoring != null ? null : () async {
                                      setDialogState(() => restoring = org.id);
                                      final ok = await _v2Action(() => _organizationSettings.restore(org.id));
                                      if (!ctx.mounted) return;
                                      setDialogState(() {
                                        restoring = null;
                                        if (ok) list.removeAt(i);
                                      });
                                      messenger.showSnackBar(SnackBar(
                                        content: Text(t.text(ok ? 'org_restored_success' : 'org_restore_failed')),
                                        backgroundColor: ok ? Colors.green : Colors.red,
                                      ));
                                      if (ok) _updateDashboardState(() { _entryKey = UniqueKey(); });
                                    },
                                    child: Text(t.text('restore_action')),
                                  ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  });

  /// Friendly message for a failed v2 copy. Checks both the server reason and
  /// the error code, since platforms report callable errors slightly differently.
  String _copyErrorKey(Object e) {
    final code = e is FirebaseFunctionsException ? e.code : '';
    final text = e is FirebaseFunctionsException ? '${e.message} ${e.details}' : '$e';
    if (text.contains('org_copy_cross_link')) return 'org_copy_cross_link';
    if (const ['org_copy_access_required', 'team_migration_required', 'org_copy_target', 'org_closed']
            .any(text.contains) ||
        const {'permission-denied', 'failed-precondition', 'not-found', 'invalid-argument'}.contains(code)) {
      return 'org_copy_target_not_allowed';
    }
    if (const {'unavailable', 'deadline-exceeded', 'internal'}.contains(code)) return 'org_copy_try_again';
    return 'operation_failed';
  }

  String _v2RoleLabel(String role, [String? roleName]) {
    final t = AppTranslations.of(context);
    if (roleName != null && roleName.trim().isNotEmpty) return roleName.trim();
    final key = 'team_role_$role';
    return t.translationKeys.contains(key) ? t[key] : t['team_role_custom'];
  }

  /// Runs a server action; false on any failure so dialogs show their error.
  Future<bool> _v2Action(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      logger.e('Organization settings request failed', error: e);
      return false;
    }
  }

  void _prefetchV2Settings(Organization org) {
    final pending = _organizationSettings.read(org.id);
    pending.ignore(); // errors are reported when the result is actually used
    _v2SettingsPrefetch[org.id] = pending;
  }

  /// The dashboard list omits private details, so load them with the
  /// caller's current permissions before opening info or edit. Uses the
  /// request started when the menu opened, shows a loader while waiting, and
  /// ignores further taps until this one finishes.
  Future<void> _openV2Settings(
      Organization org, FutureOr<void> Function(OrganizationSettings settings) open) {
    return _dialogLock.run(() async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      final t = AppTranslations.of(context);
      // Taken once: the next open fetches fresh data (e.g. after an edit).
      final pending = _v2SettingsPrefetch.remove(org.id) ?? _organizationSettings.read(org.id);
      // Only show the loader if the data is not already there (no flash).
      var done = false, loaderShown = false;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (done || !mounted) return;
        loaderShown = true;
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _buildLoadingDialog(t.text('loading')),
        );
      });
      OrganizationSettings? settings;
      try {
        settings = await pending;
      } catch (e) {
        logger.e('Could not load organization settings', error: e);
      }
      done = true;
      if (!mounted) return;
      if (loaderShown) nav.pop();
      if (settings == null) {
        messenger.showSnackBar(SnackBar(
            content: Text(t.text('org_settings_load_failed')), backgroundColor: Colors.red));
        return;
      }
      await open(settings);
    });
  }

  Widget _buildRoleBadgeLight(bool isAdmin, {String? label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isAdmin ? Icons.star_rounded : Icons.person_rounded,
          size: 12, color: Colors.white,
        ),
        const SizedBox(width: 4),
        Text(
          label ??
              (isAdmin
                  ? AppTranslations.of(context).text('admin')
                  : AppTranslations.of(context).text('member')),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ]),
    );
  }

}
