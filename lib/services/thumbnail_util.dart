import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;

class ThumbnailUtil {
  static Future<String?> generateImageThumbnail(String srcPath, String destDir) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final thumb = img.copyResize(image, width: 300);
      final outPath = p.join(destDir, '${p.basenameWithoutExtension(srcPath)}_thumb.jpg');
      final outFile = File(outPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(img.encodeJpg(thumb, quality: 80));
      return outPath;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> generateVideoThumbnail(String videoPath, String destDir) async {
    try {
      final outPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: destDir,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 300,
        quality: 75,
      );
      return outPath;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> generatePdfThumbnail(String pdfPath, String destDir) async {
    return null;
  }
}
