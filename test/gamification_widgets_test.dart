import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabidata_app/widgets/progress_ring.dart';
import 'package:sabidata_app/widgets/streak_badge.dart';
import 'package:sabidata_app/data/gamification/level.dart';

void main() {
  test('la progression de niveau suit les points et accepte les seuils API', () {
    final bronze = LevelInfo.of('', 250);
    expect(bronze.key, 'bronze');
    expect(bronze.progress, 0.5);
    expect(bronze.pointsRemaining(250), 250);

    final argent = LevelInfo.of('argent', 1250);
    expect(argent.key, 'argent');
    expect(argent.progress, 0.5);
    expect(argent.pointsRemaining(1250), 750);

    final serverConfigured = LevelInfo.of('', 300,
        thresholds: {'argent': 300, 'or': 900});
    expect(serverConfigured.key, 'argent');
    expect(serverConfigured.progress, 0);
  });

  testWidgets('ProgressRing accepte des valeurs hors bornes', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProgressRing(value: 1.7, center: Text('2450'))),
    ));
    expect(find.text('2450'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('StreakBadge affiche les jours', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StreakBadge(days: 12)),
    ));
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
  });

  testWidgets('StreakBadge pulse démarre quand highlight passe à true',
      (tester) async {
    Widget build(bool highlight) => MaterialApp(
          home: Scaffold(body: StreakBadge(days: 3, highlight: highlight)),
        );
    await tester.pumpWidget(build(false));
    var state = tester.state(find.byType(StreakBadge)) as dynamic;
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.isPulsing as bool, isFalse);
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 50));
    state = tester.state(find.byType(StreakBadge)) as dynamic;
    expect(state.isPulsing as bool, isTrue);
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.isPulsing as bool, isFalse);
  });
}
