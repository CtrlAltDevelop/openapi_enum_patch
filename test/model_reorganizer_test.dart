import 'dart:io';

import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory apiDir;
  late Directory modelsDir;
  late Directory libDir;

  const groups = {
    'crm': 'Crm',
    'ib_service': 'IbService',
    'ai_analyst': 'AiAnalyst',
  };

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('reorganizer_test');
    apiDir = Directory(p.join(sandbox.path, 'lib', 'generated', 'api_clients'))
      ..createSync(recursive: true);
    modelsDir = Directory(p.join(apiDir.path, 'models'))..createSync();
    libDir = Directory(p.join(sandbox.path, 'lib'));
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  void writeModel(String stem, String contents) {
    File(p.join(modelsDir.path, '$stem.dart')).writeAsStringSync(contents);
  }

  ReorganizeResult run() => const ModelReorganizer(
    groups: groups,
  ).run(modelsDir: modelsDir, apiDir: apiDir, rewriteRoots: [libDir]);

  String read(String relative) =>
      File(p.join(modelsDir.path, relative)).readAsStringSync();

  bool exists(String relative) =>
      File(p.join(modelsDir.path, relative)).existsSync();

  test('moves a dto into its namespace folder and strips the prefix', () {
    writeModel(
      'crm_account_types_dtos_feature_dto',
      'class CrmAccountTypesDtosFeatureDto {}',
    );
    File(
      p.join(modelsDir.path, 'crm_account_types_dtos_feature_dto.mapper.dart'),
    ).writeAsStringSync('// mapper');

    final result = run();

    expect(result.moved, 1);
    expect(result.groups, ['crm']);
    expect(exists('crm/account_types_dtos_feature_dto.dart'), isTrue);
    expect(exists('crm/account_types_dtos_feature_dto.mapper.dart'), isTrue);
    expect(
      read('crm/account_types_dtos_feature_dto.dart'),
      contains('class AccountTypesDtosFeatureDto'),
    );
  });

  test('routes enums into enums/ and drops the Enums segment', () {
    writeModel(
      'crm_enums_account_status',
      '@MappableEnum()\nenum CrmEnumsAccountStatus { active }',
    );

    run();

    expect(exists('crm/enums/account_status.dart'), isTrue);
    expect(
      read('crm/enums/account_status.dart'),
      contains('enum AccountStatus'),
    );
  });

  test('prefers the longest matching group prefix', () {
    writeModel('ib_service_partner_dto', 'class IbServicePartnerDto {}');

    final result = run();

    expect(result.groups, ['ib_service']);
    expect(exists('ib_service/partner_dto.dart'), isTrue);
  });

  test('keeps the prefix when two services claim the same type name', () {
    writeModel(
      'crm_enums_payment_transfer_type',
      '@MappableEnum()\nenum CrmEnumsPaymentTransferType { a }',
    );
    writeModel(
      'ib_service_enums_payment_transfer_type',
      '@MappableEnum()\nenum IbServiceEnumsPaymentTransferType { a }',
    );

    final result = run();

    expect(result.collisionsKept, 2);
    expect(result.renamed, 0);
    // Files never collide — they live in different folders.
    expect(exists('crm/enums/payment_transfer_type.dart'), isTrue);
    expect(exists('ib_service/enums/payment_transfer_type.dart'), isTrue);
    // …but the type names are untouched, so the code still compiles.
    expect(
      read('crm/enums/payment_transfer_type.dart'),
      contains('enum CrmEnumsPaymentTransferType'),
    );
  });

  test('rewrites relative imports inside the generated tree', () {
    writeModel('crm_order_dto', 'class CrmOrderDto {}');
    final client = File(p.join(apiDir.path, 'crm', 'crm_client.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import '../models/crm_order_dto.dart';\n"
        'class Client { CrmOrderDto? order; }\n',
      );

    run();

    expect(
      client.readAsStringSync(),
      contains("import '../models/crm/order_dto.dart';"),
    );
  });

  test('rewrites part directives for the mapper file', () {
    writeModel(
      'crm_order_dto',
      "part 'crm_order_dto.mapper.dart';\nclass CrmOrderDto {}",
    );

    run();

    expect(
      read('crm/order_dto.dart'),
      contains("part 'order_dto.mapper.dart';"),
    );
  });

  test('rewrites model URIs and type names in application sources', () {
    writeModel('crm_order_dto', 'class CrmOrderDto {}');
    final usage = File(p.join(libDir.path, 'features', 'orders.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:app/generated/api_clients/models/crm_order_dto.dart';\n"
        'CrmOrderDto build() => CrmOrderDto();\n',
      );

    run();

    final text = usage.readAsStringSync();
    expect(text, contains('generated/api_clients/models/crm/order_dto.dart'));
    expect(text, contains('OrderDto build() => OrderDto();'));
    expect(text, isNot(contains('CrmOrderDto')));
  });

  test('strips the prefix from dart_mappable derivatives too', () {
    writeModel('crm_order_dto', 'class CrmOrderDto {}');
    final usage = File(p.join(libDir.path, 'use.dart'))
      ..writeAsStringSync(
        'CrmOrderDtoMapper.ensureInitialized();\n'
        'CrmOrderDtoCopyWith? c;\n',
      );

    run();

    expect(
      usage.readAsStringSync(),
      allOf(
        contains('OrderDtoMapper.ensureInitialized();'),
        contains('OrderDtoCopyWith? c;'),
        isNot(contains('CrmOrderDto')),
      ),
    );
  });

  test('a longer type name is not corrupted by a shorter one', () {
    writeModel('crm_order', 'class CrmOrder {}');
    writeModel('crm_order_detail', 'class CrmOrderDetail {}');
    final usage = File(p.join(libDir.path, 'use.dart'))
      ..writeAsStringSync('CrmOrderDetail d; CrmOrder o;');

    run();

    expect(usage.readAsStringSync(), 'OrderDetail d; Order o;');
  });

  test('leaves files whose prefix matches no group alone', () {
    writeModel('unrelated_helper', 'class UnrelatedHelper {}');

    final result = run();

    expect(result.changed, isFalse);
    expect(exists('unrelated_helper.dart'), isTrue);
  });

  test('is idempotent once the tree is nested', () {
    writeModel('crm_order_dto', 'class CrmOrderDto {}');

    expect(run().moved, 1);
    final second = run();

    expect(second.changed, isFalse);
    expect(second.describe(), 'models already reorganized');
    expect(exists('crm/order_dto.dart'), isTrue);
  });

  test('reports a no-op when the models directory is absent', () {
    final result = const ModelReorganizer(groups: groups).run(
      modelsDir: Directory(p.join(sandbox.path, 'nope')),
      apiDir: apiDir,
      rewriteRoots: [libDir],
    );

    expect(result.changed, isFalse);
  });
}
