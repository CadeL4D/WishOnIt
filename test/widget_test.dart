// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:wishedon/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our login screen is shown.
    expect(find.text('Welcome to\nWishedOn'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Code'), findsWidgets);
    expect(find.text('Continue as Guest'), findsNothing);
    expect(find.text('Join a Group'), findsNothing);
  });
}
