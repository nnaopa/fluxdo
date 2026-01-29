import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:gal/gal.dart';
import '../services/discourse_cache_manager.dart';
import '../utils/double_tap_zoom_controller.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/common/loading_spinner.dart';

class ImageViewerPage extends StatefulWidget {
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? heroTag;
  final List<String>? galleryImages;
  final int initialIndex;
  final bool enableShare;

  const ImageViewerPage({
    super.key,
    this.imageUrl,
    this.imageBytes,
    this.heroTag,
    this.galleryImages,
    this.initialIndex = 0,
    this.enableShare = false,
  }) : assert(imageUrl != null || imageBytes != null);

  /// 使用透明路由打开图片查看器
  static void open(
    BuildContext context,
    String imageUrl, {
    String? heroTag,
    List<String>? galleryImages,
    int initialIndex = 0,
    bool enableShare = false,
  }) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageViewerPage(
            imageUrl: imageUrl,
            heroTag: heroTag,
            galleryImages: galleryImages,
            initialIndex: initialIndex,
            enableShare: enableShare,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// 打开内存图片查看器
  static void openBytes(BuildContext context, Uint8List bytes) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageViewerPage(imageBytes: bytes);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with TickerProviderStateMixin, DoubleTapZoomMixin {
  late int currentIndex;
  bool _isSaving = false;
  bool _isSharing = false;
  final DiscourseCacheManager _cacheManager = DiscourseCacheManager();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    // 初始化双击缩放
    initDoubleTapZoom();
    // 预加载相邻图片
    _preloadAdjacentImages();
  }

  @override
  void dispose() {
    disposeDoubleTapZoom();
    super.dispose();
  }

  /// 预加载相邻图片
  void _preloadAdjacentImages() {
    final images = widget.galleryImages;
    if (images == null || images.length <= 1) return;

    final preloadUrls = <String>[];
    // 预加载前一张和后一张
    if (currentIndex > 0) {
      preloadUrls.add(images[currentIndex - 1]);
    }
    if (currentIndex < images.length - 1) {
      preloadUrls.add(images[currentIndex + 1]);
    }
    _cacheManager.preloadImages(preloadUrls);
  }

  /// 获取当前显示的图片 URL
  String get _currentImageUrl {
    final images = widget.galleryImages ?? [widget.imageUrl!];
    return images[currentIndex];
  }

  /// 保存当前图片到相册
  Future<void> _saveCurrentImage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // 检查权限
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请授予相册访问权限')),
            );
          }
          return;
        }
      }

      // 使用缓存管理器获取图片字节（优先从缓存读取）
      final imageUrl = _currentImageUrl;
      final Uint8List? imageBytes = await _cacheManager.getImageBytes(imageUrl);

      if (imageBytes == null || imageBytes.isEmpty) {
        throw Exception('获取图片失败');
      }

      // 使用 putImageBytes 直接保存字节数据到相册
      final ext = _getExtensionFromUrl(imageUrl);
      await Gal.putImageBytes(imageBytes, name: 'fluxdo_${DateTime.now().millisecondsSinceEpoch}.$ext');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图片已保存到相册'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: ${e.type.message}')),
        );
      }
    } catch (e) {
      debugPrint('Save image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 保存内存图片到相册
  Future<void> _saveMemoryImage() async {
    if (_isSaving || widget.imageBytes == null) return;
    setState(() => _isSaving = true);
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请授予相册访问权限')));
        return;
      }
      await Gal.putImageBytes(widget.imageBytes!, name: 'fluxdo_${DateTime.now().millisecondsSinceEpoch}.png');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片已保存到相册'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 从 URL 中获取文件扩展名
  String _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final lastDot = path.lastIndexOf('.');
      if (lastDot != -1 && lastDot < path.length - 1) {
        return path.substring(lastDot + 1).toLowerCase();
      }
    } catch (_) {}
    return 'jpg'; // 默认返回 jpg
  }

  /// 分享当前图片
  Future<void> _shareImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      final imageUrl = _currentImageUrl;
      // 获取缓存文件（如果不存在会自动下载）
      final file = await _cacheManager.getSingleFile(imageUrl);
      
      // 分享文件
      final xFile = XFile(file.path, mimeType: 'image/${_getExtensionFromUrl(imageUrl)}');
      await Share.shareXFiles([xFile], text: imageUrl);
    } catch (e) {
      debugPrint('Share image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享失败，请重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 内存图片模式
    if (widget.imageBytes != null) {
      return ExtendedImageSlidePage(
        slideAxis: SlideAxis.both,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: (Offset offset, Size pageSize) {
          double progress = offset.distance / (pageSize.height);
          return Colors.black.withOpacity((1.0 - progress).clamp(0.0, 1.0));
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              ExtendedImage.memory(
                widget.imageBytes!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                mode: ExtendedImageMode.gesture,
                enableSlideOutPage: true,
                initGestureConfigHandler: (state) => GestureConfig(
                  minScale: 0.9, animationMinScale: 0.7, maxScale: 5.0, animationMaxScale: 5.5,
                  speed: 1.0, inertialSpeed: 500.0, initialScale: 1.0, inPageView: false,
                ),
                onDoubleTap: (state) => handleDoubleTapZoom(state),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: _isSaving
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                      : IconButton(icon: const Icon(Icons.save_alt, color: Colors.white), onPressed: _saveMemoryImage),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final images = widget.galleryImages ?? [widget.imageUrl!];
    final bool isGallery = images.length > 1;

    return ExtendedImageSlidePage(
      slideAxis: SlideAxis.both,
      slideType: SlideType.onlyImage,
      // 只处理背景透明度，不干预关闭逻辑，让库自己处理 pop
      slidePageBackgroundHandler: (Offset offset, Size pageSize) {
        double progress = offset.distance / (pageSize.height);
        return Colors.black.withOpacity((1.0 - progress).clamp(0.0, 1.0));
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            if (!isGallery)
              // 单图模式：使用最简结构，避免 PageView 带来的空白/手势问题
              ExtendedImage(
                image: discourseImageProvider(widget.imageUrl!),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                mode: ExtendedImageMode.gesture,
                enableSlideOutPage: true,
                heroBuilderForSlidingPage: widget.heroTag != null
                    ? (child) => Hero(tag: widget.heroTag!, child: child)
                    : null,
                initGestureConfigHandler: (state) {
                  return GestureConfig(
                    minScale: 0.9,
                    animationMinScale: 0.7,
                    maxScale: 4.0,
                    animationMaxScale: 4.5,
                    speed: 1.0,
                    inertialSpeed: 500.0,
                    initialScale: 1.0,
                    inPageView: false,
                    initialAlignment: InitialAlignment.center,
                  );
                },
                onDoubleTap: (state) => handleDoubleTapZoom(state, imageUrl: widget.imageUrl),
                loadStateChanged: (state) {
                  // 缓存图片尺寸用于智能缩放
                  if (state.extendedImageLoadState == LoadState.completed) {
                    final imageInfo = state.extendedImageInfo;
                    if (imageInfo != null && widget.imageUrl != null) {
                      cacheImageSize(widget.imageUrl!, Size(
                        imageInfo.image.width.toDouble(),
                        imageInfo.image.height.toDouble(),
                      ));
                    }
                  }
                  return null;
                },
              )
            else
              // 画廊模式：使用 ExtendedImageGesturePageView 支持滑动切换
              ExtendedImageGesturePageView.builder(
                itemCount: images.length,
                physics: const BouncingScrollPhysics(),
                controller: ExtendedPageController(
                  initialPage: widget.initialIndex,
                  pageSpacing: 50,
                ),
                onPageChanged: (index) {
                  setState(() {
                    currentIndex = index;
                  });
                  // 预加载相邻图片
                  _preloadAdjacentImages();
                },
                itemBuilder: (context, index) {
                  final url = images[index];
                  // 仅当当前显示的图片是初始进入的图片时，才使用 Hero 动画
                  // 因为其他图片在列表中的 Hero Tag 是未知的 (UniqueKey)
                  final shouldUseHero = index == widget.initialIndex && widget.heroTag != null;

                  return ExtendedImage(
                    image: discourseImageProvider(url),
                    mode: ExtendedImageMode.gesture,
                    enableSlideOutPage: true,
                    heroBuilderForSlidingPage: shouldUseHero
                        ? (child) => Hero(tag: widget.heroTag!, child: child)
                        : null,
                    initGestureConfigHandler: (state) {
                      return GestureConfig(
                        minScale: 0.9,
                        animationMinScale: 0.7,
                        maxScale: 4.0,
                        animationMaxScale: 4.5,
                        speed: 1.0,
                        inertialSpeed: 500.0,
                        initialScale: 1.0,
                        inPageView: true, // 必须为 true
                        initialAlignment: InitialAlignment.center,
                      );
                    },
                    onDoubleTap: (state) => handleDoubleTapZoom(state, imageUrl: url),
                    loadStateChanged: (state) {
                      if (state.extendedImageLoadState == LoadState.loading) {
                        return const Center(child: LoadingSpinner());
                      }
                      // 缓存图片尺寸用于智能缩放
                      if (state.extendedImageLoadState == LoadState.completed) {
                        final imageInfo = state.extendedImageInfo;
                        if (imageInfo != null) {
                          cacheImageSize(url, Size(
                            imageInfo.image.width.toDouble(),
                            imageInfo.image.height.toDouble(),
                          ));
                        }
                      }
                      return null;
                    },
                  );
                },
              ),

            // 顶部指示器 (仅画廊模式)
            if (isGallery)
              Positioned(
                top: MediaQuery.of(context).padding.top + 15,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${currentIndex + 1} / ${images.length}",
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // Save button
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.save_alt, color: Colors.white),
                        onPressed: _saveCurrentImage,
                      ),
              ),
            ),

            // Share button
            if (widget.enableShare)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 70, // 保存按钮右侧 (20 + 40 + 10)
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: _isSharing
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.share, color: Colors.white),
                          onPressed: _shareImage,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
