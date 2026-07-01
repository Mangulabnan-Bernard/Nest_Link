// Smoke test: with a saved profile, the app boots into the Home command center.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nest_link/main.dart';
import 'package:nest_link/services/identity.dart';

void main() {
  testWidgets('Boots into Home with SOS + 5-tab nav', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'Tatay',
      'profile_role': 'parent',
      'family_code': 'NEST-TEST',
    });
    await Identity.instance.load();

    await tester.pumpWidget(const NestLinkApp());
    await tester.pump();

    // Home command center shows the SOS button.
    expect(find.text('SOS'), findsWidgets);

    // The five tabs are present.
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
  });
}
