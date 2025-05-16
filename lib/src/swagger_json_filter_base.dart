// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flat/flat.dart' show flatten;
import 'package:gato/gato.dart' as gato;

class SwaggerJsonFilterOptions {
  /// Exclude has higher priority
  SwaggerJsonFilterOptions({
    this.includeTags,
    this.excludeTags,
    this.includePaths,
    this.excludePaths,
    this.whiteListDefinitions,
    this.clearRequired = true,
    this.addNullable = true,
  });

  /// eg: `[RegExp(r'^Include Tag.*')]`
  List<RegExp>? includeTags;

  /// eg: `[RegExp(r'^Exclude Tag$')]`
  List<RegExp>? excludeTags;

  /// eg: `[RegExp(r'^/api/v1/app/.*')]`
  List<RegExp>? includePaths;

  /// eg: `[RegExp(r'(.*?)')]`
  List<RegExp>? excludePaths;

  /// `SwaggerJsonFilter.filter` will remove Definitions which unused
  ///
  /// Use this for keep Definitions. eg: `['components.schemas.KeycloakError']`
  List<String>? whiteListDefinitions;

  /// Should clear `required` fields or not
  bool clearRequired;

  /// Should add `x-nullable` and `nullable` or not
  bool addNullable;
}

class SwaggerJsonFilter {
  /// Allocates a new SwaggerJsonFilter for the specified [options].
  const SwaggerJsonFilter({
    required this.options,
  });

  /// Filter options
  final SwaggerJsonFilterOptions options;

  /// Filter swagger json paths, return filtered json string from input [jsonString]
  String filter(String jsonString) {
    Map<String, dynamic> json = jsonDecode(jsonString);
    final Map<String, dynamic> paths = json['paths'];

    // Origin definitions list
    final List<String> definitionsList = [];
    for (final path in paths.keys) {
      _searchReferencesFor(json, paths[path], definitionsList);
    }

    _removeUnwanted(paths);

    // Allowed definitions list after filter
    final List<String> whiteList = [];
    for (final path in paths.keys) {
      _searchReferencesFor(json, paths[path], whiteList);
    }
    _whiteListDefinitions(json, whiteList);

    // Clean
    json = _clearMismatchedElements(json, definitionsList, whiteList);

    final definitionsWithProperties = _findDefinitions(json);

    // Rewrite process
    json = _forEachDefinitions(
      json,
      definitionsWithProperties,
      _rewriteDefinitions,
    );

    final result = _filterJson(json);

    return result;
  }

  Iterable<String> _findDefinitions(Map<String, dynamic> json) {
    final flattenDefinitions = flatten(json);
    final result = <String, dynamic>{};
    for (final key in flattenDefinitions.keys) {
      // Version 2
      if (key.startsWith('definitions.')) {
        final defName = key.split('.').getRange(0, 2).join('.');
        result[defName] = true;
      }
      // Version 3
      if (key.startsWith('components.schemas.')) {
        final defName = key.split('.').getRange(0, 3).join('.');
        result[defName] = true;
      }
    }
    return result.keys;
  }

  void _whiteListDefinitions(
    Map<String, dynamic> json,
    List<String> whiteList,
  ) {
    if (options.whiteListDefinitions?.isNotEmpty == true) {
      for (final defName in options.whiteListDefinitions ?? <String>[]) {
        final nestedDefinition = gato.get(json, defName);
        if (nestedDefinition is Map &&
            _shouldSaveReference(defName, whiteList)) {
          _saveReference(defName, whiteList);
        } else {
          print(
            '\x1B[33m[WARNING]\x1B[0m whiteListDefinitions: reference $defName is not Map or already saved',
          );
        }
      }
    }
  }

  /// Apply filter remove unwanted data
  void _removeUnwanted(Map<String, dynamic> paths) {
    for (final key in paths.keys.toList()) {
      // API path like '/api/v1/dashboard/'
      if (paths[key] is! Map<String, dynamic>) continue;
      final path = (paths[key] as Map<String, dynamic>);
      // Methods of API path like GET, POST, DELTE,...
      final methods = path.keys.toList();
      // include/exclude tags
      if (options.includeTags != null || options.excludeTags != null) {
        for (final method in methods) {
          if (path[method] is! Map) continue;
          // Tags of Methods of API path like 'App'
          if (path[method]['tags'] is List) {
            final tags = path[method]['tags'];
            // List of tags will be include
            final includeTags = [];
            for (final tag in tags) {
              // Default will remove tag if has options.includeTags,
              // it will change later if current tag is in include list
              bool willRemoveTag = options.includeTags != null;
              for (final regex in options.includeTags ?? <RegExp>[]) {
                if (regex.hasMatch(tag)) {
                  // Do not remove if current tag is in include list
                  willRemoveTag = false;
                }
              }
              for (final regex in options.excludeTags ?? <RegExp>[]) {
                if (regex.hasMatch(tag)) {
                  // Remove if current tag is in exclude list
                  print('delete path $key tag $tag : $regex');
                  willRemoveTag = true;
                }
              }
              if (!willRemoveTag) {
                includeTags.add(tag);
              }
            }
            // If includeTags.isEmpty then just remove path
            // Else update Tags to filtered
            if (includeTags.isEmpty) {
              path.remove(method);
            } else {
              path[method]['tags'] = includeTags;
            }
          }
        }
      }
      // include/exclude paths
      if (options.includePaths != null || options.excludePaths != null) {
        // Default will remove path if has options.includePaths,
        // it will change later if current path is in include list
        bool willRemove = options.includePaths != null;
        for (final regex in options.includePaths ?? <RegExp>[]) {
          if (regex.hasMatch(key)) {
            // Do not remove if current path is in include list
            willRemove = false;
          }
        }
        for (final regex in options.excludePaths ?? <RegExp>[]) {
          if (regex.hasMatch(key)) {
            // Remove if current path is in exclude list
            print('delete path $key : $regex');
            willRemove = true;
          }
        }
        if (willRemove) {
          paths.remove(key);
        }
      }
    }
  }

