import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/discourse/discourse_service.dart';
import 'emoji_picker.dart';
import 'image_upload_dialog.dart';
import 'link_insert_dialog.dart';

/// Markdown 工具栏组件
/// 提供格式化按钮、表情、预览切换和图片上传功能
class MarkdownToolbar extends StatefulWidget {
  /// 内容控制器（必需，用于文本操作）
  final TextEditingController controller;
  
  /// 内容焦点节点（可选，用于表情面板切换时恢复焦点）
  final FocusNode? focusNode;
  
  /// 是否显示预览按钮
  final bool showPreviewButton;
  
  /// 预览状态
  final bool isPreview;
  
  /// 预览切换回调
  final VoidCallback? onTogglePreview;

  /// 混排优化按钮回调
  final VoidCallback? onApplyPangu;

  /// 是否显示混排优化按钮
  final bool showPanguButton;
  
  /// 表情面板高度
  final double emojiPanelHeight;

  const MarkdownToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.showPreviewButton = true,
    this.isPreview = false,
    this.onTogglePreview,
    this.onApplyPangu,
    this.showPanguButton = false,
    this.emojiPanelHeight = 280.0,
  });

  @override
  State<MarkdownToolbar> createState() => MarkdownToolbarState();
}

class MarkdownToolbarState extends State<MarkdownToolbar> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  
  bool _showEmojiPanel = false;
  bool _isUploading = false;
  bool _wasKeyboardVisible = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 键盘状态变化时触发重建，以便调整表情面板高度
    final viewInsets = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets;
    final isKeyboardVisible = viewInsets.bottom > 0;
    
    if (isKeyboardVisible != _wasKeyboardVisible) {
      _wasKeyboardVisible = isKeyboardVisible;
      if (mounted) setState(() {});
    }
  }
  
  /// 是否显示表情面板（供外部查询）
  bool get showEmojiPanel => _showEmojiPanel;
  
  /// 关闭表情面板（供外部调用）
  void closeEmojiPanel() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
    }
  }
  
  /// 插入文本到光标位置
  void insertText(String text) {
    final selection = widget.controller.selection;

    if (selection.isValid) {
      final newText = widget.controller.text.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      final newSelectionIndex = selection.start + text.length;

      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newSelectionIndex),
      );
    } else {
      final currentText = widget.controller.text;
      final newText = '$currentText$text';
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  /// 用指定前后缀包裹选中文本
  void wrapSelection(String start, String end) {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final text = widget.controller.text;
    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$start$selectedText$end',
    );

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: selection.start + start.length + selectedText.length + end.length),
    );
  }

  /// 在行首添加前缀（用于标题、列表等）
  void applyLinePrefix(String prefix) {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (!selection.isValid) {
      // 没有选中，在文本末尾添加
      final newText = text.isEmpty ? prefix : '$text\n$prefix';
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      return;
    }

    // 找到选中区域所在行的开始位置
    int lineStart = selection.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    // 检查行首是否已有相同前缀
    final lineEnd = text.indexOf('\n', lineStart);
    final currentLine = lineEnd == -1
        ? text.substring(lineStart)
        : text.substring(lineStart, lineEnd);

    if (currentLine.startsWith(prefix)) {
      // 已有前缀，移除它
      final newText = text.replaceRange(lineStart, lineStart + prefix.length, '');
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start - prefix.length,
        ),
      );
    } else {
      // 添加前缀
      final newText = text.replaceRange(lineStart, lineStart, prefix);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + prefix.length,
        ),
      );
    }
  }

  /// 插入代码块（带占位符并自动选中）
  void insertCodeBlock() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (!selection.isValid) {
      // 没有选中，在文本末尾插入
      const placeholder = '在此处键入或粘贴代码';
      final codeBlock = '```\n$placeholder\n```';
      final newText = text.isEmpty ? codeBlock : '$text\n$codeBlock';
      final placeholderStart = newText.length - codeBlock.length + 4; // 4 = '```\n'.length

      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: placeholderStart,
          extentOffset: placeholderStart + placeholder.length,
        ),
      );
    } else {
      // 有选中文本，用代码块包裹
      final selectedText = selection.textInside(text);
      final codeBlock = '```\n$selectedText\n```';
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        codeBlock,
      );

      // 选中代码块内的文本
      final contentStart = selection.start + 4; // 4 = '```\n'.length
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: contentStart,
          extentOffset: contentStart + selectedText.length,
        ),
      );
    }

    // 请求焦点以便用户可以立即开始输入
    widget.focusNode?.requestFocus();
  }

  /// 插入链接（显示对话框）
  Future<void> insertLink(BuildContext context) async {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    // 获取选中的文本作为初始链接文本
    String? initialText;
    if (selection.isValid && selection.start != selection.end) {
      initialText = selection.textInside(text);
    }

    // 显示对话框
    final result = await showLinkInsertDialog(
      context,
      initialText: initialText,
    );

    if (result == null) {
      // 用户取消
      widget.focusNode?.requestFocus();
      return;
    }

    final linkText = result['text']!;
    final url = result['url']!;
    final link = '[$linkText]($url)';

    // 插入链接
    final insertPos = selection.isValid ? selection.start : text.length;
    final endPos = selection.isValid && selection.start != selection.end
        ? selection.end
        : insertPos;

    final newText = text.replaceRange(insertPos, endPos, link);

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertPos + link.length),
    );

    widget.focusNode?.requestFocus();
  }

  /// 插入删除线（带占位符并自动选中）
  void insertStrikethrough() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (!selection.isValid || selection.start == selection.end) {
      // 没有选中文本，插入带占位符的删除线
      const placeholder = '删除线文本';
      final strikethrough = '~~$placeholder~~';
      final insertPos = selection.isValid ? selection.start : text.length;
      final newText = text.replaceRange(insertPos, insertPos, strikethrough);

      // 选中占位符
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: insertPos + 2, // 2 = '~~'.length
          extentOffset: insertPos + 2 + placeholder.length,
        ),
      );
    } else {
      // 有选中文本，用删除线包裹
      final selectedText = selection.textInside(text);
      final strikethrough = '~~$selectedText~~';
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        strikethrough,
      );

      // 选中删除线内容
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start + 2,
          extentOffset: selection.start + 2 + selectedText.length,
        ),
      );
    }

    widget.focusNode?.requestFocus();
  }

  /// 插入行内代码（带占位符并自动选中）
  void insertInlineCode() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (!selection.isValid || selection.start == selection.end) {
      // 没有选中文本，插入带占位符的代码
      const placeholder = '代码';
      final code = '`$placeholder`';
      final insertPos = selection.isValid ? selection.start : text.length;
      final newText = text.replaceRange(insertPos, insertPos, code);

      // 选中占位符
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: insertPos + 1, // 1 = '`'.length
          extentOffset: insertPos + 1 + placeholder.length,
        ),
      );
    } else {
      // 有选中文本，用代码包裹
      final selectedText = selection.textInside(text);
      final code = '`$selectedText`';
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        code,
      );

      // 选中代码内容
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start + 1,
          extentOffset: selection.start + 1 + selectedText.length,
        ),
      );
    }

    widget.focusNode?.requestFocus();
  }

  /// 插入引用（带占位符并自动选中）
  void insertQuote() {
    final selection = widget.controller.selection;
    final text = widget.controller.text;

    if (!selection.isValid || selection.start == selection.end) {
      // 没有选中文本，插入带占位符的引用
      const placeholder = '引用文本';
      final quote = '> $placeholder';
      final insertPos = selection.isValid ? selection.start : text.length;

      // 如果不在行首，先添加换行
      final needNewline = insertPos > 0 && text[insertPos - 1] != '\n';
      final newText = text.replaceRange(
        insertPos,
        insertPos,
        needNewline ? '\n$quote' : quote,
      );

      // 选中占位符
      final placeholderStart = insertPos + (needNewline ? 1 : 0) + 2; // '> '.length
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: placeholderStart,
          extentOffset: placeholderStart + placeholder.length,
        ),
      );
    } else {
      // 有选中文本，在行首添加 >
      applyLinePrefix('> ');
      return;
    }

    widget.focusNode?.requestFocus();
  }

  void _toggleEmojiPanel() {
    setState(() {
      _showEmojiPanel = !_showEmojiPanel;
      if (_showEmojiPanel) {
        FocusScope.of(context).unfocus();
      } else {
        widget.focusNode?.requestFocus();
      }
    });
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      // 显示确认弹框
      if (!mounted) return;
      final result = await showImageUploadDialog(
        context,
        imagePath: image.path,
        imageName: image.name,
      );
      if (result == null) return; // 用户取消

      setState(() => _isUploading = true);

      final service = DiscourseService();
      final url = await service.uploadImage(result.path);

      if (!mounted) return;
      insertText('![${result.originalName}]($url)\n');
    } catch (_) {
      // 错误已由 ErrorInterceptor 处理
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final hasKeyboard = viewInsets.bottom > 0;
    
    // 当键盘弹出时，使用更小的表情面板高度以避免溢出
    // 键盘弹出时高度减半，确保表情面板仍然可见
    final effectiveEmojiHeight = hasKeyboard 
        ? (widget.emojiPanelHeight * 0.4).clamp(120.0, 180.0)
        : widget.emojiPanelHeight;
    
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha:0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具栏按钮行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // 表情按钮
                IconButton(
                  icon: FaIcon(
                    _showEmojiPanel
                        ? FontAwesomeIcons.keyboard
                        : FontAwesomeIcons.faceSmile,
                    size: 20,
                    color: _showEmojiPanel
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: _toggleEmojiPanel,
                ),
                Container(
                  height: 20,
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                // Markdown 工具按钮 (可滚动)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 标题按钮（带弹出菜单）
                        PopupMenuButton<int>(
                          icon: FaIcon(
                            FontAwesomeIcons.heading,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 1, child: Text('H1 - 一级标题')),
                            const PopupMenuItem(value: 2, child: Text('H2 - 二级标题')),
                            const PopupMenuItem(value: 3, child: Text('H3 - 三级标题')),
                            const PopupMenuItem(value: 4, child: Text('H4 - 四级标题')),
                            const PopupMenuItem(value: 5, child: Text('H5 - 五级标题')),
                          ],
                          onSelected: (level) {
                            applyLinePrefix('${'#' * level} ');
                          },
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.bold,
                          onPressed: () => wrapSelection('**', '**'),
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.italic,
                          onPressed: () => wrapSelection('*', '*'),
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.strikethrough,
                          onPressed: insertStrikethrough,
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.listUl,
                          onPressed: () => applyLinePrefix('- '),
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.listOl,
                          onPressed: () => applyLinePrefix('1. '),
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.link,
                          onPressed: () => insertLink(context),
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.quoteRight,
                          onPressed: insertQuote,
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.code,
                          onPressed: insertInlineCode,
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.fileCode,
                          onPressed: insertCodeBlock,
                        ),
                        _ToolbarButton(
                          icon: FontAwesomeIcons.image,
                          onPressed: _isUploading ? null : _pickAndUploadImage,
                          isLoading: _isUploading,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 20,
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                if (widget.showPanguButton)
                  IconButton(
                    icon: Icon(
                      Icons.auto_fix_high_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: widget.onApplyPangu,
                    tooltip: '混排优化',
                  ),
                // 预览按钮（放到最后）
                if (widget.showPreviewButton)
                  IconButton(
                    icon: Icon(
                      widget.isPreview ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: widget.isPreview ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: widget.onTogglePreview,
                    tooltip: widget.isPreview ? '编辑' : '预览',
                  ),
              ],
            ),
          ),
          
          // 表情面板 (使用 ClipRect 防止动画过程中溢出)
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: SizedBox(
                height: _showEmojiPanel ? effectiveEmojiHeight : 0,
                child: _showEmojiPanel
                    ? EmojiPicker(
                        onEmojiSelected: (emoji) {
                          insertText(':${emoji.name}:');
                          // 保持表情面板打开，不弹出键盘
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ToolbarButton({
    required this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FaIcon(icon, size: 16),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
