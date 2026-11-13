import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/raf_design_system.dart';
import 'features/app_shell.dart';
import 'features/settings/pages/store_settings_page.dart';
import 'core/licensing/license_gate.dart';
import 'core/licensing/license_service.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RafApp());
}

class RafApp extends StatelessWidget {
  final Widget? home;
  final LicenseService? licenseService;

  const RafApp({super.key, this.home, this.licenseService});

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode && licenseService != null) {
      throw StateError(
        'Injected licensing is unavailable in a distribution build',
      );
    }
    final service = licenseService ?? LicenseRuntime.service;
    return MaterialApp(
      title: 'دفتر الحساب',
      debugShowCheckedModeBanner: false,
      theme: RafTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LicenseGate(
        service: service,
        child: child ?? const SizedBox.shrink(),
      ),
      home: _LicensedStartup(home: home),
    );
  }
}

class _LicensedStartup extends StatefulWidget {
  final Widget? home;
  const _LicensedStartup({this.home});
  @override
  State<_LicensedStartup> createState() => _LicensedStartupState();
}

class _LicensedStartupState extends State<_LicensedStartup> {
  late final Future<StoreSettingsModel> _settings = StoreSettingsManager
      .instance
      .loadSettings();
  @override
  Widget build(BuildContext context) {
    if (widget.home != null) return widget.home!;
    return FutureBuilder(
      future: _settings,
      builder: (context, snapshot) =>
          snapshot.connectionState == ConnectionState.done
          ? const RafNavigationShell()
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
