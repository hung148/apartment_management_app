import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/ai_agent_service.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../widgets/app_dialog.dart';

class AISubscriptionDialog extends StatefulWidget {
  const AISubscriptionDialog({super.key});
  @override
  State<AISubscriptionDialog> createState() => _AISubscriptionDialogState();
}

class _AISubscriptionDialogState extends State<AISubscriptionDialog> {
  static const appleKey = String.fromEnvironment('REVENUECAT_APPLE_PUBLIC_KEY');
  static const checkout = String.fromEnvironment('REVENUECAT_CHECKOUT_URL');
  static const privacy = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const terms = String.fromEnvironment('TERMS_URL');
  final _ai = AIAgentService();
  Map<String, dynamic>? _usage;
  Package? _package;
  bool _busy = true;
  String? _error;
  bool get _apple =>
      !kIsWeb &&
      [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  bool get _configured =>
      privacy.startsWith('https://') &&
      terms.startsWith('https://') &&
      (_apple
          ? appleKey.isNotEmpty
          : checkout.startsWith('https://pay.rev.cat/'));
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      _usage = await _ai.usage();
      if (_apple && appleKey.isNotEmpty) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        if (!await Purchases.isConfigured) {
          await Purchases.configure(
            PurchasesConfiguration(appleKey)..appUserID = uid,
          );
        } else if (await Purchases.appUserID != uid) {
          await Purchases.logIn(uid);
        }
        _package = (await Purchases.getOfferings()).current?.monthly;
        if (_package == null) _error = 'ai_product_unavailable';
      }
    } catch (_) {
      _error = 'ai_product_unavailable';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action({bool restore = false, bool refresh = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (refresh) {
        await _ai.call('aiSyncSubscription', {});
      } else if (_apple) {
        if (restore) {
          await Purchases.restorePurchases();
        } else {
          if (_package == null) return;
          await Purchases.purchase(PurchaseParams.package(_package!));
        }
        await _ai.call('aiSyncSubscription', {});
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        final uri = Uri.parse(
          checkout.replaceAll(RegExp(r'/+$'), '') +
              '/' +
              Uri.encodeComponent(uid),
        );
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
          throw StateError('checkout');
      }
      _usage = await _ai.usage();
    } catch (_) {
      _error = 'ai_billing_unavailable';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final theme = Theme.of(context);
    final paid = _usage?['paid'] == true;
    return AppDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Pro',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t['close'],
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F6F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD7E6E1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_package != null) ...[
                          Text(
                            '${_package!.storeProduct.priceString} / ${t['ai_month']}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          t['ai_pro_allowance'],
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                          ),
                        ),
                        if (paid) ...[
                          const SizedBox(height: 12),
                          Text(
                            t['ai_pro_active'],
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t['ai_free_allowance'],
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (_usage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.textWithParams('ai_usage', {
                        'messages': _usage!['remainingMessages'],
                        'imports': _usage!['remainingImports'],
                      }),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                  const Divider(),
                  if (!_configured || _error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t[!_configured ? 'ai_billing_setup' : _error!],
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  Text(
                    t['ai_subscription_terms'],
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (privacy.startsWith('https://'))
                        TextButton(
                          onPressed: () => launchUrl(Uri.parse(privacy)),
                          child: Text(t['ai_privacy']),
                        ),
                      if (terms.startsWith('https://'))
                        TextButton(
                          onPressed: () => launchUrl(Uri.parse(terms)),
                          child: Text(t['ai_terms']),
                        ),
                      if (_apple && paid)
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://apps.apple.com/account/subscriptions',
                            ),
                          ),
                          child: Text(t['ai_manage_subscription']),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (!paid)
                  FilledButton(
                    onPressed:
                        _busy || !_configured || (_apple && _package == null)
                        ? null
                        : () => _action(),
                    child: Text(t['ai_subscribe']),
                  ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (_apple)
                      TextButton(
                        onPressed: _busy || appleKey.isEmpty
                            ? null
                            : () => _action(restore: true),
                        child: Text(t['ai_restore']),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: Text(t['refresh']),
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

