import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Secure Storage へ読み書きできる', (tester) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'novelty_probe', value: 'ok');
    expect(await storage.read(key: 'novelty_probe'), 'ok');
    await storage.delete(key: 'novelty_probe');
  });
}
