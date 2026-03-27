// Fixes TypeScript errors for Vite-specific ?raw imports
declare module '*?raw' {
  const content: string;
  export default content;
}

// Fixes TypeScript errors for import.meta.env properties
interface ImportMetaEnv {
  readonly BASE_URL: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
