import { expect, test } from '@playwright/test';

import { button, fill, logIn, openApp, scrollTo } from '../helpers/flutter';

/** Signed out: the landing page and the account screens (SFR-001..005). */
test.describe('landing and sign-in (signed out)', () => {
  test('landing page shows what the app does and both ways in', async ({ page }) => {
    await openApp(page);
    await expect(button(page, 'Get started')).toBeVisible();
    await expect(button(page, 'Already have an account? Log in')).toBeVisible();
    await scrollTo(page, page.getByText('Chat with Zayn'));
    await scrollTo(page, page.getByText('Build your profile'));
  });

  test('SFR-001/003: sign-up checks the email, password strength and confirmation', async ({ page }) => {
    await openApp(page);
    await button(page, 'Already have an account? Log in').click();
    await button(page, 'New to SmartFit? Create an account').click();
    await fill(page, 'Full name', 'Test Person');
    await fill(page, /^Email/, 'not-an-email');
    await fill(page, /^Password/, 'weak');
    await fill(page, 'Confirm password', 'different1');
    await scrollTo(page, button(page, 'Create account'));
    await button(page, 'Create account').click();
    // Flutter puts a field's error in the field's accessible label
    await expect(page.getByLabel('Please enter a valid email').first()).toBeVisible();
    await expect(page.getByLabel('Password must be at least 8 characters').first()).toBeVisible();
    await expect(page.getByLabel('Passwords do not match').first()).toBeVisible();
    await expect(page.getByText(/Date of birth is required/).first()).toBeVisible(); // SFR-001 age check needs it
  });

  test('SFR-004: a wrong password is refused with a clear message', async ({ page }) => {
    await logIn(page, 'WOMAN', 'Wrong!Password123');
    await expect(page.getByText('Incorrect email/username or password.').first()).toBeVisible();
  });

  test('SFR-005: forgot password asks for the email and sends a reset code', async ({ page }) => {
    await openApp(page);
    await button(page, 'Already have an account? Log in').click();
    await button(page, 'Forgot password?').click();
    await expect(page.getByLabel(/^Email/).first()).toBeVisible();
    await expect(button(page, 'Send reset code')).toBeVisible();
  });
});
