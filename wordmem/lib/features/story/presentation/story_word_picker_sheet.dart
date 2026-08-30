import 'package:flutter/material.dart';

import '../../../shared/widgets/glass.dart';

/// 指定单词选择器：搜索 + 多选，返回选中的单词列表。
/// 以 showModalBottomSheet 形式打开。
class StoryWordPickerSheet extends StatefulWidget {
  final List<String> allWords;
  final Set<String> initialSelected;

  const StoryWordPickerSheet({
    super.key,
    required this.allWords,
    required this.initialSelected,
  });

  @override
  State<StoryWordPickerSheet> createState() => _StoryWordPickerSheetState();
}

class _StoryWordPickerSheetState extends State<StoryWordPickerSheet> {
  late Set<String> _selected;
  String _query = '';
  static const _maxSelect = 25;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelected};
  }

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.allWords;
    return widget.allWords.where((w) => w.toLowerCase().contains(q)).toList();
  }

  void _toggle(String word) {
    setState(() {
      if (_selected.contains(word)) {
        _selected.remove(word);
      } else if (_selected.length < _maxSelect) {
        _selected.add(word);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多选择 25 个单词')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Text('选择单词（已选 ${_selected.length}/$_maxSelect）',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _selected.clear());
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: '搜索单词...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final word = _filtered[i];
                    final checked = _selected.contains(word);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(word),
                      onChanged: (_) => _toggle(word),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              GlassButton(
                onPressed: () =>
                    Navigator.of(context).pop(_selected.toList()),
                label: '确定（${_selected.length} 个）',
                tinted: true,
              ),
            ],
          ),
        );
      },
    );
  }
}
