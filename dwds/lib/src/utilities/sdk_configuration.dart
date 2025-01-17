// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.9

import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

class InvalidSdkConfigurationException implements Exception {
  final String message;

  InvalidSdkConfigurationException([this.message]);

  @override
  String toString() {
    var message = this.message;
    if (message == null) return 'Invalid SDK configuration';
    return 'Invalid SDK configuration: $message';
  }
}

/// SDK configuration provider interface.
///
/// Supports lazily populated configurations by allowing to create
/// configuration asyncronously.
abstract class SdkConfigurationProvider {
  Future<SdkConfiguration> get configuration;
}

/// Data class describing the SDK layout.
///
/// Provides helpers to convert paths to uris that work on all platforms.
///
/// Call [validate] method to make sure the files in the configuration
/// layout exist before reading the files.
class SdkConfiguration {
  String sdkDirectory;
  String unsoundSdkSummaryPath;
  String soundSdkSummaryPath;
  String librariesPath;
  String compilerWorkerPath;

  SdkConfiguration({
    this.sdkDirectory,
    this.unsoundSdkSummaryPath,
    this.soundSdkSummaryPath,
    this.librariesPath,
    this.compilerWorkerPath,
  });

  static Uri _toUri(String path) => path == null ? null : p.toUri(path);
  static Uri _toAbsoluteUri(String path) =>
      path == null ? null : p.toUri(p.absolute(path));

  Uri get sdkDirectoryUri => _toUri(sdkDirectory);
  Uri get soundSdkSummaryUri => _toUri(soundSdkSummaryPath);
  Uri get unsoundSdkSummaryUri => _toUri(unsoundSdkSummaryPath);
  Uri get librariesUri => _toUri(librariesPath);

  /// Note: has to be ///file: Uri to run in an isolate.
  Uri get compilerWorkerUri => _toAbsoluteUri(compilerWorkerPath);

  /// Throws [InvalidSdkConfigurationException] if configuration does not
  /// exist on disk.
  void validate({FileSystem fileSystem}) {
    fileSystem ??= const LocalFileSystem();

    validateSdkDir(fileSystem: fileSystem);

    if (unsoundSdkSummaryPath == null ||
        !fileSystem.file(unsoundSdkSummaryPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $unsoundSdkSummaryPath does not exist');
    }

    if (soundSdkSummaryPath == null ||
        !fileSystem.file(soundSdkSummaryPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $soundSdkSummaryPath does not exist');
    }

    if (librariesPath == null || !fileSystem.file(librariesPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Libraries spec $librariesPath does not exist');
    }

    if (compilerWorkerPath == null ||
        !fileSystem.file(compilerWorkerPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Compiler worker $compilerWorkerPath does not exist');
    }
  }

  /// Throws [InvalidSdkConfigurationException] if SDK root does not
  /// exist on the disk.
  void validateSdkDir({FileSystem fileSystem}) {
    fileSystem ??= const LocalFileSystem();
    if (sdkDirectory == null ||
        !fileSystem.directory(sdkDirectory).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk directory $sdkDirectory does not exist');
    }
  }
}

/// Implementation for the default SDK configuration layout.
class DefaultSdkConfigurationProvider extends SdkConfigurationProvider {
  SdkConfiguration _configuration;

  DefaultSdkConfigurationProvider();

  /// Create and validate configuration matching the default SDK layout.
  @override
  Future<SdkConfiguration> get configuration async {
    if (_configuration == null) {
      final binDir = p.dirname(Platform.resolvedExecutable);
      final sdkDir = p.dirname(binDir);

      _configuration = SdkConfiguration(
        sdkDirectory: sdkDir,
        unsoundSdkSummaryPath:
            p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill'),
        soundSdkSummaryPath:
            p.join(sdkDir, 'lib', '_internal', 'ddc_outline_sound.dill'),
        librariesPath: p.join(sdkDir, 'lib', 'libraries.json'),
        compilerWorkerPath:
            p.join(binDir, 'snapshots', 'dartdevc.dart.snapshot'),
      );
    }
    return _configuration;
  }
}
