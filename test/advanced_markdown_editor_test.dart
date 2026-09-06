import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';
import 'package:shuyo/shared/widgets/advanced_markdown_editor.dart';

void main() {
  testWidgets('long text scrolls internally while the toolbar stays fixed',
      (tester) async {
    final textController = TextEditingController(
      text: List.generate(100, (index) => '第 ${index + 1} 行正文').join('\n'),
    );
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    addTearDown(() {
      textController.dispose();
      focusNode.dispose();
      scrollController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AdvancedMarkdownEditor(
              controller: textController,
              focusNode: focusNode,
              scrollController: scrollController,
              enabled: true,
              uploading: false,
              onUploadImage: () {},
              onPreview: () {},
              expands: true,
            ),
          ),
        ),
      ),
    );

    expect(scrollController.hasClients, isTrue);
    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    final toolbarTop = tester.getTopLeft(find.byTooltip('粗体')).dy;

    await tester.drag(find.byType(TextField), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(0));
    expect(tester.getTopLeft(find.byTooltip('粗体')).dy, toolbarTop);

    await tester.drag(find.byType(TextField), const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(scrollController.offset, 0);
    expect(tester.getTopLeft(find.byTooltip('粗体')).dy, toolbarTop);
  });
}
