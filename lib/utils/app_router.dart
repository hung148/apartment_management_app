import 'package:phan_mem_quan_ly_can_ho/screens/building_room.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/login_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/organization_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/room_detail.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/splash_screen.dart';
import 'package:flutter/material.dart';

class AppRouter {
  // address
  static const String splashScreen = '/';
  static const String loginScreen = '/login';
  static const String dashboardScreen = '/dashboard';
  static const String oranizationScreen = '/organization';
  static const String buildingRoomScreen = '/building-rooms';
  static const String roomDetailScreen = '/room-detail';
  static const String paymentScreen = '/payemts';
  static const String tenantScreen = '/tenants';
  static const String reportScreen = '/report';

  /// Use this with [Navigator.pushReplacement] for a smooth fade transition.
  /// e.g. Navigator.pushReplacement(context, AppRouter.fadeRoute(const DashboardScreen()));
  static Route<dynamic> fadeRoute(
    Widget page, {
    Duration duration = const Duration(milliseconds: 500),
    RouteSettings? settings,
    
  }) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: duration,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: child,
      ),
    );
  }

  static Route<dynamic> generateRoute(RouteSettings settings) {

    // settings.name tells us which screen they want
    switch (settings.name) {
      case splashScreen:
        return MaterialPageRoute(builder: (_) => SplashScreen());
      case loginScreen:
        return MaterialPageRoute(builder: (_) => LoginScreen());
      case dashboardScreen:
        return fadeRoute(const DashboardScreen(), settings: settings);
      case oranizationScreen:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(builder: (_) => OrganizationScreen(
          organization: args['organization'],
        ), settings: settings,);
      case buildingRoomScreen:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(builder: (_) => BuildingRoomScreen(
          building: args['building'],
          organization: args['organization'],
        ), settings: settings,);
      case roomDetailScreen:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => RoomDetailScreen(
            room: args['room'],
            organization: args['organization'],
          ),
          settings: settings,
        );
      default:
        // If the route doesn't exist, show an error
        return MaterialPageRoute(builder: (_) => Scaffold(
          body: Center(child: Text(
            'Page not found',
            style: TextStyle(
              color: Colors.redAccent,
            ),
          )),
        ));
    }
  }
}