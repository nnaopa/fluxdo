import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../../models/topic.dart';
import '../../../providers/message_bus_providers.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/post/post_item.dart';
import '../../../widgets/post/post_item_skeleton.dart';
import 'topic_detail_header.dart';
import 'typing_indicator.dart';

/// 话题帖子列表
/// 负责构建 CustomScrollView 及其 Slivers
class TopicPostList extends StatelessWidget {
  final TopicDetail detail;
  final AutoScrollController scrollController;
  final GlobalKey centerKey;
  final GlobalKey headerKey;
  final int? highlightPostNumber;
  final List<TypingUser> typingUsers;
  final bool isLoggedIn;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final bool isLoadingPrevious;
  final bool isLoadingMore;
  final int centerPostIndex;
  final int? dividerPostIndex;
  final void Function(int postNumber, bool isVisible) onPostVisibilityChanged;
  final void Function(int postNumber) onJumpToPost;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post post) onEdit; // 编辑回调
  final void Function(int, bool) onVoteChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final void Function(int postId, bool accepted)? onSolutionChanged; // 解决方案状态变化
  final bool Function(ScrollNotification) onScrollNotification;

  const TopicPostList({
    super.key,
    required this.detail,
    required this.scrollController,
    required this.centerKey,
    required this.headerKey,
    required this.highlightPostNumber,
    required this.typingUsers,
    required this.isLoggedIn,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.isLoadingPrevious,
    required this.isLoadingMore,
    required this.centerPostIndex,
    required this.dividerPostIndex,
    required this.onPostVisibilityChanged,
    required this.onJumpToPost,
    required this.onReply,
    required this.onEdit,
    required this.onVoteChanged,
    this.onNotificationLevelChanged,
    this.onSolutionChanged,
    required this.onScrollNotification,
  });

  /// 在大屏上为内容添加宽度约束
  Widget _wrapContent(BuildContext context, Widget child) {
    if (Responsive.isMobile(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posts = detail.postStream.posts;
    final hasFirstPost = posts.isNotEmpty && posts.first.postNumber == 1;

    // 计算增量加载时的骨架屏数量（基于屏幕高度的 40%）
    final loadMoreSkeletonCount = calculateSkeletonCount(
      MediaQuery.of(context).size.height * 0.4,
      minCount: 2,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: CustomScrollView(
        controller: scrollController,
        center: centerKey,
        cacheExtent: 500,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          // 向上加载的 loading 指示器 - 显示骨架屏
          if (hasMoreBefore && isLoadingPrevious)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _wrapContent(context, const PostItemSkeleton()),
                childCount: loadMoreSkeletonCount,
              ),
            ),
          // 向上的内容（反向）
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 头部信息
                if (hasFirstPost && centerPostIndex > 0 && index == centerPostIndex) {
                  return _wrapContent(
                    context,
                    TopicDetailHeader(
                      detail: detail,
                      headerKey: headerKey,
                      onVoteChanged: onVoteChanged,
                      onNotificationLevelChanged: onNotificationLevelChanged,
                    ),
                  );
                }

                final postIndex = centerPostIndex - 1 - index;
                if (postIndex < 0) return null;

                final post = posts[postIndex];

                return _wrapContent(
                  context,
                  AutoScrollTag(
                    key: ValueKey('post-${post.postNumber}'),
                    controller: scrollController,
                    index: postIndex,
                    child: PostItem(
                      post: post,
                      topicId: detail.id,
                      highlight: highlightPostNumber == post.postNumber,
                      isTopicOwner: detail.createdBy?.username == post.username,
                      topicHasAcceptedAnswer: detail.hasAcceptedAnswer,
                      acceptedAnswerPostNumber: detail.acceptedAnswerPostNumber,
                      onLike: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('点赞功能开发中...')),
                      ),
                      onReply: isLoggedIn ? () => onReply(post) : null,
                      onEdit: isLoggedIn && post.canEdit ? () => onEdit(post) : null,
                      onJumpToPost: onJumpToPost,
                      onSolutionChanged: onSolutionChanged,
                      onVisibilityChanged: (isVisible) =>
                          onPostVisibilityChanged(post.postNumber, isVisible),
                    ),
                  ),
                );
              },
              childCount: centerPostIndex + (hasFirstPost && centerPostIndex > 0 ? 1 : 0),
            ),
          ),

          // 中心点及向下的内容（包含头部信息，仅当从头开始加载时）
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 头部信息
                if (hasFirstPost && centerPostIndex == 0 && index == 0) {
                  return _wrapContent(
                    context,
                    TopicDetailHeader(
                      detail: detail,
                      headerKey: headerKey,
                      onVoteChanged: onVoteChanged,
                      onNotificationLevelChanged: onNotificationLevelChanged,
                    ),
                  );
                }

                final headerOffset = (hasFirstPost && centerPostIndex == 0) ? 1 : 0;
                final adjustedIndex = centerPostIndex + index - headerOffset;

                if (adjustedIndex >= posts.length) {
                  // 底部 Loading（如果还有更多数据要加载）- 显示骨架屏
                  if (hasMoreAfter && isLoadingMore) {
                    final skeletonIndex = adjustedIndex - posts.length;
                    if (skeletonIndex < loadMoreSkeletonCount) {
                      return _wrapContent(context, const PostItemSkeleton());
                    }
                    return null;
                  }

                  // 只有在没有更多数据时，才显示正在输入
                  if (typingUsers.isNotEmpty && !hasMoreAfter) {
                    if (adjustedIndex == posts.length) {
                      return _wrapContent(context, TypingAvatars(users: typingUsers));
                    }
                  }

                  return null;
                }

                final post = posts[adjustedIndex];
                final showDivider = dividerPostIndex == adjustedIndex;

                return _wrapContent(
                  context,
                  AutoScrollTag(
                    key: ValueKey('post-${post.postNumber}'),
                    controller: scrollController,
                    index: adjustedIndex,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showDivider)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                            child: Text(
                              '上次看到这里',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        PostItem(
                          post: post,
                          topicId: detail.id,
                          highlight: highlightPostNumber == post.postNumber,
                          isTopicOwner: detail.createdBy?.username == post.username,
                          topicHasAcceptedAnswer: detail.hasAcceptedAnswer,
                          acceptedAnswerPostNumber: detail.acceptedAnswerPostNumber,
                          onLike: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('点赞功能开发中...')),
                          ),
                          onReply: isLoggedIn ? () => onReply(post) : null,
                          onEdit: isLoggedIn && post.canEdit ? () => onEdit(post) : null,
                          onJumpToPost: onJumpToPost,
                          onSolutionChanged: onSolutionChanged,
                          onVisibilityChanged: (isVisible) =>
                              onPostVisibilityChanged(post.postNumber, isVisible),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: posts.length -
                  centerPostIndex +
                  ((hasFirstPost && centerPostIndex == 0) ? 1 : 0) +
                  (hasMoreAfter && isLoadingMore ? loadMoreSkeletonCount : 0) +
                  (typingUsers.isNotEmpty && !hasMoreAfter ? 1 : 0),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: 80 + MediaQuery.of(context).padding.bottom),
          ),
        ],
      ),
    );
  }
}
