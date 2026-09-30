part of 'dashboard_screen.dart';

// Settings > Personal information: name, phone, sign-in email and password.
// Name/phone go through the server (myProfile) so every organization's member
// list shows the new name. Email and password changes are Firebase sign-in
// changes and always ask for the current password first.
extension _DashboardProfileDialogs on _DashboardScreenState {
  /// Opens the personal information dialog. The lock stops double taps from
  /// opening it twice while the profile loads.
  Future<void> _showPersonalInfoDialog() async {
    if (_profileLock.isLocked) return;
    await _profileLock.run(() async {
      final nav = Navigator.of(context, rootNavigator: true);
      final loadingText = AppTranslations.of(context).text('loading');
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AppDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: _DS.primary)),
                const SizedBox(height: 16),
                Text(loadingText, style: const TextStyle(fontWeight: FontWeight.w600, color: _DS.textPrimary)),
              ]),
            ),
          ),
        ),
      );
      Owner? owner;
      try {
        owner = await _authService.getCurrentOwner();
      } catch (e) {
        logger.e('Loading the profile failed', error: e);
      } finally {
        if (nav.mounted) nav.pop();
      }
      if (!mounted) return;
      if (owner == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppTranslations.of(context).text('profile_load_failed')),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final saved = await _showTrackedDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PersonalInfoDialog(
          owner: owner!,
          authService: _authService,
          maxWidth: _getDialogWidth(context),
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppTranslations.of(context).text('profile_saved')),
          backgroundColor: Colors.green,
        ));
      }
    });
  }

  /// After a confirmed email change the sign-in email differs from the
  /// profile; copy it to the profile and memberships. Quiet and repeatable.
  void _syncEmailIfChanged(Owner owner) {
    final authEmail = _authService.currentUser?.email?.trim().toLowerCase();
    if (authEmail == null || authEmail.isEmpty || authEmail == owner.email.trim().toLowerCase()) return;
    ProfileService().syncEmail().catchError((Object e) {
      logger.w('Email sync failed; will retry on next start', error: e);
    });
  }
}

/// Shared look for the profile dialogs.
InputDecoration _profileField(String label, {String? helper, String? error, Widget? suffix}) => InputDecoration(
      labelText: label,
      helperText: helper,
      errorText: error,
      errorMaxLines: 3,
      helperMaxLines: 3,
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

Widget _profileHeader(BuildContext context, IconData icon, String title) => Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_DS.primaryMid, _DS.primaryDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ),
      ]),
    );

