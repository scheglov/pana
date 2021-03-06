// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:pana/pana.dart';
import 'package:pana/src/version.dart';

const String goldenDir = 'test/end2end';

final _regenerateGoldens = false;

void main() {
  Directory tempDir;
  String rootPath;
  PackageAnalyzer analyzer;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pana-test');
    rootPath = await tempDir.resolveSymbolicLinks();
    final pubCacheDir = '$rootPath/pub-cache';
    await new Directory(pubCacheDir).create();
    analyzer = await PackageAnalyzer.create(pubCacheDir: pubCacheDir);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  void _verifyPackage(String fileName, String package, String version) {
    group('end2end: $package $version', () {
      Map actualMap;

      setUpAll(() async {
        var summary = await analyzer.inspectPackage(
          package,
          version: version,
          options: new InspectOptions(
            verbosity: Verbosity.verbose,
            dartdocOutputDir: '$rootPath/dartdoc',
          ),
        );

        // summary.toJson contains types which are not directly JSON-able
        // throwing it through `JSON.encode` does the trick
        actualMap = json.decode(json.encode(summary));
      });

      test('matches known good', () {
        final file = new File('$goldenDir/$fileName');
        if (_regenerateGoldens) {
          final content = new JsonEncoder.withIndent('  ').convert(actualMap);
          file.writeAsStringSync(content);
          fail('Set `_regenerateGoldens` to `false` to run tests.');
        }

        final Map content = json.decode(file.readAsStringSync());
        content['runtimeInfo']['panaVersion'] =
            matches(panaPkgVersion.toString());

        // TODO: allow future versions and remove this override
        content['runtimeInfo']['sdkVersion'] = isSemVer;

        if (content.containsKey('pkgResolution') &&
            content['pkgResolution'].containsKey('dependencies')) {
          content['pkgResolution']['dependencies']?.forEach((Map map) {
            // TODO: allow future versions and remove this override
            if (map.containsKey('resolved')) {
              map['resolved'] = isNotNull;
            }
            // TODO: allow future versions and remove this override
            if (map.containsKey('available')) {
              map['available'] = isNotNull;
            }
          });
        }

        if (content.containsKey('suggestions')) {
          content['suggestions']?.forEach((Map map) {
            // TODO: normalize paths in error reports and remove this override
            map['description'] = isNotEmpty;
          });
        }

        expect(actualMap, content);
      });

      test('Summary can round-trip', () {
        var summary = new Summary.fromJson(actualMap);

        var roundTrip = json.decode(json.encode(summary));
        expect(roundTrip, actualMap);
      });
    }, timeout: const Timeout.factor(2));
  }

  _verifyPackage('http-0.11.3-13.json', 'http', '0.11.3+13');
  _verifyPackage('pub_server-0.1.1-3.json', 'pub_server', '0.1.1+3');
  _verifyPackage('skiplist-0.1.0.json', 'skiplist', '0.1.0');
  _verifyPackage('stream-0.7.2-2.json', 'stream', '0.7.2+2');
}

Matcher isSemVer = predicate<String>((String versionString) {
  try {
    new Version.parse(versionString);
  } catch (e) {
    return false;
  }
  return true;
}, 'can be parsed as a version');
