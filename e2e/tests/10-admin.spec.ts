import { expect, test, type Page } from '@playwright/test';

import { admin, shopper } from '../helpers/env';

const ADMIN_URL = 'http://localhost:5173';

/**
 * The web admin panel (SFR-039..042), on a desktop-sized window. Needs an admin login in
 * e2e/.env.local (E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD); skipped without one. Acts only on
 * the woman test shopper: suspend + lift, and the delete dialog's guard (cancelled).
 */
test.describe.serial('admin panel', () => {
  test.skip(!admin.email || !admin.password, 'no admin login in e2e/.env.local (E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD)');
  let page: Page;
  const woman = shopper('WOMAN');
  const row = () => page.getByRole('row').filter({ hasText: woman.email });
  const nav = (label: string) => page.getByRole('navigation', { name: 'Admin sections' }).getByRole('link', { name: label });

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
    await page.goto(`${ADMIN_URL}/`);
    await page.getByLabel('Email').fill(admin.email);
    await page.getByLabel('Password').fill(admin.password);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 60_000 });
  });
  test.afterAll(async () => page?.close());

  test('SFR-041: the dashboard shows usage, top products, feedback trends and model performance', async () => {
    for (const heading of ['Chat sessions per day', 'Feedback by type', 'Most recommended', 'Model performance', 'Services']) {
      await expect(page.getByRole('heading', { name: heading })).toBeVisible({ timeout: 60_000 });
    }
  });

  test('SFR-039: find a user by email and view the details', async () => {
    await nav('Users').click();
    await page.getByLabel('Search users').fill(woman.email);
    await expect(row()).toHaveCount(1, { timeout: 30_000 });
    await row().getByRole('button', { name: 'View' }).click();
    await expect(page.getByRole('heading', { name: 'User details' })).toBeVisible();
    await page.getByRole('button', { name: 'Close' }).last().click();
  });

  test('SFR-039: suspend a user, then lift the suspension', async () => {
    await row().getByRole('button', { name: 'Suspend' }).click();
    await page.getByLabel('Reason').fill('E2E test: suspension lifted straight away');
    await page.getByRole('button', { name: 'Suspend', exact: true }).last().click();
    await expect(page.getByText('User suspended.')).toBeVisible({ timeout: 30_000 });
    await row().getByRole('button', { name: 'Lift suspension' }).click();
    await expect(page.getByText('Suspension lifted.')).toBeVisible({ timeout: 30_000 });
    await expect(row().getByRole('button', { name: 'Suspend' })).toBeVisible();
  });

  test('SFR-039: deleting a user needs DELETE typed first (cancelled here)', async () => {
    await row().getByRole('button', { name: 'Delete' }).click();
    const forever = page.getByRole('button', { name: 'Delete forever' });
    await expect(forever).toBeDisabled();
    await page.getByLabel('Type DELETE to confirm').fill('DELETE');
    await expect(forever).toBeEnabled();
    await page.getByRole('button', { name: 'Cancel' }).click();
    await expect(row()).toHaveCount(1);
  });

  test("SFR-042 (+034): the feedback page shows the shopper's comment from the look score", async () => {
    await nav('Feedback').click();
    await expect(page.getByText('Nice shirt, a bit loose for me').first()).toBeVisible({ timeout: 30_000 });
  });

  test('SFR-040: products can be managed and every store has scraping settings', async () => {
    await nav('Catalog').click();
    await expect(page.getByRole('button', { name: 'Add product' })).toBeVisible();
    await page.getByLabel('Search products').fill('shirt');
    await expect(page.getByRole('row').nth(1)).toBeVisible({ timeout: 30_000 });
    await nav('Scraping').click();
    // one settings card per store (needs migration 20261120000100_scraper_config_all_brands.sql)
    await expect(page.getByText('Products to keep').first()).toBeVisible({ timeout: 30_000 });
    expect(await page.getByText('Products to keep').count()).toBeGreaterThan(10);
  });
});
