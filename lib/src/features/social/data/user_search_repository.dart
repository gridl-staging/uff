import 'package:uff/src/features/social/domain/social_user_summary.dart';

// ignore: one_member_abstracts, kept as an interface to match repository DI pattern.
abstract interface class UserSearchRepository {
  Future<List<SocialUserSummary>> searchUsers(String query);
}
