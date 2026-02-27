const http = require("http");

const buildA = parseInt(process.argv[2]) || 3001;
const buildB = parseInt(process.argv[3]) || 3002;
const delay = parseInt(process.argv[4]) || 20;
const poisonBuildBChunk = process.argv[5] || "";
const poisonBuildAChunk = process.argv[6] || "";
const addBuildIdHeader = process.argv[7] === "--build-id-headers";
let deployed = false;

function routeRequest(urlPath) {
  // Before deploy: everything from Build A.
  if (!deployed) return { target: buildA, path: urlPath };

  // After deploy: everything from Build B, except one poisoned chunk URL.
  // If the browser asks for Build B's changed chunk, we serve Build A's old bytes
  // under the Build B URL to force bad module bindings at runtime.
  if (poisonBuildBChunk && poisonBuildAChunk) {
    const bPath = `/_next/static/chunks/${poisonBuildBChunk}`;
    if (urlPath.startsWith(bPath)) {
      const rewrittenPath = urlPath.replace(
        `/_next/static/chunks/${poisonBuildBChunk}`,
        `/_next/static/chunks/${poisonBuildAChunk}`
      );
      return { target: buildA, path: rewrittenPath };
    }
  }

  return { target: buildB, path: urlPath };
}

const proxy = http.createServer((req, res) => {
  const routed = routeRequest(req.url || "/");
  const options = {
    hostname: "localhost",
    port: routed.target,
    path: routed.path,
    method: req.method,
    headers: req.headers,
  };

  const proxyReq = http.request(options, (proxyRes) => {
    const headers = { ...proxyRes.headers };
    if (addBuildIdHeader) {
      headers["x-build-id"] = routed.target === buildA ? "build-a" : "build-b";
    }
    res.writeHead(proxyRes.statusCode, headers);
    proxyRes.pipe(res);
  });

  proxyReq.on("error", (err) => {
    res.writeHead(502);
    res.end("Proxy error: " + err.message);
  });

  req.pipe(proxyReq);
});

proxy.listen(3000, () => {
  console.log(`Proxy on :3000 (pre-deploy everything -> :${buildA})`);
  console.log(`Post-deploy routing: default -> :${buildB}`);
  if (poisonBuildBChunk && poisonBuildAChunk) {
    console.log(
      `Poisoned chunk mapping: /_next/static/chunks/${poisonBuildBChunk} -> Build A's ${poisonBuildAChunk}`
    );
  }
  if (addBuildIdHeader) {
    console.log("Injecting response header: x-build-id");
  }
  console.log(`Switching to post-deploy mode in ${delay} seconds...\n`);

  setTimeout(() => {
    deployed = true;
    console.log(`\n*** DEPLOYED! Proxy default now points to :${buildB} ***`);
    if (poisonBuildBChunk && poisonBuildAChunk) {
      console.log(
        `*** Poison active: ${poisonBuildBChunk} served from Build A bytes (${poisonBuildAChunk}) ***`
      );
    }
    console.log(`*** Go to your browser and click "Other Page" ***\n`);
  }, delay * 1000);
});
