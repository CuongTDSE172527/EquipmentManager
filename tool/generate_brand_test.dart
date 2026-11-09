// Run: flutter test tool/generate_brand_test.dart
// Render the source SVG into launcher PNGs and a multi-resolution Windows ICO.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

ui.Color color(String hex) =>
    ui.Color(int.parse('FF${hex.substring(1)}', radix: 16));

Future<Uint8List> render(XmlDocument document, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(size / 512);
  for (final element in document.rootElement.childElements) {
    double number(String name, [double fallback = 0]) =>
        double.tryParse(element.getAttribute(name) ?? '') ?? fallback;
    final path = ui.Path();
    switch (element.name.local) {
      case 'rect':
        path.addRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              number('x'),
              number('y'),
              number('width'),
              number('height'),
            ),
            ui.Radius.circular(number('rx')),
          ),
        );
      case 'circle':
        path.addOval(
          ui.Rect.fromCircle(
            center: ui.Offset(number('cx'), number('cy')),
            radius: number('r'),
          ),
        );
      case 'polygon':
        final points = element
            .getAttribute('points')!
            .split(RegExp(r'[\s,]+'))
            .map(double.parse)
            .toList();
        path.addPolygon([
          for (var i = 0; i < points.length; i += 2)
            ui.Offset(points[i], points[i + 1]),
        ], true);
      default:
        continue;
    }
    final fill = element.getAttribute('fill') ?? '#000000';
    if (fill != 'none') {
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color(fill)
          ..isAntiAlias = true,
      );
    }
    final stroke = element.getAttribute('stroke');
    if (stroke != null) {
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color(stroke)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = number('stroke-width')
          ..strokeJoin = ui.StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  test('Generate EquipmentManager brand from SVG', () async {
    final document = XmlDocument.parse(
      await File('assets/brand/logo.svg').readAsString(),
    );
    await File(
      'assets/brand/logo.png',
    ).writeAsBytes(await render(document, 512));
    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await File(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      ).writeAsBytes(await render(document, entry.value));
    }
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final frames = <Uint8List>[];
    for (final size in sizes) {
      frames.add(await render(document, size));
    }
    final header = ByteData(6 + 16 * frames.length);
    header.setUint16(2, 1, Endian.little);
    header.setUint16(4, frames.length, Endian.little);
    var offset = header.lengthInBytes;
    for (var i = 0; i < frames.length; i++) {
      final start = 6 + i * 16;
      header.setUint8(start, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint8(start + 1, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint16(start + 4, 1, Endian.little);
      header.setUint16(start + 6, 32, Endian.little);
      header.setUint32(start + 8, frames[i].length, Endian.little);
      header.setUint32(start + 12, offset, Endian.little);
      offset += frames[i].length;
    }
    await File('windows/runner/resources/app_icon.ico').writeAsBytes(
      (BytesBuilder()
            ..add(header.buffer.asUint8List())
            ..add(frames.expand((f) => f).toList()))
          .takeBytes(),
    );
  });
}
