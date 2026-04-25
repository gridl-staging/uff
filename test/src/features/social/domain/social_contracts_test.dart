import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/data/comments_repository.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// ## Test Scenarios
/// - [positive] Domain value objects preserve equality/hash semantics for stable state comparisons.
/// - [positive] CommentsRepository contract routes load/add/delete calls through one seam.
/// - [edge] Social user summaries keep relationship metadata with nullable profile fields.
class _FakeCommentsRepository implements CommentsRepository {
  _FakeCommentsRepository({
    required this.seededComments,
    required this.createdComment,
  });

  final List<ActivityComment> seededComments;
  final ActivityComment createdComment;
  final List<String> loadCallActivityIds = <String>[];
  final List<String> addBodies = <String>[];
  final List<String> deletedCommentIds = <String>[];

  @override
  Future<List<ActivityComment>> loadActivityComments(String activityId) async {
    loadCallActivityIds.add(activityId);
    return seededComments;
  }

  @override
  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  }) async {
    addBodies.add(body);
    return createdComment;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deletedCommentIds.add(commentId);
  }
}

void main() {
  group('CommentAuthor', () {
    test('supports value equality for author attribution payload', () {
      const authorA = CommentAuthor(
        userId: '11111111-1111-1111-1111-111111111111',
        displayName: 'Taylor Runner',
        avatarUrl: 'https://cdn.example.com/avatar.png',
      );
      const authorB = CommentAuthor(
        userId: '11111111-1111-1111-1111-111111111111',
        displayName: 'Taylor Runner',
        avatarUrl: 'https://cdn.example.com/avatar.png',
      );

      expect(authorA, authorB);
      expect(authorA.hashCode, authorB.hashCode);
    });
  });

  group('ActivityComment', () {
    test('supports value equality for immutable comment rows', () {
      const author = CommentAuthor(
        userId: '11111111-1111-1111-1111-111111111111',
        displayName: 'Taylor Runner',
        avatarUrl: null,
      );
      final commentA = ActivityComment(
        commentId: 'comment-1',
        activityId: 'activity-1',
        author: author,
        body: 'Great run!',
        createdAt: DateTime.utc(2026, 3, 20, 12),
      );
      final commentB = ActivityComment(
        commentId: 'comment-1',
        activityId: 'activity-1',
        author: author,
        body: 'Great run!',
        createdAt: DateTime.utc(2026, 3, 20, 12),
      );

      expect(commentA, commentB);
      expect(commentA.hashCode, commentB.hashCode);
    });
  });

  group('CommentsRepository contract', () {
    test(
      'routes all Stage 3 comment reads and writes through one seam',
      () async {
        final seededComment = ActivityComment(
          commentId: 'comment-seeded',
          activityId: 'activity-1',
          author: const CommentAuthor(
            userId: 'owner-1',
            displayName: 'Owner',
            avatarUrl: null,
          ),
          body: 'Seeded comment',
          createdAt: DateTime.utc(2026, 3, 20, 11),
        );
        final createdComment = ActivityComment(
          commentId: 'comment-created',
          activityId: 'activity-1',
          author: const CommentAuthor(
            userId: 'viewer-1',
            displayName: 'Viewer',
            avatarUrl: null,
          ),
          body: 'New comment',
          createdAt: DateTime.utc(2026, 3, 20, 12),
        );
        final repository = _FakeCommentsRepository(
          seededComments: [seededComment],
          createdComment: createdComment,
        );

        final loaded = await repository.loadActivityComments('activity-1');
        final inserted = await repository.addComment(
          activityId: 'activity-1',
          body: 'New comment',
        );
        await repository.deleteComment(inserted.commentId);

        expect(loaded, [seededComment]);
        expect(inserted, createdComment);
        expect(repository.loadCallActivityIds, ['activity-1']);
        expect(repository.addBodies, ['New comment']);
        expect(repository.deletedCommentIds, ['comment-created']);
      },
    );
  });

  group('FollowRelationship', () {
    test('supports value equality for UUID keyed shape', () {
      const relationshipA = FollowRelationship(
        currentUserId: '11111111-1111-1111-1111-111111111111',
        targetUserId: '22222222-2222-2222-2222-222222222222',
        status: FollowRelationshipStatus.following,
        followId: '33333333-3333-3333-3333-333333333333',
      );
      const relationshipB = FollowRelationship(
        currentUserId: '11111111-1111-1111-1111-111111111111',
        targetUserId: '22222222-2222-2222-2222-222222222222',
        status: FollowRelationshipStatus.following,
        followId: '33333333-3333-3333-3333-333333333333',
      );

      expect(relationshipA, relationshipB);
      expect(relationshipA.hashCode, relationshipB.hashCode);
    });
  });

  group('SocialUserSummary', () {
    test('stores profile and relationship in one action-ready model', () {
      const summary = SocialUserSummary(
        userId: '22222222-2222-2222-2222-222222222222',
        displayName: 'Taylor Runner',
        avatarUrl: 'https://cdn.example.com/avatar.jpg',
        relationship: FollowRelationship(
          currentUserId: '11111111-1111-1111-1111-111111111111',
          targetUserId: '22222222-2222-2222-2222-222222222222',
          status: FollowRelationshipStatus.outgoingPending,
          followId: '33333333-3333-3333-3333-333333333333',
        ),
      );

      expect(summary.userId, '22222222-2222-2222-2222-222222222222');
      expect(summary.displayName, 'Taylor Runner');
      expect(
        summary.relationship.status,
        FollowRelationshipStatus.outgoingPending,
      );
      expect(
        summary.relationship.followId,
        '33333333-3333-3333-3333-333333333333',
      );
    });
  });

  group('RelationshipCounts', () {
    test('supports value equality for relationship counters', () {
      const countsA = RelationshipCounts(
        userId: '11111111-1111-1111-1111-111111111111',
        followers: 12,
        following: 9,
        pendingRequests: 3,
      );
      const countsB = RelationshipCounts(
        userId: '11111111-1111-1111-1111-111111111111',
        followers: 12,
        following: 9,
        pendingRequests: 3,
      );

      expect(countsA, countsB);
      expect(countsA.hashCode, countsB.hashCode);
    });
  });
}
