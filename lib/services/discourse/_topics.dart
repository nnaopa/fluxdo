part of 'discourse_service.dart';

/// 话题相关
mixin _TopicsMixin on _DiscourseServiceBase {
  Future<TopicListResponse> getLatestTopics({int page = 0}) async {
    if (page == 0) {
      final preloaded = PreloadedDataService();
      final preloadedList = await preloaded.getInitialTopicList();
      if (preloadedList != null) {
        return preloadedList;
      }
    }

    final response = await _dio.get(
      '/latest.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// 获取话题列表（支持分类和标签筛选）
  Future<TopicListResponse> getFilteredTopics({
    required String filter,
    int? categoryId,
    String? categorySlug,
    String? parentCategorySlug,
    List<String>? tags,
    int page = 0,
  }) async {
    String path;
    final queryParams = <String, dynamic>{};

    if (page > 0) {
      queryParams['page'] = page;
    }

    if (tags != null && tags.isNotEmpty) {
      queryParams['tags'] = tags.join(',');
    }

    if (categoryId != null && categorySlug != null) {
      if (parentCategorySlug != null) {
        path = '/c/$parentCategorySlug/$categorySlug/$categoryId/l/$filter.json';
      } else {
        path = '/c/$categorySlug/$categoryId/l/$filter.json';
      }
    } else if (tags != null && tags.isNotEmpty) {
      if (tags.length == 1) {
        path = '/tag/${tags.first}/l/$filter.json';
        queryParams.remove('tags');
      } else {
        path = '/tags/intersection/${tags.join('/')}/l/$filter.json';
        queryParams.remove('tags');
      }
    } else {
      path = '/$filter.json';
    }

    final response = await _dio.get(path, queryParameters: queryParams.isNotEmpty ? queryParams : null);
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getNewTopics({int page = 0}) async {
    final response = await _dio.get(
      '/new.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getUnreadTopics({int page = 0}) async {
    final response = await _dio.get(
      '/unread.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getHotTopics({int page = 0}) async {
    final response = await _dio.get(
      '/hot.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// 获取话题详情
  Future<TopicDetail> getTopicDetail(int id, {int? postNumber, bool trackVisit = false, String? filter, String? usernameFilters}) async {
    final path = postNumber != null ? '/t/$id/$postNumber.json' : '/t/$id.json';
    final queryParams = <String, dynamic>{};
    if (trackVisit) {
      queryParams['track_visit'] = true;
    }
    if (filter != null) {
      queryParams['filter'] = filter;
    }
    if (usernameFilters != null) {
      queryParams['username_filters'] = usernameFilters;
    }
    final response = await _dio.get(
      path,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicDetail.fromJson(response.data);
  }

  /// 批量获取帖子内容
  Future<PostStream> getPosts(int topicId, List<int> postIds) async {
    final response = await _dio.get(
      '/t/$topicId/posts.json',
      queryParameters: {
        'post_ids[]': postIds,
      },
    );
    final data = response.data as Map<String, dynamic>;
    if (data.containsKey('post_stream')) {
      return PostStream.fromJson(data['post_stream'] as Map<String, dynamic>);
    }
    return PostStream.fromJson(data);
  }

  /// 按帖子编号获取帖子
  Future<PostStream> getPostsByNumber(int topicId, {required int postNumber, required bool asc}) async {
    final response = await _dio.get(
      '/t/$topicId/posts.json',
      queryParameters: {
        'post_number': postNumber,
        'asc': asc,
      },
    );
    final data = response.data as Map<String, dynamic>;
    if (data.containsKey('post_stream')) {
      return PostStream.fromJson(data['post_stream'] as Map<String, dynamic>);
    }
    return PostStream.fromJson(data);
  }

  Future<TopicListResponse> getTopTopics() async {
    final response = await _dio.get('/top.json');
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getCategoryTopics(String categorySlug) async {
    final response = await _dio.get('/c/$categorySlug.json');
    return TopicListResponse.fromJson(response.data);
  }

  /// 创建话题
  Future<int> createTopic({
    required String title,
    required String raw,
    required int categoryId,
    List<String>? tags,
  }) async {
    try {
      final data = <String, dynamic>{
        'title': title,
        'raw': raw,
        'category': categoryId,
        'archetype': 'regular',
      };

      if (tags != null && tags.isNotEmpty) {
        data['tags[]'] = tags;
      }

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
        throw Exception(respData['errors']?.toString() ?? '创建话题失败');
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

  /// 设置话题订阅级别
  Future<void> setTopicNotificationLevel(int topicId, TopicNotificationLevel level) async {
    await _dio.post(
      '/t/$topicId/notifications',
      data: {'notification_level': level.value},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// 更新话题元数据
  Future<void> updateTopic({
    required int topicId,
    String? title,
    int? categoryId,
    List<String>? tags,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (categoryId != null) data['category_id'] = categoryId;
      if (tags != null) data['tags[]'] = tags;

      await _dio.put(
        '/t/-/$topicId.json',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取话题 AI 摘要
  Future<TopicSummary?> getTopicSummary(int topicId, {bool skipAgeCheck = false}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (skipAgeCheck) {
        queryParams['skip_age_check'] = 'true';
      }

      final response = await _dio.get(
        '/discourse-ai/summarization/t/$topicId',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final data = response.data;
      if (data is Map && data['ai_topic_summary'] != null) {
        return TopicSummary.fromJson(data['ai_topic_summary'] as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 403) {
        return null;
      }
      debugPrint('[DiscourseService] getTopicSummary failed: $e');
      rethrow;
    }
  }
}
