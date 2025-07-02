import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await RingtoneService.playRingtone();
  print("📩 Background FCM Message: ${message.messageId}");
}

Future<void> acceptRequest(String requestId) async {
  await RingtoneService.stopRingtone();
  final db = await DatabaseHelper.instance.database;
  final workers = await db.query('workers', where: 'isLoggedIn = 1');
  if (workers.isEmpty) return;
  final currentPhone = workers.first['phone'] as String;
  await db.update('requests', {'assignedTo': currentPhone}, where: 'id = ?', whereArgs: [int.parse(requestId)]);
  await sendExpireNotification(requestId);
}

Future<void> rejectRequest(String requestId) async {
  await RingtoneService.stopRingtone();
  final db = await DatabaseHelper.instance.database;
  final workers = await db.query('workers', where: 'isLoggedIn = 1');
  if (workers.isEmpty) return;
  final currentPhone = workers.first['phone'] as String;
  await DatabaseHelper.instance.markRejected(int.parse(requestId), currentPhone);
}

Future<void> sendExpireNotification(String requestId) async {
  final url = Uri.parse("https://kalpatru-notifier.onrender.com/send-notification");
  await http.post(url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      "topic": "expire_request_\$requestId",
      "title": "Request Taken",
      "body": "This request has been accepted by someone else.",
    }),
  );
}

const AndroidNotificationChannel requestChannel = AndroidNotificationChannel(
  'request_channel',
  'Service Requests',
  description: 'Channel for new service request notifications',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('ringtone'),
);

class RingtoneService {
  static final AudioPlayer _player = AudioPlayer();
  static Future<void> playRingtone() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('ringtone.mpeg'));
    } catch (e) {
      print("Error playing ringtone: \$e");
    }
  }
  static Future<void> stopRingtone() async {
    try {
      await _player.stop();
    } catch (e) {
      print("Error stopping ringtone: \$e");
    }
  }
}

Future<void> handleRequestNotification(Map<String, dynamic> data) async {
  final serviceType = data['serviceType'];
  final block = data['block'];
  final flat = data['flat'];
  final requestId = data['requestId'];

  await flnp.show(
    0,
    "New Service Request",
    "\$serviceType requested at \$block-\$flat",
    NotificationDetails(
      android: AndroidNotificationDetails(
        requestChannel.id,
        requestChannel.name,
        channelDescription: requestChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('ringtone'),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('ACCEPT_\$requestId', 'Accept'),
          AndroidNotificationAction('REJECT_\$requestId', 'Reject'),
        ],
      ),
    ),
  );
  await RingtoneService.playRingtone();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      if (data['actionType'] == 'expire_request') {
        await flnp.cancel(0);
        await RingtoneService.stopRingtone();
      } else {
        await handleRequestNotification(data);
      }
    });

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(requestChannel);
  }

  await flnp.initialize(
    InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) async {
      final actionId = response.actionId ?? '';
      final context = navigatorKey.currentContext;
      if (actionId.startsWith('ACCEPT_') && context != null) {
        final requestId = actionId.replaceFirst('ACCEPT_', '');
        bool? confirmed = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Confirm"),
            content: Text("Do you really want to accept this job?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("No")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text("Yes")),
            ],
          ),
        );
        if (confirmed == true) {
          await acceptRequest(requestId);
          await FirebaseMessaging.instance.unsubscribeFromTopic("expire_request_\$requestId");
        }
      } else if (actionId.startsWith('REJECT_')) {
        final requestId = actionId.replaceFirst('REJECT_', '');
        await rejectRequest(requestId);
      }
    },
  );

  await DatabaseHelper.instance.database;
  runApp(KalptaruApp());
}

class KalptaruApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kalptaru Services',
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(primary: Colors.teal),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: AuthGateScreen(),
    );
  }
}

class AuthGateScreen extends StatefulWidget {
  @override
  _AuthGateScreenState createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  final emailController = TextEditingController();
  final passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLogin = true;
  String name = '';
  String role = 'User';
  String profession = 'Maids (कामवाली)';

  @override
  void initState() {
    super.initState();
    checkLoggedIn();
  }

