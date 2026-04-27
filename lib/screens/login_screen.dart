import 'dart:ui';

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/responsive.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/loading.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DebouncedMediaQuery(
        builder: (context, size) {
          final screenWidth = size.width;
          final double titleSize = (screenWidth * 0.055).clamp(18.0, 28.0);
          final double buttonSize = (screenWidth * 0.045).clamp(14.0, 18.0);
          final double textSize = (screenWidth * 0.045).clamp(8.0, 14.0);
          final double iconSize = (screenWidth * 0.12).clamp(36.0, 56.0);

          return Image(
            image: const AssetImage('assets/image/background_image.jpg'),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame == null) {
                return const SizedBox.expand(
                  child: ColoredBox(color: Colors.black),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  SafeArea(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: size.height,
                        ),
                        child: Center(
                          child: ChangeNotifierProvider(
                            create: (context) => ChoiceState(),
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Container(
                                padding: EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  border: Border.all(color: Colors.transparent),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    inputDecorationTheme: InputDecorationTheme(
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.15),
                                      errorStyle: TextStyle(
                                        color: Color(0xFFFF6B6B),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      labelStyle: TextStyle(color: Colors.white70),
                                      hintStyle: TextStyle(color: Colors.white54),
                          
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
                                    textTheme: Theme.of(context).textTheme.apply(
                                      bodyColor: Colors.white,
                                      displayColor: Colors.white,
                                    ),
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
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.apartment_rounded, size: iconSize, color: Colors.white70),
                                      SizedBox(height: 4),
                                      Text(
                                        "Phần Mền Quản Lý Căn Hộ",
                                        style: TextStyle(
                                          fontSize: titleSize,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      ChoicesButton(textSize: textSize),
                                      SizedBox(height: 10),
                                      Content(buttonSize: buttonSize, textSize: textSize, titleSize: titleSize,),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class Content extends StatefulWidget {
  
  final double buttonSize;
  final double textSize;
  final double titleSize;

  const Content({super.key, required this.buttonSize, required this.textSize, required this.titleSize});

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

  Choices _displayedChoice = Choices.login;
  double _opacity = 1.0;
  bool _switching = false;

  Future<void> _switchTo(Choices newChoice) async {
    if (_switching || newChoice == _displayedChoice || loading) return;
    _switching = true;

    // Fade out
    setState(() => _opacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 180));

    // Swap
    setState(() => _displayedChoice = newChoice);

    // Fade in
    setState(() => _opacity = 1.0);
    await Future.delayed(const Duration(milliseconds: 180));

    _switching = false;
  }

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
          Navigator.pushReplacementNamed(context, AppRouter.dashboardScreen);
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
    final choiceView = context.watch<ChoiceState>().choiceView;

    // Trigger switch after build if needed
    if (choiceView != _displayedChoice && !_switching) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _switchTo(choiceView));
    }

    // return AnimatedOpacity(
    //   opacity: _opacity,
    //   duration: const Duration(milliseconds: 180),
    //   curve: Curves.easeInOut,
    //   child: _displayedChoice == Choices.login ? _buildLogin(widget.titleSize) : _buildRegister(widget.titleSize),
    // );
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        child: _displayedChoice == Choices.login 
            ? _buildLogin(widget.titleSize) 
            : _buildRegister(widget.titleSize),
      ),
    );
  }

  Widget _buildLogin(double titleSize) {
    return Column(
      children: [
        Text(
          "Đăng nhập",
          style: TextStyle(
            fontSize: titleSize - 5,
            fontWeight: FontWeight.w400,  // lighter than the app title
            color: Colors.white70,        // slightly dimmed
            letterSpacing: 1.5,
          ),
        ),
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
              ),
              inputField(
                label: "Mật khẩu", 
                controller: loginPasswordController,
                labelColor: Colors.white, 
                validator: (val) => val!.length < 6 ? val.isEmpty ? "Điền mật khẩu!" : "Mật khẩu quá đơn giản!" : null,
                obscureText: true, 
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
                        fontSize: widget.textSize + 5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              if (loading) ...[
                SizedBox(height: 16,),
                Loading2(size: 25, color: Colors.grey,),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SwitchAuthLink(
          current: Choices.login,   // or Choices.register in _buildRegister()
          textSize: widget.textSize,
        ),
      ],
    );
  }

  Widget _buildRegister(double titleSize) {
    return Column(
      children: [
        Text(
          "Đăng ký",
          style: TextStyle(
            fontSize: titleSize - 5,
            fontWeight: FontWeight.w400,  // lighter than the app title
            color: Colors.white70,        // slightly dimmed
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
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
              ),
              inputField(
                label: "Xác Nhận Mật khẩu", 
                labelColor: Colors.white, 
                controller: registerComfirmedPassController,
                validator: (val) => val != registerPasswordController.text ? "Mật khẩu không khớp!" : null,
                obscureText: true, 
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
                SizedBox(height: 16,),
                Loading2(size: 25, color: Colors.grey,),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SwitchAuthLink(
          current: Choices.register,   // or Choices.register in _buildRegister()
          textSize: widget.textSize,
        ),
      ],
    );
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
  final double textSize;
  const ChoicesButton({super.key, required this.textSize});

  @override
  Widget build(BuildContext context) {
    // No longer needed — toggle is now at the bottom of the form
    return const SizedBox.shrink();
  }
}

class SwitchAuthLink extends StatefulWidget {
  final Choices current;
  final double textSize;
  const SwitchAuthLink({super.key, required this.current, required this.textSize});

  @override
  State<SwitchAuthLink> createState() => _SwitchAuthLinkState();
}

class _SwitchAuthLinkState extends State<SwitchAuthLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLogin = widget.current == Choices.login;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.read<ChoiceState>().switchChoice(
          isLogin ? Choices.register : Choices.login,
        ),
        child: RichText(
          text: TextSpan(
            text: isLogin ? "Chưa có tài khoản? " : "Đã có tài khoản? ",
            style: TextStyle(color: Colors.white70, fontSize: widget.textSize + 2),
            children: [
              TextSpan(
                text: isLogin ? "Đăng ký" : "Đăng nhập",
                style: TextStyle(
                  color: _hovered ? Colors.blue : Colors.white,
                  fontSize: widget.textSize + 2,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  decorationColor: _hovered ? Colors.blue : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum Choices { login, register }

