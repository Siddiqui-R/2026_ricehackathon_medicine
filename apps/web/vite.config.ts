// Purpose: Build the browser client and keep development API requests on the same origin.
// Inputs: Web source and optional REVA_API_ORIGIN for a trusted local Swift server.
// Outputs: Static dist assets or a loopback development server.
// Side effects: Proxies only /v1 and /health; no provider credentials enter the bundle.

import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// MARK: - Fixed local API destination and explicit proxy paths
const target = new URL(process.env.REVA_API_ORIGIN || 'http://127.0.0.1:8080');
if (
  target.protocol !== 'http:' ||
  !['localhost', '127.0.0.1', '[::1]'].includes(target.hostname) ||
  target.username ||
  target.password ||
  target.pathname !== '/' ||
  target.search ||
  target.hash
) {
  throw new Error('REVA_API_ORIGIN must be a loopback HTTP origin for the Swift server.');
}
export default defineConfig({
  define: { 'import.meta.env.VITE_REVA_VERCEL': JSON.stringify(String(process.env.VERCEL === '1')) },
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: { '/v1': { target: target.origin }, '/health': { target: target.origin } },
  },
  build: {
    target: 'es2022',
    rolldownOptions: {
      input: {
        main: fileURLToPath(new URL('./index.html', import.meta.url)),
        notFound: fileURLToPath(new URL('./404.html', import.meta.url)),
      },
    },
  },
});
