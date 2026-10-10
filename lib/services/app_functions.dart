import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Where the server functions run (2026-10-06, speed): next to the Firestore
/// database in Singapore. Must match functions/region.js.
const functionsRegion = 'asia-southeast1';

/// The app's server functions. Use this instead of FirebaseFunctions.instance,
/// which always calls us-central1.
FirebaseFunctions get appFunctions =>
    FirebaseFunctions.instanceFor(region: functionsRegion);

/// The grouped server function that serves a call (2026-10-06, speed step 4).
/// Must match the groups in functions/index.js.
String functionGroup(String call) => call == 'importSheet' ? 'heavy' : 'app';

/// One server call by its name. The server has a few grouped functions instead
/// of one per call, so the call goes to its group as {fn: name, data: data};
/// the server checks and limits it under its own name, as before.
AppCall appCallable(String name) => AppCall(name);

class AppCall {
  const AppCall(this.name);
  final String name;

  Future<HttpsCallableResult<T>> call<T>([dynamic data]) async {
    try {
      return await appFunctions
          .httpsCallable(functionGroup(name))
          .call<T>({'fn': name, 'data': data});
    } on FirebaseFunctionsException catch (e) {
      // "Sign out everywhere" ended this sign-in (2026-10-06): sign out here
      // too, which wipes the device copy and returns to the sign-in screen.
      if (isSessionRevoked(e)) await FirebaseAuth.instance.signOut();
      rethrow;
    }
  }
}

/// The server refused this sign-in because the account signed out everywhere.
bool isSessionRevoked(Object e) =>
    e is FirebaseFunctionsException &&
    e.code == 'unauthenticated' &&
    '${e.message} ${e.details}'.contains('session_revoked');
