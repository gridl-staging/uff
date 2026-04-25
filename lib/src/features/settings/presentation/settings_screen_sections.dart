part of 'settings_screen.dart';

/// TODO: Document _SettingsFormViewState.
@immutable
class _SettingsFormViewState {
  const _SettingsFormViewState({
    required this.isAuthLoading,
    required this.selectedThemeMode,
    required this.isNotificationsEnabled,
    required this.isTelemetryEnabled,
    required this.selectedUnits,
    required this.selectedVisibility,
  });

  final bool isAuthLoading;
  final ThemeMode selectedThemeMode;
  final bool isNotificationsEnabled;
  final bool isTelemetryEnabled;
  final String selectedUnits;
  final String selectedVisibility;
}

Widget _buildSettingsForm(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
) {
  final isInteractionLocked =
      viewState.isAuthLoading || state._isMutationInFlight;

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildDisplayPreferencesSection(
          state,
          viewState,
          isInteractionLocked,
        ),
        ..._buildAccountSection(state, isInteractionLocked),
        ..._buildPrivacySection(state, isInteractionLocked),
        ..._buildNotificationsSection(state, viewState, isInteractionLocked),
        ..._buildDataSection(state, viewState, isInteractionLocked),
        ..._buildAboutSection(state, isInteractionLocked),
        ..._buildDangerZoneSection(state, viewState, isInteractionLocked),
      ],
    ),
  );
}

