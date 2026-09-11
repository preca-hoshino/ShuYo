import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/forum_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ForumImageCache.setNetworkEnabled(true);
  });

  test('concurrent requests for the same image share one download', () async {
    final root = await Directory.systemTemp.createTemp('shuyo-image-cache-');
    final imageBytes = await File('assets/images/icon_clear.png').readAsBytes();
    addTearDown(() async {
      await root.delete(recursive: true);
    });

    var requestCount = 0;
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final cache = ForumImageCache.forTesting(root, downloader: (url) async {
      requestCount++;
      if (!requestStarted.isCompleted) {
        requestStarted.complete();
      }
      await releaseResponse.future;
      return imageBytes;
    });

    const url = 'https://example.com/avatar.png';
    final first = cache.getImage(url);
    await requestStarted.future;
    final second = cache.getImage(url);
    releaseResponse.complete();

    final files = await Future.wait([first, second]);
    expect(requestCount, 1);
    expect(files, everyElement(isNotNull));
    expect(files[0]!.path, files[1]!.path);
    expect(await files[0]!.exists(), isTrue);
  });

  test('a failed image request can be retried', () async {
    final root = await Directory.systemTemp.createTemp('shuyo-image-cache-');
    final imageBytes = await File('assets/images/icon_clear.png').readAsBytes();
    addTearDown(() async {
      await root.delete(recursive: true);
    });

    var requestCount = 0;
    final cache = ForumImageCache.forTesting(root, downloader: (url) async {
      requestCount++;
      if (requestCount == 1) {
        throw const HttpException('temporary failure');
      }
      return imageBytes;
    });

    const url = 'https://example.com/avatar.png';

    expect(await cache.getImage(url), isNull);
    final retried = await cache.getImage(url);
    expect(retried, isNotNull);
    expect(requestCount, 2);
  });
}
