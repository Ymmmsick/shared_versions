// Copyright (C) 2020 littlegnal
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import 'dart:io';
import 'dart:math';

import 'package:ansicolor/ansicolor.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

const spaces = 2;

/// Class that help match the package dependencies versions from [_versionsFile]
/// yaml file and override it to the other yaml file.
///
/// **NOTE:** This class only work for yaml file.
class VersionsSynchronizer {
  const VersionsSynchronizer(this._stdout, this._versionsFile);

  final Stdout _stdout;

  final File _versionsFile;

  /// Match the package dependencies versions from [_versionsFile] and override
  /// it the [destPubspecFile].
  ///
  /// If the matched versions is different, it will print the changes to the console.
  void syncTo(File destPubspecFile) {
    final pubspecMap = loadYaml(destPubspecFile.readAsStringSync());
    // 读取第一个YAML文件
    final versionYaml = loadYaml(_versionsFile.readAsStringSync());

    // 读取第二个YAML文件
    final destPubspecYaml = loadYaml(destPubspecFile.readAsStringSync());

    // 获取两个YAML文件中的dependencies节点
    final firstDependencies =
        versionYaml['dependencies'] as YamlMap? ?? YamlMap();
    final secondDependencies =
        destPubspecYaml['dependencies'] as YamlMap? ?? YamlMap();

    // 合并两个dependencies节点并去重
    final mergedDependencies = {...firstDependencies, ...secondDependencies};

    // 将合并后的dependencies节点添加回其中一个YAML文件
    destPubspecYaml['dependencies'] = mergedDependencies;

    // 保存合并后的YAML文件
    destPubspecFile.writeAsStringSync(_writeMap(destPubspecYaml));

    _stdout.writeln("Complete!");
  }

  String _writeMap(Map yaml, {int indent = 0}) {
    String str = '\n';

    for (var key in yaml.keys) {
      var value = yaml[key];
      str +=
          "${_indent(indent)}${key.toString()}: ${_writeInternal(value, indent: indent + 1)}\n";
    }

    return str;
  }

  /// Write a dart structure to a YAML string. [yaml] should be a [Map] or [List].
  String _writeInternal(dynamic yaml, {int indent = 0}) {
    String str = '';

    if (yaml is List) {
      str += _writeList(yaml, indent: indent);
    } else if (yaml is Map) {
      str += _writeMap(yaml, indent: indent);
    } else if (yaml is String) {
      str += "\"${yaml.replaceAll("\"", "\\\"")}\"";
    } else {
      str += yaml.toString();
    }
    return str;
  }

  /// Write a list to a YAML string.
  /// Pass the list in as [yaml] and indent it to the [indent] level.
  String _writeList(List yaml, {int indent = 0}) {
    String str = '\n';

    for (var item in yaml) {
      str +=
          "${_indent(indent)}- ${_writeInternal(item, indent: indent + 1)}\n";
    }

    return str;
  }

  /// Create an indented string for the level with the spaces config.
  /// [indent] is the level of indent whereas [spaces] is the
  /// amount of spaces that the string should be indented by.
  String _indent(int indent) {
    return ''.padLeft(indent * spaces, ' ');
  }

  @visibleForTesting
  String map2Lines(String key, int startIndent, int lineIndex, YamlMap map) {
    StringBuffer output = StringBuffer();
    final newKey = key + ":";
    output.writeln(
        newKey.padLeft(lineIndex * spaces + newKey.length + startIndent));
    final keys = map.keys;
    for (int i = 0; i < keys.length; i++) {
      final k = keys.elementAt(i);
      final value = map[k];
      String line;
      if (value is YamlMap) {
        line = "$k:";
        output.write(map2Lines(k, startIndent, lineIndex + i + 1, value));
      } else {
        line = "$k: $value";
        output.writeln(
            line.padLeft((lineIndex + 1) * spaces + line.length + startIndent));
        continue;
      }
    }

    return output.toString();
  }

  int _map2LinesCount(YamlMap map) {
    int sum = 0;
    final keys = map.keys;
    for (int i = 0; i < keys.length; i++) {
      final key = keys.elementAt(i);
      final value = map[key];
      if (value is YamlMap) {
        sum += 1 + _map2LinesCount(value);
      } else {
        sum += 1;
      }
    }

    return sum;
  }

  YamlMap? _findMapByKey(String key, YamlMap map) {
    YamlMap? result;
    final keys = map.keys;
    for (int i = 0; i < keys.length; i++) {
      final k = keys.elementAt(i);
      final v = map[k];

      if (k == key) {
        result = v;
        break;
      }
      if (v is YamlMap) {
        result = _findMapByKey(key, v);
        if (result != null) {
          break;
        }
      } else {
        continue;
      }
    }

    return result;
  }

  /// Create the stdout message for the changes, e.g.,
  /// ```
  /// assets_scanner:                                           -> assets_scanner:
  ///   git:                                                         path: ../
  ///     url: https://github.com/littleGnAl/assets-scanner.git
  ///     ref: master
  /// ```
  String _createStdoutMessage(
      String fromKey, YamlMap fromValue, String toKey, YamlMap toValue) {
    final fromLineLength = _map2LinesCount(fromValue) + 1;
    final toLineLength = _map2LinesCount(toValue) + 1;

    final length = max(fromLineLength, toLineLength);
    final fromLines = map2Lines(fromKey, 0, 0, fromValue);
    final fromLinesMaxLineLength = _findMaxLineLength(fromLines);
    final toLines = map2Lines(toKey, 0, 0, toValue);

    final fromLinesArr = fromLines.split("\n");
    final toLinesArr = toLines.split("\n");
    StringBuffer output = StringBuffer();
    final arrow = " -> ";
    for (int i = 0; i < length; i++) {
      String? fromLine;
      if (i < fromLineLength) {
        fromLine = fromLinesArr[i];
        output.write(_textWithRemovedColor(fromLine));
      }

      if (i < toLineLength) {
        final toLine = toLinesArr[i];
        if (i == 0) {
          output.write(arrow.padLeft(
              fromLinesMaxLineLength + arrow.length - (fromLine?.length ?? 0)));
          output.write(_textWithAddedColor(toLine));
        } else {
          output.write(_textWithAddedColor(toLine.padLeft(
              fromLinesMaxLineLength +
                  toLine.length +
                  arrow.length -
                  (fromLine?.length ?? 0))));
        }
      }

      output.writeln();
    }

    return output.toString();
  }

  int _findMaxLineLength(String lines) {
    final linesArr = lines.split("\n");
    return linesArr.fold(0, (m, e) => max(m, e.length));
  }

  String _textWithRemovedColor(String text) {
    return (AnsiPen()..red())(text);
  }

  String _textWithAddedColor(String text) {
    return (AnsiPen()..green(bold: true))(text);
  }
}