  /// Add defName to list
  void _saveReference(
    String defName,
    List<String>? list,
  ) {
    list ??= [];
    list.add(defName);
  }

  /// Check if should save defName to list
  bool _shouldSaveReference(
    String defName,
    List<String>? list,
  ) {
    return list == null || !list.contains(defName);
  }

  /// Search references for [definition] in [json] then add to [list]
  void _searchReferencesFor(
    Map<String, dynamic> json,
    Map<String, dynamic> definition,
    List<String> list,
  ) {
    final flattenDefinition = flatten(definition);
    for (final key in flattenDefinition.keys) {
      dynamic value = flattenDefinition[key];
      // Format get.responses.200.schema.$ref: #/definitions/Model
      if (key.contains(r'$ref') && value is String && value.startsWith(r'#/')) {
        // Sanitize definition name for using with [gato]
        final defName = value.substring(2).split('/').join('.');
        if (_shouldSaveReference(defName, list)) {
          _saveReference(defName, list);
          // If nestedDefinition is Map then recursive _searchReferencesFor
          final nestedDefinition = gato.get(json, defName);
          if (nestedDefinition is Map<String, dynamic>) {
            _searchReferencesFor(json, nestedDefinition, list);
          }
        }
      }
    }
  }

  /// Clear mismatched definitions
  Map<String, dynamic> _clearMismatchedElements(
    Map<String, dynamic> json,
    List<String> definitionsList,
    List<String> whiteList,
  ) {
    for (final key in definitionsList) {
      if (!whiteList.contains(key)) {
        json = gato.set(json, key, {});
      }
    }
    return json;
  }

  Map<String, dynamic> _forEachDefinitions(
    Map<String, dynamic> json,
    Iterable<String> definitions,
    void Function(Map) callback,
  ) {
    for (final key in definitions) {
      final value = gato.get<Map>(json, key);
      if (value != null) {
        // foreach object and check ['type'] is String
        // instead of ['properties'] is Map because enum do not have ['properties']
        // callback should check if have ['properties'] before process
        if (value['allOf'] is List) {
          for (int i = 0; i < value['allOf'].length; i++) {
            if (value['allOf'][i]['type'] is String) {
              callback(value['allOf'][i]);
            }
          }
        } else if (value['type'] is String) {
          callback(value);
        }
        json = gato.set(json, key, value);
      }
    }
    return json;
  }

  /// Rewrite properties
  void _rewriteDefinitions(Map value) {
    // Clear required properties because built_value not support required fields
    // https://github.com/google/built_value.dart/issues/1050
    if (options.clearRequired) {
      _clearRequiredProperties(value);
    }
    // Add nullable for support Dart null-safety,
    // using with [TryParsePlugin] will avoid cast type exception when deserialize
    if (options.addNullable) {
      _addNullableProperties(value);
    }
    // Common rewrite
    // Support enum x-enumNames
    if (value['x-enum-varnames'] == null && value['x-enumNames'] != null) {
      value['x-enum-varnames'] = value['x-enumNames'];
    }
  }

  /// Clear required properties
  void _clearRequiredProperties(Map value) {
    if (value['required'] is List) {
      value.remove('required');
    }
  }

  /// Add nullable properties
  void _addNullableProperties(Map value) {
    for (final keyProperties in (value['properties'] as Map?)?.keys ?? []) {
      // should use both nullable and x-nullable for support multiple version
      value['properties'][keyProperties]['nullable'] = true;
      value['properties'][keyProperties]['x-nullable'] = true;
      // property use $ref
      if (value['properties'][keyProperties][r'$ref'] is String) {
        final ref = value['properties'][keyProperties][r'$ref'] as String;
        // OpenAPI version 2.0 do not use anyOf NullType, will lead to problem JsonObject
        // So for version <= 3.0 use allOf with nullable, x-nullable
        value['properties'][keyProperties]['allOf'] = [
          {r'$ref': ref},
        ];
        value['properties'][keyProperties].remove(r'$ref');
      }
    }
  }

  String _filterJson(Map inputJson) {
    return const JsonEncoder.withIndent('  ').convert(inputJson);
  }
}
