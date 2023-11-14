import 'dart:convert';
import 'dart:io' show File;

import 'package:swagger_json_filter/swagger_json_filter.dart';
import 'package:test/test.dart';

void main() {
  group('filter', () {
    final specPath = 'pet.json';
    final jsonString = File(specPath).readAsStringSync();
    final json = jsonDecode(jsonString);

    test('nothing', () {
      final swaggerJsonFilter = SwaggerJsonFilter(
        options: SwaggerJsonFilterOptions(clearRequired: false),
      );
      final outputString = swaggerJsonFilter.filter(jsonString);
      final output = jsonDecode(outputString);
      expect(jsonEncode(json) == jsonEncode(output), isTrue);
    });
  });
}
