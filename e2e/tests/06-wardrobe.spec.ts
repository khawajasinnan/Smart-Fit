import { expect, test, type Page } from '@playwright/test';

import { button, openApp, seen, snap, stateFile, tab } from '../helpers/flutter';

/**
 * SFR-035..037: the outfit saved in 05 (with its try-on and hairstyle) in the wardrobe.
 * Cards flip on tap: the photo on the front, details and actions on the back.
 */
test.describe.serial('wardrobe', () => {
  let page: Page;
  const card = () => page.getByRole('button', { name: /\. Tap for details/ }).first();
  const flipped = () => page.getByRole('button', { name: /\. Showing details\. Tap to see the photo/ }).first();

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage({ storageState: stateFile('WOMAN'), viewport: { width: 412, height: 915 } });
    await openApp(page);
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
    await tab(page, 'Saved');
    await page.waitForURL(/#\/wardrobe/);
  });
  test.afterAll(async () => page.close());

  test('SFR-036: the saved outfit is listed with its try-on and the hairstyle', async () => {
    await expect(seen(page, 'My Wardrobe')).toBeVisible();
    await expect(card()).toBeVisible({ timeout: 30_000 });
    await card().click();
    await expect(flipped()).toBeVisible();
    await expect(button(page, 'My try-on')).toBeVisible(); // SFR-035: saved with its try-on
    await expect(seen(page, /Hairstyle: /)).toBeVisible(); // SFR-035/036: and its hairstyle
    await expect(seen(page, /Saved (just now|\d+ min ago|\d+ h ago|yesterday|\d+ days ago|a while ago)/)).toBeVisible(); // SFR-036: when it was saved
    await snap(page, '06-wardrobe-card');
  });

  test('SFR-036: the wardrobe can be sorted', async () => {
    await page.getByRole('button', { name: 'Sort' }).click();
    await expect(seen(page, 'Price: low to high')).toBeVisible();
    await seen(page, 'Newest first').click();
    await expect(flipped().or(card())).toBeVisible();
  });

  test('SFR-035: the saved try-on opens again', async () => {
    if (!(await flipped().isVisible())) await card().click();
    await button(page, 'My try-on').click();
    await expect(page.getByRole('button', { name: 'Zoom' }).first()).toBeVisible({ timeout: 60_000 });
    await expect(page.getByRole('button', { name: /^Download (image|all \d+ images)$/ })).toBeVisible();
    await page.waitForTimeout(1500); // the image loads
    await snap(page, '06-saved-tryon');
    await page.mouse.click(206, 40); // above the sheet: closes it
    await expect(page.getByRole('button', { name: 'Zoom' })).toHaveCount(0);
  });

  test("SFR-037: 'View on store' opens the retailer's product page", async () => {
    if (!(await flipped().isVisible())) await card().click();
    const popup = page.waitForEvent('popup');
    await button(page, 'View on store').click();
    const store = await popup;
    await store.waitForURL((u) => u.protocol === 'https:' && !['localhost', '127.0.0.1'].includes(u.hostname),
      { waitUntil: 'commit' });
    await store.close();
  });

  test('SFR-035: removing an item can be undone', async () => {
    if (!(await flipped().isVisible())) await card().click();
    const before = await page.getByRole('button', { name: /\. (Tap for details|Showing details\. Tap to see the photo)/ }).count();
    await button(page, 'Remove').click();
    await expect(seen(page, /^Removed /)).toBeVisible();
    await button(page, 'Undo').click();
    await expect(page.getByRole('button', { name: /\. (Tap for details|Showing details\. Tap to see the photo)/ }))
      .toHaveCount(before, { timeout: 30_000 });
  });
});
