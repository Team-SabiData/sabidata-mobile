// Capture d'écran de tous les écrans de l'app SabiData.
// Prérequis : backend démarré sur le LAN (cf. lib/data/api/api_config.dart).
//
// Lanceur :
//   flutter test integration_test/screenshot_test.dart -d <device-id>
//
// Les PNG sont récupérés dans build/ à la fin du run.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:sabidata_app/router.dart';
import 'package:sabidata_app/theme/app_theme.dart';
import 'package:sabidata_app/data/auth/auth_session.dart';
import 'package:sabidata_app/data/api/api_config.dart';

late Directory _shotDir;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = ApiConfig.baseUrl;
  late String access;
  late String refresh;
  late Map<String, dynamic> me;

  setUpAll(() async {
    // Répertoire où écrire les PNG (espace app, récupérable via adb run-as).
    _shotDir = await getTemporaryDirectory();
    final sub = Directory('${_shotDir.path}/sabidata_shots');
    if (sub.existsSync()) sub.deleteSync(recursive: true);
    sub.createSync(recursive: true);
    _shotDir = sub;
    // 1. Inscription d'un utilisateur de test (email unique à chaque run).
    final email = 'sabi_test_${DateTime.now().millisecondsSinceEpoch}@test.bf';
    final reg = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'Awa Traoré', 'email': email, 'password': 'secret123'}),
    );
    if (reg.statusCode == 201) {
      final body = jsonDecode(reg.body) as Map<String, dynamic>;
      access = body['access'] as String;
      refresh = body['refresh'] as String;
    } else {
      // Fallback : login si le compte existait déjà.
      final login = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': 'secret123'}),
      );
      final body = jsonDecode(login.body) as Map<String, dynamic>;
      access = body['access'] as String;
      refresh = body['refresh'] as String;
    }

    final authHeader = {'Content-Type': 'application/json', 'Authorization': 'Bearer $access'};

    // 2. Complétion du profil (profileComplete = true, consentement commercial).
    await http.post(
      Uri.parse('$baseUrl/api/me/profile'),
      headers: authHeader,
      body: jsonEncode({
        'language': 'moore',
        'dialect': 'central',
        'region': 'centre',
        'commercialConsent': true,
      }),
    );

    // 3. Récupère le profil enrichi pour setter la session côté client.
    final meRes = await http.get(Uri.parse('$baseUrl/api/me'), headers: authHeader);
    me = jsonDecode(meRes.body) as Map<String, dynamic>;

    // 4. Seed de la session partagée (lue par le routeur + les écrans).
    AuthSession.instance.setTokens(access, refresh);
    AuthSession.instance.setProfile(me);

    // 5. Second utilisateur (contributeur) qui uploade quelques clips moore/central
    //    pour que l'écran de validation du validateur (Awa) ne soit pas vide.
    final cEmail = 'sabi_contrib_${DateTime.now().millisecondsSinceEpoch}@test.bf';
    final cReg = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'Ibrahim Sawadogo', 'email': cEmail, 'password': 'secret123'}),
    );
    String? cAccess;
    if (cReg.statusCode == 201) {
      cAccess = (jsonDecode(cReg.body) as Map<String, dynamic>)['access'] as String;
    }
    if (cAccess != null) {
      // Petit buffer audio factice (l'auto-check ne teste que la durée).
      final dummy = Uint8List(2048);
      for (var i = 0; i < 3; i++) {
        final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/clips'))
          ..headers['Authorization'] = 'Bearer $cAccess'
          ..fields['rarity'] = '0'
          ..fields['durationS'] = '5'
          ..fields['commercialUse'] = 'true'
          ..fields['consentVersion'] = 'v1'
          ..fields['language'] = 'moore'
          ..fields['dialect'] = 'central'
          ..fields['region'] = 'centre';
        req.files.add(http.MultipartFile.fromBytes('audio', dummy, filename: 'clip.m4a'));
        await req.send();
      }
    }
  });

  Future<void> goto(WidgetTester tester, String name, String path,
      {Object? extra, int frames = 50}) async {
    if (extra != null) {
      appRouter.go(path, extra: extra);
    } else {
      appRouter.go(path);
    }
    // Laisse le frame se poser (animations + fetchs éventuels).
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final bytes = await IntegrationTestWidgetsFlutterBinding.instance.takeScreenshot(name);
    await File('${_shotDir.path}/$name.png').writeAsBytes(bytes);
  }

  testWidgets('capture tous les écrans', (tester) async {
    // Police : la vraie app télécharge les polices Google Fonts (réseau dispo).
    GoogleFonts.config.allowRuntimeFetching = true;

    await tester.pumpWidget(MaterialApp.router(
      title: 'SabiData',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light.copyWith(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(AppTheme.light.textTheme).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
      ),
      routerConfig: appRouter,
    ));
    // Laisse le routeur + le téléchargement des polices se poser.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Sur Android : bascule le rendu Flutter vers une image capturable.
    await IntegrationTestWidgetsFlutterBinding.instance.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    // ── Écrans publics ────────────────────────────────────────────────
    // Splash : capturé tôt (avant sa redirection auto à ~1600 ms).
    await goto(tester, '01_splash', '/', frames: 7);
    await goto(tester, '02_onboarding', '/onboarding');
    await goto(tester, '03_app_preview', '/preview');
    await goto(tester, '04_login', '/login');
    await goto(tester, '05_register', '/register');
    await goto(tester, '06_phone_login', '/phone-login');
    await goto(tester, '07_otp_verify', '/verify', extra: '+226 70 00 00 00');

    // ── Setup profil ──────────────────────────────────────────────────
    await goto(tester, '08_profile_setup', '/profile-setup');

    // ── App principale (authentifié + profil complet) ──────────────────
    await goto(tester, '09_dashboard', '/dashboard');
    await goto(tester, '10_profile', '/profile');

    // ── Activités (nécessitent consentement) ───────────────────────────
    await goto(tester, '11_recording', '/recording',
        extra: {'commercial': true, 'consent_version': 'v1'});
    await goto(tester, '12_recording_review', '/recording-review',
        extra: {'duration': '00:08', 'commercial': true, 'audio_path': null});
    await goto(tester, '13_validation', '/validation');
    await goto(tester, '14_transcription', '/transcription');

    // ── Classement & carte (publics) ───────────────────────────────────
    await goto(tester, '15_leaderboard', '/leaderboard');
    await goto(tester, '16_dialect_map', '/dialect-map');

    // ── Revenus & extras ───────────────────────────────────────────────
    await goto(tester, '17_revenue', '/revenue');
    await goto(tester, '18_withdraw', '/withdraw', extra: 'orange');
    await goto(tester, '19_expert', '/expert');
    await goto(tester, '20_conversion', '/conversion');
    await goto(tester, '21_classroom', '/classroom');

    debugPrint('SHOTS_DIR=${_shotDir.path}');
    // Compte les fichiers écrits.
    final files = _shotDir.listSync().whereType<File>().toList();
    debugPrint('SHOTS_COUNT=${files.length}');
    // Laisse le puller adb récupérer tous les PNG avant la désinstallation.
    await Future.delayed(const Duration(seconds: 20));
  });
}
