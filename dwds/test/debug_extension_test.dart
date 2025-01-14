// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

// When run locally this test may require a manifest key. This makes it easy to
// just skip it.
@Tags(['extension'])
@Timeout(Duration(seconds: 60))
@OnPlatform({
  'windows': Skip('https://github.com/dart-lang/webdev/issues/711'),
})
import 'package:dwds/src/handlers/injector.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:webdriver/io.dart';

import 'fixtures/context.dart';
import 'fixtures/utilities.dart';

// Instructions for running:
// * From the /dwds/debug_extension, build the extension: pub run build_runner build web -o build -r
// * From the /dwds, run: dart test test/debug_extension_test.dart
// * See note for Googlers below as well
// [For Googlers]
// A whitelisted developer key is needed to run these tests locally.
// Add a developer key to dwds/debug_extension/web/manifest.json.
// Otherwise, you will get 'Error Loading Extension' alert.
// Remove the key before pushing code to GitHub.
// See go/extension-identification.

final context = TestContext();

// TODO(elliette): Instead of setting a time to load, check for element on page.
// See: https://github.com/dart-lang/webdev/issues/1512
// Time for Dart DevTools to load, in seconds.
final devToolsLoadTime = const Duration(seconds: 4);

void main() async {
  Future<void> waitForDartDevToolsWithRetry({
    int retryCount = 6,
    Duration retryWait = const Duration(seconds: 1),
  }) async {
    if (retryCount == 0) return;
    var windows = await context.webDriver.windows.toList();
    await context.webDriver.driver.switchTo.window(windows.last);
    final title = await context.webDriver.title;
    if (title == 'Dart DevTools') return;

    await Future.delayed(retryWait);
    return waitForDartDevToolsWithRetry(
      retryCount: retryCount--,
      retryWait: retryWait,
    );
  }

  for (var useSse in [true, false]) {
    group(useSse ? 'SSE' : 'WebSockets', () {
      group('Without encoding', () {
        setUp(() async {
          await context.setUp(
              enableDebugExtension: true, serveDevTools: true, useSse: useSse);
          await context.extensionConnection.sendCommand('Runtime.evaluate', {
            'expression': 'fakeClick()',
          });
          // Wait for DevTools to actually open.
          await Future.delayed(devToolsLoadTime);
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can launch DevTools', () async {
          var windows = await context.webDriver.windows.toList();
          await context.webDriver.driver.switchTo.window(windows.last);
          // TODO(grouma): switch back to `fixture.webdriver.title` when
          // https://github.com/flutter/devtools/issues/2045 is fixed.
          expect(await context.webDriver.pageSource, contains('Flutter'));
          expect(await context.webDriver.currentUrl,
              contains('ide=DebugExtension'));
        });

        test('can close DevTools and relaunch', () async {
          for (var window in await context.webDriver.windows.toList()) {
            await context.webDriver.driver.switchTo.window(window);
            if (await context.webDriver.title == 'Dart DevTools') {
              await window.close();
              break;
            }
          }

          // Relaunch DevTools by (fake) clicking the extension.
          await context.extensionConnection.sendCommand('Runtime.evaluate', {
            'expression': 'fakeClick()',
          });
          await waitForDartDevToolsWithRetry();
          expect(await context.webDriver.title, 'Dart DevTools');
        });
      });

      group('With a sharded Dart app', () {
        setUp(() async {
          await context.setUp(
              enableDebugExtension: true, serveDevTools: true, useSse: useSse);
          var htmlTag =
              await context.webDriver.findElement(const By.tagName('html'));

          await context.webDriver.execute(
              "arguments[0].setAttribute('data-multiple-dart-apps', 'true');",
              [htmlTag]);
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('opens an alert', () async {
          await context.extensionConnection.sendCommand('Runtime.evaluate', {
            'expression': 'fakeClick()',
          });
          // Wait for the alert to open.
          var alert =
              await retryFn<Alert>(() => context.webDriver.switchTo.alert);
          expect(alert, isNotNull);
        });
      });

      // TODO(elliette): Figure out a way to verify that the Dart panel is added
      // to Chrome DevTools. This might not be possible to test with WebDriver,
      // because WebDriver doesn't allow you to interact with Chrome DevTools.
      group('With an internal Dart app', () {
        setUp(() async {
          await context.setUp(
              enableDebugExtension: true, serveDevTools: true, useSse: false);
          var htmlTag =
              await context.webDriver.findElement(const By.tagName('html'));

          await context.webDriver.execute(
              "arguments[0].setAttribute('data-ddr-dart-app', 'true');",
              [htmlTag]);

          await context.extensionConnection.sendCommand('Runtime.evaluate', {
            'expression': 'fakeClick()',
          });
          // Wait for DevTools to actually open.
          await Future.delayed(devToolsLoadTime);
        });

        tearDown(() async {
          await context.tearDown();
        });

        test('can launch DevTools', () async {
          var windows = await context.webDriver.windows.toList();
          await context.webDriver.driver.switchTo.window(windows.last);
          expect(await context.webDriver.title, 'Dart DevTools');
        });

        test('can close DevTools and relaunch', () async {
          for (var window in await context.webDriver.windows.toList()) {
            await context.webDriver.driver.switchTo.window(window);
            if (await context.webDriver.title == 'Dart DevTools') {
              await window.close();
              break;
            }
          }

          // Relaunch DevTools by (fake) clicking the extension.
          await context.extensionConnection.sendCommand('Runtime.evaluate', {
            'expression': 'fakeClick()',
          });
          await waitForDartDevToolsWithRetry();
          expect(await context.webDriver.title, 'Dart DevTools');
        });
      });
    });
  }

  group('With encoding', () {
    final context = TestContext();
    setUp(() async {
      await context.setUp(
          enableDebugExtension: true,
          urlEncoder: (url) async =>
              url.endsWith(r'/$debug') ? 'http://some-encoded-url:8081/' : url);
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('uses the encoded URI', () async {
      var result = await http.get(Uri.parse(
          'http://localhost:${context.port}/hello_world/main.dart$bootstrapJsExtension'));
      expect(result.body.contains('dartExtensionUri'), isTrue);
      expect(result.body.contains('http://some-encoded-url:8081/'), isTrue);
    });
  });

  group('With "any" hostname', () {
    final context = TestContext();
    final uriPattern = RegExp(r'dartExtensionUri = "([^"]+)";');

    setUp(() async {
      await context.setUp(enableDebugExtension: true, hostname: 'any');
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('generates an extensionUri with a valid valid hostname', () async {
      var result = await http.get(Uri.parse(
          'http://localhost:${context.port}/hello_world/main.dart$bootstrapJsExtension'));
      expect(result.body.contains('dartExtensionUri'), isTrue);
      var extensionUri = Uri.parse(uriPattern.firstMatch(result.body).group(1));
      expect(
          extensionUri.host,
          anyOf(
            // The hostname should've been mapped from "any" to one of the local
            // loopback addresses/IPs.
            equals('localhost'),
            equals('127.0.0.1'),
            equals('::'),
            equals('::1'),
          ));
    });
  });
}
