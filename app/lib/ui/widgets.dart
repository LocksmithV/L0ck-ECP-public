import 'package:ecp_core/ecp_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Logo + "L0ck-ECP" in the brand colours (original app bar).
class L0ckTitle extends StatelessWidget {
  const L0ckTitle({super.key, this.size = 17, this.logo = true});

  final double size;
  final bool logo;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (logo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.25),
            child: Image.asset('assets/images/logo.jpg', height: size * 1.6, fit: BoxFit.contain),
          ),
          SizedBox(width: size * 0.4),
        ],
        Text.rich(TextSpan(children: [
          TextSpan(
              text: 'L0ck',
              style: TextStyle(
                  color: L0ckColors.greenLight,
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          TextSpan(
              text: '-',
              style: TextStyle(color: L0ckColors.dim, fontSize: size, fontWeight: FontWeight.w300)),
          TextSpan(
              text: 'ECP',
              style: TextStyle(
                  color: L0ckColors.orange,
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
        ])),
      ]);
}

/// Logo, name and tagline for the lock and first-run screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18), // the JPEG's corners are not transparent
          child: Image.asset('assets/images/logo.jpg', height: 110),
        ),
        const SizedBox(height: 14),
        const L0ckTitle(size: 28, logo: false),
        const SizedBox(height: 6),
        const Text('EMERGENCY COORDINATION PLATFORM',
            textAlign: TextAlign.center,
            style: TextStyle(color: L0ckColors.dim, fontSize: 9, letterSpacing: 2.5)),
      ]);
}

/// A titled panel with the thin green frame of the original UI.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: L0ckColors.panel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: L0ckColors.border, width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title.toUpperCase(), style: labelStyle)),
            ?trailing,
          ]),
          const SizedBox(height: 8),
          // Tiles and buttons inside need a Material above the panel's colour for their ink
          Material(type: MaterialType.transparency, child: child),
        ]),
      );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// One PACE layer's state for the COMMS strip.
enum LayerState { active, standby, absent }

/// The original "COMMS" strip: PACE order with a state dot per layer.
class CommsStrip extends StatelessWidget {
  const CommsStrip({super.key, required this.states});

  final Map<PaceLayer, LayerState> states;

  static const _labels = {
    PaceLayer.primary: 'SX',
    PaceLayer.alternate: 'TOR',
    PaceLayer.contingency: 'MESH',
    PaceLayer.emergency: 'SMS',
  };

  static Color _color(LayerState s) => switch (s) {
        LayerState.active => L0ckColors.ok,
        LayerState.standby => L0ckColors.amber,
        LayerState.absent => L0ckColors.off,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: const BoxDecoration(
          color: L0ckColors.panel,
          border: Border(bottom: BorderSide(color: L0ckColors.border, width: 0.5)),
        ),
        child: Row(children: [
          const Text('COMMS', style: labelStyle),
          const SizedBox(width: 12),
          for (final l in PaceLayer.values)
            Expanded(
              child: Semantics(
                label: '${_labels[l]} ${states[l]?.name ?? 'absent'}',
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${l.index + 1}', style: const TextStyle(color: L0ckColors.dim, fontSize: 9)),
                  const SizedBox(width: 3),
                  Dot(_color(states[l] ?? LayerState.absent), size: 6),
                  const SizedBox(width: 4),
                  Text(_labels[l]!,
                      style: const TextStyle(
                          color: L0ckColors.text, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      );
}

/// Unread count, orange like the ECP accent.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: L0ckColors.orange, borderRadius: BorderRadius.circular(10)),
        child: Text('$count',
            style: const TextStyle(color: L0ckColors.bg, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}
