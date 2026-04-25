import 'package:flutter/material.dart';

/// TODO: Document UserAvatar.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.avatarUrl,
    required this.displayName,
    this.radius = 40,
    super.key,
  });

  final String? avatarUrl;
  final String? displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = trustedHttpsAvatarImageProvider(avatarUrl);
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null ? Text(_initials(displayName)) : null,
    );
  }
}

ImageProvider<Object>? trustedHttpsAvatarImageProvider(String? avatarUrl) {
  final parsedUri = Uri.tryParse(avatarUrl ?? '');
  if (parsedUri == null ||
      parsedUri.scheme != 'https' ||
      !parsedUri.hasAuthority ||
      parsedUri.host.trim().isEmpty) {
    return null;
  }
  return NetworkImage(parsedUri.toString());
}

String _initials(String? displayName) {
  if (displayName == null || displayName.trim().isEmpty) {
    return '?';
  }
  final parts = displayName.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first[0].toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
