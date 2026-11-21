import { expect, test, type Page } from '@playwright/test';

import { KIT, button, fill, logIn, scrollTo, seen, tab, upload } from '../helpers/flutter';

/**
 * The man test shopper's whole account life: onboarding as a man (SFR-006, SFR-009..013),
 * deactivate -> sign in -> reactivate, then delete for good (SFR-008). The deletion is real:
 * his account and data are gone afterwards (backend/scripts/e2e_users.py delete then only
 * tidies e2e/.env.local).
 */
test.describe.serial('a man signs up, deactivates, comes back, then deletes his account', () => {
  async function openPrivacy(page: Page) {
    await tab(page, 'Profile');
    await page.waitForURL(/#\/profile/);
    const privacy = page.getByRole('button', { name: /^Privacy & security/ }).first();
    await scrollTo(page, privacy);
    await privacy.click();
    await expect(seen(page, 'Your password, data and account')).toBeVisible(); // pushed: same web address
  }
  const tile = (page: Page, title: string) => page.getByRole('button', { name: new RegExp(`^${title}`) }).first();

  test('SFR-006, SFR-009..013: he completes the profile as a man', async ({ page }) => {
    await logIn(page, 'MAN');
    await page.waitForURL(/#\/profile-setup/, { timeout: 60_000 });
    await expect(button(page, 'Continue')).toBeVisible();
    await page.waitForTimeout(1500); // the page transition
    await page.getByRole('button', { name: /profile photo/ }).first().click();
    await expect(button(page, 'Choose from gallery')).toBeVisible();
    await page.waitForTimeout(600); // the sheet slides in
    await upload(page, button(page, 'Choose from gallery'), `${KIT}/people/men-front/IMG_1956.jpg`);
    await expect(button(page, 'Change profile photo')).toBeVisible({ timeout: 60_000 });
    await button(page, 'Male').click();
    await fill(page, 'Phone number', '03111234567');
    await button(page, 'Sindhi').click();
    await button(page, 'Continue').click();

    await expect(button(page, 'Hourglass body type')).toHaveCount(0); // a man sees the men's shapes
    await button(page, 'Rectangle body type').click();
    await expect(page.getByLabel(/Chest/).first()).toBeVisible();
    await button(page, 'Continue').click();

    await button(page, 'Brown skin tone').click();
    await button(page, 'Casual').click();
    await button(page, 'Shalwar Kameez').click();
    await scrollTo(page, button(page, 'Finish'));
    await button(page, 'Finish').click();
    await expect(page.getByText(/all set/).first()).toBeVisible({ timeout: 90_000 });
    await button(page, 'Start exploring').click();
    await page.waitForURL(/#\/home/, { timeout: 60_000 });
    await tab(page, 'Profile');
    await expect(seen(page, 'Male')).toBeVisible();
  });

  test('SFR-008: deactivating signs him out; signing in again offers Reactivate', async ({ page }) => {
    await logIn(page, 'MAN');
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
    await openPrivacy(page);
    await tile(page, 'Deactivate account').click();
    await expect(seen(page, 'Deactivate your account?')).toBeVisible();
    await button(page, 'Deactivate').click();
    await expect(seen(page, /Your account is deactivated/)).toBeVisible({ timeout: 60_000 });

    // signing in again: asked first, nothing opens until he chooses
    await logIn(page, 'MAN');
    await expect(seen(page, 'Welcome back!')).toBeVisible({ timeout: 60_000 });
    await button(page, 'Reactivate').click();
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
  });

  test('SFR-008: deleting needs DELETE typed, then the account is gone for good', async ({ page }) => {
    await logIn(page, 'MAN');
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
    await openPrivacy(page);
    await tile(page, 'Delete account').click();
    await expect(seen(page, 'Delete your account forever?')).toBeVisible();
    const forever = button(page, 'Delete forever');
    await expect(forever).toBeDisabled(); // not until DELETE is typed
    await fill(page, 'Type DELETE to confirm', 'DELETE');
    await expect(forever).toBeEnabled();
    await forever.click();
    await expect(button(page, 'Log in')).toBeVisible({ timeout: 90_000 });

    // the same email and password no longer work
    await logIn(page, 'MAN');
    await expect(page.getByText('Incorrect email/username or password.').first()).toBeVisible({ timeout: 60_000 });
  });
});
