import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // For DatabaseHelper and ViewRequestsPage

class PhoneAuthScreen extends StatefulWidget {
  final String mode; // 'login' or 'register'
  PhoneAuthScreen({required this.mode});

  @override
  _PhoneAuthScreenState createState() => _PhoneAuthScreenState();
}


class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String _verificationId = '';
  bool _otpSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyPhone() async {
    setState(() => _loading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91${_phoneController.text.trim()}',
      
      verificationCompleted: (PhoneAuthCredential credential) async {
  await FirebaseAuth.instance.signInWithCredential(credential);
  await _goToNextScreen();

},

      
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Verification Failed: ${e.message}')));
        setState(() => _loading = false);
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _loading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _signInWithOTP() async {
    setState(() => _loading = true);

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: _otpController.text.trim(),
    );

    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _goToNextScreen();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid OTP')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _goToNextScreen() async {
    final phone = _phoneController.text.trim();

    final workers = await DatabaseHelper.instance.getWorkers();
    final users = await DatabaseHelper.instance.getUsers();

    final worker = workers.firstWhere(
      (w) => w['phone'] == phone,
      orElse: () => {},
    );
    final user = users.firstWhere(
      (u) => u['phone'] == phone,
      orElse: () => {},
    );

    await DatabaseHelper.instance.logoutAll();

    if (worker.isNotEmpty) {
      await DatabaseHelper.instance.setLoggedIn(phone);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => MainDashboard(phone: phone)));
    } else if (user.isNotEmpty) {
      await DatabaseHelper.instance.setLoggedIn(phone);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => MainDashboard(phone: phone)));
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RegisterLoginScreen(preFilledPhone: phone)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Worker Login')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (!_otpSent) ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: 'Enter Phone Number'),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _verifyPhone,
                      child: Text('Send OTP'),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Enter OTP'),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _signInWithOTP,
                      child: Text('Verify & Continue'),
                    ),
                  ]
                ],
              ),
            ),
    );
  }
}


