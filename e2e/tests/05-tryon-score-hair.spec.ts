import { expect, test, type Page } from '@playwright/test';

import { KIT, button, openApp, scrollTo, seen, snap, stateFile, upload } from '../helpers/flutter';

/**
 * One shopper's path through the core features on one page (the try-on result lives in
 * the app's memory): a recommended product -> 2D try-on on a real GPU (SFR-024..028) ->
 * look score + feedback (SFR-032..034) -> hairstyles matching the outfit (SFR-029..031)
 * -> saved with the outfit (SFR-035). One GPU try-on + one hairstyle run per test run.
 */
test.describe.serial('try-on, look score and a matching hairstyle', () => {
  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage({ storageState: stateFile('WOMAN'), viewport: { width: 412, height: 915 } });
    await openApp(page);
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
  });
  test.afterAll(async () => page.close());

  test('SFR-023/024: pick a product from her recommendations and start a try-on', async () => {
    // Home's "Trending for you" is the list ranked for her profile. It needs no Gemini call:
    // the free tier allows 20 a day (found 20 Nov 2026), and Zayn's own product cards, with
    // the same "Try on" button, are checked in 04-chat.
    await scrollTo(page, seen(page, 'Trending for you'), 30);
    const tryOn = page.getByRole('button', { name: /^Try on$/ }).first();
    await scrollTo(page, tryOn);
    await page.waitForTimeout(800); // the cards slide in
    await tryOn.click();
    await page.waitForURL(/#\/try-on/);
    await expect(button(page, 'Quick, 1 photo · ~1 min')).toBeVisible();
  });

  test('SFR-026/028: the 2D try-on is made on the GPU and can be zoomed', async () => {
    await button(page, 'Quick, 1 photo · ~1 min').click();
    await upload(page, button(page, 'Gallery'), `${KIT}/people/women-front/00006_00.jpg`);
    const create = button(page, 'Create my try-on');
    await expect(create).toBeEnabled({ timeout: 60_000 });
    await create.click();
    // the cloth-warping step (21 Nov 2026): shown while the GPU works when the product's photo is a
    // studio shot (a model photo gets none), so it is photographed when it appears, not required
    const fitting = await seen(page, 'Fitting your garment').waitFor({ timeout: 90_000 }).then(() => true, () => false);
    if (fitting) await snap(page, '05-fitting-preview');
    await expect(button(page, 'Score this look')).toBeVisible({ timeout: 240_000 });
    if (await seen(page, 'How it was fitted').isVisible()) {
      await scrollTo(page, seen(page, 'How it was fitted'));
      await snap(page, '05-how-it-was-fitted');
      await page.mouse.wheel(0, -4000); // back to the top for the next steps
    }
    await page.waitForTimeout(1500); // the result image fades in
    await snap(page, '05-tryon-result');
    await page.getByRole('button', { name: 'Zoom' }).first().click();
    await expect(seen(page, /pinch to zoom/)).toBeVisible();
    await page.getByRole('button', { name: 'Close' }).click();
  });

  test('SFR-035: the outfit is saved to the wardrobe with its try-on', async () => {
    await scrollTo(page, button(page, 'Save to wardrobe'));
    await button(page, 'Save to wardrobe').click();
    await expect(button(page, 'Saved to wardrobe')).toBeVisible();
  });

  test('SFR-032/033/034: look score with hints; stars, corrections and a comment', async () => {
    await scrollTo(page, button(page, 'Score this look'));
    await button(page, 'Score this look').click();
    await expect(seen(page, /out of 100/)).toBeVisible({ timeout: 90_000 });
    await page.waitForTimeout(1500); // the score counts up
    await snap(page, '05-look-score');
    await scrollTo(page, seen(page, 'Styling hints'));
    await snap(page, '05-styling-hints');
    const stars = page.getByRole('button', { name: '4 stars' });
    await scrollTo(page, stars);
    await page.waitForTimeout(800); // let the scroll settle before tapping
    await stars.click();
    await expect(seen(page, /SmartFit learns from your rating/)).toBeVisible({ timeout: 30_000 });
    await scrollTo(page, seen(page, "What's off? (optional)"));
    // the "Size & fit" correction chip (not an occasion chip: those re-score the look)
    const chip = page.getByRole('checkbox', { name: /^Size & fit$/ }).or(page.getByRole('button', { name: /^Size & fit$/ })).last();
    await scrollTo(page, chip);
    await chip.click();
    const comment = page.getByLabel('Comment (optional)').first();
    await scrollTo(page, comment);
    await comment.click();
    await page.keyboard.type('Nice shirt, a bit loose for me');
    await scrollTo(page, button(page, 'Send feedback'));
    await button(page, 'Send feedback').click();
    await expect(seen(page, /your notes help SmartFit get better/)).toBeVisible({ timeout: 30_000 });
    await page.goBack();
  });

  test('SFR-029/030/031: hairstyles that go with this outfit, shown on her face', async () => {
    await scrollTo(page, button(page, 'Find a matching hairstyle'));
    await button(page, 'Find a matching hairstyle').click();
    await page.waitForURL(/#\/hairstyle/);
    await expect(seen(page, /Matching your outfit:/)).toBeVisible();
    await upload(page, button(page, 'Upload a photo'), `${KIT}/people/women-face.jpg`);
    await expect(seen(page, 'Best match')).toBeVisible({ timeout: 240_000 });
    await expect(seen(page, /styles for you/)).toBeVisible();
    await page.waitForTimeout(2000); // the previews load
    await snap(page, '05-hairstyle-result');
  });

  test('SFR-035: the hairstyle is saved with the outfit', async () => {
    const save = page.getByRole('button', { name: /^Save this hairstyle with / });
    await scrollTo(page, save);
    await save.click();
    await expect(seen(page, /saved with .* in your wardrobe/)).toBeVisible({ timeout: 30_000 });
  });
});
