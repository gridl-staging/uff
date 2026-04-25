String socialUserDisplayNameOrId({
  required String userId,
  required String? displayName,
}) {
  final trimmedDisplayName = displayName?.trim();
  return trimmedDisplayName == null || trimmedDisplayName.isEmpty
      ? userId
      : trimmedDisplayName;
}
