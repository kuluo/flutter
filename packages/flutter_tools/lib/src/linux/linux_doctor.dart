// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../base/io.dart';
import '../base/user_messages.dart';
import '../base/version.dart';
import '../doctor.dart';

/// A combination of version description and parsed version number.
class _VersionInfo {
  /// Constructs a VersionInfo from a version description string.
  ///
  /// This should contain a version number. For example:
  ///     "clang version 9.0.1-6+build1"
  _VersionInfo(this.description) {
    final String versionString = RegExp(r'[0-9]+\.[0-9]+\.[0-9]+').firstMatch(description).group(0);
    number = Version.parse(versionString);
  }

  // The full info string reported by the binary.
  String description;

  // The parsed Version.
  Version number;
}

/// A validator that checks for Clang and Make build dependencies
class LinuxDoctorValidator extends DoctorValidator {
  LinuxDoctorValidator({
    @required ProcessManager processManager,
    @required UserMessages userMessages,
  }) : _processManager = processManager,
       _userMessages = userMessages,
       super('Linux toolchain - develop for Linux desktop');

  final ProcessManager _processManager;
  final UserMessages _userMessages;

  static const String kClangBinary = 'clang++';
  static const String kCmakeBinary = 'cmake';
  static const String kNinjaBinary = 'ninja';

  final Map<String, Version> _requiredBinaryVersions = <String, Version>{
    kClangBinary: Version(3, 4, 0),
    kCmakeBinary: Version(3, 10, 0),
    kNinjaBinary: Version(1, 8, 0),
  };

  @override
  Future<ValidationResult> validate() async {
    ValidationType validationType = ValidationType.installed;
    final List<ValidationMessage> messages = <ValidationMessage>[];

    final Map<String, _VersionInfo> installedVersions = <String, _VersionInfo>{
      // Sort the check to make the call order predictable for unit tests.
      for (String binary in _requiredBinaryVersions.keys.toList()..sort())
          binary: await _getBinaryVersion(binary)
    };

    // Determine overall validation level.
    if (installedVersions.values.contains(null)) {
      validationType = ValidationType.missing;
    } else if (installedVersions.keys.any((String binary) =>
          installedVersions[binary].number < _requiredBinaryVersions[binary])) {
      validationType = ValidationType.partial;
    }

    // Message for Clang.
    {
      final _VersionInfo version = installedVersions[kClangBinary];
      if (version == null) {
        messages.add(ValidationMessage.error(_userMessages.clangMissing));
      } else {
        messages.add(ValidationMessage(version.description));
        final Version requiredVersion = _requiredBinaryVersions[kClangBinary];
        if (version.number < requiredVersion) {
          messages.add(ValidationMessage.error(_userMessages.clangTooOld(requiredVersion.toString())));
        }
      }
    }

    // Message for CMake.
    {
      final _VersionInfo version = installedVersions[kCmakeBinary];
      if (version == null) {
        messages.add(ValidationMessage.error(_userMessages.cmakeMissing));
      } else {
        messages.add(ValidationMessage(version.description));
        final Version requiredVersion = _requiredBinaryVersions[kCmakeBinary];
        if (version.number < requiredVersion) {
          messages.add(ValidationMessage.error(_userMessages.cmakeTooOld(requiredVersion.toString())));
        }
      }
    }

    // Message for ninja.
    {
      final _VersionInfo version = installedVersions[kNinjaBinary];
      if (version == null) {
        messages.add(ValidationMessage.error(_userMessages.ninjaMissing));
      } else {
        // The full version description is just the number, so context.
        messages.add(ValidationMessage(_userMessages.ninjaVersion(version.description)));
        final Version requiredVersion = _requiredBinaryVersions[kNinjaBinary];
        if (version.number < requiredVersion) {
          messages.add(ValidationMessage.error(_userMessages.ninjaTooOld(requiredVersion.toString())));
        }
      }
    }

    return ValidationResult(validationType, messages);
  }

  /// Returns the installed version of [binary], or null if it's not installed.
  ///
  /// Requires tha [binary] take a '--version' flag, and print a version of the
  /// form x.y.z somewhere on the first line of output.
  Future<_VersionInfo> _getBinaryVersion(String binary) async {
    ProcessResult result;
    try {
      result = await _processManager.run(<String>[
        binary,
        '--version',
      ]);
    } on ArgumentError {
      // ignore error.
    }
    if (result == null || result.exitCode != 0) {
      return null;
    }
    final String firstLine = (result.stdout as String).split('\n').first.trim();
    return _VersionInfo(firstLine);
  }
}
