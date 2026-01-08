import 'package:apartment_management_project_2/screens/dashboard_screen.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:apartment_management_project_2/widgets/loading.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ChangeNotifierProvider(
            // create this state
            create: (context) => ChoiceState(),
            child: Container(
              padding: EdgeInsets.all(8.0),
              margin: EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceBright,
                border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // only as tall as your children
                children: [
                  ChoicesButton(),
                  SizedBox(height: 10,),
                  Content(),
                ],
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
  final AuthService _authService = AuthService();

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
                  validator: (val) => val!.isEmpty ? "Điền Email!" : null,
                  optional: false,
                ),
                inputField(
                  label: "Mật khẩu", 
                  controller: loginPasswordController,
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
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: loading ? null : () => _handleLogin(), 
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Đăng nhập",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
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
                  validator: (val) => val!.isEmpty ? "Điền tên!" : null,
                  optional: false,
                ),
                inputField(
                  label: "Email", 
                  controller: registerEmailController,
                  validator: (val) => val!.isEmpty ? "Điền Email!" : null,
                  optional: false,
                ),
                inputField(
                  label: "Mật khẩu", 
                  controller: registerPasswordController,
                  validator: (val) => val!.length < 6 ? val.isEmpty ? "Điền mật khẩu!" : "Mật khẩu quá đơn giản!" : null,
                  obscureText: true, 
                  optional: false,
                ),
                inputField(
                  label: "Xác Nhận Mật khẩu", 
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
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: loading ? null : () => _handleRegister(), 
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Đăng ký",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
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

