part of 'discourse_service.dart';

/// 工具方法
mixin _UtilsMixin on _DiscourseServiceBase {
  /// 获取所有表情列表
  Future<Map<String, List<Emoji>>> getEmojis() async {
    try {
      final response = await _dio.get('/emojis.json');
      final data = response.data as Map<String, dynamic>;

      final Map<String, List<Emoji>> emojiGroups = {};

      data.forEach((group, emojis) {
        if (emojis is List) {
          emojiGroups[group] = emojis
              .map((e) => Emoji.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      });

      return emojiGroups;
    } catch (e) {
      if (e is DioException) {
        throw _handleDioError(e);
      }
      rethrow;
    }
  }

  /// 获取可用的回应表情列表
  Future<List<String>> getEnabledReactions() async {
    final preloaded = PreloadedDataService();
    return preloaded.getEnabledReactions();
  }

  /// 创建私信
  Future<int> createPrivateMessage({
    required List<String> targetUsernames,
    required String title,
    required String raw,
  }) async {
    try {
      final data = <String, dynamic>{
        'title': title,
        'raw': raw,
        'archetype': 'private_message',
        'target_recipients': targetUsernames.join(','),
      };

      final response = await _dio.post(
        '/posts.json',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final respData = response.data;

      if (respData is Map && respData.containsKey('post') && respData['post']['topic_id'] != null) {
        return respData['post']['topic_id'] as int;
      }

      if (respData is Map && respData['topic_id'] != null) {
        return respData['topic_id'] as int;
      }

      if (respData is Map && respData['success'] == false) {
        throw Exception(respData['errors']?.toString() ?? '发送私信失败');
      }

      throw Exception('未知响应格式');
    } on DioException catch (e) {
      if (e.response?.data != null && e.response!.data is Map) {
        final data = e.response!.data as Map;
        if (data['errors'] != null) {
          throw Exception((data['errors'] as List).join('\n'));
        }
      }
      rethrow;
    }
  }

}
