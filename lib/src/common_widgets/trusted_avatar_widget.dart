import 'package:flutter/material.dart';

/// Shared avatar widget that only trusts HTTPS avatar URLs.
///
/// Invalid, insecure, or missing URLs fall back to user initials (when a
/// display name is available) and finally to the generic person icon.
class TrustedAvatarWidget extends StatelessWidget {
  const TrustedAvatarWidget({
    required this.avatarUrl,
    required this.displayName,
    this.radius = 16,
    super.key,
  });

  final String? avatarUrl;
  final String? displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarImage = _trustedAvatarImageProvider(avatarUrl);

    return CircleAvatar(
      radius: radius,
      backgroundImage: avatarImage,
      child: avatarImage == null ? _fallbackAvatarChild(displayName) : null,
    );
  }
}

Widget _fallbackAvatarChild(String? displayName) {
  final initials = _initialsFromDisplayName(displayName);
  if (initials == null) {
    return const Icon(Icons.person);
  }

  return Text(
    initials,
    maxLines: 1,
    overflow: TextOverflow.clip,
  );
}

ImageProvider<Object>? _trustedAvatarImageProvider(String? avatarUrl) {
  final parsedUri = Uri.tryParse(avatarUrl ?? '');
  if (parsedUri == null ||
      parsedUri.scheme.toLowerCase() != 'https' ||
      !parsedUri.hasAuthority) {
    return null;
  }
  return NetworkImage(parsedUri.toString());
}

String? _initialsFromDisplayName(String? displayName) {
  final trimmed = displayName?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }

  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return null;
  }

  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }

  final firstInitial = words[0].substring(0, 1);
  final secondInitial = words[1].substring(0, 1);
  return '$firstInitial$secondInitial'.toUpperCase();
}
