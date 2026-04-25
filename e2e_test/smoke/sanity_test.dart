import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

void main() {
  patrolTest(
    'app launches and shows login screen when unauthenticated',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      addTearDown(() async {
        await unmountTestApp($);
        await clearAuthSession();
      });

      // Assert on a login-screen body element, not the AppBar title.
      // login_email_field is defined at LoginScreen.emailFieldKey.
      await $(find.byKey(const Key('login_email_field'))).waitUntilVisible();
    },
  );
}
