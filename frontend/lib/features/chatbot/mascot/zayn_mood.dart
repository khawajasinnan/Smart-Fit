import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Zayn, the AI stylist (spec §23.14, §23.16, §23.21): a fabulous, sassy,
/// campy Gen-Z designer guy. At rest he never stands straight (hip popped,
/// wrist flicked) and fidgets now and then; these are his moods / actions.
/// The mood names match `assets/mascot/zayn.html` and the backend's `[MOOD: x]` tag.
enum ZaynMood {
  idle,
  hello,
  happy,
  excited,
  sassy,
  confused,
  sad,
  thinking,
  listening,
  love,
  surprised,
  proud,
  wink,
  eyeroll,
  shrug,
  clap,
  dance,
  hairflip,
  cool,
  vogue,
  snap,
  strut,
  kiss,
  selfie,
  spin,
  facepalm,
  // added 18 Nov 2026
  thumbsup,
  nod,
  headshake,
  bow,
  point,
  laugh,
  yawn,
  measure;

  /// A mood from the stylist's reply (`mood` field), or null if unknown.
  static ZaynMood? fromName(String? name) {
    if (name == null) return null;
    final key = name.trim().toLowerCase();
    for (final mood in values) {
      if (mood.name == key) return mood;
    }
    return null;
  }

  /// Read out by screen readers.
  String get description => switch (this) {
        idle => 'posing with a hand on his hip',
        hello => 'waving hello',
        happy => 'happy',
        excited => 'excited',
        sassy => 'sassy, hand on hip, peeking over his glasses',
        confused => 'confused, scratching his head',
        sad => 'sad',
        thinking => 'thinking, hand on his chin',
        listening => 'listening',
        love => 'in love with this look',
        surprised => 'surprised',
        proud => 'proud, hands on hips',
        wink => 'winking',
        eyeroll => 'rolling his eyes',
        shrug => 'shrugging',
        clap => 'clapping',
        dance => 'dancing',
        hairflip => 'flipping his hair',
        cool => 'pushing up his glasses, looking cool',
        vogue => 'voguing, framing his face with his hands',
        snap => 'doing a Z-snap',
        strut => 'strutting like on a runway',
        kiss => 'blowing a kiss',
        selfie => 'taking a selfie',
        spin => 'twirling',
        facepalm => 'hiding his face in his hand',
        thumbsup => 'giving a thumbs up',
        nod => 'nodding yes',
        headshake => 'shaking his head no',
        bow => 'taking a bow',
        point => 'pointing at the outfit',
        laugh => 'laughing',
        yawn => 'stretching and yawning',
        measure => 'holding out a tape measure',
      };
}

/// What Zayn says next to the character, per mood: sassy Gen-Z, simple
/// English mixed with Roman Urdu (male forms: "karta hoon", "raha hoon").
const Map<ZaynMood, List<String>> zaynQuips = {
  ZaynMood.hello: [
    'Hey hey! Main Zayn hoon, aapka stylist. Aaj kya scene hai?',
    'Welcome back, style icon! Kya plan hai aaj?',
  ],
  ZaynMood.happy: ['Love it! Yeh hui na baat.', 'Perfect, main samajh gaya!', "Let's gooo!"],
  ZaynMood.excited: ['Look what I found for you!', 'Shopping time! Dekho yeh sab.', 'Bro, yeh options dekho!'],
  ZaynMood.sassy: ['Darling, trust me on this one.', 'Fashion police? Main hi hoon.', 'Glasses down. Sass up.'],
  ZaynMood.confused: ['Hmm, thora aur batao?', 'Wait... kya matlab?', 'Main confuse ho gaya, phir se samjhao?'],
  ZaynMood.sad: ['Oh no, yeh abhi nahi mila.', 'Kuch nahi mila... lekin hum phir try karenge!'],
  ZaynMood.thinking: ['Soch raha hoon...', 'Let me cook...', 'Hmm, ek second...'],
  ZaynMood.listening: ['Haan, bolo, main sun raha hoon!', "Go on, I'm listening!"],
  ZaynMood.love: ['Uff, kitna fire look hai!', "I'm obsessed with this!", 'Yeh to dil le gaya!'],
  ZaynMood.surprised: ['Whoa! Yeh to kamaal hai!', 'Wait, what? Wow!'],
  ZaynMood.proud: ['Done! Ab main aapko aur better jaanta hoon.', 'Proud of you, honestly.'],
  ZaynMood.wink: ['Insider tip, sirf aapke liye.', 'Trust the process. 😉'],
  ZaynMood.eyeroll: ['Seriously? Yeh combo? Hum isse better kar sakte hain.', 'Okay okay, main judge nahi kar raha... thora sa.'],
  ZaynMood.shrug: ['Depends, honestly. Aap batao?', 'Dono chal jayenge, vibe aapki.'],
  ZaynMood.clap: ['Slow clap for this pick!', 'Taste! Aapka taste top hai.'],
  ZaynMood.dance: ['Yeh fit dekh ke main naach raha hoon!', 'Vibes on point!'],
  ZaynMood.hairflip: ['Main hoon hi itna stylish.', 'Hair flip, because this look deserves it.'],
  ZaynMood.cool: ['Smooth choice. Very smooth.', 'Designer approved.'],
  ZaynMood.vogue: ['Strike a pose. Yeh look serve kar raha hai!', "It's giving cover shoot."],
  ZaynMood.snap: ['Snap snap! Slay.', 'And that, darling, is how it is done.'],
  ZaynMood.strut: ['Runway mode: ON.', 'Walk like the mall is your catwalk.'],
  ZaynMood.kiss: ['Mwah! Perfect choice.', 'Sending love to this fit. 💋'],
  ZaynMood.selfie: ['Hold on, this fit needs a selfie.', 'Posting this on my story, obviously.'],
  ZaynMood.spin: ['Twirl check!', 'Main ghoom gaya, aur look bhi!'],
  ZaynMood.facepalm: ['Honey... no. Chalo, fix karte hain.', "I can't even. Let me help."],
  ZaynMood.thumbsup: ['Approved! Yeh chalega.', 'Thumbs up, full marks.'],
  ZaynMood.nod: ['Haan haan, bilkul sahi.', 'Exactly what I was thinking.'],
  ZaynMood.headshake: ['Nahi nahi, yeh wala nahi.', 'Babe, no. Kuch better dhoondte hain.'],
  ZaynMood.bow: ['Shukriya! Aap ka stylist hamesha haazir.', 'Thank you, thank you. Main yahin hoon.'],
  ZaynMood.point: ['Yeh dekho! This one is the one.', 'Is pe nazar rakho.'],
  ZaynMood.laugh: ['Hahaha, aap bhi na!', "Stop, I'm crying. Okay, focus."],
  ZaynMood.yawn: ['Thora time lag raha hai... main yahin hoon.', 'Almost there, promise.'],
  ZaynMood.measure: ['Size check! Measurements dekh raha hoon.', 'Perfect fit ka secret: sahi size.'],
};

