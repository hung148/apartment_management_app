import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/payments_notifier.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/update_services.dart';
import 'package:apartment_management_project_2/utils/app_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setup() {
  getIt.registerLazySingleton(() => AuthService());
  getIt.registerLazySingleton(() => RoomService());
  getIt.registerLazySingleton(() => TenantService());
  getIt.registerLazySingleton(() => BuildingService());
  getIt.registerLazySingleton(() => OrganizationService());
  getIt.registerLazySingleton(() => PaymentService());
  getIt.registerLazySingleton(() => PaymentsNotifier(getIt<PaymentService>()));
  getIt.registerLazySingleton(() => UpdateService());
}

void main() async {
  // Set up global error handlers to catch uncaught exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter Error: ${details.exception}');
    print('Stack Trace: ${details.stack}');
  };

  // initialize firebase
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );



  // Configure Firestore settings BEFORE any service accesses it
  // This must happen before FirebaseFirestore.instance is first accessed
  try {
    // For web and desktop platforms, settings configuration is handled differently
    // For mobile (iOS/Android), you can configure persistence
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    print('Firestore settings note: $e');
  }
  
  // Force Firebase Auth to initialize on the main thread
  // This prevents the threading errors
  await FirebaseAuth.instance.authStateChanges().first;

  setup();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.blue),
      ),
      debugShowCheckedModeBanner: false, // disable debug sign
      initialRoute: '/', // Start at splash screen
      onGenerateRoute: AppRouter.generateRoute, // Use our router
    );
  }
}
