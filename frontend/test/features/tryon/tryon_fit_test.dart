import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';

/// The size is reported on a finished try-on, never a reason to refuse one
/// (user's call, 15 Nov 2026): the user sees the garment on themselves and
/// decides for themselves.
void main() {
  TryOnFit? parse(String status, [String note = 'why']) =>
      TryOnFit.fromJson({'status': status, 'note': note, 'size': 'L'});

  test('reads every verdict the server can send', () {
    expect(parse('fits')!.status, TryOnFitStatus.fits);
    expect(parse('small')!.status, TryOnFitStatus.small);
    expect(parse('big')!.status, TryOnFitStatus.big);
    expect(parse('unknown')!.status, TryOnFitStatus.unknown);
    // an unfamiliar value from a newer server must not crash the app
    expect(parse('something-new')!.status, TryOnFitStatus.unknown);
    expect(TryOnFit.fromJson(null), isNull);
  });

  test('small and big are wrong-size, fits and unknown are not', () {
    expect(parse('small')!.isWrongSize, isTrue);
    expect(parse('big')!.isWrongSize, isTrue);
    expect(parse('fits')!.isWrongSize, isFalse);
    expect(parse('unknown')!.isWrongSize, isFalse);
    expect(parse('fits')!.fits, isTrue);
    expect(parse('small')!.fits, isFalse);
  });

  test('a job whose size is wrong still has its try-on images', () {
    final job = TryOnJob.fromJson({
      'fit': {'status': 'small', 'basis': 'measurements', 'note': 'Too small at the chest'},
      'job_id': 'j',
      'status': 'done',
      'product_id': 'outfitters:tee',
      'category': 'upper',
      'mode': 'modal',
      'views': [
        {'angle': 'front', 'status': 'done', 'image_url': 'https://signed.example/front.jpg'},
      ],
    });
    expect(job.fit!.status, TryOnFitStatus.small);
    expect(job.fit!.note, 'Too small at the chest');
    expect(job.views.single.imageUrl, isNotNull); // the try-on still happened
  });

  test('a view carries its cloth-warping preview when the service made one (21 Nov 2026)', () {
    final made = TryOnView.fromJson({
      'angle': 'front', 'status': 'running', 'fitting_url': 'https://signed.example/u/k_fit.jpg',
    });
    expect(made.fittingUrl, 'https://signed.example/u/k_fit.jpg');
    expect(made.isDone, isFalse); // the preview comes before the result
    expect(TryOnView.fromJson({'angle': 'front', 'status': 'done'}).fittingUrl, isNull);
  });
}
