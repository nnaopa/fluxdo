import 'package:dio/dio.dart';

import '../../toast_service.dart';
import '../exceptions/api_exception.dart';

/// 错误拦截器
/// 处理 429/502/503/504 错误，转换为自定义异常
/// 操作性请求（POST/PUT/DELETE/PATCH）默认显示错误提示
/// 可通过 extra['showErrorToast'] 或 extra['isSilent'] 手动控制
class ErrorInterceptor extends Interceptor {
  /// 操作性请求方法，默认显示错误提示
  static const _mutationMethods = {'POST', 'PUT', 'DELETE', 'PATCH'};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;
    final method = err.requestOptions.method.toUpperCase();
    final extra = err.requestOptions.extra;

    // 静默模式：不显示任何错误提示
    if (extra['isSilent'] == true) {
      handler.next(err);
      return;
    }

    // 判断是否显示错误提示：
    // 1. 如果 extra 中明确指定了 showErrorToast，使用指定的值
    // 2. 否则，操作性请求默认显示
    final showErrorToast = extra.containsKey('showErrorToast')
        ? extra['showErrorToast'] == true
        : _mutationMethods.contains(method);

    // 提取错误信息
    String? errorMessage;
    final data = err.response?.data;
    if (data is Map<String, dynamic>) {
      // Discourse API 错误格式
      errorMessage = data['error'] as String? ??
          (data['errors'] as List?)?.firstOrNull?.toString();
    }

    // 重试耗尽后抛出自定义异常供 UI 层处理
    if (statusCode == 429) {
      final retryAfter =
          int.tryParse(err.response?.headers.value('retry-after') ?? '');
      if (showErrorToast) {
        ToastService.showError(errorMessage ?? '请求过于频繁，请稍后再试');
      }
      throw RateLimitException(retryAfter);
    }
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      if (showErrorToast) {
        ToastService.showError(errorMessage ?? '服务器暂时不可用，请稍后再试');
      }
      throw ServerException(statusCode!);
    }

    // 其他错误
    if (showErrorToast) {
      if (errorMessage != null) {
        ToastService.showError(errorMessage);
      } else {
        // 通用错误提示
        final message = switch (statusCode) {
          400 => '请求参数错误',
          401 => '未登录或登录已过期',
          403 => '没有权限执行此操作',
          404 => '请求的资源不存在',
          422 => '请求无法处理',
          500 => '服务器内部错误',
          _ => '请求失败 ($statusCode)',
        };
        ToastService.showError(message);
      }
    }

    handler.next(err);
  }
}
