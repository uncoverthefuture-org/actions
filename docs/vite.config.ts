import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tsconfigPaths from "vite-tsconfig-paths";

// https://vitejs.dev/config/
export default defineConfig({
    base: '/actions/',
    plugins: [
        react(),
        tsconfigPaths()
    ],
    server: {
        host: true,
        port: 3000,
    },
    preview: {
        host: true,
        port: 3000,
    },
    // Support for raw markdown imports
    assetsInclude: ['**/*.md'],
})
