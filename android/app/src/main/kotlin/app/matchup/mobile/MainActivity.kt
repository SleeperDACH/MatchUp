package app.matchup.mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity statt FlutterActivity: von local_auth (Biometrie)
// vorausgesetzt, damit der System-Biometrie-Dialog angezeigt werden kann.
class MainActivity : FlutterFragmentActivity()
