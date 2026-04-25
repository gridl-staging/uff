import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/notifications/application/notification_preferences.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';

part 'settings_screen_sections.dart';

/// TODO: Document SettingsScreen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const signOutButtonKey = Key('settings_sign_out_button');
  static const signOutButtonSemanticsId = 'settings_sign_out_button';
  static const themeModeGroupKey = Key('settings_theme_mode_group');
  static const systemThemeModeKey = Key('settings_theme_mode_system');
  static const lightThemeModeKey = Key('settings_theme_mode_light');
  static const darkThemeModeKey = Key('settings_theme_mode_dark');
  static const telemetryToggleTileKey = Key('settings_telemetry_toggle_tile');
  static const notificationsToggleTileKey = Key(
    'settings_notifications_toggle_tile',
  );
  static const privacyPolicyTileKey = Key('settings_privacy_policy_tile');
  static const termsOfServiceTileKey = Key('settings_terms_of_service_tile');
  static const hrZonesTileKey = Key('settings_hr_zones_tile');

  static const displayNameFieldKey = Key('settings_display_name_field');
  static const emailRowKey = Key('settings_email_row');
  static const changePasswordTileKey = Key('settings_change_password_tile');
  static const appleProviderTileKey = Key('settings_apple_provider_tile');
  static const googleProviderTileKey = Key('settings_google_provider_tile');
  static const saveButtonKey = Key('settings_save_button');
  static const exportDataButtonKey = Key('settings_export_data_button');
  static const deleteAccountButtonKey = Key('settings_delete_account_button');
  static const exportDataDialogKey = Key('settings_export_data_dialog');
  static const privacyZonesLinkKey = Key('settings_privacy_zones_link');
  static const unitsSegmentKey = Key('settings_units_segment');
  static const visibilitySegmentKey = Key('settings_visibility_segment');

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// TODO: Document _SettingsScreenState.
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _displayNameController = TextEditingController();

  bool _initialized = false;
  bool _allowNextPop = false;
  _SettingsFormSnapshot? _savedSnapshot;
  Profile? _lastPersistedProfile;
  String? _selectedUnits;
  String? _selectedVisibility;
  bool _isPreferenceSaveInFlight = false;
  bool _isSaveInFlight = false;
  bool _isExportInFlight = false;
  bool _isDeleteInFlight = false;

  bool get _isMutationInFlight {
    return _isPreferenceSaveInFlight ||
        _isSaveInFlight ||
        _isExportInFlight ||
        _isDeleteInFlight;
  }

  bool get _hasUnsavedChanges {
    if (!_initialized || _savedSnapshot == null) {
      return false;
    }

    return _captureSnapshot() != _savedSnapshot;
  }

  bool get _canPop => _allowNextPop || !_hasUnsavedChanges;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_handleFormValueChanged);
  }

  @override
  void dispose() {
    _displayNameController
      ..removeListener(_handleFormValueChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFormValueChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _initializeFromProfile(Profile profile) {
    final snapshot = _SettingsFormSnapshot.fromProfile(profile);
    final previousUserId = _lastPersistedProfile?.userId;
    _lastPersistedProfile = profile;

    if (!_initialized) {
      _applySnapshot(snapshot);
      _savedSnapshot = snapshot;
      _selectedUnits = profile.preferredUnits;
      _selectedVisibility = profile.defaultActivityVisibility;
      _initialized = true;
      return;
    }

    if (previousUserId != null && previousUserId != profile.userId) {
      _applySnapshot(snapshot);
      _savedSnapshot = snapshot;
      _selectedUnits = profile.preferredUnits;
      _selectedVisibility = profile.defaultActivityVisibility;
      return;
    }

    if (_hasUnsavedChanges) {
      return;
    }

    final shouldApplyPersistedValues =
        _savedSnapshot != snapshot ||
        _selectedUnits != profile.preferredUnits ||
        _selectedVisibility != profile.defaultActivityVisibility;
    if (!shouldApplyPersistedValues) {
      return;
    }

    _applySnapshot(snapshot);
    _savedSnapshot = snapshot;
    _selectedUnits = profile.preferredUnits;
    _selectedVisibility = profile.defaultActivityVisibility;
  }

  Future<void> _saveUnits(String preferredUnits) async {
    await _savePreference(
      nextValue: preferredUnits,
      currentValue: (profile) => _selectedUnits ?? profile.preferredUnits,
      selectValue: (value) => _selectedUnits = value,
      copyProfile: (profile) =>
          profile.copyWith(preferredUnits: preferredUnits),
    );
  }

  Future<void> _saveVisibility(String defaultActivityVisibility) async {
    await _savePreference(
      nextValue: defaultActivityVisibility,
      currentValue: (profile) =>
          _selectedVisibility ?? profile.defaultActivityVisibility,
      selectValue: (value) => _selectedVisibility = value,
      copyProfile: (profile) => profile.copyWith(
        defaultActivityVisibility: defaultActivityVisibility,
      ),
    );
  }

  Future<void> _savePreference({
    required String nextValue,
    required String Function(Profile profile) currentValue,
    required void Function(String value) selectValue,
    required Profile Function(Profile profile) copyProfile,
  }) async {
    if (_isMutationInFlight) {
      return;
    }

    final persistedProfile = _lastPersistedProfile;
    if (persistedProfile == null) {
      return;
    }

    final previousValue = currentValue(persistedProfile);
    if (nextValue == previousValue) {
      return;
    }

    setState(() {
      _isPreferenceSaveInFlight = true;
      selectValue(nextValue);
    });

    final updatedProfile = copyProfile(persistedProfile);
    try {
      await ref.read(profileProvider.notifier).updateProfile(updatedProfile);
      if (!mounted) {
        return;
      }

      final profileState = ref.read(profileProvider);
      if (profileState.hasError) {
        setState(() {
          selectValue(previousValue);
        });
        _showErrorSnackBar('Failed to save settings. Please try again.');
        return;
      }

      final resolvedProfile = profileState.asData?.value ?? updatedProfile;
      setState(() {
        _applyPreferenceSaveResult(resolvedProfile);
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        selectValue(previousValue);
      });
      _showErrorSnackBar('Failed to save settings. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isPreferenceSaveInFlight = false;
        });
      }
    }
  }

  void _applyPreferenceSaveResult(Profile resolvedProfile) {
    final resolvedSnapshot = _SettingsFormSnapshot.fromProfile(resolvedProfile);
    _lastPersistedProfile = resolvedProfile;
    _selectedUnits = resolvedProfile.preferredUnits;
    _selectedVisibility = resolvedProfile.defaultActivityVisibility;
    if (!_hasUnsavedChanges) {
      _applySnapshot(resolvedSnapshot);
      _savedSnapshot = resolvedSnapshot;
    }
  }

  Future<void> _save() async {
    if (_isMutationInFlight) {
      return;
    }

    final persistedProfile = _lastPersistedProfile;
    if (persistedProfile == null) {
      return;
    }

    setState(() {
      _isSaveInFlight = true;
    });

    try {
      final updatedProfile = persistedProfile.copyWith(
        displayName: _displayNameController.text,
      );

      await ref.read(profileProvider.notifier).updateProfile(updatedProfile);
      if (!mounted) {
        return;
      }

      final profileState = ref.read(profileProvider);
      if (profileState.hasError) {
        final revertedSnapshot = _SettingsFormSnapshot.fromProfile(
          persistedProfile,
        );
        setState(() {
          _applySnapshot(revertedSnapshot);
          _savedSnapshot = revertedSnapshot;
        });
        _showErrorSnackBar('Failed to save settings. Please try again.');
        return;
      }

      final resolvedProfile = profileState.asData?.value ?? updatedProfile;
      final resolvedSnapshot = _SettingsFormSnapshot.fromProfile(
        resolvedProfile,
      );
      setState(() {
        _lastPersistedProfile = resolvedProfile;
        _selectedUnits = resolvedProfile.preferredUnits;
        _selectedVisibility = resolvedProfile.defaultActivityVisibility;
        _applySnapshot(resolvedSnapshot);
        _savedSnapshot = resolvedSnapshot;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on Object {
      if (!mounted) {
        return;
      }

      final revertedSnapshot = _SettingsFormSnapshot.fromProfile(
        persistedProfile,
      );
      setState(() {
        _selectedUnits = persistedProfile.preferredUnits;
        _selectedVisibility = persistedProfile.defaultActivityVisibility;
        _applySnapshot(revertedSnapshot);
        _savedSnapshot = revertedSnapshot;
      });
      _showErrorSnackBar('Failed to save settings. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaveInFlight = false;
        });
      }
    }
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) {
      return;
    }

    if (_isMutationInFlight) {
      _showErrorSnackBar('Please wait for settings changes to finish.');
      return;
    }

    if (!_hasUnsavedChanges) {
      return;
    }

    final shouldDiscard = await showDiscardChangesDialog(context);
    if (!shouldDiscard || !mounted) {
      return;
    }

    setState(() {
      _allowNextPop = true;
    });
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  Future<void> _exportData() async {
    if (_isMutationInFlight) {
      return;
    }

    setState(() {
      _isExportInFlight = true;
    });

    try {
      final exportData = await ref
          .read(profileRepositoryProvider)
          .exportMyData();
      if (!mounted) {
        return;
      }

      final exportJson = const JsonEncoder.withIndent('  ').convert(exportData);
      setState(() {
        _isExportInFlight = false;
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: SettingsScreen.exportDataDialogKey,
          title: const Text('Exported Data'),
          content: SingleChildScrollView(child: SelectableText(exportJson)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to export data. Please try again.');
    } finally {
      if (mounted && _isExportInFlight) {
        setState(() {
          _isExportInFlight = false;
        });
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This permanently deletes your account and all data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_isMutationInFlight) {
                return;
              }
              Navigator.pop(dialogContext);
              await _deleteAccount();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    var newPassword = '';
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submitPasswordChange() async {
              if (isSaving) {
                return;
              }
              final passwordToSave = newPassword.trim();
              if (passwordToSave.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a new password.')),
                );
                return;
              }

              setDialogState(() {
                isSaving = true;
              });
              try {
                await ref
                    .read(authProvider.notifier)
                    .updatePassword(passwordToSave);
                if (!mounted) {
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated.')),
                );
              } on Object {
                if (!mounted) {
                  return;
                }
                setDialogState(() {
                  isSaving = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to update password. Please try again.',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Change Password'),
              content: TextFormField(
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password'),
                onChanged: (value) {
                  newPassword = value;
                },
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => unawaited(submitPasswordChange()),
                  child: isSaving
                      ? const ButtonProgressIndicator()
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    if (_isMutationInFlight) {
      return;
    }

    setState(() {
      _isDeleteInFlight = true;
    });

    try {
      await ref.read(profileRepositoryProvider).deleteMyAccount();
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully.')),
      );
    } on Object {
      _showErrorSnackBar('Failed to delete account. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleteInFlight = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _applySnapshot(_SettingsFormSnapshot snapshot) {
    _displayNameController.text = snapshot.displayName;
  }

  _SettingsFormSnapshot _captureSnapshot() {
    return _SettingsFormSnapshot(displayName: _displayNameController.text);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final isAuthLoading = ref.watch(authProvider).isLoading;
    final selectedThemeMode = ref.watch(themeModeProvider);
    final isNotificationsEnabled = ref.watch(notificationPreferencesProvider);
    final isTelemetryEnabled = ref.watch(telemetryEnablementProvider);

    final selectedUnits =
        _selectedUnits ?? _lastPersistedProfile?.preferredUnits ?? 'metric';
    final selectedVisibility =
        _selectedVisibility ??
        _lastPersistedProfile?.defaultActivityVisibility ??
        'private';
    final viewState = _SettingsFormViewState(
      isAuthLoading: isAuthLoading,
      selectedThemeMode: selectedThemeMode,
      isNotificationsEnabled: isNotificationsEnabled,
      isTelemetryEnabled: isTelemetryEnabled,
      selectedUnits: selectedUnits,
      selectedVisibility: selectedVisibility,
    );

    final body =
        _initialized && (profileAsync.isLoading || profileAsync.hasError)
        ? _buildSettingsForm(this, viewState)
        : profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => const Center(
              child: Text('Failed to load settings. Please try again.'),
            ),
            data: (profile) {
              if (profile == null) {
                return const Center(child: Text('No profile'));
              }

              _initializeFromProfile(profile);
              return _buildSettingsForm(this, viewState);
            },
          );

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: body,
      ),
    );
  }
}

/// Captures editable settings fields to detect unsaved changes.
@immutable
class _SettingsFormSnapshot {
  const _SettingsFormSnapshot({required this.displayName});

  factory _SettingsFormSnapshot.fromProfile(Profile profile) {
    return _SettingsFormSnapshot(displayName: profile.displayName ?? '');
  }

  final String displayName;

  @override
  bool operator ==(Object other) {
    return other is _SettingsFormSnapshot && other.displayName == displayName;
  }

  @override
  int get hashCode => displayName.hashCode;
}
