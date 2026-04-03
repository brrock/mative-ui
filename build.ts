import { chmod, mkdir, rm, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

type BuildOptions = {
  appName: string;
  entry: string;
  outDir: string;
};

function parseArgs(): BuildOptions {
  const options: BuildOptions = {
    appName: "mativeUi",
    entry: "app.ts",
    outDir: "dist",
  };

  for (const arg of Bun.argv.slice(2)) {
    if (arg.startsWith("--app-name=")) {
      options.appName = arg.slice("--app-name=".length);
    } else if (arg.startsWith("--entry=")) {
      options.entry = arg.slice("--entry=".length);
    } else if (arg.startsWith("--out-dir=")) {
      options.outDir = arg.slice("--out-dir=".length);
    }
  }

  return options;
}

async function run(command: string[], cwd: string) {
  const proc = Bun.spawn(command, {
    cwd,
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    throw new Error(`${command.join(" ")} failed with exit code ${exitCode}`);
  }
}

function infoPlist(appName: string) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${appName}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.mative.${appName}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${appName}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`;
}

async function main() {
  const root = process.cwd();
  const { appName, entry, outDir } = parseArgs();
  const resolvedOutDir = resolve(root, outDir);
  const appBundlePath = join(resolvedOutDir, `${appName}.app`);
  const contentsPath = join(appBundlePath, "Contents");
  const macOSPath = join(contentsPath, "MacOS");
  const resourcesPath = join(contentsPath, "Resources");
  const compiledBinaryPath = join(macOSPath, `${appName}-bin`);
  const launcherPath = join(macOSPath, appName);
  const dylibPath = join(macOSPath, "libmative.dylib");

  await rm(resolvedOutDir, { recursive: true, force: true });
  await mkdir(macOSPath, { recursive: true });
  await mkdir(resourcesPath, { recursive: true });

  await run(
    [
      "swiftc",
      "-emit-library",
      "-o",
      dylibPath,
      "bridge.swift",
      "-Xlinker",
      "-install_name",
      "-Xlinker",
      "@executable_path/libmative.dylib",
    ],
    root
  );

  await run(
    [
      "bun",
      "build",
      "--compile",
      "--minify",
      entry,
      "--outfile",
      compiledBinaryPath,
    ],
    root
  );

  await writeFile(
    launcherPath,
    `#!/bin/sh
cd "$(dirname "$0")"
exec "./${basename(compiledBinaryPath)}"
`
  );
  await chmod(launcherPath, 0o755);
  await writeFile(join(contentsPath, "Info.plist"), infoPlist(appName));
  await writeFile(join(contentsPath, "PkgInfo"), "APPL????");

  console.log(`Built ${appBundlePath}`);
  console.log(`Launcher: ${launcherPath}`);
  console.log(`Embedded binary: ${compiledBinaryPath}`);
  console.log(`Embedded bridge: ${dylibPath}`);
}

await main();