  Future<void> checkLoggedIn() async {
    final workers = await DatabaseHelper.instance.getWorkers();
    for (var w in workers) {
      if (w['isLoggedIn'] == 1) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainDashboard(phone: w['phone'])),
        );
        return;
      }
    }

    final users = await DatabaseHelper.instance.getUsers();
    for (var u in users) {
      if (u['isLoggedIn'] == 1) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainDashboard(phone: u['phone'])),
        );
        return;
      }
    }
  }

  Future<void> handleAuth() async {
    final email = emailController.text.trim();
    final password = passController.text.trim();

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      Map<String, dynamic> data = {
        'name': name.isEmpty ? 'User' : name,
        'phone': email,
        'role': role,
        'isLoggedIn': 1,
      };

      if (role == 'Worker') {
        data['profession'] = profession;
        await DatabaseHelper.instance.insertWorker(data);
      } else {
        await DatabaseHelper.instance.insertUser(data);
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainDashboard(phone: email)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Login" : "Register")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(labelText: 'Email'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter email' : null,
              ),
              TextFormField(
                controller: passController,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password'),
                validator: (val) =>
                    val == null || val.length < 6 ? 'Min 6 characters' : null,
              ),
              if (!isLogin) ...[
                TextFormField(
                  decoration: InputDecoration(labelText: 'Full Name'),
                  onChanged: (v) => name = v,
                ),
                DropdownButtonFormField<String>(
                  value: role,
                  items: ['User', 'Worker']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => role = v!),
                  decoration: InputDecoration(labelText: 'Role'),
                ),
                if (role == 'Worker')
                  DropdownButtonFormField<String>(
                    value: profession,
                    items: [
                      'Maids (कामवाली)',
                      'Electrician (बिजली मिस्त्री)',
                      'Milkman (दूधवाला)',
                      'Iron (कपड़े प्रेस)',
                      'Plumber (प्लंबर)',
                    ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (v) => setState(() => profession = v!),
                    decoration: InputDecoration(labelText: 'Profession'),
                  ),
              ],
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    await handleAuth();
                  }
                },
                child: Text(isLogin ? 'Login' : 'Register'),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(isLogin
                    ? "Don't have an account? Register"
                    : "Already registered? Login"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------- DASHBOARD -----------------------------------------
class MainDashboard extends StatefulWidget {
  final String phone;
  MainDashboard({required this.phone});

  @override
  _MainDashboardState createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  String role = '';
  String profession = '';

  @override
  void initState() {
    super.initState();
    detectRole();
  }

  Future<void> detectRole() async {
    final db = await DatabaseHelper.instance.database;

    final worker = await db.query(
      'workers',
      where: 'phone = ? AND isLoggedIn = 1',
      whereArgs: [widget.phone],
    );

    if (worker.isNotEmpty) {
      setState(() {
        role = 'Worker';
        profession = worker[0]['profession'] as String;
      });
      return;
    }

    final user = await db.query(
      'users',
      where: 'phone = ? AND isLoggedIn = 1',
      whereArgs: [widget.phone],
    );

    if (user.isNotEmpty) {
      setState(() {
        role = 'User';
      });
      return;
    }

    setState(() => role = 'Unknown');
  }

  Future<void> logoutUser() async {
    await FirebaseAuth.instance.signOut();
    await DatabaseHelper.instance.logoutAll();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AuthGateScreen()),
      (route) => false,
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.tealAccent),
              SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken),
          child: Image.asset(
            'assets/kalpatru_bg.jpeg',
            fit: BoxFit.cover,
            height: double.infinity,
            width: double.infinity,
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('Kalptaru Dashboard'),
            actions: [
              IconButton(
                icon: Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: logoutUser,
              )
            ],
          ),
          body: role.isEmpty
              ? Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(height: 12),
                        if (role != 'Unknown') ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              children: [
                                Text("Logged in as: $role", style: TextStyle(color: Colors.white, fontSize: 16)),
                                Text("Email: ${widget.phone}", style: TextStyle(color: Colors.white70)),
                                if (role == 'Worker')
                                  Text("Profession: $profession", style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                        ],
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            children: [
                              if (role == 'Worker')
                                _tile(context, Icons.notifications_active, 'View Requests', () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => ViewRequestsPage()));
                                }),
                              _tile(context, Icons.home_repair_service, 'Get Services', () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => MainDashboard(phone: widget.phone)));
                              }),
                              _tile(context, Icons.info_outline, 'About Us', () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => AboutPage()));
                              }),
                              _tile(context, Icons.apartment, 'Apartment Details', () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => ApartmentPage()));
                              }),
                              _tile(context, Icons.volunteer_activism, 'Support / Donate', () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => DonationPage()));
                              }),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.logout),
                            label: Text('Logout'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: logoutUser,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.tealAccent,
            onPressed: () async {
              const message = "Hi Aditya, I want help regarding Kalptaru Services app.";
              const phone = "919369250645";
              final url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeFull(message)}");
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("WhatsApp not installed or URL can't be launched")),
                );
              }
            },
            child: Icon(Icons.headset_mic, color: Colors.black),
          ),
        ),
      ],
    );
  }
}

