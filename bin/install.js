#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");

const CLAUDE_DIR = path.join(os.homedir(), ".claude");
const SETTINGS_FILE = path.join(CLAUDE_DIR, "settings.json");
const STATUSLINE_DEST = path.join(CLAUDE_DIR, "statusline.sh");
const STATUSLINE_SRC = path.resolve(__dirname, "statusline.sh");
const BACKUP_DIR = path.join(CLAUDE_DIR, "statusline-backups");
// Records what existed before the first install, so uninstall can put it back.
const MANIFEST_FILE = path.join(BACKUP_DIR, "install.json");
// Backup name used by v1.0.0 (and upstream). Migrated into BACKUP_DIR.
const LEGACY_BACKUP = STATUSLINE_DEST + ".bak";

const STATUSLINE_CONFIG = {
  type: "command",
  command: 'bash "$HOME/.claude/statusline.sh"',
  // Re-run every second (minimum allowed) so the token spinner animates.
  refreshInterval: 1,
};

const blue = "\x1b[38;2;0;153;255m";
const green = "\x1b[38;2;0;175;80m";
const red = "\x1b[38;2;255;85;85m";
const yellow = "\x1b[38;2;230;200;0m";
const dim = "\x1b[2m";
const reset = "\x1b[0m";

function log(msg) {
  console.log(`  ${msg}`);
}

function success(msg) {
  console.log(`  ${green}✓${reset} ${msg}`);
}

function warn(msg) {
  console.log(`  ${yellow}!${reset} ${msg}`);
}

function fail(msg) {
  console.error(`  ${red}✗${reset} ${msg}`);
}

function tilde(p) {
  return p.startsWith(os.homedir()) ? "~" + p.slice(os.homedir().length) : p;
}

function timestamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

// Copies a file into BACKUP_DIR under a timestamped name. Never overwrites.
function backupFile(src, label) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const base = `statusline-${timestamp()}${label ? "-" + label : ""}`;
  let dest = path.join(BACKUP_DIR, `${base}.sh`);
  for (let i = 1; fs.existsSync(dest); i++) {
    dest = path.join(BACKUP_DIR, `${base}-${i}.sh`);
  }
  fs.copyFileSync(src, dest);
  return dest;
}

function sameContent(a, b) {
  try {
    return fs.readFileSync(a).equals(fs.readFileSync(b));
  } catch {
    return false;
  }
}

// Scripts from this package carry this marker on line 2 (v1.1.0+).
const SCRIPT_MARKER = "# claude-statusline (https://github.com/rushi-me/claude-statusline)";

function isOurScript(file) {
  try {
    return fs.readFileSync(file, "utf-8").split("\n", 3).includes(SCRIPT_MARKER);
  } catch {
    return false;
  }
}

function isOurCommand(statusLine) {
  return (
    !!statusLine &&
    statusLine.type === STATUSLINE_CONFIG.type &&
    statusLine.command === STATUSLINE_CONFIG.command
  );
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf-8"));
}

// Write via a temp file + rename so an interrupted run can't leave half a file.
function writeJson(file, data) {
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n");
  fs.renameSync(tmp, file);
}

function readSettings() {
  if (!fs.existsSync(SETTINGS_FILE)) return {};
  try {
    return readJson(SETTINGS_FILE);
  } catch {
    fail(`Could not parse ${tilde(SETTINGS_FILE)}; fix it manually`);
    process.exit(1);
  }
}

function readManifest() {
  if (!fs.existsSync(MANIFEST_FILE)) return null;
  try {
    return readJson(MANIFEST_FILE);
  } catch {
    warn(`Could not parse ${tilde(MANIFEST_FILE)}; ignoring it`);
    return null;
  }
}

function checkDeps() {
  const { execSync } = require("child_process");
  return ["jq", "curl", "git"].filter((cmd) => {
    try {
      execSync(`which ${cmd}`, { stdio: "ignore" });
      return false;
    } catch {
      return true;
    }
  });
}

function uninstall() {
  console.log();
  console.log(`  ${blue}Claude Line Uninstaller${reset}`);
  console.log(`  ${dim}───────────────────────${reset}`);
  console.log();

  const settings = readSettings();
  const manifest = readManifest();

  // The pre-install script: from the manifest, or a v1.0.0-style .bak file.
  let original = manifest ? manifest.originalScript : null;
  const legacy = !manifest && fs.existsSync(LEGACY_BACKUP);
  if (legacy) original = LEGACY_BACKUP;
  if (original && !fs.existsSync(original)) {
    warn(`Original backup ${tilde(original)} is missing; cannot restore it`);
    original = null;
  }

  // Keep the current script (it may have local edits) before replacing or removing it.
  if (fs.existsSync(STATUSLINE_DEST)) {
    const saved = backupFile(STATUSLINE_DEST, "uninstalled");
    success(`Saved current statusline to ${dim}${tilde(saved)}${reset}`);
  }

  if (original) {
    fs.copyFileSync(original, STATUSLINE_DEST);
    success(`Restored previous statusline from ${dim}${tilde(original)}${reset}`);
  } else if (fs.existsSync(STATUSLINE_DEST)) {
    fs.unlinkSync(STATUSLINE_DEST);
    success(`Removed ${dim}${tilde(STATUSLINE_DEST)}${reset}`);
  } else {
    warn("No statusline found; nothing to remove");
  }

  if (!isOurCommand(settings.statusLine)) {
    // Absent, or changed by the user since install: leave it alone.
    if (settings.statusLine) warn("statusLine setting was changed since install; left as is");
    else success("Settings already clean");
  } else if (manifest && manifest.originalStatusLine) {
    settings.statusLine = manifest.originalStatusLine;
    writeJson(SETTINGS_FILE, settings);
    success(`Restored previous statusLine setting in ${dim}settings.json${reset}`);
  } else if (legacy && original) {
    // v1.0.0 install: no record of the old setting, but the restored script sits at
    // the same path, so the current setting runs it.
    success("Kept statusLine setting (it runs the restored script)");
  } else {
    delete settings.statusLine;
    writeJson(SETTINGS_FILE, settings);
    success(`Removed statusLine from ${dim}settings.json${reset}`);
  }

  if (manifest) fs.unlinkSync(MANIFEST_FILE);
  if (legacy && original) {
    const moved = backupFile(LEGACY_BACKUP, "original");
    fs.unlinkSync(LEGACY_BACKUP);
    log(`${dim}Moved statusline.sh.bak to ${tilde(moved)}${reset}`);
  }
  if (fs.existsSync(BACKUP_DIR)) {
    log(`${dim}Backups kept in ${tilde(BACKUP_DIR)}${reset}`);
  }

  console.log();
  log(`${green}Done!${reset} Restart Claude Code to apply changes.`);
  console.log();
}

