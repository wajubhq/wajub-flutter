import 'package:flutter/widgets.dart';

import '../widgets/network_logo.dart';
import 'operator_choice.dart';

/// An operator's logo, or its brand badge when the logo is missing or does
/// not load (`algorithms.brand_fallback`): a round badge in the brand's
/// colours with its mark.
class OperatorLogo extends StatelessWidget {
  const OperatorLogo({super.key, required this.choice, this.size = 32});

  final OperatorChoice choice;

  /// Width and height, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = NetworkLogo.of(
      key: ValueKey('wajub-operator-logo-${choice.id}'),
      logo: choice.logo,
      logoPng: choice.logoPng,
      width: size,
      height: size,
      fallback: _badge(),
    );
    return Semantics(
      label: choice.label,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: logo ?? _badge()),
    );
  }

  Widget _badge() {
    final badge = choice.badge;
    return Container(
      key: ValueKey('wajub-operator-badge-${choice.id}'),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(color: badge.background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          badge.badgeText(choice.label),
          maxLines: 1,
          style: TextStyle(color: badge.color, fontSize: size * 0.3, fontWeight: FontWeight.w700, height: 1),
        ),
      ),
    );
  }
}
