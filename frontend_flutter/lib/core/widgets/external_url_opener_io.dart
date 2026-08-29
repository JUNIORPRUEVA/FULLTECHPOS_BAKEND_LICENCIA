import 'dart:io';

Future<bool> openExternalUrl(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [url]);
      return true;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}
