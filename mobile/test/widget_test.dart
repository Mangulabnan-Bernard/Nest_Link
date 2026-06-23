// Smoke test: with a saved profile, the app boots into the Nest Mat tab.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nest_link/main.dart';
import 'package:nest_link/services/identity.dart';

void main() {
  testWidgets('Boots into Nest Mat when a profile exists', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'Tatay',
      'profile_role': 'parent',
    });
    await Identity.instance.load();

    await tester.pumpWidget(const NestLinkApp());
    await tester.pump();

    // Default tab is Nest Mat (title + nav label).
    expect(find.text('Nest Mat'), findsWidgets);
    expect(find.text('Chirp'), findsOneWidget);
    expect(find.text('Safe Flight'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
  });
}
