import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:uff/src/common_widgets/brand_header.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

part 'onboarding_screen_step_widgets.dart';

/// NOTE(stuart): Document OnboardingScreen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const onboardingScreenKey = Key('onboarding_screen');
  static const continueButtonKey = Key('onboarding_continue_button');
  static const skipButtonKey = Key('onboarding_skip_button');
  static const backButtonKey = Key('onboarding_back_button');
  static const pageIndicatorKey = Key('onboarding_page_indicator');
  static const retryButtonKey = Key('onboarding_retry_button');

  static const unitsSelectorKey = Key('onboarding_units_selector');
  static const unitsMetricOptionKey = Key('units_option_metric');
  static const unitsImperialOptionKey = Key('units_option_imperial');

  static const visibilityPrivateOptionKey = Key('visibility_option_private');
  static const visibilityFollowersOptionKey = Key(
    'visibility_option_followers',
  );
  static const visibilityPublicOptionKey = Key('visibility_option_public');
  static const visibilityPrivateCheckKey = Key(
    'visibility_option_private_check',
  );
  static const visibilityFollowersCheckKey = Key(
    'visibility_option_followers_check',
  );
  static const visibilityPublicCheckKey = Key('visibility_option_public_check');

  static const Map<String, String> sportOptions = <String, String>{
    'run': 'Running',
    'ride': 'Cycling',
    'hike': 'Hiking',
    'walk': 'Walking',
    'trail_run': 'Trail running',
  };

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

const _visibilityOptions = <_VisibilityOption>[
  _VisibilityOption(
    optionKey: OnboardingScreen.visibilityPrivateOptionKey,
    checkKey: OnboardingScreen.visibilityPrivateCheckKey,
    title: 'Only me',
    description: 'Only you can see your activities.',
    value: 'private',
    icon: Icons.lock,
  ),
  _VisibilityOption(
    optionKey: OnboardingScreen.visibilityFollowersOptionKey,
    checkKey: OnboardingScreen.visibilityFollowersCheckKey,
    title: 'Friends',
    description: 'Only followers can see your activities.',
    value: 'followers',
    icon: Icons.group,
  ),
  _VisibilityOption(
    optionKey: OnboardingScreen.visibilityPublicOptionKey,
    checkKey: OnboardingScreen.visibilityPublicCheckKey,
    title: 'Public',
    description: 'Everyone can see your activities.',
    value: 'public',
    icon: Icons.public,
  ),
];

