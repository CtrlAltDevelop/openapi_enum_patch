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

    test('replaces characters Dart does not allow in an identifier', () {
      expect(DartNaming.safeMemberName('in progress'), 'in_progress');
      expect(DartNaming.safeMemberName('not-started'), 'not_started');
      expect(DartNaming.safeMemberName('a  --  b'), 'a_b');
    });

    test('keeps a leading digit out of the first position', () {
      expect(DartNaming.safeMemberName('2fa'), r'$2fa');
      expect(DartNaming.safeMemberName('3'), r'$3');
    });

    test('trims surrounding whitespace', () {
      expect(DartNaming.safeMemberName('  active  '), 'active');
    });

    test('falls back to a placeholder for a name with nothing usable', () {
      expect(DartNaming.safeMemberName('   '), r'$unnamed');
      expect(DartNaming.safeMemberName(''), r'$unnamed');
    });

    test('keeps a dollar sign, which is a legal identifier character', () {
      expect(DartNaming.safeMemberName(r'usd$'), r'usd$');
    });
  });
}
