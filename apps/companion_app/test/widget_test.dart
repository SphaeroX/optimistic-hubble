import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/main.dart';
import 'package:dictula/core/constants/app_constants.dart';

void main() {
  testWidgets('Dictula App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DictulaApp());
    await tester.pumpAndSettle();

    // Verify app title is displayed
    expect(find.text(AppConstants.appName), findsOneWidget);
  });
}
