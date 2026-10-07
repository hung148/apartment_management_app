part of 'dashboard_screen.dart';

// Settings menu, language/theme preferences, app updates, and account actions.
// State and lifecycle remain owned by the dashboard screen.
extension _DashboardSettingsDialogs on _DashboardScreenState {
  // ─────────────────────────────────────────────────────────
  // SETTINGS DIALOG
  // ─────────────────────────────────────────────────────────

  void _showSettingsDialog() {
    const cornerRadius = 12.0;
    _showTrackedDialog(
      context: context,
      builder: (ctx) => AppDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_DS.primaryMid, _DS.primaryDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(cornerRadius),
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.person_outline, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    AppTranslations.of(ctx).text('account_menu'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  )),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_updateAvailable && !_checkingUpdate)
                      _buildSettingsTile(
                        icon: Icons.system_update_rounded,
                        iconBg: const Color(0xFFDCFCE7),
                        iconColor: const Color(0xFF16A34A),
                        label: AppTranslations.of(ctx).text('update'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _performUpdate();
                        },
                      ),
                    _buildSettingsTile(
                      icon: Icons.person_outline_rounded,
                      iconBg: _DS.primaryLight,
                      iconColor: _DS.primary,
                      label: AppTranslations.of(ctx).text('personal_info'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showPersonalInfoDialog();
                      },
                    ),
                    if (_accountOrganization != null && _accountIsOwner)
                      _buildSettingsTile(
                        icon: Icons.business_outlined,
                        iconBg: _DS.primaryLight,
                        iconColor: _DS.primary,
                        label: AppTranslations.of(ctx).text('org_info'),
                        onTap: () {
                          final organization = _accountOrganization!;
                          Navigator.pop(ctx);
                          if (organization.accessVersion == 2) {
                            _showSingleOrganizationActions(organization);
                          } else {
                            _showEditOrganizationDialog(organization, _authService.currentUser!.uid, information: true);
                          }
                        },
                      ),
                    if (_accountOrganization?.accessVersion == 2)
                      AccountWorkspaceButtons(
                        organizationId: _accountOrganization!.id,
                        service: getIt<TeamService>(),
                        tile: (option, onTap) => _buildSettingsTile(
                          icon: option.icon, iconBg: _DS.primaryLight,
                          iconColor: _DS.primary, label: option.label(ctx), onTap: onTap),
                        onOpen: (option) async {
                          final org = _accountOrganization!;
                          Navigator.pop(ctx);
                          var changed = false;
                          var closed = false;
                          await showAccountWorkspaceDialog(context, option: option,
                            organizationId: org.id, service: getIt<TeamService>(),
                            onChanged: () {
                              changed = true;
                              if (closed && mounted) setState(() => _entryKey = UniqueKey());
                            });
                          closed = true;
                          if (changed && mounted) setState(() => _entryKey = UniqueKey());
                        },
                      ),
                    _buildSettingsTile(
                      icon: Icons.language_rounded,
                      iconBg: _DS.primaryLight,
                      iconColor: _DS.primary,
                      label: AppTranslations.of(ctx).text('lang'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showLanguageDialog();
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.palette_outlined,
                      iconBg: _DS.primaryLight,
                      iconColor: _DS.primary,
                      label: AppTranslations.of(ctx).text('theme_color'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showThemeColorDialog();
                      },
                    ),
                    if (_accountOrganization?.accessVersion == 2) _buildSettingsTile(
                      icon: Icons.history,
                      iconBg: _DS.primaryLight,iconColor: _DS.primary,
                      label: AppTranslations.of(ctx).text('record_recovery_title'),
                      onTap: () async {
                        final org=_accountOrganization!;Navigator.pop(ctx);
                        final changed=await showDialog<bool>(context:context,barrierDismissible:false,builder:(_)=>DeletedRecordsDialog(
                          organizationId:org.id,canRecoverOrganization:_accountIsOwner,transport:(name,data)async{
                            final r=await appCallable(name).call(data);return Map<String,dynamic>.from(r.data as Map);
                          }));
                        if(changed==true&&mounted)setState(()=>_entryKey=UniqueKey());
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.logout_rounded,
                      iconBg: const Color(0xFFFFEBEB),
                      iconColor: Colors.red,
                      label: AppTranslations.of(ctx).text('logout'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _handleLogout();
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.delete_forever_rounded,
                      iconBg: const Color(0xFFFFEBEB),
                      iconColor: const Color(0xFFB91C1C),
                      label: AppTranslations.of(ctx).text('delete_account'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _handleDeleteAccount();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _DS.textPrimary),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.withValues(alpha: 0.5)),
        ]),
      ),
    );
    }

  // Language and appearance

  // ── dialogs ────────────────────────────────────────────────

  void _showLanguageDialog() {
    final notifier = getIt<LocaleNotifier>();
    Locale tempLocale = notifier.locale;
    bool savingLocale = false; // a double tap must not close two screens
    _showTrackedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
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
                      colors: [_DS.primaryMid, _DS.primaryDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.language_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppTranslations.of(ctx).text('select_language'),
                      style: const TextStyle(
                        color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: RadioGroup<Locale>(
                    groupValue: tempLocale,
                    onChanged: (v) {
                      if (v != null) setDialogState(() => tempLocale = v);
                    },
                    child: Column(children: [
                      _buildLanguageTile(
                        locale: const Locale('vi', 'VN'),
                        countryCode: 'VN',
                        label: AppTranslations.of(ctx).text('vietnamese'),
                        selected: tempLocale == const Locale('vi', 'VN'),
                        onTap: () => setDialogState(() => tempLocale = const Locale('vi', 'VN')),
                      ),
                      const SizedBox(height: 8),
                      _buildLanguageTile(
                        locale: const Locale('en', 'US'),
                        countryCode: 'US',
                        label: AppTranslations.of(ctx).text('english'),
                        selected: tempLocale == const Locale('en', 'US'),
                        onTap: () => setDialogState(() => tempLocale = const Locale('en', 'US')),
                      ),
                    ]),
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
                        child: Text(AppTranslations.of(ctx).text('cancel'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: savingLocale ? null : () async {
                          setDialogState(() => savingLocale = true);
                          await notifier.setLocale(tempLocale);  // ✅ await the async call
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _DS.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(AppTranslations.of(ctx).text('confirm'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeColorDialog() {
    final notifier = getIt<AppThemeNotifier>();
    const names = ['teal', 'indigo', 'blue', 'purple', 'amber', 'rose'];

    _showTrackedDialog(
      context: context,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ListenableBuilder(
          listenable: notifier,
          builder: (ctx, _) {
            final t = AppTranslations.of(ctx);
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppThemePalette.primaryMid, AppThemePalette.primaryDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.palette_outlined, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t.text('theme_color'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.text('theme_color_description'),
                          style: const TextStyle(color: _DS.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 16,
                          children: [
                            for (var i = 0; i < AppThemeColors.presets.length; i++)
                              _buildThemeColorChoice(
                                color: AppThemeColors.presets[i],
                                label: t.text('theme_color_${names[i]}'),
                                selected: notifier.primary.toARGB32() == AppThemeColors.presets[i].toARGB32(),
                                onTap: () => notifier.setPrimary(AppThemeColors.presets[i]),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(t.text('close')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThemeColorChoice({
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 82,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? color : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: color.withValues(alpha: 0.32),
                        blurRadius: 0,
                        spreadRadius: 4,
                      ),
                  ],
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile({
    required Locale locale,
    required String countryCode,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _DS.primaryLight : _DS.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _DS.primary.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 38, height: 26,
              child: FittedBox(
                fit: BoxFit.cover,
                child: CountryFlag.fromCountryCode(countryCode),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15,
                color: selected ? _DS.primary : _DS.textPrimary,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: _DS.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
            ),
        ]),
      ),
    );
  }

  // App updates

  // ── update ─────────────────────────────────────────────────

  Future<void> _backgroundUpdateCheck() async {
    if (_isDisposed || !mounted) return;
    _updateDashboardState(() => _checkingUpdate = true);
    try {
      final available = await _updateService
          .isUpdateAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!_isDisposed && mounted) {
        _updateDashboardState(() {
          _updateAvailable = available;
          _checkingUpdate  = false;
        });
      }
    } catch (_) {
      if (!_isDisposed && mounted) {
        _updateDashboardState(() {
          _updateAvailable = false;
          _checkingUpdate  = false;
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate || _isDisposed) return;
    _updateDashboardState(() => _checkingUpdate = true);
    try {
      final available = await _updateService
          .isUpdateAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!_isDisposed && mounted) {
        _updateDashboardState(() {
          _updateAvailable = available;
          _checkingUpdate  = false;
        });
      }
    } catch (_) {
      if (!_isDisposed && mounted) {
        _updateDashboardState(() {
          _checkingUpdate  = false;
          _updateAvailable = false;
        });
      }
    }
  }

  Future<void> _performUpdate() async {
    if (!kIsWeb && Platform.isWindows) {
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
                      colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppTranslations.of(ctx).text('available_update'),
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
                      AppTranslations.of(ctx).text('new_update_ready'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoBanner(AppTranslations.of(ctx).text('click_update_button')),
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
                        child: Text(AppTranslations.of(ctx).text('later'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(AppTranslations.of(ctx).text('update'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
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
        // Capture navigator before async gap
        final nav = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final failedText = AppTranslations.of(context).text('update_failed');

        final progressNotifier = ValueNotifier<double>(0.0);
        _showTrackedDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: true),
        );
        await _updateService.performUpdate(
            onProgress: (p) => progressNotifier.value = p);
        if (mounted) {
          nav.pop();
          messenger.showSnackBar(SnackBar(
            content: Text(failedText),
            backgroundColor: Colors.red,
          ));
        }
      }
      return;
    }

    // Non-Windows path
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final successText = AppTranslations.of(context).text('update_success');
    final failedText  = AppTranslations.of(context).text('update_failed');

    final progressNotifier = ValueNotifier<double>(0.0);
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildProgressDialog(ctx, progressNotifier, isGreen: true),
    );
    final success = await _updateService.performFlexibleUpdate();
    if (mounted) {
      nav.pop();
      if (success) {
        _updateDashboardState(() => _updateAvailable = false);
        messenger.showSnackBar(SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(failedText),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// Shared progress dialog used for update and delete flows.
  Widget _buildProgressDialog(
    BuildContext ctx,
    ValueNotifier<double> progressNotifier, {
    bool isGreen = false,
    String? titleKey,
    String? subtitleKey,
  }) {
    final color = isGreen ? const Color(0xFF16A34A) : Colors.red;
    final bgColor = isGreen ? const Color(0xFFDCFCE7) : const Color(0xFFFFEBEB);
    final icon = isGreen ? Icons.download_rounded : Icons.delete_forever_rounded;

    return AppDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (ctx2, progress, _) {
              final isDone = progress >= 1.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                    child: Icon(
                      isDone ? Icons.check_rounded : icon,
                      color: color, size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isDone
                        ? AppTranslations.of(ctx2).text('installing')
                        : AppTranslations.of(ctx2).text(titleKey ?? 'downloading_update'),
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _DS.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isDone
                        ? AppTranslations.of(ctx2).text('please_dont_close')
                        : AppTranslations.of(ctx2).text(subtitleKey ?? 'connecting'),
                    style: const TextStyle(fontSize: 13, color: _DS.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress <= 0 || progress >= 1.0 ? null : progress,
                      minHeight: 8,
                      backgroundColor: bgColor,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  if (progress > 0 && progress < 1.0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: color,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Account actions

  Future<void> _handleLogout() async {
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
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.logout_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppTranslations.of(ctx).text('confirm_logout'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  AppTranslations.of(ctx).text('confirm_logout_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5),
                ),
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
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: Text(AppTranslations.of(ctx).text('logout_action'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
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
      _logoutLock.run(() async {
        if (mounted) {
          _updateDashboardState(() {
            _ownerFuture = null;
            _orgsFuture  = null;
            _membershipFutures.clear();
          });
        }
        await _authService.signOut();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, AppRouter.loginScreen, (_) => false);
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // DELETE ACCOUNT
  // ─────────────────────────────────────────────────────────

  /// Account deletion, carried out by the server (deleteMyAccount):
  /// 1. preview what happens to each organization;
  /// 2. owners choose per organization (hand over to an administrator, or close);
  /// 3. a recent sign-in is required (password asked when needed);
  /// 4. the server deletes/hands over; the app deletes the login last.
  /// The lock keeps double taps from starting two runs.
  Future<void> _handleDeleteAccount() async {
    if (_deleteAccountLock.isLocked) return;
    await _deleteAccountLock.run(_runAccountDeletion);
  }

  Future<void> _runAccountDeletion() async {
    final service = AccountDeletionService();
    // A changed situation (an administrator lost the role, a new member...)
    // sends the user back to a fresh preview; never more than a few times.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      final preview = await _withDeletionLoader(() => service.preview());
      if (!mounted) return;
      if (preview == null) {
        _deletionSnack('account_deletion_failed');
        return;
      }
      final decisions = await _showDeletionPlanDialog(preview);
      if (decisions == null || !mounted) return;

      if (!preview.recentLogin && !await _confirmPasswordForDeletion()) return;

      final operationId = const Uuid().v4();
      var reauthTried = false;
      while (true) {
        Object? error;
        final result = await _withDeletionLoader(
          () => service.delete(decisions, operationId: operationId),
          onError: (e) => error = e,
        );
        if (!mounted) return;
        if (result != null && result['status'] == 'dataDeleted') {
          await _finishAccountDeletion();
          return;
        }
        final reason = _deletionErrorReason(error);
        if (reason == 'recent_login_required' && !reauthTried) {
          reauthTried = true;
          if (!await _confirmPasswordForDeletion()) return;
          continue;
        }
        if (reason == 'account_deletion_plan_changed' || reason == 'account_deletion_decision_required') {
          _deletionSnack('account_delete_plan_changed');
          break; // back to a fresh preview
        }
        _deletionSnack(reason == 'recent_login_required' ? 'incorrect_password' : 'account_deletion_failed');
        return;
      }
    }
  }

  /// The server has removed the data; now remove the login itself.
  Future<void> _finishAccountDeletion() async {
    var deleted = false;
    try {
      await _authService.deleteSignIn();
      deleted = true;
    } on ReauthenticationRequiredException {
      if (mounted && await _confirmPasswordForDeletion()) {
        try {
          await _authService.deleteSignIn();
          deleted = true;
        } catch (e) {
          logger.e('Deleting the sign-in failed after reauthentication', error: e);
        }
      }
    } catch (e) {
      logger.e('Deleting the sign-in failed', error: e);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final message = AppTranslations.of(context)
        .text(deleted ? 'account_deleted_success' : 'account_delete_login_left');
    if (!deleted) {
      // Data is gone; signing out avoids a half-empty dashboard. Signing in
      // again and deleting again finishes the job (the server run is repeatable).
      await _authService.signOut();
    }
    if (mounted) {
      _updateDashboardState(() {
        _ownerFuture = null;
        _orgsFuture = null;
        _membershipFutures.clear();
      });
    }
    nav.pushNamedAndRemoveUntil(AppRouter.loginScreen, (_) => false);
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: deleted ? Colors.green : Colors.orange.shade800,
      duration: Duration(seconds: deleted ? 4 : 8),
    ));
  }

  /// Asks for the password, signs in again and refreshes the token so the
  /// server sees the new sign-in time. False when cancelled or wrong.
  Future<bool> _confirmPasswordForDeletion() async {
    final password = await _promptPasswordForReauth();
    if (password == null || password.isEmpty || !mounted) return false;
    final ok = await _withDeletionLoader(() async {
      if (!await _authService.reauthenticateWithPassword(password)) return false;
      await _authService.refreshIdToken();
      return true;
    });
    if (ok != true) {
      if (mounted) _deletionSnack('incorrect_password');
      return false;
    }
    return true;
  }

  /// Runs [action] behind a blocking loader. Returns null on failure.
  Future<T?> _withDeletionLoader<T>(Future<T> Function() action, {void Function(Object e)? onError}) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final text = AppTranslations.of(context).text('loading');
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AppDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFB91C1C)),
              ),
              const SizedBox(height: 16),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _DS.textPrimary)),
            ]),
          ),
        ),
      ),
    );
    try {
      return await action();
    } catch (e) {
      logger.e('Account deletion step failed', error: e);
      onError?.call(e);
      return null;
    } finally {
      if (nav.mounted) nav.pop();
    }
  }

  String _deletionErrorReason(Object? e) {
    final text = e is FirebaseFunctionsException ? '${e.message} ${e.details}' : '$e';
    for (final key in const ['recent_login_required', 'account_deletion_plan_changed', 'account_deletion_decision_required']) {
      if (text.contains(key)) return key;
    }
    return 'failed';
  }

  void _deletionSnack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppTranslations.of(context).text(key)),
      backgroundColor: Colors.red,
    ));
  }

  /// Shows what happens to each organization and collects the owner's
  /// choices. Returns organizationId -> null (close) or userId (hand over),
  /// or null when cancelled.
  Future<Map<String, String?>?> _showDeletionPlanDialog(DeletionPreview preview) {
    const closeChoice = '';
    final choices = <String, String>{};
    final decide = preview.organizations.where((o) => o.plan == 'decide').toList();

    return _showTrackedDialog<Map<String, String?>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final t = AppTranslations.of(ctx);
        final ready = decide.every((o) => choices.containsKey(o.organizationId));

        Widget option({required bool selected, required String label, String? hint, required VoidCallback onTap}) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    size: 20, color: selected ? const Color(0xFFB91C1C) : _DS.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: _DS.textPrimary)),
                    if (hint != null)
                      Text(hint, style: const TextStyle(fontSize: 12, color: _DS.textSecondary, height: 1.3)),
                  ]),
                ),
              ]),
            ),
          );
        }

        String closeText(DeletionPlanItem o) => o.otherMembers > 0
            ? t.textWithParams('account_delete_plan_close_members', {'count': o.otherMembers})
            : t.text('account_delete_plan_close');

        Widget orgCard(DeletionPlanItem o) {
          final icon = o.plan == 'decide'
              ? Icons.swap_horiz_rounded
              : o.plan == 'close'
                  ? Icons.block_rounded
                  : Icons.logout_rounded;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: o.plan == 'leave' ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: o.plan == 'leave' ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 18, color: o.plan == 'leave' ? _DS.textSecondary : const Color(0xFFB91C1C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(o.name.isEmpty ? o.organizationId : o.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _DS.textPrimary)),
                ),
              ]),
              const SizedBox(height: 6),
              if (o.plan == 'leave')
                Text(t.text('account_delete_plan_leave'),
                    style: const TextStyle(fontSize: 13, color: _DS.textSecondary, height: 1.4)),
              if (o.plan == 'close')
                Text(closeText(o), style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), height: 1.4)),
              if (o.plan == 'decide') ...[
                Text(t.text('account_delete_plan_decide'),
                    style: const TextStyle(fontSize: 13, color: _DS.textSecondary, height: 1.4)),
                const SizedBox(height: 4),
                for (final c in o.candidates)
                  option(
                    selected: choices[o.organizationId] == c.userId,
                    label: t.textWithParams('account_delete_hand_over',
                        {'name': c.name.isEmpty ? t.text('team_role_administrator') : c.name}),
                    hint: t.text('account_delete_hand_over_hint'),
                    onTap: () => setLocal(() => choices[o.organizationId] = c.userId),
                  ),
                option(
                  selected: choices[o.organizationId] == closeChoice,
                  label: t.text('account_delete_close_for_everyone'),
                  hint: closeText(o),
                  onTap: () => setLocal(() => choices[o.organizationId] = closeChoice),
                ),
              ],
            ]),
          );
        }

        return AppDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _getDialogWidth(ctx),
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(children: [
                  const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 30),
                  const SizedBox(height: 8),
                  Text(t.text('confirm_delete_account'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.text('account_delete_intro'),
                        style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.5)),
                    const SizedBox(height: 12),
                    for (final o in preview.organizations) orgCard(o),
                    Text(t.text('account_delete_personal_data'),
                        style: const TextStyle(fontSize: 13, color: _DS.textSecondary, height: 1.4)),
                  ]),
                ),
              ),
              if (!ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(t.text('account_delete_choose_first'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                ),
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
                      child: Text(t.text('cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ready
                          ? () => Navigator.pop(ctx, <String, String?>{
                                for (final o in decide)
                                  o.organizationId:
                                      choices[o.organizationId] == closeChoice ? null : choices[o.organizationId],
                              })
                          : null,
                      icon: const Icon(Icons.delete_forever_rounded, size: 16),
                      label: Text(t.text('delete_account_action'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// Prompts the user for their password inside the given dialog context,
  /// returning the entered password or null if cancelled.
  Future<String?> _promptPasswordForReauth() {
    final pwCtrl = TextEditingController();

    return _showTrackedDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _getDialogWidth(ctx)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppTranslations.of(ctx).text('delete_account_reauth_title'),
                    style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: _DS.textPrimary, letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppTranslations.of(ctx).text('delete_account_reauth_message'),
                    style: const TextStyle(fontSize: 14, color: _DS.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pwCtrl,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: AppTranslations.of(ctx).text('password_hint'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => Navigator.pop(ctx, pwCtrl.text),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          pwCtrl.dispose();
                          Navigator.pop(ctx, null);
                        },
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
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, pwCtrl.text),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB91C1C),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(AppTranslations.of(ctx).text('confirm_and_delete'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
