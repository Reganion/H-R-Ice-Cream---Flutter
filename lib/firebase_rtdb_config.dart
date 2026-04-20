import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// Must match Laravel Kreait / `google-services.json` → `firebase_url`.
/// Change if you use a secondary Realtime Database instance.
const String kFirebaseRealtimeDatabaseUrl =
    'https://icecream-14ae7-default-rtdb.firebaseio.com';

/// App-wide RTDB instance pinned to [kFirebaseRealtimeDatabaseUrl].
FirebaseDatabase firebaseRtdb() {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: kFirebaseRealtimeDatabaseUrl,
  );
}
