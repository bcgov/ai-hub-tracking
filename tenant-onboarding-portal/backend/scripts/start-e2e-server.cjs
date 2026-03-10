process.env.PORT = process.env.PORT || '4300'
process.env.PORTAL_AUTH_MODE = process.env.PORTAL_AUTH_MODE || 'mock'
process.env.PORTAL_MOCK_ACCESS_TOKEN = process.env.PORTAL_MOCK_ACCESS_TOKEN || 'dev-token'
process.env.PORTAL_MOCK_USER_EMAIL = process.env.PORTAL_MOCK_USER_EMAIL || 'playwright.admin@gov.bc.ca'
process.env.PORTAL_MOCK_USER_NAME = process.env.PORTAL_MOCK_USER_NAME || 'Playwright Admin'
process.env.PORTAL_MOCK_USER_USERNAME = process.env.PORTAL_MOCK_USER_USERNAME || 'playwright.admin'
process.env.PORTAL_MOCK_USER_ROLES = process.env.PORTAL_MOCK_USER_ROLES || 'portal-admin'
process.env.PORTAL_TABLE_STORAGE_CONNECTION_STRING = ''
process.env.PORTAL_TABLE_STORAGE_ACCOUNT_URL = ''
process.env.PORTAL_OIDC_DISCOVERY_URL = ''

require('../dist/main.js')