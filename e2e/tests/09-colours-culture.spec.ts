import { expect, test, type Page } from '@playwright/test';

import { bringOnScreen, button, openApp, scrollTo, seen, snap, stateFile, tab } from '../helpers/flutter';

/**
 * 21 Nov 2026 additions, as the woman test shopper (Punjabi, from 02-onboarding): her culture's
 * looks on Home with a store search, and the skin tone analyzer saving to her profile. Neither
 * needs Gemini or the GPU (the CV service and the catalog only).
 */
test.describe.serial('culture looks and the skin tone analyzer', () => {
  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage({ storageState: stateFile('WOMAN'), viewport: { width: 412, height: 915 } });
    await openApp(page);
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
  });
  test.afterAll(async () => page.close());

  test("Home shows her culture's looks, each with real pieces from the stores", async () => {
    const card = seen(page, 'Your Punjabi style');
    await scrollTo(page, card, 30);
    await expect(seen(page, /Phulkari dupatta/)).toBeVisible(); // a women's look: her own gender's
    const find = page.getByRole('button', { name: /^Find on stores: / }).first();
    await scrollTo(page, find);
    await bringOnScreen(page, find); // its first look's button: the card around it is on screen
    await page.waitForTimeout(800);
    await snap(page, '09-culture-card');
    await find.click();
    await expect(seen(page, /pieces for this look|Nothing for this look/)).toBeVisible({ timeout: 90_000 });
    await page.waitForTimeout(1500);
    await snap(page, '09-culture-products');
    await page.mouse.click(206, 40); // above the sheet: closes it
  });

  test('the skin tone analyzer reads her profile photo and saves shade and undertone', async () => {
    await tab(page, 'Profile');
    await page.waitForURL(/#\/profile/);
    const analyzer = page.getByRole('button', { name: /^Skin tone analyzer/ }).first();
    await scrollTo(page, analyzer);
    await analyzer.click();
    await expect(seen(page, 'Your shade, undertone and best colours')).toBeVisible();
    await page.waitForTimeout(800); // the screen slides in
    await button(page, 'Use my profile photo').click();
    await expect(seen(page, /Shade \d+ of 10 on the Monk skin tone scale/)).toBeVisible({ timeout: 90_000 });
    await expect(seen(page, /^Undertone: /)).toBeVisible();
    await expect(seen(page, 'Colours that flatter you')).toBeVisible();
    await snap(page, '09-skin-result');
    // the two questions: both say warm
    for (const answer of ['Greenish', 'Gold']) {
      const chip = page.getByRole('checkbox', { name: answer, exact: true }).or(button(page, answer)).first();
      await scrollTo(page, chip);
      await chip.click();
      await page.waitForTimeout(600);
    }
    await expect(seen(page, 'Undertone: Warm')).toBeVisible();
    await scrollTo(page, button(page, 'Use these results'));
    await button(page, 'Use these results').click();
    await expect(seen(page, /^Saved: /)).toBeVisible({ timeout: 30_000 });
    await scrollTo(page, seen(page, 'Skin tone'));
    await expect(seen(page, /warm undertone/)).toBeVisible();
  });
});
