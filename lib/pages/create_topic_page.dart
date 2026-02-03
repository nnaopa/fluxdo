import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/widgets/common/loading_spinner.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_toolbar.dart';
import 'package:fluxdo/models/category.dart';

import 'package:fluxdo/providers/discourse_providers.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';
import 'package:fluxdo/services/emoji_handler.dart';
import 'package:fluxdo/widgets/topic/topic_filter_sheet.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/widgets/mention/mention_autocomplete.dart';
import 'package:fluxdo/widgets/topic/topic_editor_helpers.dart';

class CreateTopicPage extends ConsumerStatefulWidget {
  const CreateTopicPage({super.key});

  @override
  ConsumerState<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends ConsumerState<CreateTopicPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _toolbarKey = GlobalKey<MarkdownToolbarState>();

  // 文本处理器
  final _smartListHandler = SmartListHandler();
  final _panguHandler = PanguSpacingHandler();

  Category? _selectedCategory;
  List<String> _selectedTags = [];
  bool _isSubmitting = false;
  bool _showPreview = false;
  String? _templateContent;

  final PageController _pageController = PageController();
  int _contentLength = 0;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_updateContentLength);
    _contentController.addListener(_handleContentTextChange);
    // 初始化 EmojiHandler 以支持预览
    EmojiHandler().init();
    // 从当前筛选条件自动填入分类和标签
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyCurrentFilter());
  }

  void _applyCurrentFilter() async {
    final filter = ref.read(topicFilterProvider);
    if (filter.tags.isNotEmpty) {
      setState(() => _selectedTags = List.from(filter.tags));
    }

    // 确定要选择的分类 ID：优先使用筛选条件中的，否则使用站点默认分类
    int? targetCategoryId = filter.categoryId;
    targetCategoryId ??= await PreloadedDataService().getDefaultComposerCategoryId();

    if (targetCategoryId != null && mounted) {
      // 监听 categories 加载完成
      ref.listenManual(categoriesProvider, (previous, next) {
        next.whenData((categories) {
          if (!mounted) return;
          final category = categories.where((c) => c.id == targetCategoryId).firstOrNull;
          if (category != null && category.canCreateTopic && _selectedCategory == null) {
            _onCategorySelected(category);
          }
        });
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _contentController.removeListener(_updateContentLength);
    _contentController.removeListener(_handleContentTextChange);
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _updateContentLength() {
    setState(() => _contentLength = _contentController.text.length);
  }

  void _handleContentTextChange() {
    // 智能列表续行
    if (_smartListHandler.handleTextChange(_contentController)) {
      return;
    }

    // 自动 Pangu 空格
    if (ref.read(preferencesProvider).autoPanguSpacing) {
      if (_panguHandler.autoApply(_contentController, _smartListHandler.updatePreviousText)) {
        return;
      }
    }

    _smartListHandler.updatePreviousText(_contentController.text);
  }

  void _applyPanguSpacing() {
    _panguHandler.manualApply(_contentController, _smartListHandler.updatePreviousText);
  }

  void _onCategorySelected(Category category) {
    setState(() => _selectedCategory = category);

    final currentContent = _contentController.text.trim();
    if (currentContent.isEmpty ||
        (_templateContent != null && currentContent == _templateContent!.trim())) {
      if (category.topicTemplate != null && category.topicTemplate!.isNotEmpty) {
        _contentController.text = category.topicTemplate!;
        _templateContent = category.topicTemplate;
      } else {
        _contentController.clear();
        _templateContent = null;
      }
    }
  }

  void _togglePreview() {
    if (_showPreview) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }

    if (_selectedCategory!.minimumRequiredTags > 0 &&
        _selectedTags.length < _selectedCategory!.minimumRequiredTags) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('此分类至少需要 ${_selectedCategory!.minimumRequiredTags} 个标签')),
      );
      return;
    }

    if (_templateContent != null &&
        _contentController.text.trim() == _templateContent!.trim()) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('您尚未修改分类模板内容，确定要发布吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定发布'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(discourseServiceProvider);
      final topicId = await service.createTopic(
        title: _titleController.text.trim(),
        raw: _contentController.text,
        categoryId: _selectedCategory!.id,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(topicId);
    } catch (_) {
      // 错误已由 ErrorInterceptor 处理
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final canTagTopics = ref.watch(canTagTopicsProvider).value ?? false;
    final theme = Theme.of(context);

    // 获取站点配置的最小长度
    final minTitleLength = ref.watch(minTopicTitleLengthProvider).value ?? 15;
    final minContentLength = ref.watch(minFirstPostLengthProvider).value ?? 20;

    final showEmojiPanel = _toolbarKey.currentState?.showEmojiPanel ?? false;

    return PopScope(
      canPop: !showEmojiPanel,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        _toolbarKey.currentState?.closeEmojiPanel();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('创建话题'),
          scrolledUnderElevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('发布'),
              ),
            ),
          ],
        ),
        body: categoriesAsync.when(
          data: (categories) {
            return Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _showPreview = index == 1;
                      });
                      if (_showPreview) {
                        FocusScope.of(context).unfocus();
                        _toolbarKey.currentState?.closeEmojiPanel();
                      }
                    },
                    children: [
                      // Page 0: 编辑模式
                      Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            // 标题输入
                            TextFormField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                hintText: '键入一个吸引人的标题...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.normal,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                              maxLines: null,
                              maxLength: 200,
                              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return '请输入标题';
                                if (value.trim().length < minTitleLength) return '标题至少需要 $minTitleLength 个字符';
                                return null;
                              },
                              onTap: () {
                                _toolbarKey.currentState?.closeEmojiPanel();
                              },
                            ),

                            const SizedBox(height: 16),

                            // 元数据区域 (分类 + 标签)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CategoryTrigger(
                                  category: _selectedCategory,
                                  categories: categories,
                                  onSelected: _onCategorySelected,
                                ),
                                if (canTagTopics) ...[
                                  const SizedBox(height: 12),
                                  tagsAsync.when(
                                    data: (tags) => TagsArea(
                                      selectedCategory: _selectedCategory,
                                      selectedTags: _selectedTags,
                                      allTags: tags,
                                      onTagsChanged: (newTags) => setState(() => _selectedTags = newTags),
                                    ),
                                    loading: () => const SizedBox.shrink(),
                                    error: (e, s) => const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 20),
                            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                            const SizedBox(height: 20),

                            // 内容区域
                            MentionAutocomplete(
                              controller: _contentController,
                              focusNode: _contentFocusNode,
                              dataSource: (term) => ref.read(discourseServiceProvider).searchUsers(
                                term: term,
                                categoryId: _selectedCategory?.id,
                                includeGroups: true,
                              ),
                              child: TextFormField(
                                controller: _contentController,
                                focusNode: _contentFocusNode,
                                maxLines: null,
                                minLines: 12,
                                decoration: InputDecoration(
                                  hintText: '正文内容 (支持 Markdown)...',
                                  border: InputBorder.none,
                                  helperText: _templateContent != null ? '已填充分类模板' : null,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.6,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return '请输入内容';
                                  if (value.trim().length < minContentLength) return '内容至少需要 $minContentLength 个字符';
                                  return null;
                                },
                                onTap: () {
                                  _toolbarKey.currentState?.closeEmojiPanel();
                                },
                              ),
                            ),
                            const SizedBox(height: 40),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$_contentLength 字符',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Page 1: 预览模式
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titleController.text.isEmpty ? '（无标题）' : _titleController.text,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_selectedCategory != null)
                                  CategoryTrigger(
                                    category: _selectedCategory,
                                    categories: categories,
                                    onSelected: _onCategorySelected,
                                  ),
                                PreviewTagsList(tags: _selectedTags),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Divider(height: 1),
                            ),
                            if (_contentController.text.isEmpty)
                              Text(
                                '（无内容）',
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              )
                            else
                              MarkdownBody(data: _contentController.text),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 底部工具栏区域
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: MarkdownToolbar(
                    key: _toolbarKey,
                    controller: _contentController,
                    focusNode: _contentFocusNode,
                    isPreview: _showPreview,
                    onTogglePreview: _togglePreview,
                    onApplyPangu: _applyPanguSpacing,
                    showPanguButton: true,
                    emojiPanelHeight: 350,
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: LoadingSpinner()),
          error: (err, stack) => Center(child: Text('加载分类失败: $err')),
        ),
      ),
    );
  }
}
