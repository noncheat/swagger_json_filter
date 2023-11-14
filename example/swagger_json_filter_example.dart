import 'dart:io' show File;

import 'package:swagger_json_filter/swagger_json_filter.dart';

void main() {
  final specPath = 'pet.json';
  final jsonString = File(specPath).readAsStringSync();

  final swaggerJsonFilter = SwaggerJsonFilter(
    options: SwaggerJsonFilterOptions(
        // includeTags: [
        //   RegExp(r'^Include Tag.*'),
        // ],
        // excludeTags: [
        //   RegExp(r'^Exclude Tag$'),
        // ],
        // includePaths: [
        //   RegExp(r'^/api/v1/app/.*'),
        // ],
        // excludePaths: [
        //   RegExp(r'(.*?)'),
        // ],
        ),
  );
  final output = swaggerJsonFilter.filter(jsonString);
  File(specPath).writeAsStringSync(output);
}
