import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

void main() {
  group('toClassName', () {
    test('joins dotted schema keys', () {
      expect(
        DartNaming.toClassName('CRM.Enums.AccountStatus'),
        'CrmEnumsAccountStatus',
      );
    });

    test('splits acronym boundaries the way swagger_parser does', () {
      expect(
        DartNaming.toClassName('AIAnalyst.Enums.Analysis.AnalysisModeType'),
        'AiAnalystEnumsAnalysisAnalysisModeType',
      );
      expect(
        DartNaming.toClassName('IBService.AccountTypes.AccountTypeResult'),
        'IbServiceAccountTypesAccountTypeResult',
      );
    });

    test('handles generic and bracketed keys', () {
      expect(DartNaming.toClassName('List[Order]'), 'ListOrder');
    });

    test('handles a bare name', () {
      expect(DartNaming.toClassName('AccountData'), 'AccountData');
    });
  });

  group('toFileStem', () {
    test('converts a class name to snake_case', () {
      expect(
        DartNaming.toFileStem('CrmEnumsAccountStatus'),
        'crm_enums_account_status',
      );
      expect(
        DartNaming.toFileStem('SocialServiceInvestorStatus'),
        'social_service_investor_status',
      );
    });

    test('keeps digits attached to their word', () {
      expect(DartNaming.toFileStem('AnalysisM20'), 'analysis_m20');
    });
  });

  group('safeMemberName', () {
    test('suffixes reserved words', () {
      expect(DartNaming.safeMemberName('class'), r'class$');
      expect(DartNaming.safeMemberName('in'), r'in$');
    });

    test('leaves ordinary names alone', () {
      expect(DartNaming.safeMemberName('fundamental'), 'fundamental');
    });
  });
}
