import 'package:meta/meta.dart';

/// Point-in-time PMC metrics for a single UTC calendar day.
@immutable
class PmcDay {
  const PmcDay({
    required this.date,
    required this.ctl,
    required this.atl,
    required this.tsb,
    required this.tssOnDay,
  });

  final DateTime date;
  final double ctl;
  final double atl;
  final double tsb;
  final double tssOnDay;
}
