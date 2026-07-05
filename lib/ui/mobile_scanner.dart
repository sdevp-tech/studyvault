import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/chat_service.dart';
import '../ui/screens/chat_room_screen.dart';
import 'l10n/app_localizations.dart';
class QRScannerScreen extends StatefulWidget {
  final String? chatId;

  const QRScannerScreen({super.key, this.chatId});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(local.translate('scan_qr_code'))),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_isProcessing) return;

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              setState(() => _isProcessing = true);
              final String targetUid = barcode.rawValue!;

              // حماية وإصلاح الانهيار: التحقق من أن الكود يعود لمستخدم فعلي
              bool userExists = await ChatService().checkUserExists(targetUid);
              if (!userExists) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(local.translate('invalid_qr_code'))),
                  );
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _isProcessing = false);
                  });
                }
                break; 
              }

              // جلب الاسم الحقيقي
              String realName = await ChatService().getUserName(targetUid);

              if (widget.chatId != null) {
                await ChatService().addMemberToGroup(widget.chatId!, targetUid);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(local.translate('member_added_success'))),
                  );
                }
              } else {
                String chatId = await ChatService().startIndividualChat(targetUid, realName);
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomScreen(
                        chatId: chatId,
                        title: realName,
                      ),
                    ),
                  );
                }
              }
              break;
            }
          }
        },
      ),
    );
  }
}