Widget _profileButtons({
  required BuildContext context,
  required String primaryLabel,
  required VoidCallback? onPrimary,
  required bool busy,
  VoidCallback? onCancel,
}) {
  final t = AppTranslations.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    child: Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: busy ? null : (onCancel ?? () => Navigator.pop(context)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _DS.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(t.text('cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton(
          onPressed: busy ? null : onPrimary,
          style: FilledButton.styleFrom(
            backgroundColor: _DS.primary,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(primaryLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );
}

/// Friendly message key for a failed Firebase sign-in change.
String _authChangeErrorKey(Object e) {
  final code = e is FirebaseAuthException ? e.code : '';
  switch (code) {
    case 'wrong-password':
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'incorrect_password';
    case 'email-already-in-use':
      return 'profile_email_in_use';
    case 'invalid-email':
    case 'invalid-new-email':
      return 'profile_email_invalid';
    case 'weak-password':
      return 'auth_password_too_weak';
    case 'too-many-requests':
      return 'profile_too_many_attempts';
    case 'network-request-failed':
      return 'profile_network_error';
    default:
      return 'profile_save_failed';
  }
}

Widget _profileError(String? text) => text == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
      );

class _PersonalInfoDialog extends StatefulWidget {
  const _PersonalInfoDialog({required this.owner, required this.authService, required this.maxWidth});
  final Owner owner;
  final AuthService authService;
  final double maxWidth;

  @override
  State<_PersonalInfoDialog> createState() => _PersonalInfoDialogState();
}

class _PersonalInfoDialogState extends State<_PersonalInfoDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.owner.name);
  late final TextEditingController _phone = TextEditingController(text: widget.owner.phone ?? '');
  final ProfileService _service = ProfileService();
  bool _saving = false;
  String? _error;
  String? _nameError;
  String? _phoneError;

  // The sign-in email is the source of truth; the profile copy may lag
  // until the next start after a confirmed change.
  String get _email => widget.authService.currentUser?.email ?? widget.owner.email;

  bool get _changed =>
      ProfileService.cleanName(_name.text) != widget.owner.name.trim() ||
      _phone.text.trim() != (widget.owner.phone ?? '').trim();

  bool get _valid => ProfileService.isValidName(_name.text) && ProfileService.isValidPhone(_phone.text);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_changed || !_valid) return;
    setState(() {
      _saving = true;
      _error = _nameError = _phoneError = null;
    });
    final t = AppTranslations.of(context);
    try {
      final saved = await _service.update(name: _name.text, phone: _phone.text);
      await widget.authService.setAuthDisplayName(saved.name);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      logger.e('Saving the profile failed', error: e);
      if (!mounted) return;
      final text = e is FirebaseFunctionsException ? '${e.message} ${e.details}' : '$e';
      setState(() {
        _saving = false;
        if (text.contains('profile_name_invalid')) {
          _nameError = t.text('profile_name_invalid');
        } else if (text.contains('profile_phone_invalid')) {
          _phoneError = t.text('profile_phone_invalid');
        } else {
          _error = t.text('profile_save_failed');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final nameInvalid = !ProfileService.isValidName(_name.text);
    final phoneInvalid = !ProfileService.isValidPhone(_phone.text);
    return PopScope(
      canPop: !_saving,
      child: AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _profileHeader(context, Icons.person_outline_rounded, t.text('personal_info')),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: ProfileService.nameMaxLength,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _profileField(t.text('profile_name'),
                        helper: t.text('profile_name_helper'),
                        error: _nameError ?? (nameInvalid ? t.text('profile_name_invalid') : null)),
                    onChanged: (_) => setState(() => _nameError = null),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    enabled: !_saving,
                    maxLength: ProfileService.phoneMaxLength,
                    keyboardType: TextInputType.phone,
                    decoration: _profileField(t.text('phone'),
                        helper: t.text('profile_phone_helper'),
                        error: _phoneError ?? (phoneInvalid ? t.text('profile_phone_invalid') : null)),
                    onChanged: (_) => setState(() => _phoneError = null),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  _AccountRow(
                    icon: Icons.alternate_email_rounded,
                    label: t.text('email'),
                    value: _email,
                    action: t.text('profile_change'),
                    onTap: _saving
                        ? null
                        : () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _ChangeEmailDialog(
                                currentEmail: _email,
                                authService: widget.authService,
                                maxWidth: widget.maxWidth,
                              ),
                            ),
                  ),
                  const SizedBox(height: 8),
                  _AccountRow(
                    icon: Icons.lock_outline_rounded,
                    label: t.text('password_hint'),
                    value: '••••••••',
                    action: t.text('profile_change'),
                    onTap: _saving
                        ? null
                        : () async {
                            final changed = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _ChangePasswordDialog(
                                authService: widget.authService,
                                maxWidth: widget.maxWidth,
                              ),
                            );
                            if (changed == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(t.text('profile_password_changed')),
                                backgroundColor: Colors.green,
                              ));
                            }
                          },
                  ),
                ]),
              ),
            ),
            _profileError(_error),
            _profileButtons(
              context: context,
              primaryLabel: t.text('save'),
              busy: _saving,
              onPrimary: _changed && _valid ? _save : null,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Read-only account value with a "Change" action (email, password).
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.label, required this.value, required this.action, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: _DS.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _DS.textSecondary)),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _DS.textPrimary)),
          ]),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ]),
    );
  }
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({required this.currentEmail, required this.authService, required this.maxWidth});
  final String currentEmail;
  final AuthService authService;
  final double maxWidth;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _sentTo;

  bool get _sameAsNow => _email.text.trim().toLowerCase() == widget.currentEmail.trim().toLowerCase();
  bool get _ready => isValidEmail(_email.text) && !_sameAsNow && _password.text.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppTranslations.of(context);
    try {
      await widget.authService.requestEmailChange(password: _password.text, newEmail: _email.text);
      if (mounted) setState(() => _sentTo = _email.text.trim());
    } catch (e) {
      logger.e('Email change failed', error: e);
      if (mounted) setState(() => _error = t.text(_authChangeErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final typed = _email.text.trim();
    final emailError = typed.isEmpty
        ? null
        : !isValidEmail(typed)
            ? t.text('profile_email_invalid')
            : _sameAsNow
                ? t.text('profile_email_same')
                : null;
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _profileHeader(context, Icons.alternate_email_rounded, t.text('profile_change_email')),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: _sentTo != null
                    ? Text(
                        t.textWithParams('profile_email_link_sent', {'email': _sentTo, 'current': widget.currentEmail}),
                        style: const TextStyle(fontSize: 14, color: _DS.textPrimary, height: 1.5),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(t.textWithParams('profile_change_email_intro', {'email': widget.currentEmail}),
                            style: const TextStyle(fontSize: 13, color: _DS.textSecondary, height: 1.4)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _email,
                          enabled: !_busy,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: _profileField(t.text('profile_new_email'), error: emailError),
                          onChanged: (_) => setState(() => _error = null),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: !_showPassword,
                          decoration: _profileField(
                            t.text('profile_current_password'),
                            suffix: IconButton(
                              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          onChanged: (_) => setState(() => _error = null),
                          onSubmitted: (_) => _submit(),
                        ),
                      ]),
              ),
            ),
            _profileError(_error),
            _sentTo != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _DS.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(t.text('close')),
                      ),
                    ),
                  )
                : _profileButtons(
                    context: context,
                    primaryLabel: t.text('profile_send_link'),
                    busy: _busy,
                    onPrimary: _ready ? _submit : null,
                  ),
          ]),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.authService, required this.maxWidth});
  final AuthService authService;
  final double maxWidth;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;
  String? _resetSentTo;

  static const minLength = 6; // same as registration
  static const maxLength = 128;

  /// For a forgotten current password: email a reset link to the sign-in email.
  Future<void> _sendResetLink() async {
    final email = widget.authService.currentUser?.email;
    if (_busy || _resetSentTo != null || email == null) return;
    final t = AppTranslations.of(context);
    final lang = t.locale.languageCode;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.sendPasswordReset(email, languageCode: lang);
      if (mounted) setState(() => _resetSentTo = email);
    } catch (e) {
      logger.e('Password reset email failed', error: e);
      if (mounted) setState(() => _error = t.text(_authChangeErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _nextError(AppTranslations t) {
    final v = _next.text;
    if (v.isEmpty) return null;
    if (v.length < minLength) return t.text('auth_password_too_weak');
    if (v.length > maxLength) return t.text('auth_password_too_long');
    if (v == _current.text) return t.text('profile_password_same');
    return null;
  }

  String? _confirmError(AppTranslations t) =>
      _confirm.text.isEmpty || _confirm.text == _next.text ? null : t.text('profile_password_mismatch');

  bool get _ready =>
      _current.text.isNotEmpty &&
      _next.text.length >= minLength &&
      _next.text.length <= maxLength &&
      _next.text != _current.text &&
      _confirm.text == _next.text;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppTranslations.of(context);
    try {
      await widget.authService.changePassword(currentPassword: _current.text, newPassword: _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      logger.e('Password change failed', error: e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t.text(_authChangeErrorKey(e));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final toggle = IconButton(
      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      onPressed: () => setState(() => _show = !_show),
    );
    Widget field(TextEditingController c, String label, {String? error, bool last = false, bool first = false}) => TextField(
          controller: c,
          enabled: !_busy,
          autofocus: first,
          obscureText: !_show,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          decoration: _profileField(label, error: error, suffix: first ? toggle : null),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: last ? (_) => _submit() : null,
        );
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _profileHeader(context, Icons.lock_outline_rounded, t.text('profile_change_password')),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  field(_current, t.text('profile_current_password'), first: true),
                  const SizedBox(height: 12),
                  field(_next, t.text('profile_new_password'), error: _nextError(t)),
                  const SizedBox(height: 12),
                  field(_confirm, t.text('profile_confirm_password'), error: _confirmError(t), last: true),
                  const SizedBox(height: 8),
                  if (_resetSentTo == null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _sendResetLink,
                        icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                        label: Text(t.text('profile_forgot_current_password')),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Text(
                        t.textWithParams('profile_reset_link_sent', {'email': _resetSentTo}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF166534), height: 1.4),
                      ),
                    ),
                ]),
              ),
            ),
            _profileError(_error),
            _profileButtons(
              context: context,
              primaryLabel: t.text('profile_change_password'),
              busy: _busy,
              onPrimary: _ready ? _submit : null,
            ),
          ]),
        ),
      ),
    );
  }
}
