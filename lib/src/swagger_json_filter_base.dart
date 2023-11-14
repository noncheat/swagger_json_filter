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
    this.clearRequired = true,
  });

  List<RegExp>? includeTags;
  List<RegExp>? excludeTags;
  List<RegExp>? includePaths;
  List<RegExp>? excludePaths;
  bool clearRequired;
}

class SwaggerJsonFilter {
  const SwaggerJsonFilter({
    required this.options,
  });

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

    // Clean
    json = _clearMismatchedElements(json, definitionsList, whiteList);
    // Clear required properties because build_value not support required fields
    // https://github.com/google/built_value.dart/issues/1050
    if (options.clearRequired) json = _clearRequiredProperties(json, whiteList);

    final result = _filterJson(json);

    return result;
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

  /// Clear required properties
  Map<String, dynamic> _clearRequiredProperties(
    Map<String, dynamic> json,
    List<String> whiteList,
  ) {
    for (final key in whiteList) {
      final value = gato.get<Map>(json, key);
      if (value?['required'] is List &&
          value?['required'].isNotEmpty &&
          value?['properties'] is Map) {
        value?.remove('required');
      }
      json = gato.set(json, key, value);
    }
    return json;
  }

  String _filterJson(Map inputJson) {
    return JsonEncoder.withIndent('  ').convert(inputJson);
  }
}
