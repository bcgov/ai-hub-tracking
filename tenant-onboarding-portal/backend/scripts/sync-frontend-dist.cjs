const { cpSync, existsSync, mkdirSync, rmSync } = require("node:fs");
const { join } = require("node:path");

const frontendDistDir = join(__dirname, "..", "..", "frontend", "dist");
const bundledDistDir = join(__dirname, "..", "frontend-dist");

if (!existsSync(frontendDistDir)) {
  throw new Error(`Frontend build not found at ${frontendDistDir}`);
}

rmSync(bundledDistDir, { force: true, recursive: true });
mkdirSync(bundledDistDir, { recursive: true });
cpSync(frontendDistDir, bundledDistDir, { recursive: true });
