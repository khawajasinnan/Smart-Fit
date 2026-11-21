import { mkdirSync, writeFileSync } from 'node:fs';

import { expect, test, type Locator, type Page } from '@playwright/test';

import { shopper } from './env';

export const AUTH_DIR = new URL('../.auth/', import.meta.url);
export const stateFile = (role: 'WOMAN' | 'MAN') => new URL(`${role.toLowerCase()}.json`, AUTH_DIR).pathname.replace(/^\/([A-Za-z]:)/, '$1');
export const KIT = 'D:/Smart-Fit/datasets/tryon-test-kit';

/** Open the app and wait for Flutter's accessibility tree (E2E builds turn it on). */
export async function openApp(page: Page, hash = '') {
  await page.goto(`/${hash}`);
  await page.waitForSelector('flt-semantics', { timeout: 120_000 });
}

export const button = (page: Page, name: string | RegExp, exact = true): Locator =>
  page.getByRole('button', { name, exact: typeof name === 'string' ? exact : undefined });

/** Type into a Flutter text field found by its label (or given directly). */
export async function fill(page: Page, label: string | RegExp | Locator, text: string) {
  const field = typeof label === 'string' || label instanceof RegExp ? page.getByLabel(label).first() : label;
  await field.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(text, { delay: 15 });
}

/** Scroll the screen (mouse wheel over its middle) until `target` is visible. */
export async function scrollTo(page: Page, target: Locator, maxSteps = 25, step = 450) {
  for (let i = 0; i < maxSteps; i++) {
    if (await target.first().isVisible().catch(() => false)) return;
    await page.mouse.move(206, 480);
    await page.mouse.wheel(0, step);
    await page.waitForTimeout(350);
  }
  await expect(target.first()).toBeVisible();
}

/** Scroll until `target` is really on screen (Flutter keeps off-screen nodes "visible" in the
 * accessibility tree), for screenshots of it. */
export async function bringOnScreen(page: Page, target: Locator, maxSteps = 25, step = 300) {
  const height = page.viewportSize()?.height ?? 915;
  for (let i = 0; i < maxSteps; i++) {
    const box = await target.first().boundingBox();
    if (box && box.y >= 0 && box.y + Math.min(box.height, height * 0.6) <= height) return;
    await page.mouse.move(206, 480);
    await page.mouse.wheel(0, box && box.y < 0 ? -step : step);
    await page.waitForTimeout(300);
  }
}

export async function upload(page: Page, opener: Locator, file: string) {
  const chooser = page.waitForEvent('filechooser', { timeout: 30_000 });
  await opener.click();
  await (await chooser).setFiles(file);
}

/** Log in from the welcome page with a test shopper. */
export async function logIn(page: Page, role: 'WOMAN' | 'MAN', password?: string) {
  const who = shopper(role);
  await openApp(page);
  await button(page, 'Already have an account? Log in').click();
  await fill(page, 'Email or username', who.email);
  await fill(page, 'Password', password ?? who.password);
  await button(page, 'Log in').click();
}

/** The bottom bar's tabs, by their labels. */
export async function tab(page: Page, label: 'Home' | 'Try-On' | 'Hair' | 'Stylist' | 'Saved' | 'Profile') {
  const name = label === 'Stylist' ? 'AI Stylist' : label; // Zayn's centre button
  await page.getByRole('button', { name, exact: true }).last().click();
}

/** Debugging aid: what the screen exposes to the accessibility tree. */
export async function dump(page: Page, tag = '') {
  const nodes = await page.$$eval('flt-semantics, input, textarea', (els) => els.map((e) => ({
    role: e.getAttribute('role') ?? e.tagName.toLowerCase(), label: e.getAttribute('aria-label'),
    text: (e.childElementCount === 0 ? e.textContent : '')?.trim().slice(0, 80),
    desc: e.getAttribute('aria-description') ?? undefined,
  })).filter((n) => n.label || n.text));
  console.log(`--- ${tag}:`, JSON.stringify(nodes.slice(0, 100)));
}

/**
 * Keep a picture of an AI result for a person to judge (the try-on, the score, the
 * hairstyle): attached to the HTML report and saved as e2e/screens/<name>.png (not in
 * test-results/, which Playwright empties at the start of every run; gitignored).
 */
export async function snap(page: Page, name: string) {
  const body = await page.screenshot();
  mkdirSync('screens', { recursive: true });
  writeFileSync(`screens/${name}.png`, body);
  await test.info().attach(name, { body, contentType: 'image/png' });
}

/** Text on screen, whether Flutter exposes it as text or inside an accessible label. */
export const seen = (page: Page, text: string | RegExp): Locator =>
  page.getByText(text).or(page.getByLabel(text)).first();

/**
 * Ask Zayn and wait for `answer`. Like a person, resend once if the AI service reports a
 * temporary problem (Gemini's per-minute limit, a service that just restarted). If his
 * profile has a culture, Zayn may first ask "traditional or general styles?": answered.
 */
export async function askZayn(page: Page, text: string, answer: Locator, timeout = 180_000) {
  const send = async (t: string) => {
    await page.getByLabel('Ask your stylist...').click();
    await page.keyboard.type(t, { delay: 10 });
    await page.keyboard.press('Enter');
  };
  const problem = seen(page, /AI stylist had a problem|a bit busy/);
  const culture = seen(page, /overall general styles/);
  await send(text);
  for (let round = 0; round < 3; round++) {
    await expect(answer.or(problem).or(culture)).toBeVisible({ timeout });
    if (await answer.isVisible()) return;
    if (await culture.isVisible()) {
      await send('Overall general styles please');
    } else {
      await page.waitForTimeout(20_000);
      await send(text);
    }
    await page.waitForTimeout(1500);
  }
  await expect(answer).toBeVisible({ timeout });
}