/// TODO: Document _OnboardingScreenState.
class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;
  static const _defaultUnits = 'metric';
  static const _defaultVisibility = 'private';
  static const _defaultSportPreferences = <String>['run'];
  static const _completionFailureMessage =
      'Could not complete onboarding. Try again.';

  late final PageController _pageController;
  int _currentPageIndex = 0;
  bool _initializedFromProfile = false;
  bool _isSubmitting = false;

  String _initialPreferredUnits = _defaultUnits;
  String _selectedUnits = _defaultUnits;
  String _selectedVisibility = _defaultVisibility;
  Set<String> _selectedSports = _defaultSportPreferences.toSet();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);

    return Scaffold(
      key: OnboardingScreen.onboardingScreenKey,
      appBar: AppBar(
        title: const Text('Onboarding'),
        actions: [
          Semantics(
            identifier: 'skip_onboarding_button',
            child: TextButton(
              key: OnboardingScreen.skipButtonKey,
              onPressed: profileState.hasValue && !_isSubmitting ? _skip : null,
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
      body: profileState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: _buildProfileRecoveryState(
            message: 'Unable to load onboarding profile.',
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: _buildProfileRecoveryState(
                message: 'No profile available.',
              ),
            );
          }

          if (!_initializedFromProfile) {
            _initializeSelections(profile);
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      setState(() => _currentPageIndex = page);
                    },
                    children: [
                      const _OnboardingStepScaffold(
                        title: 'Welcome to Uff',
                        subtitle: 'Set your preferences to finish onboarding.',
                      ),
                      _buildSportPreferenceStep(),
                      _buildUnitsStep(),
                      _buildPrivacyStep(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  child: SmoothPageIndicator(
                    key: OnboardingScreen.pageIndicatorKey,
                    controller: _pageController,
                    count: _stepCount,
                    effect: const WormEffect(
                      dotHeight: 8,
                      dotWidth: 8,
                      spacing: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      key: OnboardingScreen.backButtonKey,
                      onPressed: _isSubmitting || _currentPageIndex == 0
                          ? null
                          : _goToPreviousPage,
                      child: const Text('Back'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      key: OnboardingScreen.continueButtonKey,
                      onPressed: _isSubmitting
                          ? null
                          : () => _onContinuePressed(profile),
                      child: Text(
                        _currentPageIndex == _stepCount - 1
                            ? 'Complete'
                            : 'Continue',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileRecoveryState({required String message}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            key: OnboardingScreen.retryButtonKey,
            onPressed: _retryProfileLoad,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _retryProfileLoad() {
    ref.invalidate(profileProvider);
  }

  Widget _buildSportPreferenceStep() {
    return _OnboardingStepScaffold(
      title: 'What do you track?',
      subtitle: 'Select all that apply. You can change this later.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: OnboardingScreen.sportOptions.entries
            .map((entry) {
              final sportId = entry.key;
              final label = entry.value;
              final isSelected = _selectedSports.contains(sportId);

              return FilterChip(
                key: Key('sport_chip_$sportId'),
                label: Text(label),
                selected: isSelected,
                onSelected: (selected) => _toggleSport(sportId, selected),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildUnitsStep() {
    return _OnboardingStepScaffold(
      title: 'Unit preference',
      subtitle: 'Choose your default measurement system.',
      child: SegmentedButton<String>(
        key: OnboardingScreen.unitsSelectorKey,
        segments: const [
          ButtonSegment(
            value: 'metric',
            label: Text('Metric', key: OnboardingScreen.unitsMetricOptionKey),
            icon: Icon(Icons.straighten),
          ),
          ButtonSegment(
            value: 'imperial',
            label: Text(
              'Imperial',
              key: OnboardingScreen.unitsImperialOptionKey,
            ),
            icon: Icon(Icons.square_foot),
          ),
        ],
        selected: <String>{_selectedUnits},
        onSelectionChanged: (selection) {
          setState(() {
            _selectedUnits = selection.first;
          });
        },
      ),
    );
  }

  Widget _buildPrivacyStep() {
    final optionCards = <Widget>[];
    for (var index = 0; index < _visibilityOptions.length; index++) {
      final option = _visibilityOptions[index];
      optionCards.add(
        _VisibilityOptionCard(
          option: option,
          isSelected: _selectedVisibility == option.value,
          onSelected: () {
            setState(() {
              _selectedVisibility = option.value;
            });
          },
        ),
      );
      if (index < _visibilityOptions.length - 1) {
        optionCards.add(const SizedBox(height: 12));
      }
    }

    return _OnboardingStepScaffold(
      title: 'Default activity visibility',
      subtitle: 'Choose who can see your activities by default.',
      child: Column(children: optionCards),
    );
  }

  Future<void> _onContinuePressed(Profile profile) async {
    if (_isSubmitting) {
      return;
    }

    if (_currentPageIndex == _stepCount - 1) {
      await _submit(profile: profile, useDefaults: false);
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _skip() async {
    if (_isSubmitting) {
      return;
    }

    final profile = ref.read(profileProvider).asData?.value;
    if (profile == null) {
      return;
    }

    await _submit(profile: profile, useDefaults: true);
  }

  Future<void> _submit({
    required Profile profile,
    required bool useDefaults,
  }) async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = _buildProfilePayload(profile, useDefaults: useDefaults);
    try {
      await ref.read(profileProvider.notifier).updateProfile(payload);
    } on Exception {
      if (mounted) {
        _showCompletionFailureSnackBar();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showCompletionFailureSnackBar() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(_completionFailureMessage)));
  }

  Profile _buildProfilePayload(Profile profile, {required bool useDefaults}) {
    return profile.copyWith(
      preferredUnits: useDefaults ? _initialPreferredUnits : _selectedUnits,
      defaultActivityVisibility: useDefaults
          ? _defaultVisibility
          : _selectedVisibility,
      sportPreferences: useDefaults
          ? _defaultSportPreferences
          : _orderedSelectedSports(),
      onboardingCompleted: true,
    );
  }

  Future<void> _goToPreviousPage() async {
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _toggleSport(String sportId, bool selected) {
    final nextSelection = Set<String>.from(_selectedSports);
    if (selected) {
      nextSelection.add(sportId);
    } else {
      if (nextSelection.length == 1 && nextSelection.contains(sportId)) {
        return;
      }
      nextSelection.remove(sportId);
    }

    setState(() {
      _selectedSports = nextSelection;
    });
  }

  void _initializeSelections(Profile profile) {
    _initialPreferredUnits = profile.preferredUnits;
    _selectedUnits = profile.preferredUnits;
    _selectedVisibility = _defaultVisibility;
    _selectedSports = _normalizeSports(profile.sportPreferences).toSet();
    _initializedFromProfile = true;
  }

  List<String> _normalizeSports(List<String> sportPreferences) {
    final normalized = <String>[];
    for (final sportId in OnboardingScreen.sportOptions.keys) {
      if (sportPreferences.contains(sportId)) {
        normalized.add(sportId);
      }
    }

    if (normalized.isEmpty) {
      return _defaultSportPreferences;
    }
    return normalized;
  }

  List<String> _orderedSelectedSports() {
    return OnboardingScreen.sportOptions.keys
        .where(_selectedSports.contains)
        .toList(growable: false);
  }
}
