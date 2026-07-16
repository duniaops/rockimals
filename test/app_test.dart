import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/main.dart';

void main() {
  // The scaffold's only real claim: the app boots and renders. Mostly a guard
  // against the counter template creeping back in. Real coverage starts with
  // the AnimalSystem and data spine.
  testWidgets('boots to the placeholder home', (tester) async {
    await tester.pumpWidget(const RockimalsApp());

    expect(find.text('ROCKIMALS'), findsOneWidget);
  });
}
