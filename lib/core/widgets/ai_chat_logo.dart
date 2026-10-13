import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';

class AiChatLogo extends StatelessWidget {
  const AiChatLogo({
    super.key,
    this.size = 36,
    this.padding = 0,
  });

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    // Premium transparent gradient AI logo to replace the legacy black-background PNG
    final logo = ShaderMask(
      shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
      child: Icon(
        Icons.smart_toy_outlined,
        size: size,
        color: Colors.white,
      ),
    );

    if (padding > 0) {
      return Padding(padding: EdgeInsets.all(padding), child: logo);
    }

    return logo;
  }
}
