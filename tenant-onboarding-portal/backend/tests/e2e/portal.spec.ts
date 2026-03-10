import { expect, test } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

function uniqueTenantSuffix() {
  return `${Date.now()}-${Math.floor(Math.random() * 10_000)}`;
}

test('mock auth auto-bootstraps an admin session', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: 'My tenant requests' })).toBeVisible();
  await expect(page.getByText('Playwright Admin')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Admin Queue' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign in with BCGov' })).toHaveCount(0);
});

test('admin can create, revise, and approve a tenant request', async ({ page }) => {
  const suffix = uniqueTenantSuffix();
  const tenantName = `playwright-tenant-${suffix}`;
  const displayName = `Playwright Tenant ${suffix}`;
  const updatedDepartment = `Delivery ${suffix}`;
  const reviewNote = `Approved by Playwright ${suffix}`;

  await page.goto('/tenants/new');

  await expect(
    page.getByRole('heading', { name: 'Create tenant onboarding request' }),
  ).toBeVisible();
  await page.getByLabel('Project name').fill(tenantName);
  await page.getByLabel('Display name').fill(displayName);
  await page.getByLabel('Department or branch').fill('Platform Engineering');
  await page.getByPlaceholder('name@gov.bc.ca').first().fill('owner@gov.bc.ca');
  await page.getByRole('button', { name: 'Submit request' }).click();

  await expect(page).toHaveURL(new RegExp(`/tenants/${tenantName}$`));
  await expect(page.getByRole('heading', { name: displayName })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Generated tfvars' })).toBeVisible();
  await expect(page.getByText('dev.tfvars')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Version history' })).toBeVisible();
  await expect(page.getByText('v1')).toBeVisible();

  await page.getByRole('link', { name: 'Create updated version' }).click();
  await expect(page.getByRole('heading', { name: `Update ${tenantName}` })).toBeVisible();
  await page.getByLabel('Department or branch').fill(updatedDepartment);
  await page.getByRole('button', { name: 'Create updated version' }).click();

  await expect(page).toHaveURL(new RegExp(`/tenants/${tenantName}$`));
  await expect(
    page.locator('.summary-row__value', { hasText: updatedDepartment }).first(),
  ).toBeVisible();
  await expect(page.getByRole('cell', { name: 'v2' })).toBeVisible();

  await page.getByRole('button', { name: 'Admin Queue' }).click();
  await expect(page.getByRole('heading', { name: 'Review queue' })).toBeVisible();

  const pendingRow = page.locator('tr', { hasText: displayName }).first();
  await expect(pendingRow).toBeVisible();
  await pendingRow.getByRole('link', { name: 'Review' }).click();

  await expect(page.getByRole('heading', { name: displayName })).toBeVisible();
  await page.locator('textarea').fill(reviewNote);
  await page.getByRole('button', { name: 'Approve' }).click();

  await expect(page.getByRole('heading', { name: 'Review queue' })).toBeVisible();
  await page.goto(`/tenants/${tenantName}`);
  await expect(page).toHaveURL(new RegExp(`/tenants/${tenantName}$`));
  await expect(page.locator('.status-badge--approved').first()).toBeVisible();
});