// ---------------------- Donation Page ----------------------
class DonationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Support Us")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              "If you'd like to support this app and help us improve services for Kalptaru residents, please consider donating!",
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 30),
            Image.asset('assets/qr.jpeg', height: 200), // Replace with your QR
            SizedBox(height: 20),
            Text("UPI ID: acpedwardlivingston-1@oksbi", style: TextStyle(fontSize: 16, color: Colors.tealAccent)),
            SizedBox(height: 10),
            Text(
              "Scan the QR code or send to UPI above.\nThank you for your support ❤️",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Payment / Donation")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView(
          children: [
            Text(
              "Pay for completed service OR support Kalptaru app.",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            Text(
              "This payment includes worker charges + small app commission.\nPlease pay only after the work is done.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 30),
            Image.asset('assets/qr.jpeg', height: 200),
            SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text("Scan the QR code to pay", style: TextStyle(fontSize: 16)),
                  SizedBox(height: 10),
                  Text("UPI ID:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("acpedwardlivingston-1@oksbi", style: TextStyle(fontSize: 16, color: Colors.tealAccent)),
                ],
              ),
            ),
            SizedBox(height: 30),
            Divider(thickness: 1),
            SizedBox(height: 20),
            Text(
              "After payment, the worker will take a photo of the payment receipt and send it to us on WhatsApp for verification.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                const message = "Hi Aditya, this is the payment screenshot for completed service.";
                const phone = "919369250645";
                final url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeFull(message)}");

                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Could not open WhatsApp"),
                  ));
                }
              },
              icon: Icon(Icons.chat),
              label: Text("Contact Admin on WhatsApp"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------ BookingForm ------------------------------------

class BookingForm extends StatefulWidget {
  final String serviceType;
  BookingForm({required this.serviceType});

  @override
  _BookingFormState createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  final _formKey = GlobalKey<FormState>();
  String issue = '', block = '', flat = '';
  DateTime selectedDate = DateTime.now();
  String selectedHour = '10', selectedMeridiem = 'AM';
  List<String> hours = List.generate(12, (i) => '${i + 1}');

  String? selectedFloor;
  String? selectedFlatOnFloor;

  List<String> floors = List.generate(12, (i) => '${i + 1}');
  List<String> flatsOnFloor = List.generate(8, (i) => '${(i + 1).toString().padLeft(2, '0')}');

  // Maid-specific
  List<String> selectedWorks = [];
  final List<String> workOptions = [
    'Jhadu (झाड़ू)',
    'Pocha (पोंछा)',
    'Dusting (धूल साफ करना)',
    'Cooking (खाना बनाना)',
    'Clothes Washing (कपड़े धोना)',
    'Utensil Cleaning (बर्तन साफ करना)',
  ];
  String maidNote = '';

  // Milkman-specific
  String? selectedLitres;
  String milkNote = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.serviceType} Form')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.serviceType == 'Maids (कामवाली)') ...[
                    SizedBox(height: 12),
                    Text("Select Work Required:", style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Wrap(
                      spacing: 8.0,
                      children: workOptions.map((work) {
                        return FilterChip(
                          label: Text(work),
                          selected: selectedWorks.contains(work),
                          onSelected: (selected) {
                            setState(() {
                              selected ? selectedWorks.add(work) : selectedWorks.remove(work);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(labelText: 'Write note for maid'),
                      maxLines: 2,
                      onChanged: (val) => maidNote = val,
                    ),
                  ] else if (widget.serviceType == 'Milkman (दूधवाला)') ...[
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: 'Select Litres of Milk'),
                      items: ['1', '2', '3', '4', '5']
                          .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                          .toList(),
                      onChanged: (val) => setState(() => selectedLitres = val!),
                      validator: (val) => val == null ? 'Please select litres' : null,
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(labelText: 'Note for Milkman'),
                      maxLines: 2,
                      onChanged: (val) => milkNote = val,
                    ),
                  ] else ...[
                    SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(labelText: 'Write your issue here'),
                      maxLines: 3,
                      onChanged: (val) => issue = val,
                      validator: (val) => val == null || val.isEmpty ? 'Please enter issue' : null,
                    ),
                  ],

                  ListTile(
                    title: Text("Select Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedHour,
                          items: hours.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                          onChanged: (val) => setState(() => selectedHour = val!),
                          decoration: InputDecoration(labelText: "Time:"),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedMeridiem,
                          items: ['AM', 'PM'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (val) => setState(() => selectedMeridiem = val!),
                          decoration: InputDecoration(labelText: "AM/PM"),
                        ),
                      ),
                    ],
                  ),

                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: 'Select Block'),
                    items: ['D', 'E'].map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (val) => setState(() => block = val!),
                    validator: (val) => val == null ? 'Please select block' : null,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(labelText: 'Floor'),
                          value: selectedFloor,
                          items: floors
                              .map((floor) => DropdownMenuItem(value: floor, child: Text('Floor $floor')))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedFloor = val;
                              selectedFlatOnFloor = null;
                            });
                          },
                          validator: (val) => val == null ? 'Select floor' : null,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(labelText: 'Flat'),
                          value: selectedFlatOnFloor,
                          items: flatsOnFloor
                              .map((flat) => DropdownMenuItem(value: flat, child: Text('Flat $flat')))
                              .toList(),
                          onChanged: (val) => setState(() => selectedFlatOnFloor = val),
                          validator: (val) => val == null ? 'Select flat' : null,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        flat = '${selectedFloor ?? ''}${selectedFlatOnFloor ?? ''}';

                        String finalIssue;
                        if (widget.serviceType == 'Maids (कामवाली)') {
                          finalIssue = '''Work: ${selectedWorks.join(", ")}
Note: $maidNote''';
                        } else if (widget.serviceType == 'Milkman (दूधवाला)') {
                          finalIssue = '''Milk Required: $selectedLitres Litres
Note: $milkNote''';
                        } else {
                          finalIssue = issue;
                        }

                        await DatabaseHelper.instance.insertRequest({
                          'serviceType': widget.serviceType,
                          'issue': finalIssue,
                          'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                          'time': '$selectedHour $selectedMeridiem',
                          'block': block,
                          'flat': flat,
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Request Submitted!')),
                        );
                        Navigator.pop(context);
                      }
                    },
                    child: Text('Submit Request'),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------- Register Page ----------------------
