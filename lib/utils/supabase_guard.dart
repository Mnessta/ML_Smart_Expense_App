import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns true only when Supabase has been initialized successfully.
bool isSupabaseInitialized() {
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}
