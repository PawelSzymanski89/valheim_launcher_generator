import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() async {
  final image = img.Image(width: 256, height: 256);
  img.fill(image, color: img.ColorRgb8(30, 20, 10));

  final random = math.Random(42);
  const blockSize = 16;
  for (var y = 0; y < 256; y += blockSize) {
    for (var x = 0; x < 256; x += blockSize) {
      if (random.nextDouble() > 0.6) {
        final r = 40 + random.nextInt(30);
        final g = 30 + random.nextInt(25);
        final b = 20 + random.nextInt(20);
        img.fillRect(image, x1: x, y1: y, x2: x + blockSize, y2: y + blockSize, color: img.ColorRgb8(r, g, b));
      }
    }
  }

  // 4. Draw huge acronym (scaling for smoothness and 99% height)
  // Use a wide transparent buffer to avoid clipping before trimming
  const acronym = 'VLG';
  final textBuffer = img.Image(width: 512, height: 128, numChannels: 4);
  img.fill(textBuffer, color: img.ColorRgba8(0, 0, 0, 0)); // Transparent
  
  img.drawString(
    textBuffer,
    acronym,
    font: img.arial48,
    x: 10, // Small indent to avoid edge clipping
    y: (128 - 48) ~/ 2,
    color: img.ColorRgba8(218, 165, 32, 255), // Gold
  );

  // Trim transparent edges around the text to get exact bounds
  final trimmed = img.trim(textBuffer, mode: img.TrimMode.transparent);

  // Scale up trimmed text to 99% of 256px height (approx 253px)
  final hugeText = img.copyResize(
    trimmed,
    height: 253,
    interpolation: img.Interpolation.linear,
  );

  // Composite onto center of 256x256 image
  img.compositeImage(
    image,
    hugeText,
    dstX: (256 - hugeText.width) ~/ 2,
    dstY: (256 - hugeText.height) ~/ 2,
  );

  final png = img.encodePng(image);
  File('assets/images/logo.png').writeAsBytesSync(png);
  print('Generator icon generated at assets/images/logo.png');
}
