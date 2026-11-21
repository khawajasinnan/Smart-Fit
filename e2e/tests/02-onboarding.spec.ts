import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { expect, test } from '@playwright/test';

import { AUTH_DIR, KIT, button, fill, logIn, scrollTo, stateFile, upload } from '../helpers/flutter';

/** SFR-006, SFR-009..013: a new user must complete the profile before anything else. */
test('a new user completes the mandatory profile, then reaches Home', async ({ page }) => {
  await logIn(page, 'WOMAN');
  await page.waitForURL(/#\/profile-setup/, { timeout: 60_000 });

  // SFR-013: nothing else opens until the profile is complete
  await page.goto('/#/home');
  await page.waitForURL(/#\/profile-setup/, { timeout: 60_000 });
  await expect(button(page, 'Continue')).toBeVisible();
  await page.waitForTimeout(1500); // let the redirect's page transition finish

  // step 1: photo (SFR-009), gender (SFR-010), phone, culture
  const photo = page.getByRole('button', { name: /profile photo/ }).first();
  await photo.click();
  await expect(button(page, 'Choose from gallery')).toBeVisible();
  await page.waitForTimeout(600); // the sheet slides in
  await upload(page, button(page, 'Choose from gallery'), `${KIT}/people/women-front/00006_00.jpg`);
  await expect(button(page, 'Change profile photo')).toBeVisible({ timeout: 60_000 });
  await button(page, 'Female').click();
  await fill(page, 'Phone number', '03001234567');
  await button(page, 'Punjabi').click();
  await button(page, 'Continue').click();

  // step 2: body shape (a woman sees the women's five), usual size, measurements (SFR-011)
  await expect(button(page, 'Hourglass body type')).toBeVisible();
  await expect(button(page, 'Trapezoid body type')).toHaveCount(0);
  await button(page, 'Hourglass body type').click();
  const sizeM = page.getByRole('checkbox', { name: 'M', exact: true }).or(button(page, 'M')).first();
  await scrollTo(page, sizeM);
  await sizeM.click();
  await expect(page.getByLabel(/Chest/).first()).toBeVisible();
  await button(page, 'Continue').click();

  // step 3: skin tone (SFR-012) with its undertone, and styles
  await button(page, 'Medium skin tone').click();
  const warm = page.getByRole('checkbox', { name: 'Warm', exact: true }).or(button(page, 'Warm')).first();
  await scrollTo(page, warm);
  await warm.click();
  await button(page, 'Casual').click();
  await button(page, 'Lawn Suit').click();
  await scrollTo(page, button(page, 'Finish'));
  await button(page, 'Finish').click();

  // done: the celebration, then Home
  await expect(page.getByText(/all set/).first()).toBeVisible({ timeout: 90_000 });
  await button(page, 'Start exploring').click();
  await page.waitForURL(/#\/home/, { timeout: 60_000 });
  mkdirSync(fileURLToPath(AUTH_DIR), { recursive: true });
  await page.context().storageState({ path: stateFile('WOMAN') });
});
