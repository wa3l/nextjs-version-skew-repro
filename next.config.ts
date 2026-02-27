import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  generateBuildId: async () => {
    return process.env.NEXT_PUBLIC_BUILD_ID || "development";
  },
};

export default nextConfig;
