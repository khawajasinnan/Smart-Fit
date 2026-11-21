import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/utils/auth_callback_url.dart';

/// The Google sign-in code is removed from the web address bar after use.
void main() {
  test('removes the one-time code and keeps the route', () {
    expect(withoutAuthCallbackParams(Uri.parse('http://localhost:5000/?code=76a6#/home')),
        'http://localhost:5000/#/home');
  });

  test('removes an error redirect, keeps other parameters', () {
    expect(
        withoutAuthCallbackParams(
            Uri.parse('http://localhost:5000/?error=access_denied&error_description=x&utm=1#/login')),
        'http://localhost:5000/?utm=1#/login');
  });

  test('a normal address is left alone', () {
    expect(withoutAuthCallbackParams(Uri.parse('http://localhost:5000/#/chat')), isNull);
  });
}
