import 'package:flutter_test/flutter_test.dart';

import 'package:studentapp_new/main.dart';

void main() {
  testWidgets('App starts on login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentApp(initialRoute: '/login'));

    await tester.pump();

    expect(find.text('TPIS'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
