import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/chatbot/data/models/app_screen_link.dart';
import 'package:smartfit/features/chatbot/data/services/chatbot_api_service.dart';
import 'package:smartfit/features/chatbot/screens/ai_stylist_chat_screen.dart';

void main() {
  test('the backend screen keys (chat_orchestrator/tools.py SCREENS) all map to an app screen', () {
    const backend = ['home', 'tryon', 'hairstyle', 'chat', 'wardrobe', 'profile', 'edit_profile', 'help', 'privacy'];
    expect(AppScreenLink.values.map((l) => l.key).toList(), backend);
    expect(AppScreenLink.fromKey('tryon')!.route, RoutePaths.tryOn);
    expect(AppScreenLink.fromKey('hairstyle')!.route, RoutePaths.hairstyle);
    expect(AppScreenLink.fromKey('edit_profile')!.route, RoutePaths.profileSetup);
  });

  test('a reply only carries a known screen', () {
    expect(ChatbotReply.fromJson({'reply': 'Tap Try-On', 'open': 'tryon'}).openScreen, AppScreenLink.tryOn);
    expect(ChatbotReply.fromJson({'reply': 'x', 'open': 'admin'}).openScreen, isNull);
    expect(ChatbotReply.fromJson({'reply': 'x', 'open': 'https://evil.example'}).openScreen, isNull);
    expect(ChatbotReply.fromJson({'reply': 'x'}).openScreen, isNull);
  });

  Future<GoRouter> pumpChatWith(WidgetTester tester, AppScreenLink link) async {
    Widget stub(String name) => Scaffold(body: Text('stub:$name'));
    final router = GoRouter(
      initialLocation: RoutePaths.chat,
      routes: [
        GoRoute(path: RoutePaths.chat, builder: (_, _) => Scaffold(body: OpenScreenButton(link: link))),
        GoRoute(path: RoutePaths.tryOn, builder: (_, _) => stub('tryon')),
        GoRoute(path: RoutePaths.help, builder: (_, _) => stub('help')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router));
    return router;
  }

  testWidgets('a tab screen switches to that tab', (tester) async {
    await pumpChatWith(tester, AppScreenLink.tryOn);
    await tester.tap(find.text('Open Virtual Try-On'));
    await tester.pumpAndSettle();
    expect(find.text('stub:tryon'), findsOneWidget);
  });

  testWidgets('help opens on top of the chat, so back returns to Zayn', (tester) async {
    final router = await pumpChatWith(tester, AppScreenLink.help);
    await tester.tap(find.text('Open Help & support'));
    await tester.pumpAndSettle();
    expect(find.text('stub:help'), findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open Help & support'), findsOneWidget);
  });
}
