part of 'discourse_service.dart';

/// 上传相关
mixin _UploadsMixin on _DiscourseServiceBase {
  /// 获取图片请求头
  Future<Map<String, String>> getHeaders() async {
    final headers = <String, String>{
      'User-Agent': AppConstants.userAgent,
    };

    final cookies = await _cookieJar.getCookieHeader();
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }

    return headers;
  }

  /// 下载图片
  Future<Uint8List?> downloadImage(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          extra: {
            'skipCsrf': true,
            'skipAuthCheck': true,
          },
        ),
      );

      if (response.data is! List<int>) {
        debugPrint('[DiscourseService] Invalid response data type for image: $url');
        return null;
      }

      final bytes = Uint8List.fromList(response.data);

      if (bytes.isEmpty) {
        debugPrint('[DiscourseService] Empty image data: $url');
        return null;
      }

      final contentType = response.headers.value('content-type')?.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) {
        debugPrint('[DiscourseService] Invalid content-type for image: $contentType, url: $url');
        return null;
      }

      if (!_isValidImageData(bytes)) {
        debugPrint('[DiscourseService] Invalid image data (magic bytes check failed): $url');
        return null;
      }

      return bytes;
    } catch (e) {
      debugPrint('[DiscourseService] Download image failed: $e, url: $url');
      return null;
    }
  }

  /// 验证图片数据是否有效
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }

    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      return true;
    }

    // WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }

    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true;
    }

    // ICO
    if (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01 && bytes[3] == 0x00) {
      return true;
    }

    return false;
  }

  /// 上传图片
  Future<String> uploadImage(String filePath) async {
    try {
      final fileName = filePath.split('/').last;

      final formData = FormData.fromMap({
        'upload_type': 'composer',
        'synchronous': true,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        '/uploads.json',
        queryParameters: {'client_id': MessageBusService().clientId},
        data: formData,
      );

      final data = response.data;
      if (data is Map) {
        if (data['short_url'] != null) {
          return data['short_url'];
        }
        if (data['url'] != null) {
          return data['url'];
        }
      }

      throw Exception('上传响应中未包含 URL');
    } on DioException catch (e) {
      debugPrint('[DiscourseService] Upload image failed: $e');
      if (e.response?.statusCode == 413) {
        throw Exception('图片文件过大，请压缩后重试');
      }
      if (e.response?.statusCode == 422) {
        final data = e.response?.data;
        if (data is Map && data['errors'] != null) {
          throw Exception((data['errors'] as List).join('\n'));
        }
        throw Exception('图片格式不支持或不符合要求');
      }
      rethrow;
    } catch (e) {
      debugPrint('[DiscourseService] Upload image failed: $e');
      rethrow;
    }
  }

  /// 批量解析 short_url
  Future<List<Map<String, dynamic>>> lookupUrls(List<String> shortUrls) async {
    final missingUrls = shortUrls.where((url) => !_urlCache.containsKey(url)).toList();

    if (missingUrls.isEmpty) return [];

    try {
      final response = await _dio.post(
        '/uploads/lookup-urls',
        data: {'short_urls': missingUrls},
      );

      final List<dynamic> uploads = response.data;
      final result = <Map<String, dynamic>>[];

      for (final item in uploads) {
        if (item is Map<String, dynamic>) {
          result.add(item);
          if (item['short_url'] != null && item['url'] != null) {
            _urlCache[item['short_url']] = item['url'];
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('[DiscourseService] lookupUrls failed: $e');
      return [];
    }
  }

  /// 解析单个 short_url
  Future<String?> resolveShortUrl(String shortUrl) async {
    if (!shortUrl.startsWith('upload://')) return shortUrl;

    if (_urlCache.containsKey(shortUrl)) {
      return _urlCache[shortUrl];
    }

    await lookupUrls([shortUrl]);
    return _urlCache[shortUrl];
  }
}
