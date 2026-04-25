// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_comments_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(commentsRepository)
const commentsRepositoryProvider = CommentsRepositoryProvider._();

final class CommentsRepositoryProvider
    extends
        $FunctionalProvider<
          CommentsRepository,
          CommentsRepository,
          CommentsRepository
        >
    with $Provider<CommentsRepository> {
  const CommentsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commentsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commentsRepositoryHash();

  @$internal
  @override
  $ProviderElement<CommentsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CommentsRepository create(Ref ref) {
    return commentsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommentsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommentsRepository>(value),
    );
  }
}

String _$commentsRepositoryHash() =>
    r'd18fc9190d2dda158666109858ffafbb5bcdd7c5';

@ProviderFor(activityComments)
const activityCommentsProvider = ActivityCommentsFamily._();

final class ActivityCommentsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ActivityComment>>,
          List<ActivityComment>,
          FutureOr<List<ActivityComment>>
        >
    with
        $FutureModifier<List<ActivityComment>>,
        $FutureProvider<List<ActivityComment>> {
  const ActivityCommentsProvider._({
    required ActivityCommentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'activityCommentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activityCommentsHash();

  @override
  String toString() {
    return r'activityCommentsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ActivityComment>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ActivityComment>> create(Ref ref) {
    final argument = this.argument as String;
    return activityComments(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityCommentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activityCommentsHash() => r'170543a2de0fc68f9ae224ab1b77638412ece631';

final class ActivityCommentsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ActivityComment>>, String> {
  const ActivityCommentsFamily._()
    : super(
        retry: null,
        name: r'activityCommentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ActivityCommentsProvider call(String activityId) =>
      ActivityCommentsProvider._(argument: activityId, from: this);

  @override
  String toString() => r'activityCommentsProvider';
}

/// Single mutation path for adding comments to an activity.

@ProviderFor(AddCommentController)
const addCommentControllerProvider = AddCommentControllerProvider._();

/// Single mutation path for adding comments to an activity.
final class AddCommentControllerProvider
    extends $AsyncNotifierProvider<AddCommentController, void> {
  /// Single mutation path for adding comments to an activity.
  const AddCommentControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'addCommentControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$addCommentControllerHash();

  @$internal
  @override
  AddCommentController create() => AddCommentController();
}

String _$addCommentControllerHash() =>
    r'a8009f4ad2473a7da5b27027c6bfd0a595a5bd60';

/// Single mutation path for adding comments to an activity.

abstract class _$AddCommentController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}

/// Single mutation path for deleting comments on an activity.

@ProviderFor(DeleteCommentController)
const deleteCommentControllerProvider = DeleteCommentControllerProvider._();

/// Single mutation path for deleting comments on an activity.
final class DeleteCommentControllerProvider
    extends $AsyncNotifierProvider<DeleteCommentController, void> {
  /// Single mutation path for deleting comments on an activity.
  const DeleteCommentControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteCommentControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteCommentControllerHash();

  @$internal
  @override
  DeleteCommentController create() => DeleteCommentController();
}

String _$deleteCommentControllerHash() =>
    r'f8b5122da2f4845cf0c8811a798c757eee355214';

/// Single mutation path for deleting comments on an activity.

abstract class _$DeleteCommentController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
