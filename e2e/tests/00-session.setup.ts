import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { expect, test } from '@playwright/test';

import { AUTH_DIR, logIn, stateFile } from '../helpers/flutter';

/**
 * Saves a logged-in session for a test shopper whose profile is already complete
 * (after 02-onboarding ran once), so the later files can run on their own:
 *   npx playwright test tests/00-session.setup.ts
 */
for (const role of ['WOMAN', 'MAN'] as const) {
  test(`session for the ${role.toLowerCase()} test shopper`, async ({ page }) => {
    await logIn(page, role);
    const refused = page.getByText('Incorrect email/username or password.').first();
    const signedIn = () => /#\/(home|profile-setup)/.test(page.url());
    await expect.poll(async () => signedIn() || (await refused.isVisible()), { timeout: 90_000 }).toBe(true);
    test.skip(!signedIn(), 'this test shopper was deleted (08-account-man deletes the man)');
    test.skip(page.url().includes('profile-setup'), 'profile not completed yet: run 02-onboarding first');
    mkdirSync(fileURLToPath(AUTH_DIR), { recursive: true });
    await page.context().storageState({ path: stateFile(role) });
  });
}
