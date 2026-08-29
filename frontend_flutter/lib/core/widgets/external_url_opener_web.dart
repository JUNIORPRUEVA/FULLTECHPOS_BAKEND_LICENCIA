import 'package:universal_html/html.dart' as html;

Future<bool> openExternalUrl(String url) async {
  html.window.open(url, '_blank');
  return true;
}
