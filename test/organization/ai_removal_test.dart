import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app navigation cannot install AI or purchase surfaces', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('ChatOverlayManager')));
    expect(main, isNot(contains('_chatRouteObserver')));
    expect(main, isNot(contains('AIAgentService')));
    final source = Directory('lib').listSync(recursive: true)
        .whereType<File>().where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync()).join('\n');
    expect(source, isNot(contains('purchases_flutter')));
    expect(source, isNot(contains("call('aiChat'")));
    expect(source, isNot(contains("call('aiImportCommit'")));
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('purchases_flutter:')));
  });
}
