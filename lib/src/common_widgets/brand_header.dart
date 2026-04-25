import 'package:flutter/material.dart';

/// TODO: Document BrandHeader.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  static const brandHeaderKey = Key('brand_header');
  static const assetPath = 'assets/brand/app_icon_1024.png';

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: brandHeaderKey,
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(assetPath, width: 80, height: 80),
        ),
      ),
    );
  }
}
