import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/discourse_cache_manager.dart';
import '../../pages/image_viewer_page.dart';
import '../../utils/svg_utils.dart';

/// Discourse 图片组件
///
/// 基于 CachedNetworkImage，支持：
/// - 内存缓存 + 磁盘缓存
/// - SVG 图片渲染
/// - upload:// 短链接解析
/// - Cloudflare 鉴权
/// - 点击查看大图 (Lightbox)
class DiscourseImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool enableLightbox;
  final String? heroTag;
  final List<String> galleryImages;
  final int initialIndex;

  const DiscourseImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.enableLightbox = false,
    this.heroTag,
    this.galleryImages = const [],
    this.initialIndex = 0,
  });

  @override
  State<DiscourseImage> createState() => _DiscourseImageState();
}

class _DiscourseImageState extends State<DiscourseImage> {
  String? _resolvedUrl;
  bool _isLoading = true;
  bool _hasError = false;

  static final DiscourseCacheManager _cacheManager = DiscourseCacheManager();

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(DiscourseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl() async {
    if (!widget.url.startsWith('upload://')) {
      // 普通 URL，不需要解析
      if (mounted) {
        setState(() {
          _resolvedUrl = widget.url;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // 需要解析短链接
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final resolved = await DiscourseService().resolveShortUrl(widget.url);
      if (mounted) {
        setState(() {
          _resolvedUrl = resolved;
          _isLoading = false;
          _hasError = resolved == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  bool get _isSvg {
    if (_resolvedUrl == null) return false;
    final uri = Uri.tryParse(_resolvedUrl!);
    if (uri == null) return false;
    return uri.path.toLowerCase().endsWith('.svg');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return _buildPlaceholder(theme);
    }

    if (_hasError || _resolvedUrl == null) {
      return _buildErrorWidget(theme);
    }

    Widget imageWidget;
    if (_isSvg) {
      imageWidget = _buildSvgImage(theme);
    } else {
      imageWidget = _buildCachedImage(theme);
    }

    // Hero 动画
    if (widget.heroTag != null) {
      imageWidget = Hero(tag: widget.heroTag!, child: imageWidget);
    }

    // Lightbox
    if (widget.enableLightbox && !_isSvg) {
      return GestureDetector(
        onTap: _openLightbox,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildCachedImage(ThemeData theme) {
    return CachedNetworkImage(
      imageUrl: _resolvedUrl!,
      cacheManager: _cacheManager,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => _buildPlaceholder(theme),
      errorWidget: (context, url, error) => _buildErrorWidget(theme),
      // 优化内存占用
      memCacheWidth: widget.width != null
          ? (widget.width! * MediaQuery.of(context).devicePixelRatio).toInt()
          : null,
      memCacheHeight: widget.height != null
          ? (widget.height! * MediaQuery.of(context).devicePixelRatio).toInt()
          : null,
    );
  }

  Widget _buildSvgImage(ThemeData theme) {
    return FutureBuilder<File>(
      future: _cacheManager.getSingleFile(_resolvedUrl!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildPlaceholder(theme);
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildErrorWidget(theme);
        }

        return FutureBuilder<String>(
          future: snapshot.data!.readAsString(),
          builder: (context, svgSnapshot) {
            if (!svgSnapshot.hasData) {
              return _buildPlaceholder(theme);
            }

            var svgContent = svgSnapshot.data!;
            final svgWidth = _parseSvgDimension(svgContent, 'width');
            final svgHeight = _parseSvgDimension(svgContent, 'height');

            // 清理 SVG 使其能被 flutter_svg 正确渲染
            svgContent = SvgUtils.sanitize(svgContent);

            return SvgPicture.string(
              svgContent,
              width: widget.width ?? svgWidth,
              height: widget.height ?? svgHeight,
              fit: widget.fit,
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height ?? 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height ?? 60,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.outline,
          size: 24,
        ),
      ),
    );
  }

  void _openLightbox() {
    ImageViewerPage.open(
      context,
      _resolvedUrl!,
      heroTag: widget.heroTag,
      galleryImages: widget.galleryImages.isNotEmpty ? widget.galleryImages : null,
      initialIndex: widget.initialIndex,
      enableShare: true,
    );
  }

  /// 从 SVG 内容解析尺寸属性
  double? _parseSvgDimension(String svg, String attr) {
    final match = RegExp('$attr="(\\d+(?:\\.\\d+)?)"').firstMatch(svg);
    if (match != null) return double.tryParse(match.group(1)!);
    return null;
  }
}
