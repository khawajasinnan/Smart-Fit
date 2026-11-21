import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/chatbot/screens/ai_stylist_chat_screen.dart';

/// SFR-016 / SFR-017: in the chat the user can have a camera photo, a gallery
/// photo or their existing profile photo analysed for this session.
void main() {
  Future<ChatAttachChoice?> pick(WidgetTester tester, String option) async {
    ChatAttachChoice? picked;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showModalBottomSheet<ChatAttachChoice>(
              context: context,
              builder: (_) => const ChatAttachSheet(maxImages: 4),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(option)); // the sheet scrolls on short screens
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('offers the three ways to be analysed and the outfit pictures', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: ChatAttachSheet(maxImages: 4)),
    ));
    for (final t in ['Analyse me for this chat', 'Take a photo of me', 'Choose a photo of me', 'Use my profile photo',
        'Show Zayn a picture', 'Outfit photos from gallery']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('each option returns its choice', (tester) async {
    expect(await pick(tester, 'Take a photo of me'), ChatAttachChoice.scanCamera);
    expect(await pick(tester, 'Choose a photo of me'), ChatAttachChoice.scanGallery);
    expect(await pick(tester, 'Use my profile photo'), ChatAttachChoice.scanProfile);
    expect(await pick(tester, 'Outfit photos from gallery'), ChatAttachChoice.outfitGallery);
  });
}
