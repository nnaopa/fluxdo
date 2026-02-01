import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/discourse_service.dart';
import '../../services/message_bus_service.dart';
import '../../utils/time_utils.dart';
import '../discourse_providers.dart';
import 'message_bus_service_provider.dart';
import 'models.dart';

/// 话题频道监听器
/// 监听新回复和正在输入的用户
class TopicChannelNotifier extends Notifier<TopicChannelState> {
  TopicChannelNotifier(this.topicId);
  final int topicId;
  
  @override
  TopicChannelState build() {
    final messageBus = ref.watch(messageBusServiceProvider);
    final service = ref.watch(discourseServiceProvider);
    final topicChannel = '/topic/$topicId';
    final presenceChannel = '/presence/discourse-presence/reply/$topicId';
    
    void onTopicMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is! Map<String, dynamic>) return;
      
      final type = data['type'] as String?;
      final postId = data['id'] as int?;
      final updatedAtStr = data['updated_at'] as String?;
      final updatedAt = TimeUtils.parseUtcTime(updatedAtStr) ?? DateTime.now();
      
      debugPrint('[TopicChannel] 收到消息: type=$type, postId=$postId');
      
      switch (type) {
        case 'created':
          state = state.copyWith(hasNewReplies: true);
          _tryLoadNewReplies(topicId);
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.created, updatedAt);
          }
          break;
          
        case 'revised':
        case 'rebaked':
          if (postId != null) {
            final msgType = type == 'revised' 
                ? TopicMessageType.revised 
                : TopicMessageType.rebaked;
            _addPostUpdate(postId, msgType, updatedAt);
            _triggerPostRefresh(topicId, postId);
          }
          break;
          
        case 'deleted':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.deleted, updatedAt);
            _triggerPostDeleted(topicId, postId, permanent: false);
          }
          break;
          
        case 'destroyed':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.destroyed, updatedAt);
            _triggerPostDeleted(topicId, postId, permanent: true);
          }
          break;
          
        case 'recovered':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.recovered, updatedAt);
            _triggerPostRecovered(topicId, postId);
          }
          break;
          
        case 'acted':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.acted, updatedAt);
            _triggerPostRefresh(topicId, postId, preserveCooked: true);
          }
          break;
          
        case 'liked':
        case 'unliked':
          if (postId != null) {
            final likesCount = data['likes_count'] as int?;
            final userId = data['user_id'] as int?;
            final msgType = type == 'liked' 
                ? TopicMessageType.liked 
                : TopicMessageType.unliked;
            _addPostUpdate(
              postId, 
              msgType, 
              updatedAt,
              likesCount: likesCount,
              userId: userId,
            );
            _triggerLikeUpdate(topicId, postId, likesCount, userId, isLiked: type == 'liked');
          }
          break;
          
        case 'read':
          if (postId != null) {
            final readersCount = data['readers_count'] as int?;
            _addPostUpdate(
              postId, 
              TopicMessageType.read, 
              updatedAt,
              readersCount: readersCount,
            );
          }
          break;
          
        case 'stats':
          final postsCount = data['posts_count'] as int?;
          final likeCount = data['like_count'] as int?;
          final lastPostedAtStr = data['last_posted_at'] as String?;
          final lastPostedAt = TimeUtils.parseUtcTime(lastPostedAtStr);
          
          state = state.copyWith(
            statsUpdate: TopicStatsUpdate(
              postsCount: postsCount,
              likeCount: likeCount,
              lastPostedAt: lastPostedAt,
            ),
          );
          break;
          
        case 'move_to_inbox':
          state = state.copyWith(messageArchived: false);
          break;
          
        case 'archived':
          state = state.copyWith(messageArchived: true);
          break;
          
        case 'remove_allowed_user':
          debugPrint('[TopicChannel] 用户被移出私信');
          break;
          
        default:
          debugPrint('[TopicChannel] 未知消息类型: $type');
      }
    }
    
    void onPresenceMessage(MessageBusMessage message) {
      final data = message.data;
      debugPrint('[Presence] 收到消息: $data');
      
      if (data is! Map<String, dynamic>) return;
      
      // 获取当前用户 ID，用于过滤掉自己
      final currentUser = ref.read(currentUserProvider).value;
      final currentUserId = currentUser?.id;
      
      final currentUsers = List<TypingUser>.from(state.typingUsers);
      bool changed = false;
      
      final enteringUsersList = data['entering_users'] as List<dynamic>?;
      if (enteringUsersList != null) {
        for (final u in enteringUsersList) {
          final userMap = u as Map<String, dynamic>;
          final user = TypingUser(
            id: userMap['id'] as int? ?? 0,
            username: userMap['username'] as String? ?? '',
            avatarTemplate: userMap['avatar_template'] as String? ?? '',
          );
          
          // 过滤掉当前用户自己
          if (user.username.isNotEmpty && user.id > 0 && user.id != currentUserId) {
            if (!currentUsers.any((element) => element.id == user.id)) {
              currentUsers.add(user);
              changed = true;
            }
          }
        }
      }
      
      final leavingUserIds = data['leaving_user_ids'] as List<dynamic>?;
      if (leavingUserIds != null) {
        for (final id in leavingUserIds) {
          if (id is int) {
            final beforeCount = currentUsers.length;
            currentUsers.removeWhere((u) => u.id == id);
            if (currentUsers.length != beforeCount) {
              changed = true;
            }
          }
        }
      }
      
      if (changed) {
        state = state.copyWith(typingUsers: currentUsers);
      }
    }
    
    messageBus.subscribe(topicChannel, onTopicMessage);
    messageBus.subscribe(presenceChannel, onPresenceMessage);

    // 异步加载初始 presence 状态
    _loadInitialPresence(service, messageBus, presenceChannel, topicId, onPresenceMessage);

    ref.onDispose(() {
      messageBus.unsubscribe(topicChannel, onTopicMessage);
      messageBus.unsubscribe(presenceChannel, onPresenceMessage);
    });

    return const TopicChannelState();
  }

  Future<void> _loadInitialPresence(
    DiscourseService service,
    MessageBusService messageBus,
    String presenceChannel,
    int topicId,
    void Function(MessageBusMessage) onMessage,
  ) async {
    try {
      final presence = await service.getPresence(topicId);
      debugPrint('[Presence] 初始状态: users=${presence.users.length}, messageId=${presence.messageId}');

      // 过滤掉当前用户
      final currentUser = ref.read(currentUserProvider).value;
      final currentUserId = currentUser?.id;
      final filteredUsers = presence.users.where((u) => u.id != currentUserId).toList();

      state = state.copyWith(typingUsers: filteredUsers);

      // 更新订阅的 messageId，避免重复接收旧消息
      messageBus.unsubscribe(presenceChannel, onMessage);
      messageBus.subscribeWithMessageId(presenceChannel, onMessage, presence.messageId);
    } catch (e) {
      debugPrint('[Presence] 初始化失败: $e');
      // 订阅已经在 build() 中完成，这里不需要再次订阅
    }
  }
  
  void _tryLoadNewReplies(int topicId) {
    // 注意：这里只用 topicId 创建 params，因为 family provider 的 key 匹配
    // 需要和 topic_detail_page.dart 使用相同的 params 结构
    // TODO: 考虑使用只含 topicId 的 key 或者通过其他方式同步
    final params = TopicDetailParams(topicId);
    try {
      final notifier = ref.read(topicDetailProvider(params).notifier);
      notifier.loadNewReplies();
      // 注意：不要在这里调用 clearNewReplies()，因为 loadNewReplies 是异步的
      // hasNewReplies 状态会在下次消息时被覆盖，或让 UI 层消费后清除
    } catch (e) {
      debugPrint('[TopicChannel] 尝试加载新回复失败: $e');
    }
  }
  
  void clearNewReplies() {
    state = state.copyWith(hasNewReplies: false);
  }
  
  void _addPostUpdate(
    int postId, 
    TopicMessageType type, 
    DateTime updatedAt, {
    int? likesCount,
    int? readersCount,
    int? userId,
  }) {
    final update = PostUpdate(
      postId: postId,
      type: type,
      updatedAt: updatedAt,
      likesCount: likesCount,
      readersCount: readersCount,
      userId: userId,
    );
    
    final updates = List<PostUpdate>.from(state.postUpdates);
    updates.add(update);
    if (updates.length > 50) {
      updates.removeAt(0);
    }
    
    state = state.copyWith(postUpdates: updates);
  }
  
  void _triggerPostRefresh(int topicId, int postId, {bool preserveCooked = false}) {
    final params = TopicDetailParams(topicId);
    try {
      final notifier = ref.read(topicDetailProvider(params).notifier);
      notifier.refreshPost(postId, preserveCooked: preserveCooked);
    } catch (e) {
      debugPrint('[TopicChannel] 刷新帖子失败: $e');
    }
  }
  
  void _triggerPostDeleted(int topicId, int postId, {required bool permanent}) {
    final params = TopicDetailParams(topicId);
    try {
      final notifier = ref.read(topicDetailProvider(params).notifier);
      if (permanent) {
        notifier.removePost(postId);
      } else {
        notifier.markPostDeleted(postId);
      }
    } catch (e) {
      debugPrint('[TopicChannel] 标记帖子删除失败: $e');
    }
  }
  
  void _triggerPostRecovered(int topicId, int postId) {
    final params = TopicDetailParams(topicId);
    try {
      final notifier = ref.read(topicDetailProvider(params).notifier);
      notifier.markPostRecovered(postId);
    } catch (e) {
      debugPrint('[TopicChannel] 标记帖子恢复失败: $e');
    }
  }
  
  void _triggerLikeUpdate(int topicId, int postId, int? likesCount, int? userId, {required bool isLiked}) {
    final params = TopicDetailParams(topicId);
    try {
      final notifier = ref.read(topicDetailProvider(params).notifier);
      notifier.updatePostLikes(postId, likesCount: likesCount);
    } catch (e) {
      debugPrint('[TopicChannel] 更新点赞失败: $e');
    }
  }
  
  void clearPostUpdates() {
    state = state.copyWith(postUpdates: []);
  }
  
  void clearStatsUpdate() {
    state = state.copyWith(clearStatsUpdate: true);
  }
  
  void clearTypingUsers() {
    state = state.copyWith(typingUsers: []);
  }
}

final topicChannelProvider = NotifierProvider.family.autoDispose<TopicChannelNotifier, TopicChannelState, int>(
  TopicChannelNotifier.new,
);
