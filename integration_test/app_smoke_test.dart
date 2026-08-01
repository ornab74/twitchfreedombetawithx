import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('integration harness starts', (WidgetTester tester) async {
    // Full vault/model/media tests run in platform CI with injected temporary
    // paths and synthetic Twitch fixtures. This sentinel ensures the integration
    // target is discoverable on every generated platform.
    expect(true, isTrue);
  });
}
