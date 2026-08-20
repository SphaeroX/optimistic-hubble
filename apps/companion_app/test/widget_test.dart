import 'package:flutter_test/flutter_test.dart';
import 'package:companion_app/main.dart';
import 'package:companion_app/core/constants/app_constants.dart';

void main() {
  testWidgets('Companion App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const XiaoCompanionApp());
    await tester.pumpAndSettle();

    // Verify app title is displayed
    expect(find.text(AppConstants.appName), findsOneWidget);
    // Verify monitor tab is active
    expect(find.text('Battery & Power'), findsOneWidget);
  });
}
