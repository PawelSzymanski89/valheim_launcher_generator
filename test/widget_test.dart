import 'package:flutter_test/flutter_test.dart';
import 'package:valheim_launcher_generator/main.dart';
import 'package:provider/provider.dart';
import 'package:valheim_launcher_generator/generator/config_manager.dart';

void main() {
  testWidgets('Wizard renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GeneratorProvider(),
        child: const ValheimGeneratorApp(),
      ),
    );
    expect(find.text('BRANDING'), findsOneWidget);
  });
}
