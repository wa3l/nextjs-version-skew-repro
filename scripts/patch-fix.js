const fs = require("fs");
const path = require("path");

const FILES = [
  "node_modules/next/dist/client/components/router-reducer/fetch-server-response.js",
  "node_modules/next/dist/esm/client/components/router-reducer/fetch-server-response.js",
];

function patchFile(filePath) {
  const fullPath = path.resolve(filePath);
  if (!fs.existsSync(fullPath)) {
    console.log(`  Skipping ${filePath} (not found)`);
    return { status: "skipped" };
  }

  let content = fs.readFileSync(fullPath, "utf8");
  const isESM = filePath.includes("/esm/");
  const getAppBuildIdCall = isESM ? "getAppBuildId()" : "(0, _appbuildid.getAppBuildId)()";

  if (content.includes("__VERSION_SKEW_EARLY_HEADER_CHECK__")) {
    console.log(`  Skipping ${filePath} (already patched)`);
    return { status: "already" };
  }

  // Patch 1: Do not start Flight decoding inside createFetch.
  content = content.replace(
    /let flightResponsePromise = shouldImmediatelyDecode \? createFromNextFetch\(fetchPromise, headers\) : null;/g,
    "let flightResponsePromise = null; // __VERSION_SKEW_EARLY_HEADER_CHECK__"
  );

  // Patch 2: In redirect replay path, keep decode deferred too.
  content = content.replace(
    /flightResponsePromise = shouldImmediatelyDecode \? createFromNextFetch\(fetchPromise, headers\) : null;/g,
    "flightResponsePromise = null; // __VERSION_SKEW_EARLY_HEADER_CHECK__"
  );

  // Patch 3: Add early build-id check before any decode in fetchServerResponse.
  const bailoutCode = `
        const headerBuildId = res.headers.get('x-build-id');
        if (headerBuildId && ${getAppBuildIdCall} !== headerBuildId) {
            console.warn('[version-skew-fix] Early build mismatch detected; forcing hard reload', {
                clientBuildId: ${getAppBuildIdCall},
                serverBuildId: headerBuildId,
                url: res.url,
            });
            return doMpaNavigation(res.url);
        }
`;

  content = content.replace(
    /(if \(!isFlightResponse \|\| !res\.ok \|\| !res\.body\) \{[\s\S]*?return doMpaNavigation\(responseUrl\.toString\(\)\);\n        \})/,
    `$1
${bailoutCode}        // __VERSION_SKEW_EARLY_HEADER_CHECK__`
  );

  if (!content.includes("__VERSION_SKEW_EARLY_HEADER_CHECK__")) {
    console.log(`  Failed to patch ${filePath} (pattern mismatch)`);
    return { status: "failed" };
  }

  fs.writeFileSync(fullPath, content);
  console.log(`  Patched ${filePath}`);
  return { status: "patched" };
}

console.log("Applying Next.js early header-check patch...");
const results = FILES.map(patchFile);
const patched = results.filter((r) => r.status === "patched").length;
const already = results.filter((r) => r.status === "already").length;
const failed = results.filter((r) => r.status === "failed").length;

if (failed > 0 || patched + already === 0) {
  console.error(
    `Patch failed (patched=${patched}, already=${already}, failed=${failed}).`
  );
  process.exit(1);
}

console.log(`Done (patched=${patched}, already=${already}).`);