List<Widget> _buildDisplayPreferencesSection(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return [
    const _SectionHeader(title: 'Display Preferences'),
    const Text('Units'),
    const SizedBox(height: 8),
    _buildUnitsSegment(state, viewState, isInteractionLocked),
    const SizedBox(height: 16),
    const Text('Activity Visibility'),
    const SizedBox(height: 8),
    _buildVisibilitySegment(state, viewState, isInteractionLocked),
    const SizedBox(height: 16),
    _buildThemeModeGroup(state, viewState, isInteractionLocked),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

Widget _buildUnitsSegment(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return SegmentedButton<String>(
    key: SettingsScreen.unitsSegmentKey,
    segments: const [
      ButtonSegment(value: 'metric', label: Text('Metric')),
      ButtonSegment(value: 'imperial', label: Text('Imperial')),
    ],
    selected: {viewState.selectedUnits},
    onSelectionChanged: isInteractionLocked
        ? null
        : (selection) {
            if (selection.isEmpty) {
              return;
            }
            unawaited(state._saveUnits(selection.first));
          },
  );
}

Widget _buildVisibilitySegment(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return SegmentedButton<String>(
    key: SettingsScreen.visibilitySegmentKey,
    segments: const [
      ButtonSegment(value: 'public', label: Text('Public')),
      ButtonSegment(value: 'followers', label: Text('Followers')),
      ButtonSegment(value: 'private', label: Text('Private')),
    ],
    selected: {viewState.selectedVisibility},
    onSelectionChanged: isInteractionLocked
        ? null
        : (selection) {
            if (selection.isEmpty) {
              return;
            }
            unawaited(state._saveVisibility(selection.first));
          },
  );
}

Widget _buildThemeModeGroup(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return RadioGroup<ThemeMode>(
    key: SettingsScreen.themeModeGroupKey,
    groupValue: viewState.selectedThemeMode,
    onChanged: (value) {
      if (isInteractionLocked) {
        return;
      }
      _onThemeModeSelected(state.ref, value);
    },
    child: const Column(
      children: [
        RadioListTile<ThemeMode>(
          key: SettingsScreen.systemThemeModeKey,
          title: Text('System'),
          value: ThemeMode.system,
        ),
        RadioListTile<ThemeMode>(
          key: SettingsScreen.lightThemeModeKey,
          title: Text('Light'),
          value: ThemeMode.light,
        ),
        RadioListTile<ThemeMode>(
          key: SettingsScreen.darkThemeModeKey,
          title: Text('Dark'),
          value: ThemeMode.dark,
        ),
      ],
    ),
  );
}

List<Widget> _buildAccountSection(
  _SettingsScreenState state,
  bool isInteractionLocked,
) {
  final authState = state.ref.watch(authProvider).asData?.value;
  final email =
      authState?.map(
        authenticated: (value) => value.email,
        unauthenticated: (_) => '',
      ) ??
      '';
  final connectedProvidersAsync = state.ref.watch(connectedProvidersProvider);
  final connectedProviders =
      connectedProvidersAsync.asData?.value ?? const <String>[];
  final isAppleConnected = connectedProviders.contains('apple');
  final isGoogleConnected = connectedProviders.contains('google');

  return [
    const _SectionHeader(title: 'Account'),
    ListTile(
      key: SettingsScreen.emailRowKey,
      title: const Text('Email'),
      subtitle: Text(email),
    ),
    ListTile(
      key: SettingsScreen.changePasswordTileKey,
      title: const Text('Change Password'),
      trailing: const Icon(Icons.chevron_right),
      enabled: !isInteractionLocked,
      onTap: isInteractionLocked
          ? null
          : () => unawaited(state._showChangePasswordDialog()),
    ),
    ListTile(
      key: SettingsScreen.appleProviderTileKey,
      title: const Text('Apple'),
      subtitle: Text(isAppleConnected ? 'Connected' : 'Not connected'),
    ),
    ListTile(
      key: SettingsScreen.googleProviderTileKey,
      title: const Text('Google'),
      subtitle: Text(isGoogleConnected ? 'Connected' : 'Not connected'),
    ),
    TextFormField(
      key: SettingsScreen.displayNameFieldKey,
      controller: state._displayNameController,
      enabled: !isInteractionLocked,
      decoration: const InputDecoration(labelText: 'Display Name'),
    ),
    const SizedBox(height: 12),
    ElevatedButton(
      key: SettingsScreen.saveButtonKey,
      onPressed: isInteractionLocked ? null : state._save,
      child: state._isSaveInFlight
          ? const ButtonProgressIndicator()
          : const Text('Save'),
    ),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

List<Widget> _buildPrivacySection(
  _SettingsScreenState state,
  bool isInteractionLocked,
) {
  return [
    const _SectionHeader(title: 'Privacy'),
    ListTile(
      key: SettingsScreen.privacyZonesLinkKey,
      title: const Text('Privacy Zones'),
      trailing: const Icon(Icons.chevron_right),
      onTap: isInteractionLocked
          ? null
          : () => state.context.push(ProfileRoutes.privacyZonesPath),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'Your default activity visibility applies to new activities. '
        'You can still adjust visibility per activity before saving.',
      ),
    ),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

List<Widget> _buildNotificationsSection(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return [
    const _SectionHeader(title: 'Notifications'),
    SwitchListTile(
      key: SettingsScreen.notificationsToggleTileKey,
      title: const Text('Push notifications'),
      subtitle: Text(
        viewState.isNotificationsEnabled
            ? 'On. This device can show push notifications.'
            : 'Off. This device will not show push notifications.',
      ),
      value: viewState.isNotificationsEnabled,
      onChanged: isInteractionLocked
          ? null
          : (value) => _onNotificationsEnabledChanged(state.ref, value),
    ),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

List<Widget> _buildDataSection(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  return [
    const _SectionHeader(title: 'Data'),
    OutlinedButton(
      key: SettingsScreen.exportDataButtonKey,
      onPressed: isInteractionLocked ? null : state._exportData,
      child: state._isExportInFlight
          ? const ButtonProgressIndicator()
          : const Text('Export My Data'),
    ),
    const SizedBox(height: 8),
    SwitchListTile(
      key: SettingsScreen.telemetryToggleTileKey,
      title: const Text('Runtime telemetry'),
      subtitle: Text(
        viewState.isTelemetryEnabled
            ? 'On. Uff captures new runtime events and queues them for upload.'
            : 'Off. Uff stops new runtime capture and clears queued telemetry.',
      ),
      value: viewState.isTelemetryEnabled,
      onChanged: isInteractionLocked
          ? null
          : (value) => _onTelemetryEnabledChanged(state.ref, value),
    ),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

List<Widget> _buildAboutSection(
  _SettingsScreenState state,
  bool isInteractionLocked,
) {
  return [
    const _SectionHeader(title: 'About'),
    ListTile(
      key: SettingsScreen.hrZonesTileKey,
      title: const Text('Heart Rate Zones'),
      subtitle: const Text('Set your lactate threshold heart rate'),
      trailing: const Icon(Icons.chevron_right),
      onTap: isInteractionLocked
          ? null
          : () => state.context.push(SettingsRoutes.hrZonesPath),
    ),
    ListTile(
      key: SettingsScreen.privacyPolicyTileKey,
      title: const Text('Privacy Policy'),
      trailing: const Icon(Icons.chevron_right),
      onTap: isInteractionLocked
          ? null
          : () => state.context.push(LegalRoutes.privacyPath),
    ),
    ListTile(
      key: SettingsScreen.termsOfServiceTileKey,
      title: const Text('Terms of Service'),
      trailing: const Icon(Icons.chevron_right),
      onTap: isInteractionLocked
          ? null
          : () => state.context.push(LegalRoutes.termsPath),
    ),
    const AboutListTile(
      icon: Icon(Icons.info_outline),
      applicationName: 'Uff',
      applicationLegalese: 'Build in progress.',
      child: Text('About Uff'),
    ),
    const SizedBox(height: 24),
    const Divider(),
  ];
}

List<Widget> _buildDangerZoneSection(
  _SettingsScreenState state,
  _SettingsFormViewState viewState,
  bool isInteractionLocked,
) {
  final signOutAction = isInteractionLocked
      ? null
      : () => state.ref.read(authProvider.notifier).signOut();

  return [
    const _SectionHeader(title: 'Danger Zone'),
    Semantics(
      key: SettingsScreen.signOutButtonKey,
      // Expose one explicit accessibility node for the full sign-out control.
      // The looser "wrap the button and let semantics merge naturally"
      // approach passed widget finders but failed in DeviceCloud because the
      // visible button node did not actually carry the identifier that Maestro
      // looks up on iOS.
      container: true,
      button: true,
      enabled: !isInteractionLocked,
      identifier: SettingsScreen.signOutButtonSemanticsId,
      // Keep the label stable even while the progress indicator is visible so
      // release-smoke selectors and assistive tech both describe the same
      // destructive action consistently.
      label: 'Sign Out',
      onTap: signOutAction,
      child: ExcludeSemantics(
        // Exclude the nested button semantics so we publish one deterministic
        // node instead of relying on platform-specific semantics merging.
        child: OutlinedButton(
          onPressed: signOutAction,
          child: viewState.isAuthLoading
              ? const ButtonProgressIndicator()
              : const Text('Sign Out'),
        ),
      ),
    ),
    const SizedBox(height: 12),
    OutlinedButton(
      key: SettingsScreen.deleteAccountButtonKey,
      onPressed: isInteractionLocked ? null : state._showDeleteConfirmation,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(state.context).colorScheme.error,
      ),
      child: state._isDeleteInFlight
          ? const ButtonProgressIndicator()
          : const Text('Delete Account'),
    ),
  ];
}

void _onThemeModeSelected(WidgetRef ref, ThemeMode? selectedThemeMode) {
  if (selectedThemeMode == null) {
    return;
  }

  ref.read(themeModeProvider.notifier).setThemeMode(selectedThemeMode);
}

void _onTelemetryEnabledChanged(WidgetRef ref, bool isEnabled) {
  ref
      .read(telemetryEnablementProvider.notifier)
      .setTelemetryEnabled(isEnabled: isEnabled);
}

void _onNotificationsEnabledChanged(WidgetRef ref, bool isEnabled) {
  ref
      .read(notificationPreferencesProvider.notifier)
      .setNotificationsEnabled(isEnabled: isEnabled);
}

/// Lightweight section label used to group settings tiles.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
