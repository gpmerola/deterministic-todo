import 'package:deterministic_todo/domain/link_syntax.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identifiers and generic file names show only the site', () {
    expect(
      friendlyLinkLabel(
        'https://chatgpt.com/c/6ac22c33-b194-83ed-91d1-2b4bef0a1338',
      ),
      'chatgpt.com',
    );
    expect(
      friendlyLinkLabel('https://leap.slam.nhs.uk/index.php'),
      'leap.slam.nhs.uk',
    );
    expect(friendlyLinkLabel('https://example.com/12345'), 'example.com');
    expect(friendlyLinkLabel('https://www.example.com/'), 'example.com');
  });

  test('readable segments stay, without file extensions', () {
    expect(
      friendlyLinkLabel(
        'https://emckclac.sharepoint.com/sites/x/Expenses.aspx',
      ),
      'emckclac.sharepoint.com › Expenses',
    );
    expect(
      friendlyLinkLabel('https://member.rcpsych.ac.uk/cpd-cycle-home'),
      'member.rcpsych.ac.uk › cpd cycle home',
    );
    expect(
      friendlyLinkLabel(
        'https://example.com/a-very-long-readable-segment-that-goes-on',
      ),
      'example.com',
    );
  });

  test('stored automatic labels follow the new rule, custom ones stay', () {
    const url = 'https://chatgpt.com/c/6ac22c33-b194-83ed-91d1-2b4bef0a1338';
    expect(
      displayLinkLabel(
        'chatgpt.com › 6ac22c33 b194 83ed 91d1 2b4bef0a1338',
        url,
      ),
      'chatgpt.com',
    );
    expect(displayLinkLabel('Bozza tesi', url), 'Bozza tesi');
  });
}
