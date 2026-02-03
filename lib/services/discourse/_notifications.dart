part of 'discourse_service.dart';

/// 通知相关
mixin _NotificationsMixin on _DiscourseServiceBase {
  /// 获取通知列表
  Future<NotificationListResponse> getNotifications({int? offset}) async {
    final queryParams = <String, dynamic>{
      'limit': 30,
      'recent': true,
      'bump_last_seen_reviewable': true,
    };
    if (offset != null) {
      queryParams['offset'] = offset;
    }

    final response = await _dio.get(
      '/notifications',
      queryParameters: queryParams,
    );
    return NotificationListResponse.fromJson(response.data);
  }

  /// 标记所有通知为已读
  Future<void> markAllNotificationsRead() async {
    await _dio.put('/notifications/mark-read');
  }

  /// 标记单条通知为已读
  Future<void> markNotificationRead(int id) async {
    await _dio.put('/notifications/mark-read', data: {'id': id});
  }
}
