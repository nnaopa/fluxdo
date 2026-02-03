import 'dart:async';
import 'package:flutter/foundation.dart';
import 'discourse/discourse_service.dart';

/// Presence 状态管理服务
/// 用于在用户输入回复时通知服务器"正在输入"状态
class PresenceService {
  final DiscourseService _service;
  
  // 当前活跃的频道
  final Set<String> _activeChannels = {};
  
  // 定时刷新计时器（每 30 秒发送一次心跳）
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 30);
  
  // 防抖计时器
  Timer? _debounceTimer;
  static const _debounceDelay = Duration(milliseconds: 500);
  
  PresenceService(this._service);
  
  /// 进入回复频道
  void enterReplyChannel(int topicId) {
    final channel = '/discourse-presence/reply/$topicId';
    if (_activeChannels.contains(channel)) return;
    
    debugPrint('[PresenceService] 进入频道: $channel');
    _activeChannels.add(channel);
    _debouncedUpdate();
    _startHeartbeat();
  }
  
  /// 离开回复频道
  void leaveReplyChannel(int topicId) {
    final channel = '/discourse-presence/reply/$topicId';
    if (!_activeChannels.contains(channel)) return;
    
    debugPrint('[PresenceService] 离开频道: $channel');
    _activeChannels.remove(channel);
    _updatePresence(leaveChannels: [channel]);
    
    if (_activeChannels.isEmpty) {
      _stopHeartbeat();
    }
  }
  
  /// 防抖更新
  void _debouncedUpdate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      _updatePresence(presentChannels: _activeChannels.toList());
    });
  }
  
  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_activeChannels.isNotEmpty) {
        debugPrint('[PresenceService] 心跳: ${_activeChannels.length} 个频道');
        _updatePresence(presentChannels: _activeChannels.toList());
      }
    });
  }
  
  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// 发送更新请求
  Future<void> _updatePresence({
    List<String>? presentChannels,
    List<String>? leaveChannels,
  }) async {
    try {
      await _service.updatePresence(
        presentChannels: presentChannels,
        leaveChannels: leaveChannels,
      );
    } catch (e) {
      debugPrint('[PresenceService] Update failed: $e');
    }
  }
  
  /// 释放资源
  void dispose() {
    debugPrint('[PresenceService] 释放资源');
    _debounceTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    // 离开所有频道
    if (_activeChannels.isNotEmpty) {
      _updatePresence(leaveChannels: _activeChannels.toList());
      _activeChannels.clear();
    }
  }
}
