import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lang.dart';
import 'theme.dart';
import 'widgets.dart';

const appVersion = '0.1.5';
const _github = 'https://github.com/LocksmithV';
const _web = 'https://l0cksm1thv.duckdns.org';

/// Who made it, where to find more, the licence, and what the app is not for.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(BuildContext context, String uri) async {
    final ok = await const MethodChannel('cz.l0ck.ecp/activity').invokeMethod<bool>('openUri', {'uri': uri});
    if (ok != true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.openFailed)));
    }
  }

  Widget _link(BuildContext context, String label, String uri) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(color: L0ckColors.greenLight)),
        subtitle: Text(uri, style: const TextStyle(color: L0ckColors.data)),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _open(context, uri),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/images/top-logo.jpg', fit: BoxFit.fitWidth),
        ),
        const SizedBox(height: 12),
        Text(l.aboutVersion(appVersion), textAlign: TextAlign.center, style: const TextStyle(color: L0ckColors.dim)),
        const SizedBox(height: 6),
        Text(l.aboutTagline, textAlign: TextAlign.center, style: const TextStyle(color: L0ckColors.text)),
        const SizedBox(height: 12),
        Panel(
          title: l.aboutAuthor,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('L0ckSm1thV',
                style: TextStyle(color: L0ckColors.data, fontSize: 18, fontWeight: FontWeight.bold)),
            _link(context, 'GitHub', _github),
            _link(context, l.aboutWeb, _web),
          ]),
        ),
        Panel(
          title: l.aboutDisclaimer,
          child: Text(l.aboutDisclaimerText, style: const TextStyle(color: L0ckColors.text, height: 1.35)),
        ),
        Panel(
          title: l.aboutLicense,
          child: Text(l.aboutLicenseText, style: const TextStyle(color: L0ckColors.text)),
        ),
        Panel(
          title: l.aboutThirdParty,
          child: Text(l.aboutThirdPartyText, style: const TextStyle(color: L0ckColors.dim, fontSize: 12)),
        ),
      ]),
    );
  }
}
