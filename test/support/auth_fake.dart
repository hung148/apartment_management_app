import 'package:firebase_auth/firebase_auth.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';

class UserFake implements User {
  @override
  String get uid => 'user';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuthFake implements AuthService {
  @override
  User get currentUser => UserFake();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
