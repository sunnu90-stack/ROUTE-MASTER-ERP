import 'package:flutter/material.dart';

void main() {
  runApp(const MitraApp());
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DESIGN SYSTEM & COLORS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class MitraColors {
  static const Color saffron = Color(0xFFFF6B35);
  static const Color gold = Color(0xFFFFB800);
  static const Color emerald = Color(0xFF00C389);
  static const Color indigo = Color(0xFF2D1B69);
  static const Color sky = Color(0xFF000000);
  static const Color black = Color(0xFF000000);
  static const Color bgDeep = Color(0xFF0A0612);
  static const Color bgCard = Color(0xFF120C24);
  static const Color textPrimary = Color(0xFFF5F0FF);
  static const Color textSecondary = Color(0xA6F5F0FF); // 65% opacity
  static const Color textMuted = Color(0x59F5F0FF); // 35% opacity
  static const Color border = Color(0x337C5CDD); // rgba(124,92,221,0.2)
}

class MitraApp extends StatelessWidget {
  const MitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MITRA App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: MitraColors.bgDeep,
        brightness: Brightness.dark,
        fontFamily: 'Mukta', // Ensure this is in pubspec.yaml
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: MitraColors.textPrimary),
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 01: SPLASH
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Simulate loading and navigate to Login
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0A3E), MitraColors.black, Color(0xFF0F2A1A)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Logo Block
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MitraColors.saffron, MitraColors.gold],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: MitraColors.saffron.withOpacity(0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: const Center(
                child: Text('ðŸŽ“', style: TextStyle(fontSize: 40)),
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Baloo 2'),
                children: [
                  TextSpan(
                      text: 'MI',
                      style: TextStyle(color: MitraColors.textPrimary)),
                  TextSpan(
                      text: 'TRA',
                      style: TextStyle(color: MitraColors.saffron)),
                ],
              ),
            ),
            const Text(
              'AR LEARNING PLATFORM',
              style: TextStyle(
                color: MitraColors.textSecondary,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const CircularProgressIndicator(color: MitraColors.saffron),
            const SizedBox(height: 16),
            const Text(
              'Ministry of Education, Govt. of India',
              style: TextStyle(color: MitraColors.textMuted, fontSize: 10),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 03: LOGIN / OTP
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isStudent = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Top Art Header
          Container(
            height: 180,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A0A3E),
                  MitraColors.black,
                  Color(0xFF0A2010)
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [MitraColors.saffron, MitraColors.gold],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: MitraColors.saffron.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: const Center(
                    child: Text('ðŸŽ“', style: TextStyle(fontSize: 36))),
              ),
            ),
          ),

          // Scrollable Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Namaste! ðŸ™',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sign in to continue learning',
                    style: TextStyle(
                        fontSize: 13, color: MitraColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Role Selector
                  const Text('I AM A',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MitraColors.textMuted,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildRoleButton('Student', 'ðŸŽ’', isStudent, () {
                        setState(() => isStudent = true);
                      }),
                      const SizedBox(width: 8),
                      _buildRoleButton('Teacher', 'ðŸ‘©â€ðŸ«', !isStudent,
                          () {
                        setState(() => isStudent = false);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Mobile Input
                  const Text('MOBILE NUMBER',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MitraColors.textMuted,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: MitraColors.bgCard,
                      border:
                          Border.all(color: MitraColors.saffron, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text('ðŸ‡®ðŸ‡³ +91  |  ',
                            style: TextStyle(color: MitraColors.textMuted)),
                        Expanded(
                          child: TextFormField(
                            initialValue: '98765 43210',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // OTP Boxes
                  const Text('ENTER OTP',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MitraColors.textMuted,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildOtpBox('4', true),
                      _buildOtpBox('2', true),
                      _buildOtpBox('8', true),
                      _buildOtpBox('', false),
                      _buildOtpBox('', false),
                      _buildOtpBox('', false),
                    ],
                  ),

                  // WhatsApp Hint
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: MitraColors.emerald.withOpacity(0.1),
                      border: Border.all(
                          color: MitraColors.emerald.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: const [
                        Text('ðŸ’¬ ', style: TextStyle(fontSize: 14)),
                        Text('OTP sent via WhatsApp to +91 987XX',
                            style: TextStyle(
                                fontSize: 11, color: MitraColors.emerald)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor:
                            MitraColors.saffron, // Simple solid color for CTA
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/home'),
                      child: const Text('Verify & Login â†’',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleButton(
      String title, String emoji, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive
                ? MitraColors.saffron.withOpacity(0.12)
                : MitraColors.bgCard,
            border: Border.all(
                color: isActive ? MitraColors.saffron : MitraColors.border,
                width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? MitraColors.saffron
                        : MitraColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(String val, bool filled) {
    return Container(
      width: 45,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MitraColors.bgCard,
        border: Border.all(
            color: filled ? MitraColors.saffron : MitraColors.border, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        val.isEmpty ? '_' : val,
        style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: filled ? MitraColors.saffron : MitraColors.textPrimary),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 05: HOME
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: MitraColors.bgCard,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: MitraColors.saffron,
        unselectedItemColor: MitraColors.textMuted,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'HOME'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'LEARN'),
          BottomNavigationBarItem(icon: Icon(Icons.view_in_ar), label: 'AR'),
          BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events), label: 'RANKS'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'PROFILE'),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: MitraColors.bgCard,
                border: Border(
                    bottom: BorderSide(color: MitraColors.border, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ðŸŒ… Good morning,',
                      style: TextStyle(
                          fontSize: 12, color: MitraColors.textMuted)),
                  const Text('Priya Sharma ðŸ‘‹',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: MitraColors.saffron.withOpacity(0.12),
                      border: Border.all(
                          color: MitraColors.saffron.withOpacity(0.25)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('ðŸ« Class IX Â· Govt. School Jaipur',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MitraColors.saffron)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      Text('ðŸ”¥ 14 ',
                          style: TextStyle(
                              color: MitraColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      Text('day streak  Â·  ',
                          style: TextStyle(
                              color: MitraColors.textMuted, fontSize: 12)),
                      Text('â­ 2,840 ',
                          style: TextStyle(
                              color: MitraColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      Text('XP',
                          style: TextStyle(
                              color: MitraColors.textMuted, fontSize: 12)),
                    ],
                  )
                ],
              ),
            ),

            // Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Continue Learning
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('CONTINUE LEARNING',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: MitraColors.textMuted,
                                letterSpacing: 1.5)),
                        Text('See all',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: MitraColors.saffron)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: MitraColors.bgCard,
                        border: Border.all(
                            color: MitraColors.saffron.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Science Â· Chapter 3',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: MitraColors.textMuted)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: MitraColors.saffron.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('65%',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: MitraColors.saffron)),
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('ðŸ”¬ Microscopy & Cell Structure AR',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: 0.65,
                            backgroundColor: MitraColors.border,
                            color: MitraColors.saffron,
                            borderRadius: BorderRadius.circular(5),
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Subjects Grid
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('SUBJECTS',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: MitraColors.textMuted,
                                letterSpacing: 1.5)),
                        Text('6 of 6',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: MitraColors.saffron)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.4,
                      children: [
                        _buildSubjectCard('Science', 'ðŸ”¬',
                            '68% Â· 14 AR topics', const Color(0x1F6366F1)),
                        _buildSubjectCard('Maths', 'ðŸ“', '45% Â· 18 topics',
                            const Color(0x1F10B981)),
                        _buildSubjectCard('History', 'ðŸ“œ', '30% Â· 12 topics',
                            const Color(0x1FF59E0B)),
                        _buildSubjectCard('Geography', 'ðŸŒ',
                            '55% Â· 10 topics', const Color(0x1F06B6D4)),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(
      String title, String emoji, String meta, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: MitraColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const Spacer(),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: MitraColors.textPrimary)),
          Text(meta,
              style:
                  const TextStyle(fontSize: 10, color: MitraColors.textMuted)),
        ],
      ),
    );
  }
}
