import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:fl_chart/fl_chart.dart';

/**
 * MUMWISE - FINANCIAL INDEPENDENCE FOR BUSY MUMS
 * Features: AI Money Saving Tips, Investment Guidance, Cost Comparisons,
 * Renovation Savings, Batch Cooking Calculator, Smart Shopping Assistant
 */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat
  await Purchases.configure(
    PurchasesConfiguration('goog_tlIFORxqKQfSWwofPiniJuIoDEJ'),
  );

  tz.initializeTimeZones();
  await _initNotifications();

  runApp(const MumWiseApp());
}

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await notificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
}

class MumWiseApp extends StatelessWidget {
  const MumWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MumWise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2ECC71),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// === MODELS ===

enum UserTier { free, pro, premium }

class UserSession {
  final String userId;
  final String email;
  int trialsRemaining;
  int adviceCreditsRemaining;
  int analysisCreditsRemaining;
  UserTier tier;
  bool dailyTipsEnabled;
  double savingsGoal;
  double currentSavings;

  UserSession({
    required this.userId,
    required this.email,
    this.trialsRemaining = 5,
    this.adviceCreditsRemaining = 0,
    this.analysisCreditsRemaining = 0,
    this.tier = UserTier.free,
    this.dailyTipsEnabled = true,
    this.savingsGoal = 1000.0,
    this.currentSavings = 0.0,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    userId: json['user_id'] ?? '',
    email: json['email'] ?? '',
    trialsRemaining: json['trials_remaining'] ?? 5,
    adviceCreditsRemaining: json['advice_credits_remaining'] ?? 0,
    analysisCreditsRemaining: json['analysis_credits_remaining'] ?? 0,
    tier: UserTier.values.firstWhere(
      (t) => t.toString().split('.').last == (json['tier'] ?? 'free'),
      orElse: () => UserTier.free,
    ),
    dailyTipsEnabled: json['daily_tips_enabled'] ?? true,
    savingsGoal: (json['savings_goal'] ?? 1000.0).toDouble(),
    currentSavings: (json['current_savings'] ?? 0.0).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'trials_remaining': trialsRemaining,
    'advice_credits_remaining': adviceCreditsRemaining,
    'analysis_credits_remaining': analysisCreditsRemaining,
    'tier': tier.toString().split('.').last,
    'daily_tips_enabled': dailyTipsEnabled,
    'savings_goal': savingsGoal,
    'current_savings': currentSavings,
  };
}

class ExpenseEntry {
  final String id;
  final String category;
  final double amount;
  final DateTime date;
  final String notes;

  ExpenseEntry({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.notes = '',
  });

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) => ExpenseEntry(
    id: json['id'] ?? '',
    category: json['category'] ?? '',
    amount: (json['amount'] ?? 0.0).toDouble(),
    date: DateTime.parse(json['date']),
    notes: json['notes'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'amount': amount,
    'date': date.toIso8601String(),
    'notes': notes,
  };
}

class FinancialGoal {
  final String id;
  final String title;
  final double targetAmount;
  final double currentAmount;
  final DateTime deadline;
  final String category;

  FinancialGoal({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.deadline,
    required this.category,
  });

  factory FinancialGoal.fromJson(Map<String, dynamic> json) => FinancialGoal(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    targetAmount: (json['target_amount'] ?? 0.0).toDouble(),
    currentAmount: (json['current_amount'] ?? 0.0).toDouble(),
    deadline: DateTime.parse(json['deadline']),
    category: json['category'] ?? '',
  );
}

// === API SERVICE ===

class ApiService {
  static const String baseUrl =
      'https://mum-hdfvdudvdgaydvdg.eastus-01.azurewebsites.net';

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getFinancialAdvice(
    String userId,
    String query,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/financial/advice'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'query': query}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> compareCosts(
    String userId,
    String type,
    List<String> items,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/financial/compare'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'type': type, 'items': items}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getShoppingAlternatives(
    String userId,
    String product,
    File? productImage,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/financial/shopping-alternatives'),
    );
    request.fields['user_id'] = userId;
    request.fields['product'] = product;

