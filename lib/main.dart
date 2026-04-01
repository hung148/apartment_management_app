import 'package:apartment_management_project_2/services/ai_agent_service.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/payments_notifier.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/update_services.dart';

import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class LocaleNotifier extends ChangeNotifier {
  Locale _locale = const Locale('vi', 'VN');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }
}

final getIt = GetIt.instance;

void setup() {
  getIt.registerLazySingleton(() => AuthService());
  getIt.registerLazySingleton(() => AIAgentService());
  getIt.registerLazySingleton(() => RoomService());
  getIt.registerLazySingleton(() => TenantService());
  getIt.registerLazySingleton(() => BuildingService());
  getIt.registerLazySingleton(() => OrganizationService());
  getIt.registerLazySingleton(() => PaymentService());
  getIt.registerLazySingleton(() => PaymentsNotifier(getIt<PaymentService>()));
  getIt.registerLazySingleton(() => UpdateService());
  getIt.registerLazySingleton(() => LocaleNotifier());
}

void main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    final error = details.exception;
    if (error is PlatformException && error.code == 'permission-denied') return;
    if (error.toString().contains('permission-denied')) return;
    print('Flutter Error: ${details.exception}');
    print('Stack Trace: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is PlatformException && error.code == 'permission-denied') return true;
    if (error.toString().contains('permission-denied')) return true;
    return false;
  };

  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      minimumSize: Size(480, 600),
      size: Size(900, 700),
      center: true,
      title: 'Phần Mền Quản Lý Căn Hộ',
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.show();
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    print('Firestore settings note: $e');
  }

  await FirebaseAuth.instance.authStateChanges().first;

  setup();

  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: getIt<LocaleNotifier>(),
      builder: (context, child) {
        final localeNotifier = getIt<LocaleNotifier>();

        return MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => child!,
          locale: localeNotifier.locale,
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('vi', 'VN'),
            Locale('en', 'US'),
          ],
          title: 'Flutter Demo',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          debugShowCheckedModeBanner: false,
          initialRoute: '/',
          onGenerateRoute: AppRouter.generateRoute,
        );
      },
    );
  }
}