import { expect, test } from '@playwright/test';

import { openApp, stateFile, tab } from '../helpers/flutter';

test.use({ storageState: stateFile('WOMAN') });

/** The 6 tabs open their screens (SFR-013: open now that the profile is complete). */
test('every tab opens its screen', async ({ page }) => {
  await openApp(page);
  await page.waitForURL(/#\/home/, { timeout: 90_000 });
  const tabs = [
    ['Try-On', /#\/try-on/, /What would you like to try on\?/],
    ['Hair', /#\/hairstyle/, /hairstyle/i],
    ['Stylist', /#\/chat/, /Ask your stylist/],
    ['Saved', /#\/wardrobe/, /wardrobe/i],
    ['Profile', /#\/profile/, /Edit profile/],
    ['Home', /#\/home/, /Virtual\s+Try-On/],
  ] as const;
  for (const [label, url, text] of tabs) {
    await tab(page, label);
    await page.waitForURL(url, { timeout: 30_000 });
    await expect(page.getByText(text).or(page.getByLabel(text)).first()).toBeVisible({ timeout: 30_000 });
  }
});