    if (productImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath('image', productImage.path),
      );
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getRenovationAdvice(
    String userId,
    String projectType,
    double budget,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/financial/renovation'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'project_type': projectType,
        'budget': budget,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getInvestmentGuidance(
    String userId,
    double amount,
    String riskTolerance,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/financial/investment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'risk_tolerance': riskTolerance,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getBatchCookingCosts(
    String userId,
    List<String> meals,
    int servings,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/financial/batch-cooking'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'meals': meals,
        'servings': servings,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getDailyTip(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/financial/daily-tip?user_id=$userId'),
    );
    return jsonDecode(response.body);
  }

  static Future<List<ExpenseEntry>> getExpenses(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/user/$userId/expenses'),
    );
    final List<dynamic> data = jsonDecode(response.body)['expenses'];
    return data.map((e) => ExpenseEntry.fromJson(e)).toList();
  }

  static Future<void> saveExpense(String userId, ExpenseEntry expense) async {
    await http.post(
      Uri.parse('$baseUrl/user/$userId/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(expense.toJson()),
    );
  }

  static Future<List<FinancialGoal>> getGoals(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/goals'));
    final List<dynamic> data = jsonDecode(response.body)['goals'];
    return data.map((e) => FinancialGoal.fromJson(e)).toList();
  }
}

// === AUTH WRAPPER ===

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  UserSession? session;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');

    if (userData != null) {
      setState(() {
        session = UserSession.fromJson(jsonDecode(userData));
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  void handleAuth(UserSession user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_session', jsonEncode(user.toJson()));
    setState(() => session = user);

    // === SYNC WITH REVENUECAT ===
    try {
      await Purchases.logIn(user.userId);
      await Purchases.setEmail(user.email);

      // UPDATE THIS STRING FOR EACH APP:
      await Purchases.setAttributes({
        'app_name':
            'MumWise', // Change to 'MumWise', 'AICoach', 'PacksLight', etc.
        'signup_tier': user.tier.toString(),
      });
    } catch (e) {
      debugPrint('RevenueCat user sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return session == null
        ? LoginScreen(onSuccess: handleAuth)
        : MainNavigation(
          user: session!,
          onSessionUpdate: (u) => setState(() => session = u),
        );
  }
}

// === LOGIN SCREEN ===

class LoginScreen extends StatefulWidget {
  final Function(UserSession) onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final response =
          isLogin
              ? await ApiService.login(
                _emailController.text,
                _passController.text,
              )
              : await ApiService.register(
                _emailController.text,
                _passController.text,
              );

      if (response['success'] == true) {
        widget.onSuccess(UserSession.fromJson(response['user']));
      } else {
        _showError(response['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      _showError('Network error. Please check your connection.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        final response = await ApiService.loginWithGoogle(auth.idToken!);

        if (response['success'] == true) {
          widget.onSuccess(UserSession.fromJson(response['user']));
        }
      }
    } catch (e) {
      _showError('Google sign-in failed');
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showError('Please enter your email');
      return;
    }

    try {
      final response = await ApiService.forgotPassword(_emailController.text);
      _showError(
        response['message'] ?? 'Password reset link sent',
        isError: false,
      );
    } catch (e) {
      _showError('Failed to send reset link');
    }
  }

  void _showError(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.green.shade700, Colors.teal.shade400],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'MumWise',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Financial Independence Made Simple',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 48),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.contains('@') ? null : 'Invalid email',
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.length >= 6 ? null : 'Min 6 characters',
                    ),

                    if (isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child:
                            isLoading
                                ? const CircularProgressIndicator()
                                : Text(
                                  isLogin ? 'Login' : 'Register',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? 'New here? Create Account'
                            : 'Have an account? Login',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white54)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white54)),
                        ],
                      ),
                    ),

                    OutlinedButton.icon(
                      onPressed: _loginWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === MAIN NAVIGATION ===

class MainNavigation extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onSessionUpdate;

  const MainNavigation({
    super.key,
    required this.user,
    required this.onSessionUpdate,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _updatePages();
  }

  @override
  void didUpdateWidget(MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _updatePages();
    }
  }

  void _updatePages() {
    _pages = [
      HomeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      MoneySaversScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      InvestmentScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      AIAssistantScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      UpgradeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      ProfileScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Save',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: 'Invest',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'AI Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Upgrade',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// === HOME SCREEN ===

class HomeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const HomeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _dailyTip;
  bool _isLoadingTip = false;
  List<ExpenseEntry> _recentExpenses = [];

  @override
  void initState() {
    super.initState();
    _loadDailyTip();
    _loadRecentExpenses();
  }

  Future<void> _loadDailyTip() async {
    setState(() => _isLoadingTip = true);
    try {
      final response = await ApiService.getDailyTip(widget.user.userId);
      if (response['success'] == true) {
        setState(() => _dailyTip = response['tip']);
      }
    } catch (e) {
      // Handle error silently
    } finally {
      setState(() => _isLoadingTip = false);
    }
  }

  Future<void> _loadRecentExpenses() async {
    try {
      final expenses = await ApiService.getExpenses(widget.user.userId);
      setState(() => _recentExpenses = expenses.take(5).toList());
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    final savingsProgress =
        widget.user.savingsGoal > 0
            ? (widget.user.currentSavings / widget.user.savingsGoal).clamp(
              0.0,
              1.0,
            )
            : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MumWise',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: const Icon(Icons.bolt, size: 18),
              label: Text(
                '${widget.user.trialsRemaining} Credits',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.green.shade100,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadDailyTip();
          await _loadRecentExpenses();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 16),
            _buildSavingsGoalCard(savingsProgress),
            const SizedBox(height: 16),
            _buildDailyTipCard(),
            const SizedBox(height: 16),
            _buildQuickActionsGrid(),
            const SizedBox(height: 16),
            _buildRecentExpenses(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.green.shade600, Colors.teal.shade400],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back, ${widget.user.email.split('@')[0]}!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Let\'s build your financial independence today',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatChip(
                Icons.account_balance_wallet,
                'Tier',
                widget.user.tier.toString().split('.').last.toUpperCase(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsGoalCard(double progress) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Savings Goal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '\$${widget.user.currentSavings.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                Text(
                  '\$${widget.user.savingsGoal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% Complete',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTipCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Daily Money Tip',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _isLoadingTip
                ? const Center(child: CircularProgressIndicator())
                : Text(
                  _dailyTip ?? 'Loading today\'s tip...',
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _QuickActionCard(
              icon: Icons.shopping_cart,
              title: 'Shopping Swaps',
              color: Colors.blue,
              onTap: () {
                // Navigate to shopping swaps
              },
            ),
            _QuickActionCard(
              icon: Icons.restaurant,
              title: 'Batch Cooking',
              color: Colors.orange,
              onTap: () {
                // Navigate to batch cooking
              },
            ),
            _QuickActionCard(
              icon: Icons.home_repair_service,
              title: 'Renovation Tips',
              color: Colors.purple,
              onTap: () {
                // Navigate to renovation
              },
            ),
            _QuickActionCard(
              icon: Icons.calculate,
              title: 'Cost Compare',
              color: Colors.teal,
              onTap: () {
                // Navigate to cost calculator
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentExpenses() {
    if (_recentExpenses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Expenses',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._recentExpenses.map(
          (expense) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.attach_money, color: Colors.green.shade700),
              ),
              title: Text(expense.category),
              subtitle: Text(DateFormat('MMM dd, yyyy').format(expense.date)),
              trailing: Text(
                '\$${expense.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// === MONEY SAVERS SCREEN ===

class MoneySaversScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const MoneySaversScreen({
    super.key,
    required this.user,
    required this.onUpdate,
  });

  @override
  State<MoneySaversScreen> createState() => _MoneySaversScreenState();
}

class _MoneySaversScreenState extends State<MoneySaversScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Savers'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Shopping', icon: Icon(Icons.shopping_bag)),
            Tab(text: 'Batch Cooking', icon: Icon(Icons.restaurant)),
            Tab(text: 'Renovation', icon: Icon(Icons.home_repair_service)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ShoppingTab(user: widget.user, onUpdate: widget.onUpdate),
          _BatchCookingTab(user: widget.user, onUpdate: widget.onUpdate),
          _RenovationTab(user: widget.user, onUpdate: widget.onUpdate),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _ShoppingTab extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const _ShoppingTab({required this.user, required this.onUpdate});

  @override
  State<_ShoppingTab> createState() => _ShoppingTabState();
}

class _ShoppingTabState extends State<_ShoppingTab> {
  final _productController = TextEditingController();
  File? _productImage;
  bool _isAnalyzing = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _productImage = File(pickedFile.path));
    }
  }

  Future<void> _findAlternatives() async {
    if (_productController.text.isEmpty && _productImage == null) {
      _showError('Please enter a product name or upload an image');
      return;
    }

    if (widget.user.trialsRemaining <= 0 &&
        widget.user.adviceCreditsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final response = await ApiService.getShoppingAlternatives(
        widget.user.userId,
        _productController.text,
        _productImage,
      );

      if (response['success'] == true) {
        if (widget.user.adviceCreditsRemaining > 0) {
          widget.user.adviceCreditsRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showResults(response['alternatives']);
      } else {
        _showError(response['message'] ?? 'Analysis failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showResults(List<dynamic> alternatives) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Shopping Alternatives',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: alternatives.length,
                          itemBuilder: (context, index) {
                            final alt = alternatives[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(alt['product'] ?? ''),
                                subtitle: Text(alt['store'] ?? ''),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${alt['price']}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    if (alt['savings'] != null)
                                      Text(
                                        'Save \$${alt['savings']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your credits. Upgrade to continue saving money!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.shopping_cart, size: 80, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'Find Cheaper Alternatives',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a product or describe what you\'re looking for',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          if (_productImage != null) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: FileImage(_productImage!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Upload Product Image'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _productController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'Or describe the product...\n\nExample: "Organic almond milk, 1L"',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 24),

          if (_isAnalyzing)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _findAlternatives,
              icon: const Icon(Icons.search),
              label: const Text('Find Cheaper Options'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchCookingTab extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const _BatchCookingTab({required this.user, required this.onUpdate});

  @override
  State<_BatchCookingTab> createState() => _BatchCookingTabState();
}

class _BatchCookingTabState extends State<_BatchCookingTab> {
  final _servingsController = TextEditingController(text: '4');
  final List<String> _selectedMeals = [];
  final List<String> _mealOptions = [
    'Spaghetti Bolognese',
    'Chicken Curry',
    'Vegetable Stir Fry',
    'Beef Stew',
    'Lasagna',
    'Chili Con Carne',
    'Shepherd\'s Pie',
    'Chicken Soup',
  ];

  bool _isAnalyzing = false;

  Future<void> _analyzeCosts() async {
    if (_selectedMeals.isEmpty) {
      _showError('Please select at least one meal');
      return;
    }

    if (widget.user.trialsRemaining <= 0 &&
        widget.user.analysisCreditsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final servings = int.tryParse(_servingsController.text) ?? 4;
      final response = await ApiService.getBatchCookingCosts(
        widget.user.userId,
        _selectedMeals,
        servings,
      );

      if (response['success'] == true) {
        if (widget.user.analysisCreditsRemaining > 0) {
          widget.user.analysisCreditsRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showResults(response['analysis']);
      } else {
        _showError(response['message'] ?? 'Analysis failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showResults(Map<String, dynamic> analysis) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Batch Cooking Analysis',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            Text(
                              'Total Cost: \$${analysis['total_cost'] ?? '0.00'}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cost per Serving: \$${analysis['per_serving'] ?? '0.00'}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Breakdown by Meal:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...(analysis['meals'] as List? ?? []).map((meal) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        meal['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Total: \$${meal['cost'] ?? '0.00'}',
                                      ),
                                      Text(
                                        'Per Serving: \$${meal['per_serving'] ?? '0.00'}',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your analysis credits. Upgrade to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.restaurant, size: 80, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'Batch Cooking Cost Calculator',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compare costs and save money on family meals',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _servingsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Number of Servings',
              prefixIcon: const Icon(Icons.people),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Select Meals to Compare:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _mealOptions.map((meal) {
                  final isSelected = _selectedMeals.contains(meal);
                  return FilterChip(
                    label: Text(meal),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMeals.add(meal);
                        } else {
                          _selectedMeals.remove(meal);
                        }
                      });
                    },
                    backgroundColor: Colors.grey.shade200,
                    selectedColor: Colors.orange.shade100,
                  );
                }).toList(),
          ),

          const SizedBox(height: 24),

          if (_isAnalyzing)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _analyzeCosts,
              icon: const Icon(Icons.calculate),
              label: const Text('Analyze Costs'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _RenovationTab extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const _RenovationTab({required this.user, required this.onUpdate});

  @override
  State<_RenovationTab> createState() => _RenovationTabState();
}

class _RenovationTabState extends State<_RenovationTab> {
  final _budgetController = TextEditingController();
  String _selectedProject = 'Kitchen';
  final List<String> _projectTypes = [
    'Kitchen',
    'Bathroom',
    'Living Room',
    'Bedroom',
    'Garden',
    'Outdoor Space',
    'Painting',
    'Flooring',
  ];

  bool _isAnalyzing = false;

  Future<void> _getAdvice() async {
    if (_budgetController.text.isEmpty) {
      _showError('Please enter your budget');
      return;
    }

    if (widget.user.trialsRemaining <= 0 &&
        widget.user.adviceCreditsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final budget = double.tryParse(_budgetController.text) ?? 0;
      final response = await ApiService.getRenovationAdvice(
        widget.user.userId,
        _selectedProject,
        budget,
      );

      if (response['success'] == true) {
        if (widget.user.adviceCreditsRemaining > 0) {
          widget.user.adviceCreditsRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showResults(response['advice']);
      } else {
        _showError(response['message'] ?? 'Failed to get advice');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showResults(Map<String, dynamic> advice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Renovation Savings Tips',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            _buildAdviceSection(
                              'DIY Opportunities',
                              advice['diy_tips'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            _buildAdviceSection(
                              'Cost-Effective Materials',
                              advice['material_tips'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            _buildAdviceSection(
                              'Professional vs DIY',
                              advice['comparison'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            if (advice['estimated_savings'] != null)
                              Card(
                                color: Colors.green.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Potential Savings',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '\$${advice['estimated_savings']}',
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildAdviceSection(String title, List<dynamic> tips) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...tips.map(
          (tip) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(tip.toString())),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your credits. Upgrade to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.home_repair_service, size: 80, color: Colors.purple),
          const SizedBox(height: 16),
          const Text(
            'Renovation Savings Guide',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get AI-powered tips to save on home improvements',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          DropdownButtonFormField<String>(
            value: _selectedProject,
            decoration: InputDecoration(
              labelText: 'Project Type',
              prefixIcon: const Icon(Icons.construction),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            items:
                _projectTypes.map((project) {
                  return DropdownMenuItem(value: project, child: Text(project));
                }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedProject = value);
              }
            },
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Budget (\$)',
              prefixIcon: const Icon(Icons.attach_money),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (_isAnalyzing)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _getAdvice,
              icon: const Icon(Icons.tips_and_updates),
              label: const Text('Get Savings Tips'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

// === INVESTMENT SCREEN ===

class InvestmentScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const InvestmentScreen({
    super.key,
    required this.user,
    required this.onUpdate,
  });

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen> {
  final _amountController = TextEditingController();
  String _riskTolerance = 'Moderate';
  bool _isAnalyzing = false;

  final List<String> _riskLevels = ['Conservative', 'Moderate', 'Aggressive'];

  Future<void> _getGuidance() async {
    if (_amountController.text.isEmpty) {
      _showError('Please enter an amount');
      return;
    }

    if (widget.user.trialsRemaining <= 0 &&
        widget.user.adviceCreditsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final amount = double.tryParse(_amountController.text) ?? 0;
      final response = await ApiService.getInvestmentGuidance(
        widget.user.userId,
        amount,
        _riskTolerance,
      );

      if (response['success'] == true) {
        if (widget.user.adviceCreditsRemaining > 0) {
          widget.user.adviceCreditsRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showResults(response['guidance']);
      } else {
        _showError(response['message'] ?? 'Failed to get guidance');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showResults(Map<String, dynamic> guidance) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Investment Guidance',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            _buildGuidanceSection(
                              'Recommended Allocation',
                              guidance['allocation'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            _buildGuidanceSection(
                              'Investment Options',
                              guidance['options'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            _buildGuidanceSection(
                              'Risk Considerations',
                              guidance['risks'] ?? [],
                            ),
                            const SizedBox(height: 16),
                            if (guidance['next_steps'] != null)
                              Card(
                                color: Colors.blue.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Next Steps',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        guidance['next_steps'].toString(),
                                        style: const TextStyle(height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildGuidanceSection(String title, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.trending_up, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(item.toString())),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your credits. Upgrade to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investment Guide')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.trending_up, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Grow Your Money',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get personalized investment guidance for beginners',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount to Invest (\$)',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _riskTolerance,
              decoration: InputDecoration(
                labelText: 'Risk Tolerance',
                prefixIcon: const Icon(Icons.speed),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              items:
                  _riskLevels.map((level) {
                    return DropdownMenuItem(value: level, child: Text(level));
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _riskTolerance = value);
                }
              },
            ),

            const SizedBox(height: 24),

            if (_isAnalyzing)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed: _getGuidance,
                icon: const Icon(Icons.lightbulb),
                label: const Text('Get Investment Advice'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),

            const SizedBox(height: 32),

            Card(
              color: Colors.amber.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Investment Basics',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('• Start small and be consistent'),
                    Text('• Diversify your investments'),
                    Text('• Think long-term (5+ years)'),
                    Text('• Never invest money you can\'t afford to lose'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === AI ASSISTANT SCREEN ===

class AIAssistantScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const AIAssistantScreen({
    super.key,
    required this.user,
    required this.onUpdate,
  });

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    if (widget.user.trialsRemaining <= 0 &&
        widget.user.adviceCreditsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    final userMessage = _messageController.text;
    setState(() {
      _messages.add({'role': 'user', 'content': userMessage});
      _isTyping = true;
    });

    _messageController.clear();

    try {
      final response = await ApiService.getFinancialAdvice(
        widget.user.userId,
        userMessage,
      );

      if (response['success'] == true) {
        if (widget.user.adviceCreditsRemaining > 0) {
          widget.user.adviceCreditsRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': response['advice'] ?? 'Sorry, I couldn\'t process that.',
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': 'Sorry, there was an error. Please try again.',
        });
      });
    } finally {
      setState(() => _isTyping = false);
    }
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your credits. Upgrade to continue chatting!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Financial Assistant'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              onPressed: () {
                setState(() => _messages.clear());
              },
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear Chat',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_messages.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ask me anything about money!',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _SuggestionChip(
                            label: 'How to save \$500/month?',
                            onTap: () {
                              _messageController.text =
                                  'How can I save \$500 per month?';
                              _sendMessage();
                            },
                          ),
                          _SuggestionChip(
                            label: 'Best grocery stores?',
                            onTap: () {
                              _messageController.text =
                                  'What are the best budget grocery stores?';
                              _sendMessage();
                            },
                          ),
                          _SuggestionChip(
                            label: 'Emergency fund tips',
                            onTap: () {
                              _messageController.text =
                                  'How do I build an emergency fund?';
                              _sendMessage();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _TypingIndicator();
                  }

                  final message = _messages[index];
                  final isUser = message['role'] == 'user';

                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isUser
                                ? Colors.green.shade600
                                : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        message['content'],
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask about saving, investing, budgeting...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.green.shade600,
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send, color: Colors.white),
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
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.green.shade50,
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DotAnimation(delay: 0),
            const SizedBox(width: 4),
            _DotAnimation(delay: 200),
            const SizedBox(width: 4),
            _DotAnimation(delay: 400),
          ],
        ),
      ),
    );
  }
}

class _DotAnimation extends StatefulWidget {
  final int delay;

  const _DotAnimation({required this.delay});

  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// === UPGRADE SCREEN ===

class UpgradeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const UpgradeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isProcessing = false;

  Future<void> _purchaseSubscription(String productId) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        final purchaserInfo = await Purchases.purchasePackage(package);

        if (purchaserInfo.customerInfo.entitlements.all[productId]?.isActive ??
            false) {
          if (productId.contains('pro')) {
            widget.user.tier = UserTier.pro;
            widget.user.adviceCreditsRemaining = 11;
            widget.user.analysisCreditsRemaining = 11;
          } else if (productId.contains('premium')) {
            widget.user.tier = UserTier.premium;
            widget.user.adviceCreditsRemaining = 20;
            widget.user.analysisCreditsRemaining = 20;
          }

          widget.onUpdate(widget.user);
          _showSuccess('Subscription activated!');
        }
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _purchaseCredits(String productId, int credits) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        await Purchases.purchasePackage(package);

        widget.user.trialsRemaining += credits;
        widget.onUpdate(widget.user);
        _showSuccess('$credits credits added!');
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body:
          _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 80,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unlock Financial Freedom',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Get unlimited access to AI-powered money advice',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stars, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Current: ${widget.user.tier.toString().split('.').last.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'Monthly Subscriptions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Pro Plan',
                      price: '\$25/month',
                      features: const [
                        '11 AI Advice Credits',
                        '11 Analysis Credits',
                        'Unlimited Chat',
                        'Priority Support',
                      ],
                      color: Colors.blue,
                      onTap: () => _purchaseSubscription('pro'),
                    ),

                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Premium Plan',
                      price: '\$35/month',
                      features: const [
                        '20 AI Advice Credits',
                        '20 Analysis Credits',
                        'Unlimited Everything',
                        'Personal Finance Coach',
                        'Early Access Features',
                        'Premium Support',
                      ],
                      color: Colors.purple,
                      onTap: () => _purchaseSubscription('premium'),
                      recommended: true,
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'One-Time Credit Packs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _CreditPackCard(
                      title: 'Power Pack',
                      credits: 25,
                      price: '\$40',
                      onTap: () => _purchaseCredits('credits_25', 25),
                    ),

                    const SizedBox(height: 12),

                    _CreditPackCard(
                      title: 'Starter Pack',
                      credits: 10,
                      price: '\$15',
                      onTap: () => _purchaseCredits('credits_10', 10),
                    ),

                    const SizedBox(height: 32),
                    Card(
                      color: Colors.green.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  'Secure Payments',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text('• Cancel anytime, no questions asked'),
                            Text('• Powered by RevenueCat & App Store'),
                            Text('• 100% secure payment processing'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;
  final bool recommended;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.features,
    required this.color,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          elevation: recommended ? 8 : 2,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: color),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 20, color: color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RECOMMENDED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CreditPackCard extends StatelessWidget {
  final String title;
  final int credits;
  final String price;
  final VoidCallback onTap;

  const _CreditPackCard({
    required this.title,
    required this.credits,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.add_shopping_cart, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$credits Universal Credits'),
        trailing: Text(
          price,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// === PROFILE SCREEN ===

class ProfileScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const ProfileScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  void _updateSavingsGoal() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(
          text: widget.user.savingsGoal.toString(),
        );
        return AlertDialog(
          title: const Text('Set Savings Goal'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target Amount (\$)',
              prefixIcon: Icon(Icons.savings),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(controller.text) ?? 0;
                setState(() => widget.user.savingsGoal = amount);
                widget.onUpdate(widget.user);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.green,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            widget.user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Center(
            child: Chip(
              label: Text(
                '${widget.user.tier.toString().split('.').last.toUpperCase()} TIER',
              ),
              backgroundColor: Colors.green.shade100,
            ),
          ),

          const SizedBox(height: 32),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Credits Overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _CreditRow(
                    label: 'Universal Credits',
                    value: widget.user.trialsRemaining.toString(),
                  ),
                  _CreditRow(
                    label: 'Advice Credits',
                    value: widget.user.adviceCreditsRemaining.toString(),
                  ),
                  _CreditRow(
                    label: 'Analysis Credits',
                    value: widget.user.analysisCreditsRemaining.toString(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('Daily Money Tips'),
            subtitle: const Text('Receive daily financial advice'),
            value: widget.user.dailyTipsEnabled,
            onChanged: (value) {
              setState(() => widget.user.dailyTipsEnabled = value);
              widget.onUpdate(widget.user);
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.savings),
            title: const Text('Savings Goal'),
            subtitle: Text('\$${widget.user.savingsGoal.toStringAsFixed(2)}'),
            trailing: const Icon(Icons.edit),
            onTap: _updateSavingsGoal,
          ),

          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Expense Tracker'),
            onTap: () {
              // Navigate to expense tracker
            },
          ),

          ListTile(
            leading: const Icon(Icons.track_changes),
            title: const Text('Financial Goals'),
            onTap: () {
              // Navigate to goals
            },
          ),

          const SizedBox(height: 32),

          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Need Help?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Email us at support@mumwise.com'),
                  Text('We\'re here to help you achieve financial freedom!'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String value;

  const _CreditRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
