import 'dart:convert';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/profile/avatar_crop_page.dart';

void main() {
  testWidgets('avatar crop uses fixed circular interactive controls',
      (tester) async {
    final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8DA'
      'wMDAxMDAwMAAAAwBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    await tester.pumpWidget(
      MaterialApp(home: AvatarCropPage(image: image)),
    );
    await tester.pump();

    final crop = tester.widget<Crop>(find.byType(Crop));
    expect(crop.withCircleUi, isTrue);
    expect(crop.interactive, isTrue);
    expect(crop.fixCropRect, isTrue);
    expect(find.text('双指缩放并拖动图片'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
  });
}
