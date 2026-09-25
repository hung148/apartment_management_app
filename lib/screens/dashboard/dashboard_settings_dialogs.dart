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
                    child: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppTranslations.of(ctx).text('settings'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3,
                    ),
                  ),
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
                        onPressed: () async {
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
                                selected: notifier.primary.value == AppThemeColors.presets[i].value,
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
          Navigator.pushReplacementNamed(context, AppRouter.loginScreen);
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // DELETE ACCOUNT
  // ─────────────────────────────────────────────────────────

  Future<void> _handleDeleteAccount() async {
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
                    colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
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
                    child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppTranslations.of(ctx).text('confirm_delete_account'),
                    textAlign: TextAlign.center,
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
                  AppTranslations.of(ctx).text('confirm_delete_account_message'),
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
                      icon: const Icon(Icons.delete_forever_rounded, size: 16),
                      label: Text(AppTranslations.of(ctx).text('delete_account_action'),
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
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      _deleteAccountLock.run(() => _performAccountDeletion());
    }
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

  Future<void> _performAccountDeletion({String? password}) async {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final successText = AppTranslations.of(context).text('account_deleted_success');
    final failText = AppTranslations.of(context).text('account_deletion_failed');
    final incorrectPwText = AppTranslations.of(context).text('incorrect_password');

    if (password != null) {
      final reauthed = await _authService.reauthenticateWithPassword(password);
      if (!reauthed) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(incorrectPwText),
          backgroundColor: Colors.red,
        ));
        return;
      }
      if (!mounted) return;
    }

    final statusNotifier = ValueNotifier<String>(
      AppTranslations.of(context).text('deleting_account'),
    );
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFB91C1C)),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (ctx, status, _) => Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _DS.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    bool success = false;
    bool needsReauth = false;
    try {
      success = await _authService.deleteAccount(
        onStatusUpdate: (s) => statusNotifier.value = s,
      );
    } on ReauthenticationRequiredException {
      needsReauth = true;
    } catch (_) {
      success = false;
    }

    if (!mounted) return;
    nav.pop(); // close loading dialog

    if (needsReauth) {
      final enteredPassword = await _promptPasswordForReauth();
      if (enteredPassword != null && enteredPassword.isNotEmpty && mounted) {
        await _performAccountDeletion(password: enteredPassword);
      }
      return;
    }

    if (success) {
      if (mounted) {
        _updateDashboardState(() {
          _ownerFuture = null;
          _orgsFuture  = null;
          _membershipFutures.clear();
        });
      }
      nav.pushReplacementNamed(AppRouter.loginScreen);
      messenger.showSnackBar(SnackBar(
        content: Text(successText),
        backgroundColor: Colors.green,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(failText),
        backgroundColor: Colors.red,
      ));
    }
  }

}
