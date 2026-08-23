import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _encoder = YamlEncoder();

/// Re-reads [document]'s encoding to prove the data survived the trip.
Object? roundTrip(Object? document) => loadYaml(_encoder.convert(document));

void main() {
  test('writes a mapping in block style', () {
    expect(
      _encoder.convert({
        'openapi': '3.0.3',
        'info': {'title': 'Website API', 'version': '0.1.0'},
      }),
      '''
openapi: 3.0.3
info:
  title: Website API
  version: 0.1.0
''',
    );
  });

  test('hangs a sequence off its key at the same indentation', () {
    expect(
      _encoder.convert({
        'schema': {
          'enum': ['ar', 'de'],
          'type': 'string',
        },
      }),
      '''
schema:
  enum:
  - ar
  - de
  type: string
''',
    );
  });

  test('writes a mapping inside a sequence against the bullet', () {
    expect(
      _encoder.convert({
        'parameters': [
          {'in': 'query', 'name': 'locale'},
          {'in': 'path', 'name': 'id', 'required': true},
        ],
      }),
      '''
parameters:
- in: query
  name: locale
- in: path
  name: id
  required: true
''',
    );
  });

  test('writes a multi-line string as a literal block', () {
    expect(_encoder.convert({'description': '* `ar` - ar\n* `de` - de'}), '''
description: |-
  * `ar` - ar
  * `de` - de
''');
  });

  test('reads a literal block back unchanged', () {
    const text =
        'Exchange client credentials for a token.\n\nSecond paragraph.';
    expect(roundTrip({'description': text}), {'description': text});
  });

  test('falls back to a quoted scalar when a block would lose data', () {
    // A trailing newline and trailing spaces are both stripped by `|-`.
    for (final text in const ['line\n', 'a  \nb', ' indented\nb', 'a\r\nb']) {
      final encoded = _encoder.convert({'x': text});
      expect(encoded, isNot(contains('|-')), reason: 'for ${text.codeUnits}');
      expect(loadYaml(encoded), {'x': text});
    }
  });

  test('quotes scalars that would read back as another type', () {
    final document = {
      'zero': '0',
      'version': '3.0',
      'yes': 'yes',
      'nothing': 'null',
      'tilde': '~',
      'empty': '',
      'dashed': '- not a list',
      'colon': 'key: value',
      'hash': 'trailing # comment',
      'padded': ' spaced ',
      'star': '*anchor',
      'brace': '{inline}',
      'quote': "it's fine",
      'tabbed': 'a\tb',
    };
    expect(roundTrip(document), document);
  });

  test('leaves ordinary scalars unquoted', () {
    expect(
      _encoder.convert({'name': 'locale', r'$ref': '#/components/schemas/Foo'}),
      // A leading `#` is an indicator, so the ref is quoted — exactly how
      // OpenAPI exporters write it.
      "name: locale\n\$ref: '#/components/schemas/Foo'\n",
    );
  });

  test('keeps non-string scalar types', () {
    final document = {
      'count': 100,
      'rate': 1.5,
      'ok': true,
      'off': false,
      'nothing': null,
    };
    expect(roundTrip(document), document);
  });

  test('writes empty collections inline', () {
    expect(
      _encoder.convert({
        'security': [
          {'oauth2': <String>[]},
          <String, Object?>{},
        ],
      }),
      'security:\n- oauth2: []\n- {}\n',
    );
  });

  test('quotes keys that need it', () {
    final document = {
      '200': {'description': 'ok'},
      'no': 1,
    };
    expect(roundTrip(document), document);
  });

  test('nests sequences of sequences', () {
    final document = {
      'matrix': [
        [1, 2],
        [3, 4],
      ],
    };
    expect(roundTrip(document), document);
  });

  test('honours a custom indent', () {
    expect(
      const YamlEncoder(indent: 4).convert({
        'info': {'title': 'API'},
      }),
      'info:\n    title: API\n',
    );
  });

  test('renders a bare scalar document', () {
    expect(_encoder.convert('hello'), 'hello\n');
    expect(_encoder.convert(<String, Object?>{}), '{}\n');
  });
}
