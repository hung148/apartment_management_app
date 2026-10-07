import 'package:cloud_functions/cloud_functions.dart';

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

  Future<HttpsCallableResult<T>> call<T>([dynamic data]) => appFunctions
      .httpsCallable(functionGroup(name))
      .call<T>({'fn': name, 'data': data});
}