function install() {
  console.log();
  console.log(`  ${blue}Claude Line Installer${reset}`);
  console.log(`  ${dim}─────────────────────${reset}`);
  console.log();

  const missing = checkDeps();
  if (missing.length > 0) {
    fail(`Missing required dependencies: ${missing.join(", ")}`);
    log(`  Install them and try again.`);
    if (missing.includes("jq")) {
      log(`  ${dim}brew install jq${reset}`);
    }
    process.exit(1);
  }
  success("Dependencies found (jq, curl, git)");

  if (!fs.existsSync(CLAUDE_DIR)) {
    fs.mkdirSync(CLAUDE_DIR, { recursive: true });
    success(`Created ${tilde(CLAUDE_DIR)}`);
  }

  // Parse settings before touching any file, so a broken settings.json aborts cleanly.
  const settings = readSettings();
  let manifest = readManifest();

  if (!manifest) {
    // First install (or first since v1.0.0): record what uninstall should restore.
    manifest = {
      installedAt: new Date().toISOString(),
      originalScript: null,
      originalStatusLine: isOurCommand(settings.statusLine) ? null : settings.statusLine || null,
    };
    if (fs.existsSync(LEGACY_BACKUP)) {
      // v1.0.0 kept the pre-install script here; the current file is our older version.
      manifest.originalScript = backupFile(LEGACY_BACKUP, "original");
      fs.unlinkSync(LEGACY_BACKUP);
      // v1.0.0 overwrote the old setting without saving it. The old script lived at the
      // same path, so the current setting is the best record of how it was run.
      if (!manifest.originalStatusLine && isOurCommand(settings.statusLine)) {
        manifest.originalStatusLine = settings.statusLine;
      }
      success(`Moved statusline.sh.bak to ${dim}${tilde(manifest.originalScript)}${reset}`);
    } else if (fs.existsSync(STATUSLINE_DEST) && !isOurScript(STATUSLINE_DEST)) {
      manifest.originalScript = backupFile(STATUSLINE_DEST, "original");
      success(`Backed up existing statusline to ${dim}${tilde(manifest.originalScript)}${reset}`);
    }
  }

  // Back up what is installed now (upgrades, local edits) unless it is identical to the
  // new script or already saved as the original. Backups are never overwritten.
  if (
    fs.existsSync(STATUSLINE_DEST) &&
    !sameContent(STATUSLINE_DEST, STATUSLINE_SRC) &&
    !(manifest.originalScript && sameContent(STATUSLINE_DEST, manifest.originalScript))
  ) {
    const saved = backupFile(STATUSLINE_DEST);
    success(`Backed up current statusline to ${dim}${tilde(saved)}${reset}`);
  }

  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  writeJson(MANIFEST_FILE, manifest);

  fs.copyFileSync(STATUSLINE_SRC, STATUSLINE_DEST);
  fs.chmodSync(STATUSLINE_DEST, 0o755);
  success(`Installed statusline to ${dim}${tilde(STATUSLINE_DEST)}${reset}`);

  if (isOurCommand(settings.statusLine)) {
    if (settings.statusLine.refreshInterval === undefined) {
      // Older installs ran only on events; add the timer that drives the spinner.
      settings.statusLine = {
        ...settings.statusLine,
        refreshInterval: STATUSLINE_CONFIG.refreshInterval,
      };
      writeJson(SETTINGS_FILE, settings);
      success(`Enabled ${STATUSLINE_CONFIG.refreshInterval}s refresh in ${dim}settings.json${reset}`);
    } else {
      success("Settings already configured");
    }
  } else {
    if (settings.statusLine) {
      warn("Replaced existing statusLine setting (saved; uninstall restores it)");
    }
    settings.statusLine = STATUSLINE_CONFIG;
    writeJson(SETTINGS_FILE, settings);
    success(`Updated ${dim}settings.json${reset} with statusLine config`);
  }

  console.log();
  log(`${green}Done!${reset} Restart Claude Code to see your new status line.`);
  console.log();
}

if (process.argv.includes("--uninstall")) {
  uninstall();
} else {
  install();
}