/// Lines when the user taps Zayn.
const List<String> zaynPokeQuips = [
  'Oye! Main stylist hoon, punching bag nahi.',
  'Careful, the jacket is limited edition.',
  'Aur kuch? Main ready hoon!',
  'Need a style check? Just ask!',
  "Don't touch the hair. It took 20 minutes.",
  'Excuse me, I was in the middle of a pose.',
  'Careful, the nails are fresh.',
];

class ZaynState {
  const ZaynState({this.mood = ZaynMood.idle, this.quip, this.seq = 0});

  final ZaynMood mood;
  final String? quip;

  /// Increases on every reaction, so the same mood twice still re-animates the bubble.
  final int seq;
}

/// The mascot's current mood and line. Events from the chat call [react];
/// a reaction falls back to idle after its hold time ([hold] null = until the
/// next reaction, e.g. thinking while the stylist answers).
class ZaynController extends StateNotifier<ZaynState> {
  ZaynController({Random? random}) : _random = random ?? Random(), super(const ZaynState());

  final Random _random;
  Timer? _revert;

  static const Duration defaultHold = Duration(seconds: 6);

  void react(ZaynMood mood, {String? quip, bool speak = true, Duration? hold = defaultHold}) {
    _revert?.cancel();
    state = ZaynState(mood: mood, quip: quip ?? (speak ? _pick(zaynQuips[mood]) : null), seq: state.seq + 1);
    if (hold != null && mood != ZaynMood.idle) {
      _revert = Timer(hold, () {
        if (mounted) state = ZaynState(seq: state.seq + 1);
      });
    }
  }

  /// The user is typing: listen, without repeating the line on every key.
  ({ZaynMood mood, String quip})? _pendingIntro;

  /// Zayn's next opening line instead of the usual hello (e.g. his reaction
  /// to a notification answer); the chat screen takes it when it opens.
  void setPendingIntro(ZaynMood mood, String quip) => _pendingIntro = (mood: mood, quip: quip);

  ({ZaynMood mood, String quip})? takePendingIntro() {
    final intro = _pendingIntro;
    _pendingIntro = null;
    return intro;
  }

  void listening() {
    if (state.mood == ZaynMood.listening) {
      react(ZaynMood.listening, quip: state.quip, hold: const Duration(seconds: 4));
    } else if (state.mood == ZaynMood.idle || state.mood == ZaynMood.hello) {
      react(ZaynMood.listening, hold: const Duration(seconds: 4));
    }
  }

  /// Tapped: a playful reaction.
  void poke() {
    const moods = [
      ZaynMood.sassy, ZaynMood.wink, ZaynMood.hairflip, ZaynMood.cool, ZaynMood.dance, ZaynMood.eyeroll,
      ZaynMood.vogue, ZaynMood.snap, ZaynMood.kiss, ZaynMood.spin, ZaynMood.strut, ZaynMood.selfie,
      ZaynMood.laugh, ZaynMood.thumbsup, ZaynMood.point, ZaynMood.bow,
    ];
    react(moods[_random.nextInt(moods.length)], quip: _pick(zaynPokeQuips), hold: const Duration(seconds: 4));
  }

  String? _pick(List<String>? lines) => (lines == null || lines.isEmpty) ? null : lines[_random.nextInt(lines.length)];

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }
}

final zaynProvider = StateNotifierProvider<ZaynController, ZaynState>((ref) => ZaynController());
