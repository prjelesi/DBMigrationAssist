import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:5000',
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('reactflow'))        return 'vendor-reactflow';
          if (id.includes('@fluentui'))        return 'vendor-fluentui';
          if (id.includes('@tanstack'))        return 'vendor-query';
          if (id.includes('react-dom') || id.includes('react-router') || id.includes('/react/'))
                                               return 'vendor-react';
          if (id.includes('node_modules'))     return 'vendor';
        },
      },
    },
  },
})