class RegisterProvider extends StatefulWidget {
  @override
  _RegisterProviderState createState() => _RegisterProviderState();
}

class _RegisterProviderState extends State<RegisterProvider> {
  final _formKey = GlobalKey<FormState>();
  String name = '', email = '', profession = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register as Service Provider')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Full Name'),
                    onChanged: (val) => name = val,
                    validator: (val) => val == null || val.isEmpty ? 'Enter name' : null,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (val) => email = val,
                    validator: (val) => val == null || val.isEmpty ? 'Enter email' : null,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Profession'),
                    onChanged: (val) => profession = val,
                    validator: (val) => val == null || val.isEmpty ? 'Enter profession' : null,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        await DatabaseHelper.instance.insertWorker({
                          'name': name,
                          'phone': email, // 👈 Reusing phone field for email
                          'profession': profession,
                          'role': 'Worker',
                          'isLoggedIn': 1,
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Registered Successfully')),
                        );

                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MainDashboard(phone: email),
                          ),
                        );
                      }
                    },
                    child: Text('Register'),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ---------------------- About & Apartment Page ----------------------
class AboutPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("About Developer")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'This application is built by Aditya (IIT Ropar) with the vision of making daily service requests in Kalptaru Apartments simple, accessible, and efficient.',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

class ApartmentPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Apartment Details")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Kalptaru Apartments:\n• Blocks: D & E\n• Floors: 12\n• Flats/Floor: 8\n• Contact Admin: +91-9369250645',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

