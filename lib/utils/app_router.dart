import 'package:apartment_management_project_2/screens/building_room.dart';
import 'package:apartment_management_project_2/screens/dashboard_screen.dart';
import 'package:apartment_management_project_2/screens/login_screen.dart';
import 'package:apartment_management_project_2/screens/organization_screen.dart';
import 'package:apartment_management_project_2/screens/room_detail.dart';
import 'package:apartment_management_project_2/screens/splash_screen.dart';
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
  static Route<dynamic> generateRoute(RouteSettings settings) {
    // settings.name tells us which screen they want
    switch (settings.name) {
      case splashScreen:
        return MaterialPageRoute(builder: (_) => SplashScreen());
      case loginScreen:
        return MaterialPageRoute(builder: (_) => LoginScreen());
      case dashboardScreen:
        return MaterialPageRoute(builder: (_) => DashboardScreen());
      case oranizationScreen:
        return MaterialPageRoute(builder: (_) => OrganizationScreen(), settings: settings,);
      case buildingRoomScreen:
        return MaterialPageRoute(builder: (_) => BuildingRoomScreen(), settings: settings,);
      case roomDetailScreen:
        return MaterialPageRoute(builder: (_) => RoomDetailScreen(), settings: settings,);
      default:
        // If the route doesn't exist, show an error
        return MaterialPageRoute(builder: (_) => Scaffold(
          body: Center(child: Text(
            'Page not found',
            style: TextStyle(
              color: Colors.redAccent,
            ),
            )
          ),
        ));
    }
  }
}