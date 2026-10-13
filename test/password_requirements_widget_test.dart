import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/auth/widgets/password_requirements.dart';

void main() {
  testWidgets('shows live password requirements while typing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PasswordRequirementsList(password: 'Abc123!')),
      ),
    );

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('Includes an uppercase letter'), findsOneWidget);
    expect(find.text('Includes a lowercase letter'), findsOneWidget);
    expect(find.text('Includes a number'), findsOneWidget);
    expect(find.text('Includes a special character'), findsOneWidget);
  });
}