// ---------------------- Database Helper ----------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(directory.path, 'kalptaru.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT,
        role TEXT,
        isLoggedIn INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE workers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT,
        role TEXT,
        profession TEXT,
        isLoggedIn INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serviceType TEXT,
        issue TEXT,
        date TEXT,
        time TEXT,
        block TEXT,
        flat TEXT,
        assignedTo TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE rejections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        requestId INTEGER,
        phone TEXT
      )
    ''');
  }

  Future<void> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertWorker(Map<String, dynamic> worker) async {
    final db = await database;
    await db.insert('workers', worker, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertRequest(Map<String, dynamic> request) async {
    final db = await database;
    await db.insert('requests', request, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markRejected(int requestId, String phone) async {
    final db = await database;
    await db.insert('rejections', {
      'requestId': requestId,
      'phone': phone,
    });
  }

  Future<void> setLoggedIn(String phone) async {
    final db = await database;
    
    
    await db.update('users', {'isLoggedIn': 1}, where: 'phone = ?', whereArgs: [phone]);
    await db.update('workers', {'isLoggedIn': 1}, where: 'phone = ?', whereArgs: [phone]);
  }

  Future<void> logoutAll() async {
    final db = await database;
   
 
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await database;
    return await db.query('users');
  }

  Future<List<Map<String, dynamic>>> getWorkers() async {
    final db = await database;
    return await db.query('workers');
  }

  Future<List<Map<String, dynamic>>> getRequests(String phone) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT * FROM requests
      WHERE (assignedTo IS NULL OR assignedTo = ?)
      AND id NOT IN (
        SELECT requestId FROM rejections WHERE phone = ?
      )
      ORDER BY date DESC, time DESC
    ''', [phone, phone]);
  }

  Future<void> unassignRequest(int id) async {
    final db = await database;
    await db.update('requests', {'assignedTo': null}, where: 'id = ?', whereArgs: [id]);
  }
}

class ViewRequestsPage extends StatefulWidget {
  @override
  _ViewRequestsPageState createState() => _ViewRequestsPageState();
}

class _ViewRequestsPageState extends State<ViewRequestsPage> {
  String currentPhone = '';
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    initWorker();
  }

  Future<void> initWorker() async {
    final workers = await DatabaseHelper.instance.getWorkers();
    final loggedIn = workers.firstWhere(
      (w) => w['isLoggedIn'] == 1,
      orElse: () => <String, dynamic>{},
    );
    if (loggedIn.isNotEmpty) {
      currentPhone = loggedIn['phone'];
      loadRequests();
    }
  }

  Future<void> loadRequests() async {
    final data = await DatabaseHelper.instance.getRequests(currentPhone);
    setState(() => requests = data);
  }

  Future<void> sendExpireNotification(String requestId) async {
    final url = Uri.parse("https://kalpatru-notifier.onrender.com/send-notification");
    await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "topic": "expire_request_\$requestId",
        "title": "Request Taken",
        "body": "This request has been accepted by someone else.",
      }),
    );
  }

  Future<void> sendFCMToProfessionTopic(String profession) async {
    final topic = profession.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final url = Uri.parse("https://kalpatru-notifier.onrender.com/send-notification");
    await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "topic": topic,
        "title": "Service Request Cancelled",
        "body": "A service request for \$profession is active again.",
      }),
    );
  }

  Future<void> assignRequest(int id, String phone) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('requests', {'assignedTo': phone}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cancelRequest(int id, Map<String, dynamic> req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Cancel Accepted Request?"),
        content: Text("Do you really want to cancel and reopen this request for others?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text("Yes")),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.unassignRequest(id);
      await sendFCMToProfessionTopic(req['serviceType']);
      await loadRequests();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Request cancelled and reactivated."))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Service Requests')),
      body: requests.isEmpty
          ? Center(child: Text("No service requests."))
          : ListView.builder(
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final req = requests[index];
                final assignedTo = req['assignedTo'];
                final requestId = req['id'];

               return Card(
  color: Colors.black,
  margin: EdgeInsets.all(8),
  child: ListTile(
    title: Text(req['serviceType'], style: TextStyle(color: Colors.white)),
    subtitle: Text(
      'Issue: ${req['issue']}\n'
      'Date: ${req['date']} at ${req['time']}\n'
      'Block: ${req['block']} • Flat: ${req['flat']}\n'
      'Status: ${assignedTo == null ? "Pending" : assignedTo == currentPhone ? "You Accepted" : "Assigned to other"}',
      style: TextStyle(color: Colors.white70),
    ),
    trailing: assignedTo == null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check, color: Colors.green),
                onPressed: () async {
                  await assignRequest(requestId, currentPhone);
                  await sendExpireNotification(requestId.toString());
                  await loadRequests();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ Request accepted!"))
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text("Reject Request?"),
                      content: Text("Are you sure you want to reject this request?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text("No")),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text("Yes")),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await DatabaseHelper.instance.markRejected(requestId, currentPhone);
                    await loadRequests();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("❌ Request rejected."))
                    );
                  }
                },
              ),
            ],
          )
        : assignedTo == currentPhone
            ? TextButton(
                onPressed: () => cancelRequest(requestId, req),
                child: Text('Cancel', style: TextStyle(color: Colors.orange)),
              )
            : null,
  ),
);

              },
            ),
    );
  }
}




