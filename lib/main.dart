import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_notifier.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/app_check_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/local_emulators.dart';
import 'package:phan_mem_quan_ly_can_ho/services/update_services.dart';

import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/auth_redirect.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/device_sealer.dart';
import 'services/device_session.dart';
import 'services/read_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'utils/app_window.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class LocaleNotifier extends ChangeNotifier {
  Locale _locale = const Locale('vi', 'VN');

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
    notifyListeners();
  }
}

final getIt = GetIt.instance;

void setup() {
  getIt.registerLazySingleton(() => AuthService());
  getIt.registerLazySingleton(() => RoomService());
  getIt.registerLazySingleton(() => TenantService());
  getIt.registerLazySingleton(() => BuildingService());
  getIt.registerLazySingleton(() => OrganizationService());
  getIt.registerLazySingleton(() => TeamService());
  getIt.registerLazySingleton(() => PaymentService());
  getIt.registerLazySingleton(() => PaymentsNotifier(getIt<PaymentService>()));
  getIt.registerLazySingleton(() => UpdateService());
  getIt.registerLazySingleton(() => LocaleNotifier());
  getIt.registerLazySingleton(() => AppThemeNotifier());
  getIt.registerLazySingleton(() => BookingService());
  getIt.registerLazySingleton(() => BookingsNotifier(getIt<BookingService>()));
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
    if (error is PlatformException && error.code == 'permission-denied')
      return true;
    if (error.toString().contains('permission-denied')) return true;
    return false;
  };

  WidgetsFlutterBinding.ensureInitialized();

  await initializeAppWindow();

  // Local test mode (tool\local.ps1) uses the emulators on this computer and
  // has no App Check; every other build is unchanged.
  await Firebase.initializeApp(
    options: localEmulators
        ? localFirebaseOptions
        : DefaultFirebaseOptions.currentPlatform,
  );
  if (localEmulators) {
    await useLocalEmulators();
  } else {
    await activateAppCheck();
  }

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

  final prefs = await SharedPreferences.getInstance();
  // The copy of server answers kept on this device (2026-10-06, speed): it
  // belongs to the signed-in account; signing out or switching account wipes
  // it before anything else can read it.
  ReadCache.shared = ReadCache(
    prefs,
    account: () => FirebaseAuth.instance.currentUser?.uid,
    // Encrypted; and nothing saved on a computer not remembered at sign-in.
    sealer: createDeviceSealer(),
    enabled: () => rememberThisDevice,
  );
  await ReadCache.shared!.keepOnlyAccount(
    FirebaseAuth.instance.currentUser?.uid,
  );
  FirebaseAuth.instance.authStateChanges().listen(
    (user) => ReadCache.shared?.keepOnlyAccount(user?.uid),
  );
  await getIt<AppThemeNotifier>().load();
  final savedLang = prefs.getString('language_code') ?? 'vi';
  final savedCountry = savedLang == 'vi' ? 'VN' : 'US';
  getIt<LocaleNotifier>().setLocale(Locale(savedLang, savedCountry));

  runApp(const MyApp());
  // The page's own loading screen stays until the app has drawn (web).
  WidgetsBinding.instance.addPostFrameCallback((_) => hideStartScreen());
  watchAuthChanges(navigatorKey);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: getIt<LocaleNotifier>(),
      builder: (context, child) {
        final localeNotifier = getIt<LocaleNotifier>();
        return ListenableBuilder(
          listenable: getIt<AppThemeNotifier>(),
          builder: (context, child) => MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => child!,
            locale: localeNotifier.locale,
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
            onGenerateTitle: (context) =>
                AppTranslations.of(context)['app_title'],
            theme: buildAppTheme(getIt<AppThemeNotifier>().primary),
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            // Always start at the splash, even when the browser address (after a
            // reload) points at an inner screen: those screens need arguments
            // that a reload cannot restore, and the splash decides between login
            // and dashboard from the current sign-in.
            // An organization address (U1) is remembered and opened by the
            // dashboard after sign-in, with the list underneath for Back.
            onGenerateInitialRoutes: (initialRoute) {
              if (initialRoute.startsWith('/org/')) {
                AppRouter.pendingAddress = initialRoute;
              }
              return [
                AppRouter.generateRoute(
                  const RouteSettings(name: AppRouter.splashScreen),
                ),
              ];
            },
            onGenerateRoute: AppRouter.generateRoute,
          ),
        );
      },
    );
  }
}
