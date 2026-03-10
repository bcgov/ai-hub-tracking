const { spawn } = require("node:child_process");
const path = require("node:path");

const backendDir = path.resolve(__dirname, "..");
const frontendDir = path.resolve(backendDir, "../frontend");
const sharedEnv = {
  ...process.env,
  PORT: "4310",
  PORTAL_AUTH_MODE: "mock",
  PORTAL_MOCK_ACCESS_TOKEN: process.env.PORTAL_MOCK_ACCESS_TOKEN || "dev-token",
  PORTAL_MOCK_USER_EMAIL:
    process.env.PORTAL_MOCK_USER_EMAIL || "playwright.admin@gov.bc.ca",
  PORTAL_MOCK_USER_NAME:
    process.env.PORTAL_MOCK_USER_NAME || "Playwright Admin",
  PORTAL_MOCK_USER_USERNAME:
    process.env.PORTAL_MOCK_USER_USERNAME || "playwright.admin",
  PORTAL_MOCK_USER_ROLES: process.env.PORTAL_MOCK_USER_ROLES || "portal-admin",
  PORTAL_TABLE_STORAGE_CONNECTION_STRING: "",
  PORTAL_TABLE_STORAGE_ACCOUNT_URL: "",
  PORTAL_OIDC_DISCOVERY_URL: "",
};

const children = [];

function startProcess(name, cwd, command, env) {
  const child = spawn(command, {
    cwd,
    env,
    stdio: "inherit",
    shell: true,
  });

  child.on("exit", (code, signal) => {
    if (shuttingDown) {
      return;
    }

    const reason = signal ? `signal ${signal}` : `code ${code}`;
    console.error(`[e2e-dev] ${name} exited unexpectedly with ${reason}`);
    shutdown(code || 1);
  });

  children.push(child);
}

let shuttingDown = false;

function shutdown(exitCode = 0) {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  for (const child of children) {
    if (!child.killed) {
      child.kill("SIGTERM");
    }
  }

  setTimeout(() => process.exit(exitCode), 250);
}

process.on("SIGINT", () => shutdown(0));
process.on("SIGTERM", () => shutdown(0));

startProcess("backend", backendDir, "npm run start:dev", sharedEnv);
startProcess(
  "frontend",
  frontendDir,
  "npm run dev -- --host 127.0.0.1 --port 4173",
  {
    ...process.env,
    PORTAL_API_PORT: "4310",
  },
);
