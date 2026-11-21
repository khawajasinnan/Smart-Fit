import { expect, test } from '@playwright/test';

import { askZayn, button, openApp, seen, stateFile, tab } from '../helpers/flutter';

test.use({ storageState: stateFile('WOMAN') });

async function openChat(page) {
  await openApp(page);
  await page.waitForURL(/#\/home/, { timeout: 90_000 });
  await tab(page, 'Stylist');
  await expect(page.getByLabel('Ask your stylist...')).toBeVisible();
}

/** Zayn (SFR-014..018) and the photo analysis in the chat (SFR-016/017, SFR-019..021). */
test.describe.serial('AI stylist chat', () => {
  test('app help: Zayn explains where the try-on is and offers a button to it', async ({ page }) => {
    await openChat(page);
    await button(page, 'New chat').click();
    await askZayn(page, "I can't find the virtual try-on in the app", button(page, 'Open Virtual Try-On'));
    await expect(seen(page, /Try-On/)).toBeVisible();
    await button(page, 'Open Virtual Try-On').click();
    await page.waitForURL(/#\/try-on/);
  });

  test('SFR-015/022/023: a request with occasion and budget brings real products', async ({ page }) => {
    await openChat(page);
    await button(page, 'New chat').click();
    // product cards come with "Try on" buttons (SFR-024)
    await askZayn(page, 'Show me a casual lawn suit for daily wear under 8000 PKR, any colour',
      page.getByRole('button', { name: /^Try on$/ }).first());
  });

  test('SFR-016/017: the attach sheet offers camera, gallery and the profile photo for analysis', async ({ page }) => {
    await openChat(page);
    await button(page, 'Add a photo').click();
    for (const option of ['Take a photo of me', 'Choose a photo of me', 'Use my profile photo', 'Outfit photos from gallery']) {
      await expect(page.getByRole('button', { name: new RegExp(`^${option}`) })).toBeVisible();
    }
    // SFR-017 + SFR-019..021: the profile photo is analysed without a new upload
    await page.getByRole('button', { name: /^Use my profile photo/ }).click();
    await expect(seen(page, /Body shape|Estimated size|Skin tone/)).toBeVisible({ timeout: 120_000 });
  });

  test('SFR-018/038: past chats are kept in the history', async ({ page }) => {
    await openChat(page);
    await button(page, 'History').click();
    await expect(seen(page, /lawn suit|try-on/i)).toBeVisible({ timeout: 30_000 });
  });
});