Future<void> registerWithEmail(String email, String password) async {
  try {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    print('✅ Registration successful');
  } catch (e) {
    print('❌ Registration failed: $e');
  }
}

Future<void> loginWithEmail(String email, String password) async {
  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    print('✅ Login successful');
  } catch (e) {
    print('❌ Login failed: $e');
  }
}

class EmailAuthScreen extends StatefulWidget {
  @override
  _EmailAuthScreenState createState() => _EmailAuthScreenState();
}

class RegisterExtraInfoScreen extends StatefulWidget {
  final String email;
  RegisterExtraInfoScreen({required this.email});

  @override
  _RegisterExtraInfoScreenState createState() => _RegisterExtraInfoScreenState();
}

class _RegisterExtraInfoScreenState extends State<RegisterExtraInfoScreen> {
  String name = '', role = 'User', profession = 'Maids (कामवाली)';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Complete Registration")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextFormField(
              decoration: InputDecoration(labelText: 'Your Name'),
              onChanged: (val) => name = val,
            ),
            DropdownButtonFormField<String>(
              value: role,
              items: ['User', 'Worker']
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (val) => setState(() => role = val!),
              decoration: InputDecoration(labelText: 'Select Role'),
            ),
            if (role == 'Worker')
              DropdownButtonFormField<String>(
                value: profession,
                items: [
                  'Maids (कामवाली)',
                  'Electrician (बिजली मिस्त्री)',
                  'Milkman (दूधवाला)',
                  'Iron (कपड़े प्रेस)',
                  'Plumber (प्लंबर)',
                ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (val) => setState(() => profession = val!),
                decoration: InputDecoration(labelText: 'Select Profession'),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                Map<String, dynamic> userData = {
                  'name': name,
                  'phone': widget.email,
                  'role': role,
                  'isLoggedIn': 1,
                };
                if (role == 'Worker') {
                  userData['profession'] = profession;
                  await DatabaseHelper.instance.insertWorker(userData);
                } else {
                  await DatabaseHelper.instance.insertUser(userData);
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MainDashboard(phone: widget.email),
                  ),
                );
              },
              child: Text("Finish"),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final emailController = TextEditingController();
  final passController = TextEditingController();

  // ✅ Email format validation function
  bool isValidEmail(String email) {
    final regex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
       r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
       r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$");

    return regex.hasMatch(email);
  }

  // ✅ Email check function (placed outside build/onPressed)
  Future<bool> isEmailRegistered(String email) async {
    final users = await DatabaseHelper.instance.getUsers();
    final workers = await DatabaseHelper.instance.getWorkers();

    return users.any((u) => u['phone'] == email) ||
           workers.any((w) => w['phone'] == email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gmail Login/Register")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            SizedBox(height: 20),

            // ✅ Register Button
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final pass = passController.text.trim();

                // ✅ Email format check
                if (!isValidEmail(email)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('⚠️ Please enter a valid email address.')),
                  );
                  return;
                }

                final alreadyExists = await isEmailRegistered(email);

                if (alreadyExists) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('⚠️ This email is already registered. Please login instead.')),
                  );
                  return;
                }

                await registerWithEmail(email, pass);

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => RegisterExtraInfoScreen(email: email)),
                );
              },
              child: Text("Register"),
            ),

            // ✅ Login Button
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final pass = passController.text.trim();

                // ✅ Email format check
                if (!isValidEmail(email)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('⚠️ Please enter a valid email address.')),
                  );
                  return;
                }

                await loginWithEmail(email, pass);

                final existingUsers = (await DatabaseHelper.instance.getUsers())
                    .where((u) => u['phone'] == email)
                    .toList();

                final existingWorkers = (await DatabaseHelper.instance.getWorkers())
                    .where((w) => w['phone'] == email)
                    .toList();

                if (existingUsers.isNotEmpty || existingWorkers.isNotEmpty) {
                  await DatabaseHelper.instance.setLoggedIn(email);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => MainDashboard(phone: email)),
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => RegisterExtraInfoScreen(email: email)),
                  );
                }
              },
              child: Text("Login"),
            ),
          ],
        ),
      ),
    );
  }
}


