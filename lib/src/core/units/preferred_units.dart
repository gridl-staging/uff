import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';

const metricPreferredUnits = 'metric';
const imperialPreferredUnits = 'imperial';

bool usesImperialUnits(String? preferredUnits) {
  return preferredUnits == imperialPreferredUnits;
}

SplitUnit splitUnitForPreferredUnits(String? preferredUnits) {
  return usesImperialUnits(preferredUnits)
      ? SplitUnit.mile
      : SplitUnit.kilometer;
}
