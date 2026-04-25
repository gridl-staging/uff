part of 'onboarding_screen.dart';

/// NOTE(stuart): Document _OnboardingStepScaffold.
class _OnboardingStepScaffold extends StatelessWidget {
  const _OnboardingStepScaffold({
    required this.title,
    required this.subtitle,
    this.child,
  });

  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandHeader(),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(subtitle),
          if (child != null) ...[const SizedBox(height: 16), child!],
        ],
      ),
    );
  }
}

/// NOTE(stuart): Document _VisibilityOption.
class _VisibilityOption {
  const _VisibilityOption({
    required this.optionKey,
    required this.checkKey,
    required this.title,
    required this.description,
    required this.value,
    required this.icon,
  });

  final Key optionKey;
  final Key checkKey;
  final String title;
  final String description;
  final String value;
  final IconData icon;
}

/// NOTE(stuart): Document _VisibilityOptionCard.
class _VisibilityOptionCard extends StatelessWidget {
  const _VisibilityOptionCard({
    required this.option,
    required this.isSelected,
    required this.onSelected,
  });

  final _VisibilityOption option;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: option.optionKey,
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).cardColor,
          ),
          child: Row(
            children: [
              Icon(option.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(option.description),
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.check_circle, key: option.checkKey),
            ],
          ),
        ),
      ),
    );
  }
}
