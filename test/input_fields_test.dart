import 'package:phan_mem_quan_ly_can_ho/widgets/responsive_form_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';

void main() {
  TextEditingValue edit(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );
  test('Money groups commas and preserves decimal amounts and caret', () {
    final formatter = CurrencyInputFormatter(decimalDigits: 2);
    expect(
      formatter.formatEditUpdate(edit(''), edit('1234567')).text,
      '1,234,567',
    );
    final decimal = formatter.formatEditUpdate(edit('1,234'), edit('1,234.'));
    expect(decimal.text, '1,234.');
    expect(decimal.selection.baseOffset, 6);
    expect(
      formatter.formatEditUpdate(decimal, edit('1,234.56')).text,
      '1,234.56',
    );
    expect(CurrencyParser.parse('1,234.56'), 1234.56);
    expect(
      formatter
          .formatEditUpdate(edit('123'), edit('123', 0))
          .selection
          .baseOffset,
      0,
    );
    expect(formatter.formatEditUpdate(edit('12'), edit('12..')).text, '12');
    expect(formatter.formatEditUpdate(edit('1,000'), edit('')).text, '');
  });
  test('Money leaves composing input untouched and rejects extra decimals', () {
    final formatter = CurrencyInputFormatter(decimalDigits: 2);
    final composing = TextEditingValue(
      text: '1234',
      composing: TextRange(start: 0, end: 4),
    );
    expect(formatter.formatEditUpdate(edit(''), composing), composing);
    expect(
      formatter.formatEditUpdate(edit('12.34'), edit('12.345')).text,
      '12.34',
    );
    expect(CurrencyParser.tryParse('invalid'), isNull);
  });
  for (final locale in [const Locale('vi', 'VN'), const Locale('en', 'US')]) {
    testWidgets('Date picker supports $locale at phone width', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedDatePicker(
                labelText: 'Date',
                initialDate: DateTime(2026, 9, 8),
                firstDate: DateTime(2026, 9, 1),
                lastDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(locale.languageCode == 'vi' ? '08/09/2026' : '09/08/2026'),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Paired money fields stack on a narrow phone with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: SizedBox(
              width: 320,
              child: ResponsiveFormRow(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '1,234,567.89',
                      decoration: const InputDecoration(
                        labelText: 'Monthly rent',
                        suffixText: 'USD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: '999,999.99',
                      decoration: const InputDecoration(
                        labelText: 'Security deposit',
                        suffixText: 'USD',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byType(TextFormField).last).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextFormField).first).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Changing language reformats the same selected date', (
    tester,
  ) async {
    late StateSetter update;
    var locale = const Locale('vi', 'VN');
    DateTime? selected = DateTime(2026, 9, 8);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: LocalizedDatePicker(
                labelText: 'Date',
                initialDate: selected,
                onDateChanged: (value) => selected = value,
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('08/09/2026'), findsOneWidget);
    update(() => locale = const Locale('en', 'US'));
    await tester.pumpAndSettle();
    expect(find.text('09/08/2026'), findsOneWidget);
    expect(selected, DateTime(2026, 9, 8));
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
}
