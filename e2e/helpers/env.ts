import { config } from 'dotenv';
import { fileURLToPath } from 'node:url';

config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)), quiet: true });

export const shopper = (role: 'WOMAN' | 'MAN') => ({
  email: process.env[`E2E_${role}_EMAIL`] ?? '',
  password: process.env[`E2E_${role}_PASSWORD`] ?? '',
  id: process.env[`E2E_${role}_ID`] ?? '',
});

export const admin = {
  email: process.env.E2E_ADMIN_EMAIL ?? '',
  password: process.env.E2E_ADMIN_PASSWORD ?? '',
};
