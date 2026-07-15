import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
class MyQRScreen extends StatelessWidget {
  const MyQRScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
    return Scaffold(
      body: Center(child: Text(local.translate('please_login_first')))
    );
  }

    return Scaffold(
      appBar: AppBar(title: Text(local.translate('my_contact_card'))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Text(
            local.translate('scan_my_qr_to_chat'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: QrImageView(
                data: user.uid, // هذا هو الـ UID الذي سيقرأه تطبيق الطرف الآخر
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            Text( 
            local.translate('qr_code_disclaimer'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          ],
        ),
      ),
    );
  }
}