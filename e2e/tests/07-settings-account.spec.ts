import { expect, test, type Page } from '@playwright/test';

import { button, fill, logIn, openApp, scrollTo, seen, stateFile, tab } from '../helpers/flutter';

/** SFR-007: the profile can be viewed and changed; the account screens open (SFR-008 in 08). */
test.describe.serial('profile and settings', () => {
  let page: Page;
  const tile = (title: string) => page.getByRole('button', { name: new RegExp(`^${title}`) }).first();
  const back = () => page.getByRole('button', { name: 'Back', exact: true }).first().click(); // the app's own arrow

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage({ storageState: stateFile('WOMAN'), viewport: { width: 412, height: 915 } });
    await openApp(page);
    await page.waitForURL(/#\/home/, { timeout: 90_000 });
    await tab(page, 'Profile');
    await page.waitForURL(/#\/profile/);
  });
  test.afterAll(async () => page.close());

  test('SFR-007: the profile shows her details', async () => {
    await expect(seen(page, 'Your style profile')).toBeVisible();
    for (const fact of ['Gender', 'Height · weight', 'Body type', 'Skin tone']) {
      await expect(seen(page, fact)).toBeVisible();
    }
    await expect(seen(page, 'Female')).toBeVisible();
  });

  test('SFR-007: the name can be changed', async () => {
    await page.getByRole('button', { name: 'Change your name' }).click();
    await expect(seen(page, 'Your name')).toBeVisible();
    const field = page.getByRole('textbox').last(); // the dialog's only field (its hint shows only when empty)
    await fill(page, field, 'Ayesha Edited');
    await button(page, 'Save').click();
    await expect(seen(page, 'Ayesha Edited')).toBeVisible({ timeout: 30_000 });
    // and back, so a rerun starts the same way
    await page.getByRole('button', { name: 'Change your name' }).click();
    await fill(page, page.getByRole('textbox').last(), 'Ayesha Test');
    await button(page, 'Save').click();
    await expect(seen(page, 'Ayesha Test')).toBeVisible({ timeout: 30_000 });
  });

  test('SFR-007/012: the skin tone can be changed through Edit profile', async () => {
    const target = (await seen(page, 'Olive').isVisible()) ? 'Brown' : 'Olive';
    await button(page, 'Edit profile').click();
    await expect(button(page, 'Continue')).toBeVisible(); // pushed screens keep the web address as it was
    await page.waitForTimeout(1000); // the screen slides in: a tap during the slide is lost
    await button(page, 'Continue').click(); // photo, gender, phone: kept
    await expect(seen(page, 'Your shape & size')).toBeVisible();
    await page.waitForTimeout(1000); // the step slides in: a tap during the slide is lost
    await button(page, 'Continue').click(); // body type and measurements: kept
    await button(page, `${target} skin tone`).click();
    await scrollTo(page, button(page, 'Save changes'));
    await button(page, 'Save changes').click();
    await expect(seen(page, 'Your style profile')).toBeVisible({ timeout: 60_000 }); // back on the profile
    await scrollTo(page, seen(page, 'Skin tone'));
    // the card's facts are read as one label ("... Skin tone Olive ..."), or as separate texts
    await expect(page.getByLabel(new RegExp(`Skin tone\\s+${target}\\b`)).or(page.getByText(target, { exact: true })).first())
      .toBeVisible({ timeout: 30_000 });
  });

  test('SFR-007: notification preferences are on the profile', async () => {
    const reminder = page.getByRole('switch', { name: /^Daily style reminder/ });
    await scrollTo(page, reminder);
    await expect(seen(page, 'Outfits ready, body analysis done, try-on results')).toBeVisible(); // the main switch
  });

  test('privacy: her data can be viewed; the password form opens', async () => {
    await scrollTo(page, tile('Privacy & security'));
    await tile('Privacy & security').click();
    await expect(seen(page, 'Your password, data and account')).toBeVisible();
    await tile('View & copy my data').click();
    await expect(seen(page, 'Your SmartFit data')).toBeVisible({ timeout: 30_000 });
    await expect(button(page, 'Copy to clipboard')).toBeVisible();
    await page.mouse.click(206, 40); // above the sheet: closes it
    await expect(seen(page, 'Your SmartFit data')).toBeHidden();
    await tile('Change password').click();
    await expect(page.getByLabel(/^New password/).first()).toBeVisible();
    await expect(page.getByLabel(/^Confirm new password/).first()).toBeVisible();
    await button(page, 'Cancel').click();
    // SFR-008: both ways to leave are offered (used for real in 08-account-man)
    await expect(tile('Deactivate account')).toBeVisible();
    await expect(tile('Delete account')).toBeVisible();
    await back();
    await expect(seen(page, 'Your style profile')).toBeVisible();
  });

  test('help & support and about open', async () => {
    await scrollTo(page, tile('Help & support'));
    await tile('Help & support').click();
    await expect(seen(page, "We're here to help")).toBeVisible();
    await back();
    await scrollTo(page, tile('About SmartFit'));
    await tile('About SmartFit').click();
    await expect(page.getByText('About', { exact: true }).or(page.getByLabel('About', { exact: true })).first())
      .toBeVisible();
    await back();
  });
});

/** SFR-004: log out ends the session (a fresh one: the saved session stays usable for other files). */
test('SFR-004: log out, and the app opens signed out', async ({ browser }) => {
  const page = await browser.newPage({ viewport: { width: 412, height: 915 } });
  await logIn(page, 'WOMAN');
  await page.waitForURL(/#\/home/, { timeout: 90_000 });
  await tab(page, 'Profile');
  await scrollTo(page, button(page, 'Log out'));
  await button(page, 'Log out').click();
  await expect(seen(page, 'Log out?')).toBeVisible();
  await page.getByRole('button', { name: 'Log out', exact: true }).last().click();
  await expect(button(page, 'Already have an account? Log in').or(button(page, 'Log in'))).toBeVisible({ timeout: 60_000 });
  await openApp(page);
  await expect(button(page, 'Get started')).toBeVisible({ timeout: 60_000 }); // nobody signed in
  await page.close();
});
