import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';

void main() {
  testWidgets('Confirmation scrolls with large text on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.8)),
                  child: AppAlertDialog(
                    title: const Text('Confirm changes'),
                    content: Text(
                      List.filled(
                        20,
                        'Review the details before saving.',
                      ).join(' '),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Save changes'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save changes').hitTestable(), findsOneWidget);
  });
  testWidgets('Custom form keeps actions above the keyboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: AppDialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Edit booking'),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(
                        12,
                        (i) => TextField(
                          decoration: InputDecoration(labelText: 'Field $i'),
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text('Save')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save').hitTestable(), findsOneWidget);
  });
}
