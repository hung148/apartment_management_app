import 'dart:ui';

import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:apartment_management_project_2/widgets/loading.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/image/background_image.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ChangeNotifierProvider(
              // create this state
              create: (context) => ChoiceState(),
              child: Padding(
                padding: EdgeInsets.all(20.0), // outer spacing
                child: Container(
                  padding: EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.transparent, // was Colors.white.withValues(alpha: 0.20)
                    border: Border.all(
                      color: Colors.transparent, // remove the border too
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      // Make input fields have a light fill
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.15),
                        errorStyle: TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontWeight: FontWeight.bold,
                        ),
                        labelStyle: TextStyle(color: Colors.white70),
                        hintStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white, width: 1.5),
                        ),
                      ),
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        error: Color(0xFFFF6B6B),
                      ),
                      // White text throughout
                      textTheme: Theme.of(context).textTheme.apply(
                        bodyColor: Colors.white,
                        displayColor: Colors.white,
                      ),
                      // SegmentedButton styling
                      segmentedButtonTheme: SegmentedButtonThemeData(
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith((states) =>
                            states.contains(WidgetState.selected) ? Colors.black87 : Colors.white70,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith((states) =>
                            states.contains(WidgetState.selected)
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.transparent,
                          ),
                          side: WidgetStateProperty.all(
                            BorderSide(color: Colors.white38),
                          ),
                        ),
                      ),
                      textSelectionTheme: TextSelectionThemeData(
                        cursorColor: Colors.white,
                        selectionColor: Colors.white38,
                        selectionHandleColor: Colors.white,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // only as tall as your children
                      children: [
                        // App branding
                        Icon(Icons.apartment_rounded, size: 48, color: Colors.white70),
                        SizedBox(height: 4),
                        Text(
                          "Phần Mền Quản Lý Căn Hộ",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                        SizedBox(height: 16),
                        ChoicesButton(),
                        SizedBox(height: 10,),
                        Content(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Content extends StatefulWidget {
  const Content({super.key});

  @override
  State<Content> createState() => _ContentState();
}

// TextEditingController values are being reset when switch between login and register views 
// because the entire widget tree is being rebuilt. To stop this use
// AutomaticKeepAliveClientMixin
class _ContentState extends State<Content> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // create a AuthService object to access Firebase backend
  final AuthService _authService = getIt<AuthService>();

  // loading 
  bool loading = false;

  final _formKey1 = GlobalKey<FormState>();

  final _formKey2 = GlobalKey<FormState>();

  final loginEmailController = TextEditingController();
  final loginPasswordController = TextEditingController();

  final registerNameController = TextEditingController();
  final registerEmailController = TextEditingController();
  final registerPasswordController = TextEditingController();
  final registerComfirmedPassController = TextEditingController();
  
  String? login_error;

  String? register_error;

  // login function
  Future<void> _handleLogin() async {
    if(!_formKey1.currentState!.validate()) return;

    setState(() {
      loading = true;
      login_error = null;
    });
    
    await Future.delayed(const Duration(seconds: 2));

    try {
      User? user = await _authService.signInWithEmailPassword(
        loginEmailController.text.trim(), 
        loginPasswordController.text
      );

      if (user != null) {
        
        // Check if Firebase still has the user
        final currentUser = FirebaseAuth.instance.currentUser;
        print('🔍 Current user after login: ${currentUser?.uid}');
        // Navidate to dashboard
        if (mounted) {
          Navigator.pushReplacementNamed(
            context, 
            AppRouter.dashboardScreen,
          );
        }
      } else {
        // login fail
        setState(() {
          login_error = "Đăng nhập thất bại. Kiểm tra email và mật khẩu.";
        });
      }
    } catch(e) {
      setState(() {
        login_error = "Lỗi: ${e.toString()}";
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // Register function
  Future<void> _handleRegister() async {
    if (!_formKey2.currentState!.validate()) return;

    setState(() {
      loading = true;
      register_error = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    try {
      // Use AuthService to register
      final owner = await _authService.registerWithEmailPassword(
        email: registerEmailController.text.trim(),
        password: registerPasswordController.text,
        name: registerNameController.text.trim(),
      );

      if (owner != null) {
        // Registration successful - navigate to dashboard
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRouter.dashboardScreen);
        }
      } else {
        // Registration failed
        setState(() {
          register_error = 'Đăng ký thất bại. Email có thể đã được sử dụng.';
        },);
      }
    } catch (e) {
      setState(() {
        register_error = 'Lỗi: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    loginEmailController.dispose();
    loginPasswordController.dispose();
    registerNameController.dispose();
    registerEmailController.dispose();
    registerPasswordController.dispose();
    registerComfirmedPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var choiceState = context.watch<ChoiceState>();
    var choiceView = choiceState.choiceView;

    if (choiceView == Choices.login) {
      return Column(
        children: [
          Form(
            key: _formKey1,
            child: Column(
              children: [
                inputField(
                  label: "Email", 
                  controller: loginEmailController,
                  labelColor: Colors.white,
                  maxLength: 100,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  validator: (val) {
                    if (val!.isEmpty) return "Điền Email!";
                    if (val.length > 254) return "Email không hợp lệ!";  // RFC 5321 max
                    return null;
                  },
                  optional: false,
                ),
                inputField(
                  label: "Mật khẩu", 
                  controller: loginPasswordController,
                  labelColor: Colors.white, 
                  validator: (val) => val!.length < 6 ? val.isEmpty ? "Điền mật khẩu!" : "Mật khẩu quá đơn giản!" : null,
                  obscureText: true, 
                  optional: false,
                ),
              ],
            ),
          ),
          if (login_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                login_error!,
                style: TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 20,),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, // full width
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: loading ? null : () => _handleLogin(),
                    borderRadius: BorderRadius.circular(10),
                    splashColor: Colors.blue.withValues(alpha: 0.9),
                    highlightColor: Colors.blue.withValues(alpha: 0.75),
                    hoverColor: Colors.blue.withValues(alpha: 0.8),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: loading
                            ? [Colors.grey.withValues(alpha: 0.3), Colors.grey.withValues(alpha: 0.3)]
                            : [Colors.blue.withValues(alpha: 0.6), Colors.lightBlue.withValues(alpha: 0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        "Đăng nhập",  
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (loading) ...[
                  SizedBox(width: 16,),
                  Loading2(size: 25),
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Form(
            key: _formKey2,
            child: Column(
              children: [
                inputField(
                  label: "Tên", 
                  controller: registerNameController,
                  labelColor: Colors.white, 
                  validator: (val) {
                    if (val!.isEmpty) return "Điền tên!";
                    if (val.length > 100) return "Tên quá dài!";
                    return null;
                  },
                  optional: false,
                ),
                inputField(
                  label: "Email", 
                  controller: registerEmailController,
                  labelColor: Colors.white, 
                  validator: (val) {
                    if (val!.isEmpty) return "Điền Email!";
                    if (val.length > 254) return "Email không hợp lệ!";  // RFC 5321 max
                    return null;
                  },
                  optional: false,
                ),
                inputField(
                  label: "Mật khẩu", 
                  controller: registerPasswordController,
                  labelColor: Colors.white, 
                  validator: (val) {
                    if (val!.isEmpty) return "Điền mật khẩu!";
                    if (val.length < 6) return "Mật khẩu quá đơn giản!";
                    if (val.length > 128) return "Mật khẩu quá dài!";
                    return null;
                  },
                  obscureText: true, 
                  optional: false,
                ),
                inputField(
                  label: "Xác Nhận Mật khẩu", 
                  labelColor: Colors.white, 
                  controller: registerComfirmedPassController,
                  validator: (val) => val != registerPasswordController.text ? "Mật khẩu không khớp!" : null,
                  obscureText: true, 
                  optional: false,
                ),
              ],
            ),
          ),
          if (register_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                register_error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 20,),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, // full width
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: loading ? null : () => _handleRegister(),
                    borderRadius: BorderRadius.circular(10),
                    splashColor: Colors.blue.withValues(alpha: 0.9),
                    highlightColor: Colors.blue.withValues(alpha: 0.75),
                    hoverColor: Colors.blue.withValues(alpha: 0.8),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: loading
                            ? [Colors.grey.withValues(alpha: 0.3), Colors.grey.withValues(alpha: 0.3)]
                            : [Colors.blue.withValues(alpha: 0.6), Colors.lightBlue.withValues(alpha: 0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        "Đăng ký",  // or "Đăng ký"
                        textAlign: TextAlign.center,  
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (loading) ...[
                  SizedBox(width: 16,),
                  Loading2(size: 25),
                ],
              ],
            ),
          ),
        ],
      );
    }
  }
}

class ChoiceState extends ChangeNotifier {
  Choices choiceView = Choices.login;

  void switchChoice(Choices currentChoice) {
    choiceView = currentChoice;
    notifyListeners();
  }
}

class ChoicesButton extends StatelessWidget {
  const ChoicesButton({super.key});

  @override
  Widget build(BuildContext context) {
    var choiceState = context.watch<ChoiceState>();
    var choiceView = choiceState.choiceView;
    
    return SegmentedButton<Choices>(
      segments: const <ButtonSegment<Choices>>[
        ButtonSegment<Choices>(
          value: Choices.login,
          label: Text('Đăng nhập'),
        ),
        ButtonSegment<Choices>(
          value: Choices.register,
          label: Text('Đăng ký'),
        ),
      ],
      selected: <Choices>{choiceView},
      onSelectionChanged: (Set<Choices> newSelection) {
        choiceState.switchChoice(newSelection.first);
      },
    );
  }
}

enum Choices { login, register }

