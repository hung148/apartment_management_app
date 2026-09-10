import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_agent_service.dart';
import '../utils/app_localizations.dart';
import '../widgets/app_dialog.dart';

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
      }
    } catch (_) {
      _error = 'ai_billing_unavailable';
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
    return AppAlertDialog(
      title: Text('AI Pro'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['ai_pro_allowance']),
          const SizedBox(height: 12),
          Text(t['ai_free_allowance']),
          if (_package != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${_package!.storeProduct.priceString} / ${t['ai_month']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          if (_usage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                t.textWithParams('ai_usage', {
                  'messages': _usage!['remainingMessages'],
                  'imports': _usage!['remainingImports'],
                }),
              ),
            ),
          if (_usage?['paid'] == true) Text(t['ai_pro_active']),
          Text(t['ai_subscription_terms']),
          if (!_configured) Text(t['ai_billing_setup']),
          if (_error != null)
            Text(
              t[_error!],
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
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
              if (_apple)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://apps.apple.com/account/subscriptions'),
                  ),
                  child: Text(t['ai_manage_subscription']),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t['close']),
        ),
        if (_apple)
          TextButton(
            onPressed: _busy || appleKey.isEmpty
                ? null
                : () => _action(restore: true),
            child: Text(t['ai_restore']),
          ),
        TextButton(
          onPressed: _busy ? null : () => _action(refresh: true),
          child: Text(t['refresh']),
        ),
        if (_usage?['paid'] != true)
          FilledButton(
            onPressed: _busy || !_configured || (_apple && _package == null)
                ? null
                : () => _action(),
            child: Text(t['ai_subscribe']),
          ),
      ],
    );
  }
}
